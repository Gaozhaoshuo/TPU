module systolic #(
         parameter SYS_ARRAY_SIZE = 8,     // Size of the systolic array, default is 8
         parameter DATA_WIDTH = 32     // Data width, default is 32
       ) (
         // Clock and reset
         input  wire                              clk,                 // Clock signal
         input  wire                              rst_n,               // Reset signal, active low

         // Control signals
         input  wire [2:0]                        dtype_sel,           // Operation mode selection
         input  wire                              mixed_precision,     // Mixed precision control signal
         input  wire                              compute,             // Start computation signal, active high

         // Input data queues
         input  wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0]  a_queue_in,          // Input data for A queue
         input  wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0]  b_queue_in,          // Input data for B queue
         input  wire [SYS_ARRAY_SIZE-1:0]             valid_a_queue_in,    // Valid signal for A queue
         input  wire [SYS_ARRAY_SIZE-1:0]             valid_b_queue_in,    // Valid signal for B queue

         // Output data
         output reg  signed [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] row_output,       // Row multiply-accumulate result output
         output reg                                     row_output_valid,  // Row multiply-accumulate result valid signal
         output reg                                     mul_done         // Multiply-accumulate operation completion signal
       );

// Data type modes
localparam INT4_MODE = 3'b000;  // INT4 data type mode
localparam INT8_MODE = 3'b001;  // INT8 data type mode
localparam FP16_MODE = 3'b010;  // FP16 data type mode
localparam FP32_MODE = 3'b011;  // FP32 data type mode

// Internal signals
reg  signed [DATA_WIDTH-1:0] matrix_mul_2D    [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1]; // 2D matrix for current multiply-accumulate results
wire signed [DATA_WIDTH-1:0] matrix_mul_2D_nx [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1]; // 2D matrix for next cycle multiply-accumulate results
reg  signed [DATA_WIDTH-1:0] a_queue         [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1]; // A matrix data register queue
reg  signed [DATA_WIDTH-1:0] b_queue         [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1]; // B matrix data register queue
reg                  valid_a_queue     [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1];         // A matrix data valid signal queue
reg                  valid_b_queue     [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1];         // B matrix data valid signal queue
wire                 out_valid         [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1];         // ALU output valid signal
reg                  alu_complete      [0:SYS_ARRAY_SIZE-1][0:SYS_ARRAY_SIZE-1];         // ALU completion status
reg  [SYS_ARRAY_SIZE-1:0] row_complete;                                              // Row completion flags
reg  [SYS_ARRAY_SIZE-1:0] row_done;                                                  // Row done flags for current cycle

 //解决high fanout问题
reg clean_for_queue, clean_for_alu, clean_for_matrix, clean_for_output;        
// 定义缓冲信号
wire clean_for_queue_buf;
wire clean_for_alu_buf;
wire clean_for_matrix_buf;
wire clean_for_output_buf;

// 插入缓冲器
assign clean_for_queue_buf = mul_done;
assign clean_for_alu_buf = mul_done;
assign clean_for_matrix_buf = mul_done;
assign clean_for_output_buf = mul_done;

// 修改 clean 信号生成逻辑
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        clean_for_queue  <= 1'b0;
        clean_for_alu    <= 1'b0;
        clean_for_matrix <= 1'b0;
        clean_for_output <= 1'b0;
      end
    else
      begin
        clean_for_queue  <= clean_for_queue_buf;
        clean_for_alu    <= clean_for_alu_buf;
        clean_for_matrix <= clean_for_matrix_buf;
        clean_for_output <= clean_for_output_buf;
      end
  end
integer r, c;

