module sram_segsel (
         input  wire                      clk,
         input  wire                      wr_en,
         input  wire [4:0]                addr,
         input  wire [1:0]                seg_sel,
         input  wire [255:0]              data_in,
         output reg  [1023:0]             data_out
       );

reg [1023:0] memory [0:31];

always @(posedge clk)
  begin
    if (wr_en)
      begin
        case (seg_sel)
          2'b00:
            memory[addr][255:0]     <= data_in;
          2'b01:
            memory[addr][511:256]   <= data_in;
          2'b10:
            memory[addr][767:512]   <= data_in;
          2'b11:
            memory[addr][1023:768]  <= data_in;
          default:
            memory[addr] <= memory[addr];
        endcase
      end
    data_out <= memory[addr];
  end

endmodule
