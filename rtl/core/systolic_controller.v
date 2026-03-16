module systolic_controller #(
         parameter MAX_DATA_SIZE        = 32,   // Maximum number of data units
         parameter SYS_ARRAY_SIZE       = 8,    // Array size
         parameter K_SIZE               = 16,   // Data unit size for SRAMA/B
         parameter DATA_WIDTH           = 32,   // Data width
         parameter SHARE_SRAM_ADDR_WIDTH = 7,   // Shared SRAM address width
         parameter SRAM_ADDR_WIDTH      = 5     // SRAMA/B/C address width
       ) (
         // Clock and reset signals
         input  wire                              clk,                   // Clock signal
         input  wire                              rst_n,                 // Reset signal, active low

         // Control signals
         input  wire                              tpu_start,             // Start GEMM signal, active high
         input  wire                              dma_load_start,        // Start load-only command
         input  wire [2:0]                        mtype_sel,             // Matrix type selection signal
         input  wire [2:0]                        dtype_sel,             // Data type selection signal
         input  wire                              mixed_precision,       // Mixed precision control signal

         // sram_loader interface
         output wire [SHARE_SRAM_ADDR_WIDTH-1:0]  read_share_sram_addr,  // Read address for shared SRAM
         input  wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] share_sram_data_out, // Data output from shared SRAM
         output wire                              sram_a_wen,            // Write enable for SRAMA
         output wire                              sram_b_wen,            // Write enable for SRAMB
         output wire                              sram_c_wen,            // Write enable for SRAMC
         output wire                              sram_d_wen,            // Write enable for SRAMD
         output wire [K_SIZE*DATA_WIDTH-1:0]      sram_a_data_in,        // Data input to SRAMA
         output wire [K_SIZE*DATA_WIDTH-1:0]      sram_b_data_in,        // Data input to SRAMB
         output wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] sram_c_data_in,      // Data input to SRAMC
         output wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sram_d_data_in,      // Data input to SRAMD
         output wire [SRAM_ADDR_WIDTH-1:0]        load_srama_addr,       // Write address for SRAMA
         output wire [SRAM_ADDR_WIDTH-1:0]        load_sramb_addr,       // Write address for SRAMB
         output wire [SRAM_ADDR_WIDTH-1:0]        load_sramc_addr,       // Write address for SRAMC
         output wire [SRAM_ADDR_WIDTH-1:0]        load_sramd_addr,       // Write address for SRAMD
         output wire [SRAM_ADDR_WIDTH-1:0]        read_srama_addr,       // Read address for SRAMA
         output wire [SRAM_ADDR_WIDTH-1:0]        read_sramb_addr,       // Read address for SRAMB
         output wire [SRAM_ADDR_WIDTH-1:0]        read_sramc_addr,       // Read address for SRAMC
         input  wire [K_SIZE*DATA_WIDTH-1:0]      sram_a_data_out,       // Data output from SRAMA
         input  wire [K_SIZE*DATA_WIDTH-1:0]      sram_b_data_out,       // Data output from SRAMB
         input  wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] sram_c_data_out,     // Data output from SRAMC


         output reg                               tpu_busy,             // TPU busy signal
         output wire [1:0]                        high_low_sel,          // Data bit selection for SRAMD write-back

         output reg                               tpu_done,              // One-cycle pulse when compute pipeline reaches MAIN_DONE
         output reg                               load_done              // One-cycle pulse when DMA_LOAD finishes loading A/B/C
       );

// Matrix type definitions
localparam m16n16k16 = 3'b001;  // m16n16k16 matrix type
localparam m32n8k16  = 3'b010;  // m32n8k16 matrix type
localparam m8n32k16  = 3'b100;  // m8n32k16 matrix type

// Main state machine states
localparam MAIN_IDLE            = 3'd0;  // Idle state
localparam MAIN_START_LOAD_SRAM = 3'd1;  // Start loading SRAM
localparam MAIN_LOAD_SRAM       = 3'd2;  // Loading SRAM
localparam MAIN_COMPUTE         = 3'd3;  // Legacy 4-phase compute state
localparam MAIN_DONE            = 3'd4;  // Computation done state

