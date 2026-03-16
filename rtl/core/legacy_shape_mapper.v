module legacy_shape_mapper #(
    parameter SRAM_ADDR_WIDTH = 5,
    parameter ROW_INDEX_WIDTH = 6
) (
    input  wire [2:0]                    mtype_sel,
    input  wire [ROW_INDEX_WIDTH-1:0]    logical_row_idx,
    output reg  [SRAM_ADDR_WIDTH-1:0]    mapped_addr,
    output reg  [1:0]                    seg_sel,
    output reg  [2:0]                    bursts_per_row,
    output reg  [ROW_INDEX_WIDTH-1:0]    max_rows
);

localparam M16N16K16 = 3'b001;
localparam M32N8K16  = 3'b010;
localparam M8N32K16  = 3'b100;

localparam ROWS_PER_GROUP = 6'd8;
reg [ROW_INDEX_WIDTH-1:0] row_minus_group;
reg [ROW_INDEX_WIDTH-1:0] row_minus_2group;

always @(*) begin
    mapped_addr    = {SRAM_ADDR_WIDTH{1'b0}};
    seg_sel        = 2'b00;
    bursts_per_row = 3'd1;
    max_rows       = 6'd16;
    row_minus_group  = logical_row_idx - ROWS_PER_GROUP;
    row_minus_2group = logical_row_idx - (2 * ROWS_PER_GROUP);

    case (mtype_sel)
        M16N16K16: begin
            bursts_per_row = 3'd2;
            max_rows       = 6'd16;
            if (logical_row_idx < ROWS_PER_GROUP) begin
                mapped_addr = logical_row_idx[SRAM_ADDR_WIDTH-1:0];
                seg_sel     = 2'b00;
            end else if (logical_row_idx < (2 * ROWS_PER_GROUP)) begin
                mapped_addr = row_minus_group[SRAM_ADDR_WIDTH-1:0];
                seg_sel     = 2'b01;
            end else if (logical_row_idx < (3 * ROWS_PER_GROUP)) begin
                mapped_addr = row_minus_group[SRAM_ADDR_WIDTH-1:0];
                seg_sel     = 2'b00;
            end else if (logical_row_idx < (4 * ROWS_PER_GROUP)) begin
                mapped_addr = row_minus_2group[SRAM_ADDR_WIDTH-1:0];
                seg_sel     = 2'b01;
            end
        end
        M32N8K16: begin
            bursts_per_row = 3'd1;
            max_rows       = 6'd32;
            mapped_addr    = logical_row_idx[SRAM_ADDR_WIDTH-1:0];
            seg_sel        = 2'b00;
        end
        M8N32K16: begin
            bursts_per_row = 3'd4;
            max_rows       = 6'd8;
            mapped_addr    = logical_row_idx[2:0];
            if (logical_row_idx < ROWS_PER_GROUP) begin
                seg_sel = 2'b00;
            end else if (logical_row_idx < (2 * ROWS_PER_GROUP)) begin
                seg_sel = 2'b01;
            end else if (logical_row_idx < (3 * ROWS_PER_GROUP)) begin
                seg_sel = 2'b10;
            end else if (logical_row_idx < (4 * ROWS_PER_GROUP)) begin
                seg_sel = 2'b11;
            end
        end
        default: begin
            bursts_per_row = 3'd1;
            max_rows       = 6'd16;
            mapped_addr    = {SRAM_ADDR_WIDTH{1'b0}};
            seg_sel        = 2'b00;
        end
    endcase
end

endmodule
