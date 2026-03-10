module systolic_input_loader #(
    parameter SYS_ARRAY_SIZE  = 8,     // Size of the systolic array
    parameter K_SIZE          = 16,    // Size of SRAMA/B data units
    parameter DATA_WIDTH      = 32,    // Data width
    parameter SRAM_ADDR_WIDTH = 5      // Address width for SRAMA/B
) (
    // Clock and reset
    input  wire                              clk,                      // Clock signal
    input  wire                              rst_n,                    // Reset signal, active low

    // Start signals for loading systolic input
    input  wire [3:0]                        load_systolic_input_start_m16n16k16,
    input  wire [3:0]                        load_systolic_input_start_m32n8k16,
    input  wire [3:0]                        load_systolic_input_start_m8n32k16,

    // SRAM address outputs
    output reg  [SRAM_ADDR_WIDTH-1:0]        read_srama_addr,          // Read address for SRAMA
    output reg  [SRAM_ADDR_WIDTH-1:0]        read_sramb_addr,          // Read address for SRAMB

    // Systolic array inputs
    output reg  [SYS_ARRAY_SIZE-1:0]         load_en_row,           // Delayed load enable for rows
    output reg  [SYS_ARRAY_SIZE-1:0]         load_en_col            // Delayed load enable for columns
);

// State definitions
localparam IDLE        = 5'd0;  // Idle state

localparam m16n16k16_LOAD_A0_B0 = 5'd1;  // Load state for m16n16k16 (block A0, B0)
localparam m16n16k16_LOAD_A0_B1 = 5'd2;  // Load state for m16n16k16 (block A0, B1)
localparam m16n16k16_LOAD_A1_B0 = 5'd3;  // Load state for m16n16k16 (block A1, B0)
localparam m16n16k16_LOAD_A1_B1 = 5'd4;  // Load state for m16n16k16 (block A1, B1)

localparam m32n8k16_LOAD_A0_B   = 5'd5;  // Load state for m32n8k16 (block A0)
localparam m32n8k16_LOAD_A1_B   = 5'd6;  // Load state for m32n8k16 (block A1)
localparam m32n8k16_LOAD_A2_B   = 5'd7;  // Load state for m32n8k16 (block A2)
localparam m32n8k16_LOAD_A3_B   = 5'd8;  // Load state for m32n8k16 (block A3)

localparam m8n32k16_LOAD_A_B0   = 5'd9;  // Load state for m8n32k16 (block B0)
localparam m8n32k16_LOAD_A_B1   = 5'd10; // Load state for m8n32k16 (block B1)
localparam m8n32k16_LOAD_A_B2   = 5'd11; // Load state for m8n32k16 (block B2)
localparam m8n32k16_LOAD_A_B3   = 5'd12; // Load state for m8n32k16 (block B3)

localparam WAIT_DELAY1 = 5'd13; // Delay state 1
localparam WAIT_DELAY2 = 5'd14; // Delay state 2
localparam WAIT_DELAY3 = 5'd15; // Delay state 3
localparam DONE        = 5'd16; // Done state

localparam BLOCK_ADDR_OFFSET = 4'd8; // Block address offset for SRAM addressing

