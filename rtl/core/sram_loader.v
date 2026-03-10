module sram_loader #(
         parameter K_SIZE               = 16,    // Number of data units for SRAMA/B
         parameter MAX_DATA_SIZE        = 32,    // Number of data units for SRAMC
         parameter DATA_WIDTH           = 32,    // Data width
         parameter SHARE_SRAM_ADDR_WIDTH = 7,    // Address width for shared SRAM
         parameter SRAM_ADDR_WIDTH      = 5      // Address width for SRAMA/B/C
       ) (
         // Clock and reset
         input  wire                              clk,                   // Clock signal
         input  wire                              rst_n,                 // Reset signal, active low

         // Inputs from state machine
         input  wire                              load_sram_start,       // Start loading signal
         input  wire [2:0]                        mtype_sel,             // Matrix type selection signal

         // SRAM control signals
         output reg  [SHARE_SRAM_ADDR_WIDTH-1:0]  read_share_sram_addr,  // Read address for shared SRAM
         output reg  [SRAM_ADDR_WIDTH-1:0]        load_srama_addr_d2,    // Write address for SRAMA (delayed)
         output reg  [SRAM_ADDR_WIDTH-1:0]        load_sramb_addr_d2,    // Write address for SRAMB (delayed)
         output reg  [SRAM_ADDR_WIDTH-1:0]        load_sramc_addr_d2,    // Write address for SRAMC (delayed)
         output reg                               sram_a_wen_d2,         // Write enable for SRAMA (delayed)
         output reg                               sram_b_wen_d2,         // Write enable for SRAMB (delayed)
         output reg                               sram_c_wen_d2,         // Write enable for SRAMC (delayed)
         output reg                               load_ab_done,          // SRAMA and SRAMB loading done signal

         // SRAM data transfer
         input  wire [MAX_DATA_SIZE*DATA_WIDTH-1:0]  share_sram_data_out,   // Data output from shared SRAM
         output reg  [K_SIZE*DATA_WIDTH-1:0]      sram_a_data_in,        // Data input to SRAMA
         output reg  [K_SIZE*DATA_WIDTH-1:0]      sram_b_data_in,        // Data input to SRAMB
         output reg  [MAX_DATA_SIZE*DATA_WIDTH-1:0]  sram_c_data_in         // Data input to SRAMC
       );

// Matrix type definitions
localparam m16n16k16 = 3'b001;  // m16n16k16: 16x16 matrix
localparam m32n8k16  = 3'b010;  // m32n8k16:  32x8 matrix
localparam m8n32k16  = 3'b100;  // m8n32k16:  8x32 matrix

// Matrix size parameters
localparam M_M16N16K16 = 6'd16; // Rows of matrix A for m16n16k16
localparam N_M16N16K16 = 6'd16; // Columns of matrix B for m16n16k16
localparam M_M32N8K16  = 6'd32; // Rows of matrix A for m32n8k16
localparam N_M32N8K16  = 6'd8;  // Columns of matrix B for m32n8k16
localparam M_M8N32K16  = 6'd8;  // Rows of matrix A for m8n32k16
localparam N_M8N32K16  = 6'd32; // Columns of matrix B for m8n32k16

// Shared SRAM address offset
localparam OFF = 7'd32;

// State definitions
localparam IDLE                      = 4'd0;  // Idle state
localparam LOAD_SHARE_SRAM_TO_SRAMA  = 4'd1;  // Load matrix A to SRAMA
localparam LOAD_SHARE_SRAM_TO_SRAMB  = 4'd2;  // Load matrix B to SRAMB
localparam WAIT_DELAY1               = 4'd3;  // Delay state 1
localparam WAIT_DELAY2               = 4'd4;  // Delay state 2
localparam LOAD_AB_DONE              = 4'd5;  // SRAMA/B loading done
localparam LOAD_SHARE_SRAM_TO_SRAMC  = 4'd6;  // Load matrix C to SRAMC
localparam WAIT_DELAY3               = 4'd7;  // Delay state 3
localparam WAIT_DELAY4               = 4'd8;  // Delay state 4
localparam LOAD_C_DONE               = 4'd9;  // SRAMC loading done