// Data queue update
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n || clean_for_queue)
      begin
        for (r = 0; r < SYS_ARRAY_SIZE; r = r + 1)
          begin
            for (c = 0; c < SYS_ARRAY_SIZE; c = c + 1)
              begin
                a_queue[r][c]       <= 'd0;
                b_queue[r][c]       <= 'd0;
                valid_a_queue[r][c] <= 'd0;
                valid_b_queue[r][c] <= 'd0;
              end
          end
      end
    else if (compute)
      begin
        // Update column 0 of A
        for (r = 0; r < SYS_ARRAY_SIZE; r = r + 1)
          begin
            a_queue[r][0]       <= a_queue_in[r*DATA_WIDTH +: DATA_WIDTH];
            valid_a_queue[r][0] <= valid_a_queue_in[r];
          end
        // Update row 0 of B
        for (c = 0; c < SYS_ARRAY_SIZE; c = c + 1)
          begin
            b_queue[0][c]       <= b_queue_in[c*DATA_WIDTH +: DATA_WIDTH];
            valid_b_queue[0][c] <= valid_b_queue_in[c];
          end
        // Propagate A data from left to right
        for (r = 0; r < SYS_ARRAY_SIZE; r = r + 1)
          begin
            for (c = 1; c < SYS_ARRAY_SIZE; c = c + 1)
              begin
                a_queue[r][c]       <= a_queue[r][c-1];
                valid_a_queue[r][c] <= valid_a_queue[r][c-1];
              end
          end
        // Propagate B data from top to bottom
        for (r = 1; r < SYS_ARRAY_SIZE; r = r + 1)
          begin
            for (c = 0; c < SYS_ARRAY_SIZE; c = c + 1)
              begin
                b_queue[r][c]       <= b_queue[r-1][c];
                valid_b_queue[r][c] <= valid_b_queue[r-1][c];
              end
          end
      end
  end

// Instantiate ALUs
genvar row, col;
generate
  for (row = 0; row < SYS_ARRAY_SIZE; row = row + 1)
    begin : row_gen
      for (col = 0; col < SYS_ARRAY_SIZE; col = col + 1)
        begin : col_gen
          alu u_alu (
                .clk            (clk),
                .rst_n          (rst_n),
                .valid          (valid_a_queue[row][col] & valid_b_queue[row][col]),
                .in_a_left      (a_queue[row][col]),
                .in_b_up        (b_queue[row][col]),
                .mode           (dtype_sel),
                .clean          (clean_for_alu),
                .mixed_precision(mixed_precision),
                .out_valid      (out_valid[row][col]),
                .sum            (matrix_mul_2D_nx[row][col])
              );
        end
    end
endgenerate

// Track ALU completion status and store computation results
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n || clean_for_matrix)
      begin
        for (r = 0; r < SYS_ARRAY_SIZE; r = r + 1)
          begin
            for (c = 0; c < SYS_ARRAY_SIZE; c = c + 1)
              begin
                alu_complete[r][c]  <= 'd0;
                matrix_mul_2D[r][c] <= 'd0;
              end
          end
      end
    else
      begin
        for (r = 0; r < SYS_ARRAY_SIZE; r = r + 1)
          begin
            for (c = 0; c < SYS_ARRAY_SIZE; c = c + 1)
              begin
                if (out_valid[r][c])
                  begin
                    alu_complete[r][c]  <= 1'b1;
                    matrix_mul_2D[r][c] <= matrix_mul_2D_nx[r][c];
                  end
              end
          end
      end
  end

// Output logic: check row completion, generate row_output, and update operation count
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      begin
        row_complete     <= 'd0;
        row_output       <= 'd0;
        row_output_valid <= 1'b0;
        row_done         <= 'd0;
        mul_done         <= 1'b0;
      end
    else if (clean_for_output)
      begin
        row_complete     <= 'd0;
        row_output       <= 'd0;
        row_output_valid <= 1'b0;
        row_done         <= 'd0;
        mul_done         <= 1'b0;
      end
    else
      begin
        row_output_valid <= 1'b0;
        mul_done         <= 1'b0;  // Default to low, pulse high only when operation completes

        // Check if all rows are complete for the current matrix operation
        if (&row_complete && !mul_done)
          begin
            mul_done <= 1'b1;            // Signal completion of one matrix operation
          end

        for (r = 0; r < SYS_ARRAY_SIZE; r = r + 1)
          begin
            if (!row_complete[r])
              begin
                row_done[r] = 1'b1;  // Initially assume the row is done
                for (c = 0; c < SYS_ARRAY_SIZE; c = c + 1)
                  begin
                    if (!alu_complete[r][c])
                      begin
                        row_done[r] = 1'b0;  // Row is not done if any ALU is incomplete
                      end
                  end
                if (row_done[r])
                  begin
                    row_complete[r] <= 1'b1;
                    for (c = 0; c < SYS_ARRAY_SIZE; c = c + 1)
                      begin
                        row_output[c*DATA_WIDTH +: DATA_WIDTH] <= matrix_mul_2D[r][c];
                      end
                    row_output_valid <= 1'b1;
                  end
              end
          end
      end
  end

endmodule