// Internal signals
reg [4:0] current_state;        // Current state of the FSM
reg [4:0] next_state;           // Next state of the FSM
reg [5:0] counter;              // Counter for loading cycles

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
            case (1'b1) // Priority-based selection of start signals
                load_systolic_input_start_m16n16k16[0]: next_state = m16n16k16_LOAD_A0_B0;
                load_systolic_input_start_m16n16k16[1]: next_state = m16n16k16_LOAD_A0_B1;
                load_systolic_input_start_m16n16k16[2]: next_state = m16n16k16_LOAD_A1_B0;
                load_systolic_input_start_m16n16k16[3]: next_state = m16n16k16_LOAD_A1_B1;
                load_systolic_input_start_m32n8k16[0]:  next_state = m32n8k16_LOAD_A0_B;
                load_systolic_input_start_m32n8k16[1]:  next_state = m32n8k16_LOAD_A1_B;
                load_systolic_input_start_m32n8k16[2]:  next_state = m32n8k16_LOAD_A2_B;
                load_systolic_input_start_m32n8k16[3]:  next_state = m32n8k16_LOAD_A3_B;
                load_systolic_input_start_m8n32k16[0]:  next_state = m8n32k16_LOAD_A_B0;
                load_systolic_input_start_m8n32k16[1]:  next_state = m8n32k16_LOAD_A_B1;
                load_systolic_input_start_m8n32k16[2]:  next_state = m8n32k16_LOAD_A_B2;
                load_systolic_input_start_m8n32k16[3]:  next_state = m8n32k16_LOAD_A_B3;
                default: next_state = IDLE;
            endcase
        end
        m16n16k16_LOAD_A0_B0: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;  // Move to delay state after loading
            end else begin
                next_state = m16n16k16_LOAD_A0_B0;  // Continue loading
            end
        end
        m16n16k16_LOAD_A0_B1: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m16n16k16_LOAD_A0_B1;
            end
        end
        m16n16k16_LOAD_A1_B0: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m16n16k16_LOAD_A1_B0;
            end
        end
        m16n16k16_LOAD_A1_B1: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m16n16k16_LOAD_A1_B1;
            end
        end
        m32n8k16_LOAD_A0_B: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m32n8k16_LOAD_A0_B;
            end
        end
        m32n8k16_LOAD_A1_B: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m32n8k16_LOAD_A1_B;
            end
        end
        m32n8k16_LOAD_A2_B: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m32n8k16_LOAD_A2_B;
            end
        end
        m32n8k16_LOAD_A3_B: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m32n8k16_LOAD_A3_B;
            end
        end
        m8n32k16_LOAD_A_B0: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m8n32k16_LOAD_A_B0;
            end
        end
        m8n32k16_LOAD_A_B1: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m8n32k16_LOAD_A_B1;
            end
        end
        m8n32k16_LOAD_A_B2: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m8n32k16_LOAD_A_B2;
            end
        end
        m8n32k16_LOAD_A_B3: begin
            if (counter == SYS_ARRAY_SIZE - 1) begin
                next_state = WAIT_DELAY1;
            end else begin
                next_state = m8n32k16_LOAD_A_B3;
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
            m16n16k16_LOAD_A0_B0: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter;                // Update SRAMA address
                    read_sramb_addr <= counter;                // Update SRAMB address
                end else begin
                    counter         <= 'd0;                    // Reset counter
                    read_srama_addr <= 'd0;                    // Reset address
                    read_sramb_addr <= 'd0;                    // Reset address
                end
            end
            m16n16k16_LOAD_A0_B1: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter;                // Update SRAMA address
                    read_sramb_addr <= counter + BLOCK_ADDR_OFFSET; // Offset SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m16n16k16_LOAD_A1_B0: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter + BLOCK_ADDR_OFFSET; // Offset SRAMA address
                    read_sramb_addr <= counter;                // Update SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m16n16k16_LOAD_A1_B1: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter + BLOCK_ADDR_OFFSET; // Offset SRAMA address
                    read_sramb_addr <= counter + BLOCK_ADDR_OFFSET; // Offset SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m32n8k16_LOAD_A0_B: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter;                // Update SRAMA address
                    read_sramb_addr <= counter;                // Update SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m32n8k16_LOAD_A1_B: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter + BLOCK_ADDR_OFFSET; // Offset SRAMA address
                    read_sramb_addr <= counter;                // Update SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m32n8k16_LOAD_A2_B: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter + 2*BLOCK_ADDR_OFFSET; // Offset SRAMA address
                    read_sramb_addr <= counter;                // Update SRAMB address
                end else 
                    begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m32n8k16_LOAD_A3_B: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter + 3*BLOCK_ADDR_OFFSET; // Offset SRAMA address
                    read_sramb_addr <= counter;                // Update SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m8n32k16_LOAD_A_B0: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter;                // Update SRAMA address
                    read_sramb_addr <= counter;                // Update SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m8n32k16_LOAD_A_B1: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter;                // Update SRAMA address
                    read_sramb_addr <= counter + BLOCK_ADDR_OFFSET; // Offset SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m8n32k16_LOAD_A_B2: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter;                // Update SRAMA address
                    read_sramb_addr <= counter + 2*BLOCK_ADDR_OFFSET; // Offset SRAMB address
                end else begin
                    counter         <= 'd0;
                    read_srama_addr <= 'd0;
                    read_sramb_addr <= 'd0;
                end
            end
            m8n32k16_LOAD_A_B3: begin
                if (counter < SYS_ARRAY_SIZE) begin
                    counter         <= counter + 1;
                    read_srama_addr <= counter;                // Update SRAMA address
                    read_sramb_addr <= counter + 3*BLOCK_ADDR_OFFSET; // Offset SRAMB address
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
            m16n16k16_LOAD_A0_B0, m16n16k16_LOAD_A0_B1,
            m16n16k16_LOAD_A1_B0, m16n16k16_LOAD_A1_B1,
            m32n8k16_LOAD_A0_B, m32n8k16_LOAD_A1_B,
            m32n8k16_LOAD_A2_B, m32n8k16_LOAD_A3_B,
            m8n32k16_LOAD_A_B0, m8n32k16_LOAD_A_B1,
            m8n32k16_LOAD_A_B2, m8n32k16_LOAD_A_B3,
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