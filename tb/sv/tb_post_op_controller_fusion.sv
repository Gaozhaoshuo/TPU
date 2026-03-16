`timescale 1ns / 1ps

module tb_post_op_controller_fusion;

  reg  [7:0] active_opcode;
  reg        active_gemm_relu_fuse;
  reg        compute_done;
  reg        ewise_done;
  reg        dma_store_issue_pulse;
  wire       fused_ewise_start_pulse;
  wire       writeback_start_pulse;

  post_op_controller dut (
      .active_opcode(active_opcode),
      .active_gemm_relu_fuse(active_gemm_relu_fuse),
      .compute_done(compute_done),
      .ewise_done(ewise_done),
      .dma_store_issue_pulse(dma_store_issue_pulse),
      .fused_ewise_start_pulse(fused_ewise_start_pulse),
      .writeback_start_pulse(writeback_start_pulse)
  );

  initial begin
    active_opcode = 8'h10;
    active_gemm_relu_fuse = 1'b0;
    compute_done = 1'b0;
    ewise_done = 1'b0;
    dma_store_issue_pulse = 1'b0;

    compute_done = 1'b1;
    #1;
    if (fused_ewise_start_pulse) begin
      $display("ERROR: non-fused GEMM should not trigger fused_ewise_start_pulse");
      $finish(1);
    end
    if (!writeback_start_pulse) begin
      $display("ERROR: non-fused GEMM should trigger immediate writeback");
      $finish(1);
    end

    compute_done = 1'b0;
    active_gemm_relu_fuse = 1'b1;
    compute_done = 1'b1;
    #1;
    if (!fused_ewise_start_pulse) begin
      $display("ERROR: fused GEMM should trigger fused_ewise_start_pulse");
      $finish(1);
    end
    if (writeback_start_pulse) begin
      $display("ERROR: fused GEMM should defer writeback until ewise_done");
      $finish(1);
    end

    compute_done = 1'b0;
    ewise_done = 1'b1;
    #1;
    if (!writeback_start_pulse) begin
      $display("ERROR: fused GEMM should trigger writeback after ewise_done");
      $finish(1);
    end

    ewise_done = 1'b0;
    active_opcode = 8'h02;
    dma_store_issue_pulse = 1'b1;
    #1;
    if (!writeback_start_pulse) begin
      $display("ERROR: DMA_STORE should directly trigger writeback");
      $finish(1);
    end

    $display("Verification passed: post_op_controller sequences GEMM, fused EWISE, and DMA_STORE correctly.");
    $finish;
  end

endmodule
