`timescale 1ns / 1ps

module tb_ewise_unit_relu_fp32_m16n16;

  reg clk;
  reg rst_n;
  reg start;
  reg [2:0] dtype_sel;
  reg mixed_precision;
  reg [2:0] mtype_sel;
  wire active;
  wire done;
  wire sram_d_wen;
  wire [4:0] sram_d_addr;
  wire [1:0] sram_d_seg_sel;
  wire [255:0] sram_d_data_in;
  wire [1023:0] sram_d_data_out;

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
    mtype_sel = 3'b001; // m16n16k16 => 16 physical rows, 2 segments each

    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    sram_d.memory[0] = 1024'd0;
    sram_d.memory[1] = 1024'd0;
    sram_d.memory[0][255:0]   = {32'h40400000, 32'h00000000, 32'h3E800000, 32'hBF000000,
                                 32'h40000000, 32'hC0000000, 32'h3F800000, 32'hBF800000};
    sram_d.memory[0][511:256] = {32'h3F000000, 32'hBF800000, 32'h40800000, 32'hC0800000,
                                 32'h40A00000, 32'hC0A00000, 32'h40C00000, 32'hC0C00000};
    sram_d.memory[1][255:0]   = {32'h3F19999A, 32'h80000000, 32'h40800000, 32'hC0800000,
                                 32'h3FC00000, 32'hBF400000, 32'h3F000000, 32'hBF800000};
    sram_d.memory[1][511:256] = {32'h41200000, 32'hC1200000, 32'h41300000, 32'hC1300000,
                                 32'h41400000, 32'hC1400000, 32'h41500000, 32'hC1500000};

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

    if (sram_d.memory[0][511:256] !== {32'h3F000000, 32'h00000000, 32'h40800000, 32'h00000000,
                                       32'h40A00000, 32'h00000000, 32'h40C00000, 32'h00000000}) begin
      $display("ERROR: row0 segment1 relu result mismatch");
      $finish(1);
    end

    if (sram_d.memory[1][255:0] !== {32'h3F19999A, 32'h00000000, 32'h40800000, 32'h00000000,
                                     32'h3FC00000, 32'h00000000, 32'h3F000000, 32'h00000000}) begin
      $display("ERROR: row1 segment0 relu result mismatch");
      $finish(1);
    end

    if (sram_d.memory[1][511:256] !== {32'h41200000, 32'h00000000, 32'h41300000, 32'h00000000,
                                       32'h41400000, 32'h00000000, 32'h41500000, 32'h00000000}) begin
      $display("ERROR: row1 segment1 relu result mismatch");
      $finish(1);
    end

    $display("Verification passed: EWISE unit applies FP32 RELU over SRAM-D physical rows for m16n16.");
    $finish;
  end

endmodule
