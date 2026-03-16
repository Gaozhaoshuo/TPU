module systolic_input_loader #(
    parameter SYS_ARRAY_SIZE  = 8,     // Size of the systolic array
    parameter K_SIZE          = 16,    // Size of SRAMA/B data units
    parameter DATA_WIDTH      = 32,    // Data width
    parameter SRAM_ADDR_WIDTH = 5      // Address width for SRAMA/B
) (
    // Clock and reset
    input  wire                              clk,                      // Clock signal
    input  wire                              rst_n,                    // Reset signal, active low

    // Start signal for loading one legacy phase
    input  wire [2:0]                        mtype_sel,
    input  wire [3:0]                        load_systolic_input_start,

    // SRAM address outputs
    output reg  [SRAM_ADDR_WIDTH-1:0]        read_srama_addr,          // Read address for SRAMA
    output reg  [SRAM_ADDR_WIDTH-1:0]        read_sramb_addr,          // Read address for SRAMB

    // Systolic array inputs
    output reg  [SYS_ARRAY_SIZE-1:0]         load_en_row,           // Delayed load enable for rows
    output reg  [SYS_ARRAY_SIZE-1:0]         load_en_col            // Delayed load enable for columns
);

// State definitions
localparam IDLE        = 4'd0;  // Idle state
localparam LOAD_PHASE0 = 4'd1;
localparam LOAD_PHASE1 = 4'd2;
localparam LOAD_PHASE2 = 4'd3;
localparam LOAD_PHASE3 = 4'd4;
localparam WAIT_DELAY1 = 4'd5; // Delay state 1
localparam WAIT_DELAY2 = 4'd6; // Delay state 2
localparam WAIT_DELAY3 = 4'd7; // Delay state 3
localparam DONE        = 4'd8; // Done state

localparam BLOCK_ADDR_OFFSET = 4'd8; // Block address offset for SRAM addressing

// Internal signals
reg [3:0] current_state;        // Current state of the FSM
reg [3:0] next_state;           // Next state of the FSM
reg [5:0] counter;              // Counter for loading cycles
wire [1:0] active_phase_idx;
wire [1:0] a_block_idx;
wire [1:0] b_block_idx;
wire       phase_cfg_valid;

assign active_phase_idx = current_state - LOAD_PHASE0;

legacy_tile_phase_mapper u_legacy_tile_phase_mapper (
    .mtype_sel(mtype_sel),
    .phase_idx(active_phase_idx),
    .a_block_idx(a_block_idx),
    .b_block_idx(b_block_idx),
    .phase_valid(phase_cfg_valid)
);

// State transition logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;         // Reset to idle state
    end else begin
        current_state <= next_state;   // Transition to next state
    end
end

// Next state logic
always @(*) begin
    case (current_state)
        IDLE: begin
            case (1'b1) // Priority-based selection of phase start
                load_systolic_input_start[0]: next_state = LOAD_PHASE0;
                load_systolic_input_start[1]: next_state = LOAD_PHASE1;
                load_systolic_input_start[2]: next_state = LOAD_PHASE2;
                load_systolic_input_start[3]: next_state = LOAD_PHASE3;
                default: next_state = IDLE;
            endcase
        end
        LOAD_PHASE0, LOAD_PHASE1, LOAD_PHASE2, LOAD_PHASE3: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = current_state;
            end
        end
        WAIT_DELAY1: begin
            next_state = WAIT_DELAY2;      // Progress through delay states
        end
        WAIT_DELAY2: begin
            next_state = WAIT_DELAY3;
        end
        WAIT_DELAY3: begin
            next_state = DONE;             // Finish delay and move to done
        end
        DONE: begin
            next_state = IDLE;             // Return to idle after completion
        end
        default: begin
            next_state = IDLE;             // Default to idle state
        end
    endcase
end

// Counter and address generation logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter         <= 'd0;            // Reset counter
        read_srama_addr <= 'd0;            // Reset SRAMA address
        read_sramb_addr <= 'd0;            // Reset SRAMB address
    end else begin
        case (current_state)
            LOAD_PHASE0, LOAD_PHASE1, LOAD_PHASE2, LOAD_PHASE3: begin
                if (counter < SYS_ARRAY_SIZE && phase_cfg_valid) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter + (a_block_idx * BLOCK_ADDR_OFFSET);
                    read_sramb_addr <= counter + (b_block_idx * BLOCK_ADDR_OFFSET);
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            WAIT_DELAY1, WAIT_DELAY2, WAIT_DELAY3: begin
                counter         <= 'd0;                    // Reset counter during delay
                read_srama_addr <= 'd0;                    // Reset SRAMA address
                read_sramb_addr <= 'd0;                    // Reset SRAMB address
            end
            DONE: begin
                counter         <= 'd0;                    // Reset counter when done
                read_srama_addr <= 'd0;                    // Reset SRAMA address
                read_sramb_addr <= 'd0;                    // Reset SRAMB address
            end
            default: begin
                counter         <= 'd0;                    // Default reset for counter
                read_srama_addr <= 'd0;                    // Default reset for SRAMA address
                read_sramb_addr <= 'd0;                    // Default reset for SRAMB address
            end
        endcase
    end
end

// Control signals and data transfer logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        load_en_row <= 'd0;         // Reset row load enable
        load_en_col <= 'd0;         // Reset column load enable
    end else begin
        case (current_state)
            LOAD_PHASE0, LOAD_PHASE1, LOAD_PHASE2, LOAD_PHASE3,
            WAIT_DELAY1: begin
            load_en_row <= (1 << counter - 1);  // counter - 1等待数据信号延迟
            load_en_col <= (1 << counter - 1);  
            end
            default: begin
                load_en_row <= 'd0;             // Default disable for row load enable
                load_en_col <= 'd0;             // Default disable for column load enable
            end
        endcase
    end
end

endmodule