// Internal signals
reg [3:0]                        current_state;        // Current state
reg [3:0]                        next_state;           // Next state
reg [$clog2(MAX_DATA_SIZE)-1:0]  counter;              // Counter (width adaptive to MAX_DATA_SIZE)
reg [5:0]                        m_max;                // Dynamic row count
reg [5:0]                        n_max;                // Dynamic column count

reg [SRAM_ADDR_WIDTH-1:0]        load_srama_addr;      // SRAMA address
reg [SRAM_ADDR_WIDTH-1:0]        load_srama_addr_d1;   // SRAMA address (delayed 1 cycle)
reg [SRAM_ADDR_WIDTH-1:0]        load_sramb_addr;      // SRAMB address
reg [SRAM_ADDR_WIDTH-1:0]        load_sramb_addr_d1;   // SRAMB address (delayed 1 cycle)
reg [SRAM_ADDR_WIDTH-1:0]        load_sramc_addr;      // SRAMC address
reg [SRAM_ADDR_WIDTH-1:0]        load_sramc_addr_d1;   // SRAMC address (delayed 1 cycle)
reg                              sram_a_wen;           // SRAMA write enable
reg                              sram_a_wen_d1;        // SRAMA write enable (delayed 1 cycle)
reg                              sram_b_wen;           // SRAMB write enable
reg                              sram_b_wen_d1;        // SRAMB write enable (delayed 1 cycle)
reg                              sram_c_wen;           // SRAMC write enable
reg                              sram_c_wen_d1;        // SRAMC write enable (delayed 1 cycle)

// Dynamically select matrix dimensions
always @(*)
  begin
    case (mtype_sel)
      m16n16k16:
        begin
          m_max = M_M16N16K16;
          n_max = N_M16N16K16;
        end
      m32n8k16:
        begin
          m_max = M_M32N8K16;
          n_max = N_M32N8K16;
        end
      m8n32k16:
        begin
          m_max = M_M8N32K16;
          n_max = N_M8N32K16;
        end
      default:
        begin
          m_max = 'd0;
          n_max = 'd0;
        end
    endcase
  end

// State transition
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        current_state <= IDLE;
      end
    else
      begin
        current_state <= next_state;
      end
  end

// Next state logic
always @(*)
  begin
    case (current_state)
      IDLE:
        begin
          next_state = load_sram_start ? LOAD_SHARE_SRAM_TO_SRAMA : IDLE;
        end
      LOAD_SHARE_SRAM_TO_SRAMA:
        begin
          next_state = (counter == m_max - 1) ? LOAD_SHARE_SRAM_TO_SRAMB : LOAD_SHARE_SRAM_TO_SRAMA;
        end
      LOAD_SHARE_SRAM_TO_SRAMB:
        begin
          next_state = (counter == n_max - 1) ? WAIT_DELAY1 : LOAD_SHARE_SRAM_TO_SRAMB;
        end
      WAIT_DELAY1:
        begin
          next_state = WAIT_DELAY2;
        end
      WAIT_DELAY2:
        begin
          next_state = LOAD_AB_DONE;
        end
      LOAD_AB_DONE:
        begin
          next_state = LOAD_SHARE_SRAM_TO_SRAMC;
        end
      LOAD_SHARE_SRAM_TO_SRAMC:
        begin
          next_state = (counter == m_max - 1) ? WAIT_DELAY3 : LOAD_SHARE_SRAM_TO_SRAMC;
        end
      WAIT_DELAY3:
        begin
          next_state = WAIT_DELAY4;
        end
      WAIT_DELAY4:
        begin
          next_state = LOAD_C_DONE;
        end
      LOAD_C_DONE:
        begin
          next_state = IDLE;
        end
      default:
        begin
          next_state = IDLE;
        end
    endcase
  end

