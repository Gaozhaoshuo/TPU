module ewise_unit #(
         parameter SYS_ARRAY_SIZE = 8,
         parameter DATA_WIDTH = 32,
         parameter SRAM_ADDR_WIDTH = 5
       ) (
         input  wire                             clk,
         input  wire                             rst_n,
         input  wire                             start,
         input  wire [2:0]                       dtype_sel,
         input  wire                             mixed_precision,
         input  wire [2:0]                       mtype_sel,
         input  wire [SYS_ARRAY_SIZE*DATA_WIDTH*4-1:0] sram_d_data_out,

         output reg                              active,
         output reg                              done,
         output reg                              sram_d_wen,
         output reg  [SRAM_ADDR_WIDTH-1:0]       sram_d_addr,
         output reg  [1:0]                       sram_d_seg_sel,
         output reg  [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sram_d_data_in
       );

localparam [2:0] FP32_MODE = 3'b011;

localparam [2:0]
           IDLE       = 3'b000,
           READ_ROW   = 3'b001,
           CAPTURE    = 3'b010,
           WRITE_SEG  = 3'b011,
           DONE_PULSE = 3'b100;

reg [2:0] state;
reg [SRAM_ADDR_WIDTH-1:0] row_idx;
reg [2:0]                 seg_idx;
reg [SRAM_ADDR_WIDTH-1:0] prefetch_addr;
reg [SYS_ARRAY_SIZE*DATA_WIDTH*4-1:0] row_buffer;
reg [2:0]                 bursts_per_row;
reg [5:0]                 max_rows;

wire [SRAM_ADDR_WIDTH-1:0] mapper_addr_unused;
wire [1:0]                 mapper_seg_unused;
wire [2:0]                 shape_bursts_per_row;
wire [5:0]                 shape_max_rows;
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] transformed_segment;

legacy_shape_mapper #(
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .ROW_INDEX_WIDTH(6)
) u_legacy_shape_mapper (
  .mtype_sel(mtype_sel),
  .logical_row_idx(6'd0),
  .mapped_addr(mapper_addr_unused),
  .seg_sel(mapper_seg_unused),
  .bursts_per_row(shape_bursts_per_row),
  .max_rows(shape_max_rows)
);

assign transformed_segment = relu_segment(select_segment(row_buffer, seg_idx),
                                          dtype_sel,
                                          mixed_precision);

function automatic [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] select_segment;
  input [SYS_ARRAY_SIZE*DATA_WIDTH*4-1:0] row_data;
  input [2:0] segment_idx;
  begin
    case (segment_idx[1:0])
      2'b00: select_segment = row_data[255:0];
      2'b01: select_segment = row_data[511:256];
      2'b10: select_segment = row_data[767:512];
      default: select_segment = row_data[1023:768];
    endcase
  end
endfunction

function automatic [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] relu_segment;
  input [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] src;
  input [2:0]                           in_dtype_sel;
  input                                 in_mixed_precision;
  integer i;
  reg [SYS_ARRAY_SIZE*DATA_WIDTH-1:0]   tmp;
  reg [DATA_WIDTH-1:0]                  elem;
  begin
    tmp = src;
    if ((in_dtype_sel == FP32_MODE) && (~in_mixed_precision))
      begin
        for (i = 0; i < SYS_ARRAY_SIZE; i = i + 1)
          begin
            elem = src[i*DATA_WIDTH +: DATA_WIDTH];
            tmp[i*DATA_WIDTH +: DATA_WIDTH] = elem[31] ? {DATA_WIDTH{1'b0}} : elem;
          end
      end
    relu_segment = tmp;
  end
endfunction

always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        state         <= IDLE;
        row_idx       <= {SRAM_ADDR_WIDTH{1'b0}};
        seg_idx       <= 3'd0;
        prefetch_addr <= {SRAM_ADDR_WIDTH{1'b0}};
        row_buffer    <= {(SYS_ARRAY_SIZE*DATA_WIDTH*4){1'b0}};
        bursts_per_row <= 3'd0;
        max_rows      <= 6'd0;
        active        <= 1'b0;
        done          <= 1'b0;
      end
    else
      begin
        done       <= 1'b0;

        case (state)
          IDLE:
            begin
              active <= 1'b0;
              row_idx <= {SRAM_ADDR_WIDTH{1'b0}};
              seg_idx <= 3'd0;
              if (start)
                begin
                  active         <= 1'b1;
                  bursts_per_row <= shape_bursts_per_row;
                  max_rows       <= shape_max_rows;
                  prefetch_addr  <= {SRAM_ADDR_WIDTH{1'b0}};
                  state          <= READ_ROW;
                end
            end

          READ_ROW:
            begin
              state       <= CAPTURE;
            end

          CAPTURE:
            begin
              row_buffer <= sram_d_data_out;
              seg_idx    <= 3'd0;
              state      <= WRITE_SEG;
            end

          WRITE_SEG:
            begin
              if (seg_idx == bursts_per_row - 1'b1)
                begin
                  if (row_idx == max_rows[SRAM_ADDR_WIDTH-1:0] - 1'b1)
                    begin
                      active <= 1'b0;
                      state  <= DONE_PULSE;
                    end
                  else
                    begin
                      row_idx <= row_idx + 1'b1;
                      prefetch_addr <= row_idx + 1'b1;
                      state   <= READ_ROW;
                    end
                end
              else
                begin
                  seg_idx <= seg_idx + 1'b1;
                end
            end

          DONE_PULSE:
            begin
              done  <= 1'b1;
              state <= IDLE;
            end

          default:
            begin
              state <= IDLE;
            end
        endcase
      end
  end

always @(*)
  begin
    sram_d_wen     = 1'b0;
    sram_d_addr    = prefetch_addr;
    sram_d_seg_sel = 2'b00;
    sram_d_data_in = {(SYS_ARRAY_SIZE*DATA_WIDTH){1'b0}};

    if (state == WRITE_SEG)
      begin
        sram_d_wen     = 1'b1;
        sram_d_addr    = row_idx;
        sram_d_seg_sel = seg_idx[1:0];
        sram_d_data_in = transformed_segment;
      end
  end

endmodule
