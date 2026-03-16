module legacy_tile_phase_mapper (
    input  wire [2:0] mtype_sel,
    input  wire [1:0] phase_idx,
    output reg  [1:0] a_block_idx,
    output reg  [1:0] b_block_idx,
    output reg        phase_valid
);

localparam M16N16K16 = 3'b001;
localparam M32N8K16  = 3'b010;
localparam M8N32K16  = 3'b100;

always @(*) begin
    a_block_idx = 2'd0;
    b_block_idx = 2'd0;
    phase_valid = 1'b0;

    case (mtype_sel)
        M16N16K16: begin
            phase_valid = 1'b1;
            case (phase_idx)
                2'd0: begin a_block_idx = 2'd0; b_block_idx = 2'd0; end
                2'd1: begin a_block_idx = 2'd0; b_block_idx = 2'd1; end
                2'd2: begin a_block_idx = 2'd1; b_block_idx = 2'd0; end
                2'd3: begin a_block_idx = 2'd1; b_block_idx = 2'd1; end
            endcase
        end
        M32N8K16: begin
            phase_valid = 1'b1;
            a_block_idx = phase_idx;
            b_block_idx = 2'd0;
        end
        M8N32K16: begin
            phase_valid = 1'b1;
            a_block_idx = 2'd0;
            b_block_idx = phase_idx;
        end
        default: begin
            a_block_idx = 2'd0;
            b_block_idx = 2'd0;
            phase_valid = 1'b0;
        end
    endcase
end

endmodule