// Counter and address update
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        counter              <= 'd0;
        read_share_sram_addr <= 'd0;
        load_srama_addr      <= 'd0;
        load_sramb_addr      <= 'd0;
        load_sramc_addr      <= 'd0;
      end
    else
      begin
        case (current_state)
          LOAD_SHARE_SRAM_TO_SRAMA:
            begin
              read_share_sram_addr <= counter;
              load_srama_addr      <= counter;
              counter              <= (counter == m_max - 1) ? 'd0 : counter + 1;
            end
          LOAD_SHARE_SRAM_TO_SRAMB:
            begin
              read_share_sram_addr <= counter + OFF;
              load_sramb_addr      <= counter;
              counter              <= (counter == n_max - 1) ? 'd0 : counter + 1;
            end
          LOAD_SHARE_SRAM_TO_SRAMC:
            begin
              read_share_sram_addr <= counter + OFF + OFF;
              load_sramc_addr      <= counter;
              counter              <= (counter == m_max - 1) ? 'd0 : counter + 1;
            end
          default:
            begin
              counter              <= 'd0;
              read_share_sram_addr <= 'd0;
              load_srama_addr      <= 'd0;
              load_sramb_addr      <= 'd0;
              load_sramc_addr      <= 'd0;
            end
        endcase
      end
  end

// Control signals and data transfer
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        sram_a_wen     <= 1'b0;
        sram_b_wen     <= 1'b0;
        sram_c_wen     <= 1'b0;
        load_ab_done   <= 1'b0;
        sram_a_data_in <= 'd0;
        sram_b_data_in <= 'd0;
        sram_c_data_in <= 'd0;
      end
    else
      begin
        sram_a_data_in <= share_sram_data_out[K_SIZE*DATA_WIDTH-1:0]; // Extract lower K_SIZE data units
        sram_b_data_in <= share_sram_data_out[K_SIZE*DATA_WIDTH-1:0]; // Extract lower K_SIZE data units
        sram_c_data_in <= share_sram_data_out;

        case (current_state)
          LOAD_SHARE_SRAM_TO_SRAMA:
            begin
              sram_a_wen <= 1'b1;
            end
          LOAD_SHARE_SRAM_TO_SRAMB:
            begin
              sram_a_wen <= 1'b0;
              sram_b_wen <= 1'b1;
            end
          LOAD_AB_DONE:
            begin
              load_ab_done <= 1'b1;
            end
          LOAD_SHARE_SRAM_TO_SRAMC:
            begin
              sram_c_wen <= 1'b1;
            end
          default:
            begin
              sram_a_wen   <= 1'b0;
              sram_b_wen   <= 1'b0;
              sram_c_wen   <= 1'b0;
              load_ab_done <= 1'b0;
            end
        endcase
      end
  end

// Delay logic for address and write enable signals
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        load_srama_addr_d1 <= 'd0;
        load_srama_addr_d2 <= 'd0;
        load_sramb_addr_d1 <= 'd0;
        load_sramb_addr_d2 <= 'd0;
        load_sramc_addr_d1 <= 'd0;
        load_sramc_addr_d2 <= 'd0;
        sram_a_wen_d1      <= 1'b0;
        sram_a_wen_d2      <= 1'b0;
        sram_b_wen_d1      <= 1'b0;
        sram_b_wen_d2      <= 1'b0;
        sram_c_wen_d1      <= 1'b0;
        sram_c_wen_d2      <= 1'b0;
      end
    else
      begin
        load_srama_addr_d1 <= load_srama_addr;
        load_srama_addr_d2 <= load_srama_addr_d1;
        load_sramb_addr_d1 <= load_sramb_addr;
        load_sramb_addr_d2 <= load_sramb_addr_d1;
        load_sramc_addr_d1 <= load_sramc_addr;
        load_sramc_addr_d2 <= load_sramc_addr_d1;
        sram_a_wen_d1      <= sram_a_wen;
        sram_a_wen_d2      <= sram_a_wen_d1;
        sram_b_wen_d1      <= sram_b_wen;
        sram_b_wen_d2      <= sram_b_wen_d1;
        sram_c_wen_d1      <= sram_c_wen;
        sram_c_wen_d2      <= sram_c_wen_d1;
      end
  end

endmodule
