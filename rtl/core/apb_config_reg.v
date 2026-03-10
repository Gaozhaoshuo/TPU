module apb_config_reg (
    // APB interface
    input  wire       pclk,        // APB clock
    input  wire       presetn,     // APB reset, active low
    input  wire       psel,        // APB select
    input  wire       penable,     // APB enable
    input  wire       pwrite,      // APB write
    input  wire [6:0] pwdata,      // APB write data
    output reg        pready,      // APB ready
    output wire       pslverr,     // APB slave error

    // Configuration outputs
    output reg  [2:0] dtype_sel,   // Mode: INT4, INT8, FP16, FP32
    output reg  [2:0] mtype_sel,   // Matrix type: 16x16, 32x8, 8x32
    output reg        mixed_precision // Mixed precision enable
);

// State machine states
localparam [1:0]
    IDLE     = 2'b00,
    TRANSFER = 2'b01;

// Registers
reg [1:0] state;

// Slave error detection
assign pslverr = psel && penable && (
    !pwrite ||                         // Non-write request
    pwdata[6:4] == 3'b000 ||           // Invalid mtype_sel
    pwdata[3:1] == 3'b000              // Invalid dtype_sel
);

// State and control logic
always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
        state <= IDLE;
        pready <= 1'b0;
        dtype_sel <= 3'b0;
        mixed_precision <= 1'b0;
        mtype_sel <= 3'b0;
    end else begin
        pready <= 1'b0;
        case (state)
            IDLE:
                if (psel && !penable && pwrite)
                    state <= TRANSFER;
            TRANSFER:
                if (psel && penable && pwrite) begin
                    pready <= 1'b1;
                    mtype_sel <= pwdata[6:4];
                    dtype_sel <= pwdata[3:1];
                    mixed_precision <= pwdata[0];
                    state <= IDLE;
                end else begin
                    state <= IDLE;
                end
            default:
                state <= IDLE;
        endcase
    end
end

endmodule