// Sub-state machine states
localparam SUB_IDLE        = 2'd0;  // Sub-state idle
localparam SUB_START_PHASE = 2'd1;  // Start one compute phase
localparam SUB_MUL_PHASE   = 2'd2;  // Wait for the active phase to finish

// State machine registers
reg [2:0] current_main_state;  // Current main state (3-bit)
reg [2:0] next_main_state;     // Next main state (3-bit)
reg [1:0] current_sub_state;   // Current sub-state
reg [1:0] next_sub_state;      // Next sub-state
reg [1:0] current_phase_idx;   // Current legacy phase: 0..3
reg [1:0] next_phase_idx;      // Next legacy phase

// sram_loader internal signals
reg        load_sram_start;    // SRAM load start signal
wire       load_ab_done;       // SRAMA and SRAMB load done signal
wire       sram_load_done;     // SRAMA/B/C loading done signal
wire       mul_done;           // Multiplication done signal
reg        compute;            // Compute start signal
wire       legacy_mtype_valid;
reg        load_only_mode;
reg        next_load_only_mode;


// systolic_input_loader internal signal
reg [3:0]  load_systolic_input_start;  // One-hot phase start for the current legacy shape

// Internal connection signals
wire [SYS_ARRAY_SIZE-1:0]                          load_en_row;         // Row load enable
wire [SYS_ARRAY_SIZE-1:0]                          load_en_col;         // Column load enable
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0]   row_data_out;        // Row data output from systolic_input
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0]   col_data_out;        // Column data output from systolic_input
wire [SYS_ARRAY_SIZE-1:0]                              row_data_out_valid;  // Row data output valid
wire [SYS_ARRAY_SIZE-1:0]                             col_data_out_valid;  // Column data output valid
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] row_output;       // Row output from systolic
wire                              row_output_valid;    // Row output valid from systolic
wire                              sys_outcome_valid;   // System outcome valid
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sys_outcome_row;  // System outcome row
wire                              c_valid;             // C matrix valid
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] c_row;            // C matrix row
wire                              compute_done;          // Computation done signal

assign legacy_mtype_valid = (mtype_sel == m16n16k16) ||
                            (mtype_sel == m32n8k16)  ||
                            (mtype_sel == m8n32k16);
// Instantiate sram_loader
sram_loader #(
              .K_SIZE               (K_SIZE),
              .MAX_DATA_SIZE        (MAX_DATA_SIZE),
              .DATA_WIDTH           (DATA_WIDTH),
              .SHARE_SRAM_ADDR_WIDTH(SHARE_SRAM_ADDR_WIDTH),
              .SRAM_ADDR_WIDTH      (SRAM_ADDR_WIDTH)
            ) u_sram_loader (
              .clk                  (clk),
              .rst_n                (rst_n),
              .load_sram_start      (load_sram_start),
              .mtype_sel            (mtype_sel),
              .read_share_sram_addr (read_share_sram_addr),
              .load_srama_addr_d2   (load_srama_addr),
              .load_sramb_addr_d2   (load_sramb_addr),
              .load_sramc_addr_d2   (load_sramc_addr),
              .sram_a_wen_d2        (sram_a_wen),
              .sram_b_wen_d2        (sram_b_wen),
              .sram_c_wen_d2        (sram_c_wen),
              .load_ab_done         (load_ab_done),
              .load_done            (sram_load_done),
              .share_sram_data_out  (share_sram_data_out),
              .sram_a_data_in       (sram_a_data_in),
              .sram_b_data_in       (sram_b_data_in),
              .sram_c_data_in       (sram_c_data_in)
            );

// Instantiate systolic_input_loader
systolic_input_loader #(
                        .SYS_ARRAY_SIZE      (SYS_ARRAY_SIZE),
                        .K_SIZE          (K_SIZE),
                        .DATA_WIDTH      (DATA_WIDTH),
                        .SRAM_ADDR_WIDTH (SRAM_ADDR_WIDTH)
                      ) u_systolic_input_loader (
                        .clk                     (clk),
                        .rst_n                   (rst_n),
                        .mtype_sel                (mtype_sel),
                        .load_systolic_input_start(load_systolic_input_start),
                        .read_srama_addr         (read_srama_addr),
                        .read_sramb_addr         (read_sramb_addr),
                        .load_en_row             (load_en_row),
                        .load_en_col             (load_en_col)
                      );

