module command_queue #(
         parameter CMD_WIDTH = 128,
         parameter DEPTH = 8,
         parameter LEVEL_WIDTH = $clog2(DEPTH + 1)
       ) (
         input  wire                  clk,
         input  wire                  rst_n,

         input  wire                  push_valid,
         output wire                  push_ready,
         input  wire [CMD_WIDTH-1:0]  push_data,

         output wire                  pop_valid,
         input  wire                  pop_ready,
         output wire [CMD_WIDTH-1:0]  pop_data,

         output wire                  empty,
         output wire                  full,
         output wire [LEVEL_WIDTH-1:0] level
       );

localparam PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

reg [CMD_WIDTH-1:0] mem [0:DEPTH-1];
reg [PTR_WIDTH-1:0] wr_ptr;
reg [PTR_WIDTH-1:0] rd_ptr;
reg [LEVEL_WIDTH-1:0] used_count;

wire push_fire;
wire pop_fire;

assign empty = (used_count == {LEVEL_WIDTH{1'b0}});
assign full  = (used_count == DEPTH[LEVEL_WIDTH-1:0]);
assign level = used_count;

assign push_ready = ~full;
assign pop_valid  = ~empty;
assign pop_data   = mem[rd_ptr];

assign push_fire = push_valid && push_ready;
assign pop_fire  = pop_valid && pop_ready;

always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        wr_ptr     <= {PTR_WIDTH{1'b0}};
        rd_ptr     <= {PTR_WIDTH{1'b0}};
        used_count <= {LEVEL_WIDTH{1'b0}};
      end
    else
      begin
        if (push_fire)
          begin
            mem[wr_ptr] <= push_data;
            if (wr_ptr == DEPTH - 1)
              wr_ptr <= {PTR_WIDTH{1'b0}};
            else
              wr_ptr <= wr_ptr + 1'b1;
          end

        if (pop_fire)
          begin
            if (rd_ptr == DEPTH - 1)
              rd_ptr <= {PTR_WIDTH{1'b0}};
            else
              rd_ptr <= rd_ptr + 1'b1;
          end

        case ({push_fire, pop_fire})
          2'b10:
            used_count <= used_count + 1'b1;
          2'b01:
            used_count <= used_count - 1'b1;
          default:
            used_count <= used_count;
        endcase
      end
  end

endmodule
