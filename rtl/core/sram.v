module sram #(
         parameter DEPTH       = 32,    // Depth of the SRAM (number of rows)
         parameter SIZE        = 16,    // Number of data units per row
         parameter DATA_WIDTH  = 32     // Width of each data unit
       ) (
         // Clock and control signals
         input  wire                      clk,        // Clock signal
         input  wire                      we,      // Write enable, active high
         input  wire [$clog2(DEPTH)-1:0]  addr,       // Address line, width is log2(DEPTH)

         // Data interface
         input  wire [SIZE*DATA_WIDTH-1:0] data_in,   // Input data, width is SIZE * DATA_WIDTH
         output reg  [SIZE*DATA_WIDTH-1:0] data_out   // Output data, width is SIZE * DATA_WIDTH
       );

// Memory array: DEPTH rows, each row is SIZE * DATA_WIDTH bits
reg [SIZE*DATA_WIDTH-1:0] memory [0:DEPTH-1];

// Read and write operations
always @(posedge clk)
  begin
    if (we)
      begin
        memory[addr] <= data_in;  // Write data to memory when we is high
      end
    data_out <= memory[addr];     // Always read data from memory
  end

endmodule