// Instantiate systolic_input
systolic_input #(
                 .SYS_ARRAY_SIZE   (SYS_ARRAY_SIZE),
                 .K_SIZE       (K_SIZE),
                 .DATA_WIDTH   (DATA_WIDTH)
               ) u_systolic_input (
                 .clk                  (clk),
                 .rst_n                (rst_n),
                 .load_en_row          (load_en_row),
                 .load_en_col          (load_en_col),
                 .row_data_in          (sram_a_data_out),
                 .col_data_in          (sram_b_data_out),
                 .row_data_out         (row_data_out),
                 .col_data_out         (col_data_out),
                 .row_data_out_valid   (row_data_out_valid),
                 .col_data_out_valid   (col_data_out_valid)
               );

// Instantiate systolic array
systolic #(
           .SYS_ARRAY_SIZE   (SYS_ARRAY_SIZE),
           .DATA_WIDTH   (DATA_WIDTH)
         ) u_systolic (
           .clk               (clk),
           .rst_n             (rst_n),
           .dtype_sel         (dtype_sel),
           .mixed_precision   (mixed_precision),
           .compute           (compute),
           .a_queue_in        (row_data_out),
           .b_queue_in        (col_data_out),
           .valid_a_queue_in  (row_data_out_valid),
           .valid_b_queue_in  (col_data_out_valid),
           .row_output        (row_output),
           .row_output_valid  (row_output_valid),
           .mul_done          (mul_done)
         );

// Instantiate matrix_adder_loader
matrix_adder_loader #(
                      .SYS_ARRAY_SIZE(SYS_ARRAY_SIZE),
                      .MAX_DATA_SIZE(MAX_DATA_SIZE),
                      .DATA_WIDTH(DATA_WIDTH),
                      .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH)
                    ) u_matrix_adder_loader (
                      .clk(clk),
                      .rst_n(rst_n),
                      .row_output_valid(row_output_valid),
                      .row_output(row_output),
                      .read_sramc_addr(read_sramc_addr),
                      .sram_c_data_out(sram_c_data_out),
                      .sys_outcome_valid(sys_outcome_valid),
                      .sys_outcome_row(sys_outcome_row),
                      .c_valid(c_valid),
                      .c_row(c_row),
                      .mtype_sel(mtype_sel)
                    );

// Instantiate matrix_adder
matrix_adder #(
               .SYS_ARRAY_SIZE(SYS_ARRAY_SIZE),
               .MAX_DATA_SIZE(MAX_DATA_SIZE),  
               .DATA_WIDTH(DATA_WIDTH),
               .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH)
             ) u_matrix_adder (
               .clk(clk),
               .rst_n(rst_n),
               .sys_outcome_row(sys_outcome_row),
               .sys_outcome_valid(sys_outcome_valid),
               .c_row(c_row),
               .c_valid(c_valid),
               .sum_row(sram_d_data_in),
               .sum_valid(sram_d_wen),
               .compute_done(compute_done),
               .write_addr(load_sramd_addr),
               .high_low_sel(high_low_sel),
               .dtype_sel(dtype_sel),
               .mixed_precision(mixed_precision),
               .mtype_sel(mtype_sel)
             );

// State transition logic
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        current_main_state <= MAIN_IDLE;
        current_sub_state  <= SUB_IDLE;
        current_phase_idx  <= 2'd0;
        load_only_mode     <= 1'b0;
      end
    else
      begin
        current_main_state <= next_main_state;
        current_sub_state  <= next_sub_state;
        current_phase_idx  <= next_phase_idx;
        load_only_mode     <= next_load_only_mode;
      end
  end

