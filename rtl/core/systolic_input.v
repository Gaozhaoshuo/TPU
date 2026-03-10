module systolic_input #(
         parameter SYS_ARRAY_SIZE  = 8,    // Size of the systolic array
         parameter K_SIZE      = 16,    // Size of input data units
         parameter DATA_WIDTH  = 32    // Data width
       ) (
         // Clock and reset
         input  wire                              clk,            // Clock signal
         input  wire                              rst_n,          // Reset signal, active low

         // Control signals
         input  wire [SYS_ARRAY_SIZE-1:0]             load_en_row,    // Load enable signal for rows
         input  wire [SYS_ARRAY_SIZE-1:0]             load_en_col,    // Load enable signal for columns

         // Input data
         input  wire [K_SIZE*DATA_WIDTH-1:0]      row_data_in,    // Row input data
         input  wire [K_SIZE*DATA_WIDTH-1:0]      col_data_in,    // Column input data

         // Output data
         output wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0]  row_data_out,   // Row output data
         output wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0]  col_data_out,   // Column output data
         output wire [SYS_ARRAY_SIZE-1:0]             row_data_out_valid, // Row output data valid signal
         output wire [SYS_ARRAY_SIZE-1:0]             col_data_out_valid  // Column output data valid signal
       );

// Generate row shift registers
genvar a;
generate
  for (a = 0; a < SYS_ARRAY_SIZE; a = a + 1)
    begin : row_shift_reg_gen
      shift_register #(
                       .K_SIZE      (K_SIZE),
                       .DATA_WIDTH  (DATA_WIDTH)
                     ) row_shift_reg (
                       .clk            (clk),
                       .rst_n          (rst_n),
                       .load_en        (load_en_row[a]),
                       .data_in        (row_data_in),
                       .data_out       (row_data_out[a*DATA_WIDTH +: DATA_WIDTH]),
                       .data_out_valid (row_data_out_valid[a])
                     );
    end
endgenerate

// Generate column shift registers
genvar b;
generate
  for (b = 0; b < SYS_ARRAY_SIZE; b = b + 1)
    begin : col_shift_reg_gen
      shift_register #(
                       .K_SIZE      (K_SIZE),
                       .DATA_WIDTH  (DATA_WIDTH)
                     ) col_shift_reg (
                       .clk            (clk),
                       .rst_n          (rst_n),
                       .load_en        (load_en_col[b]),
                       .data_in        (col_data_in),
                       .data_out       (col_data_out[b*DATA_WIDTH +: DATA_WIDTH]),
                       .data_out_valid (col_data_out_valid[b])
                     );
    end
endgenerate

endmodule

module shift_register #(
    parameter K_SIZE      = 16,    // Number of data units
    parameter DATA_WIDTH  = 32    // Data width, default is 32
  ) (
    // Clock and reset
    input  wire                       clk,            // Clock signal
    input  wire                       rst_n,          // Reset signal, active low

    // Control signal
    input  wire                       load_en,        // Load enable signal

    // Input and output data
    input  wire [K_SIZE*DATA_WIDTH-1:0] data_in,      // Input data, total width is K_SIZE * DATA_WIDTH
    output reg  [DATA_WIDTH-1:0]        data_out,     // Output data, width is DATA_WIDTH
    output reg                          data_out_valid // Output data valid signal
  );

// Internal signals
reg [K_SIZE*DATA_WIDTH-1:0] shift_reg;     // Shift register to store K_SIZE data units of DATA_WIDTH bits
reg [$clog2(K_SIZE):0]      shift_count;    // Counter for shift operations, width adaptive to K_SIZE
reg                         shifting;       // Shift state flag: 1 for shifting, 0 for idle

// Shift register logic
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        shift_reg      <= 'd0;
        data_out       <= 'd0;
        data_out_valid <= 1'b0;
        shift_count    <= 'd0;
        shifting       <= 1'b0;
      end
    else
      begin
        if (load_en)
          begin
            // Load input data in parallel and initialize shift state
            shift_reg      <= data_in;
            shift_count    <= 'd0;
            shifting       <= 1'b1;
            data_out_valid <= 1'b0;
          end
        else if (shifting)
          begin
            if (shift_count < K_SIZE)
              begin
                // Right shift by SHIFT_WIDTH bits, output the lowest DATA_WIDTH bits
                shift_reg <= {{DATA_WIDTH{1'b0}}, shift_reg[K_SIZE*DATA_WIDTH-1:DATA_WIDTH]};
                data_out <= shift_reg[DATA_WIDTH-1:0];
                data_out_valid <= 1'b1;
                shift_count    <= shift_count + 1;
              end
            else
              begin
                // Shift complete, stop and reset
                shift_reg      <= 'd0;
                data_out       <= 'd0;
                data_out_valid <= 1'b0;
                shifting       <= 1'b0;
              end
          end
        else
          begin
            data_out       <= 'd0;
            data_out_valid <= 1'b0;
          end
      end
  end

endmodule
