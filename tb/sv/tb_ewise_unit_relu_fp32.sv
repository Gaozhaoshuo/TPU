`timescale 1ns / 1ps

module tb_ewise_unit_relu_fp32;

  reg         clk;
  reg         rst_n;
  reg         start;
  reg  [2:0]  dtype_sel;
  reg         mixed_precision;
  reg  [2:0]  mtype_sel;
  wire        active;
  wire        done;
  wire        sram_d_wen;
  wire [4:0]  sram_d_addr;
  wire [1:0]  sram_d_seg_sel;
  wire [255:0] sram_d_data_in;
  wire [1023:0] sram_d_data_out;
  reg          test_done;

  ewise_unit dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .dtype_sel(dtype_sel),
      .mixed_precision(mixed_precision),
      .mtype_sel(mtype_sel),
      .sram_d_data_out(sram_d_data_out),
      .active(active),
      .done(done),
      .sram_d_wen(sram_d_wen),
      .sram_d_addr(sram_d_addr),
      .sram_d_seg_sel(sram_d_seg_sel),
      .sram_d_data_in(sram_d_data_in)
  );

  sram_segsel sram_d (
      .clk(clk),
      .wr_en(sram_d_wen),
      .addr(sram_d_addr),
      .seg_sel(sram_d_seg_sel),
      .data_in(sram_d_data_in),
      .data_out(sram_d_data_out)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;
    dtype_sel = 3'b011;
    mixed_precision = 1'b0;
    mtype_sel = 3'b100; // m8n32k16 => 8 physical rows, 4 segments each
    test_done = 1'b0;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    // Preload two rows with mixed positive/negative FP32 values.
    sram_d.memory[0] = 1024'd0;
    sram_d.memory[7] = 1024'd0;
    sram_d.memory[0][255:0]     = {32'h40400000, 32'h00000000, 32'h3E800000, 32'hBF000000,
                                   32'h40000000, 32'hC0000000, 32'h3F800000, 32'hBF800000};
    sram_d.memory[0][511:256]   = {32'h40400000, 32'h00000000, 32'h3E800000, 32'hBF000000,
                                   32'h40000000, 32'hC0000000, 32'h3F800000, 32'hBF800000};
    sram_d.memory[0][767:512]   = {32'h40400000, 32'h00000000, 32'h3E800000, 32'hBF000000,
                                   32'h40000000, 32'hC0000000, 32'h3F800000, 32'hBF800000};
    sram_d.memory[0][1023:768]  = {32'h40400000, 32'h00000000, 32'h3E800000, 32'hBF000000,
                                   32'h40000000, 32'hC0000000, 32'h3F800000, 32'hBF800000};
    sram_d.memory[7][255:0]     = {32'h3F19999A, 32'h80000000, 32'h40800000, 32'hC0800000,
                                   32'h3FC00000, 32'hBF400000, 32'h3F000000, 32'hBF800000};
    sram_d.memory[7][511:256]   = {32'h3F19999A, 32'h80000000, 32'h40800000, 32'hC0800000,
                                   32'h3FC00000, 32'hBF400000, 32'h3F000000, 32'hBF800000};
    sram_d.memory[7][767:512]   = {32'h3F19999A, 32'h80000000, 32'h40800000, 32'hC0800000,
                                   32'h3FC00000, 32'hBF400000, 32'h3F000000, 32'hBF800000};
    sram_d.memory[7][1023:768]  = {32'h3F19999A, 32'h80000000, 32'h40800000, 32'hC0800000,
                                   32'h3FC00000, 32'hBF400000, 32'h3F000000, 32'hBF800000};

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    wait(done == 1'b1);
    @(posedge clk);

    if (sram_d.memory[0][255:0] !== {32'h40400000, 32'h00000000, 32'h3E800000, 32'h00000000,
                                     32'h40000000, 32'h00000000, 32'h3F800000, 32'h00000000}) begin
      $display("ERROR: row0 segment0 relu result mismatch");
      $finish(1);
    end

    if (sram_d.memory[7][255:0] !== {32'h3F19999A, 32'h00000000, 32'h40800000, 32'h00000000,
                                     32'h3FC00000, 32'h00000000, 32'h3F000000, 32'h00000000}) begin
      $display("ERROR: row7 segment0 relu result mismatch");
      $finish(1);
    end

    if (sram_d.memory[7][511:256] !== {32'h3F19999A, 32'h00000000, 32'h40800000, 32'h00000000,
                                       32'h3FC00000, 32'h00000000, 32'h3F000000, 32'h00000000}) begin
      $display("ERROR: row7 segment1 relu result mismatch");
      $finish(1);
    end

    $display("Verification passed: EWISE unit applies FP32 RELU over SRAM-D physical rows.");
    test_done = 1'b1;
    $finish;
  end

  initial begin : timeout_block
    repeat (300) @(posedge clk);
    if (test_done)
      disable timeout_block;
    $display("ERROR: timeout waiting ewise_unit done. state=%0d row_idx=%0d seg_idx=%0d active=%0b bursts_per_row=%0d max_rows=%0d",
             dut.state, dut.row_idx, dut.seg_idx, active, dut.bursts_per_row, dut.max_rows);
    $finish(1);
  end

endmodule