// Next state logic
always @(*)
  begin
    next_main_state = current_main_state;
    next_sub_state  = current_sub_state;
    next_phase_idx  = current_phase_idx;
    next_load_only_mode = load_only_mode;

    case (current_main_state)
      MAIN_IDLE:
        begin
          next_sub_state  = SUB_IDLE;
          next_phase_idx  = 2'd0;
          if (tpu_start || dma_load_start)
            begin
              next_load_only_mode = dma_load_start;
              next_main_state = MAIN_START_LOAD_SRAM;
            end
          else
            begin
              next_main_state = MAIN_IDLE;
            end
        end
      MAIN_START_LOAD_SRAM:
        begin
          next_sub_state  = SUB_IDLE;
          next_phase_idx  = 2'd0;
          next_load_only_mode = load_only_mode;
          next_main_state = MAIN_LOAD_SRAM;
        end
      MAIN_LOAD_SRAM:
        begin
          next_sub_state  = SUB_IDLE;
          next_phase_idx  = 2'd0;
          if (load_only_mode)
            begin
              if (sram_load_done)
                begin
                  next_main_state = MAIN_DONE;
                end
              else
                begin
                  next_main_state = MAIN_LOAD_SRAM;
                end
            end
          else if (load_ab_done)
            begin
              next_main_state = legacy_mtype_valid ? MAIN_COMPUTE : MAIN_IDLE;
            end
          else
            begin
              next_main_state = MAIN_LOAD_SRAM;
            end
        end
      MAIN_COMPUTE:
        begin
          case (current_sub_state)
            SUB_IDLE:
              begin
                next_phase_idx = 2'd0;
                next_sub_state = SUB_START_PHASE;
              end
            SUB_START_PHASE:
              begin
                next_sub_state = SUB_MUL_PHASE;
              end
            SUB_MUL_PHASE:
              begin
                if (current_phase_idx == 2'd3)
                  begin
                    if (compute_done)
                      begin
                        next_sub_state  = SUB_IDLE;
                        next_phase_idx  = 2'd0;
                        next_load_only_mode = 1'b0;
                        next_main_state = MAIN_DONE;
                      end
                    else
                      begin
                        next_sub_state = SUB_MUL_PHASE;
                      end
                  end
                else
                  begin
                    if (mul_done)
                      begin
                        next_phase_idx = current_phase_idx + 1'b1;
                        next_sub_state = SUB_START_PHASE;
                      end
                    else
                      begin
                        next_sub_state = SUB_MUL_PHASE;
                      end
                  end
              end
            default:
              begin
                next_main_state = MAIN_IDLE;
                next_sub_state  = SUB_IDLE;
                next_phase_idx  = 2'd0;
              end
          endcase
        end
      MAIN_DONE:
        begin
          next_main_state = MAIN_IDLE;
          next_sub_state  = SUB_IDLE;
          next_phase_idx  = 2'd0;
          next_load_only_mode = 1'b0;
        end
      default:
        begin
          next_main_state = MAIN_IDLE;
          next_sub_state  = SUB_IDLE;
          next_phase_idx  = 2'd0;
          next_load_only_mode = 1'b0;
        end
    endcase
  end

// Control signal logic
always @(*)
  begin
    // Default values
    load_sram_start           = 1'b0;
    load_systolic_input_start = 'd0;
    compute                  = 1'b0;
    tpu_busy                 = 1'b0;
    tpu_done                 = 1'b0;
    load_done                = 1'b0;
    case (current_main_state)
      MAIN_START_LOAD_SRAM:
        begin
          tpu_busy        = 1'b1;
          load_sram_start = 1'b1;
        end
      MAIN_LOAD_SRAM:
        begin
          tpu_busy        = 1'b1;
          load_sram_start = 1'b0;
        end
      MAIN_COMPUTE:
        begin
          tpu_busy = 1'b1;
          compute  = 1'b1;
          if (current_sub_state == SUB_START_PHASE)
            begin
              load_systolic_input_start = (4'b0001 << current_phase_idx);
            end
        end
      MAIN_DONE:
        begin
          compute  = 1'b0;
          tpu_busy = 1'b0;
          tpu_done = ~load_only_mode;
          load_done = load_only_mode;
        end
    endcase
  end

endmodule
