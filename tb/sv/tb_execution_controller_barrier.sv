`timescale 1ns / 1ps

module tb_execution_controller_barrier;

  reg         clk;
  reg         rst_n;
  reg         cmd_valid;
  wire        cmd_ready;
  reg  [7:0]  cmd_opcode;
  reg  [2:0]  cmd_dtype_sel;
  reg         cmd_mixed_precision;
  reg         cmd_gemm_relu_fuse;
  reg  [2:0]  cmd_legacy_mtype_sel;
  reg         cmd_is_dma_load;
  reg         cmd_is_supported_dma_load;
  reg         cmd_is_dma_store;
  reg         cmd_is_supported_dma_store;
  reg         cmd_is_supported_gemm;
  reg         cmd_is_ewise;
  reg         cmd_is_supported_ewise;
  reg         cmd_is_barrier;
  reg         load_done;
  reg         ewise_done;
  reg         compute_done;
  reg         writeback_done;
  wire [7:0]  active_opcode;
  wire [2:0]  active_dtype_sel;
  wire        active_mixed_precision;
  wire        active_gemm_relu_fuse;
  wire [2:0]  active_mtype_sel;
  wire        active_waits_for_load;
  wire        active_waits_for_ewise;
  wire        active_waits_for_writeback;
  wire        gemm_issue_pulse;
  wire        dma_load_issue_pulse;
  wire        dma_store_issue_pulse;
  wire        ewise_issue_pulse;
  wire        barrier_issue_pulse;
  wire        exec_start_pulse;
  wire        exec_inflight;

  execution_controller dut (
      .clk(clk),
      .rst_n(rst_n),
      .cmd_valid(cmd_valid),
      .cmd_ready(cmd_ready),
      .cmd_opcode(cmd_opcode),
      .cmd_dtype_sel(cmd_dtype_sel),
      .cmd_mixed_precision(cmd_mixed_precision),
      .cmd_gemm_relu_fuse(cmd_gemm_relu_fuse),
      .cmd_legacy_mtype_sel(cmd_legacy_mtype_sel),
      .cmd_is_dma_load(cmd_is_dma_load),
      .cmd_is_supported_dma_load(cmd_is_supported_dma_load),
      .cmd_is_dma_store(cmd_is_dma_store),
      .cmd_is_supported_dma_store(cmd_is_supported_dma_store),
      .cmd_is_supported_gemm(cmd_is_supported_gemm),
      .cmd_is_ewise(cmd_is_ewise),
      .cmd_is_supported_ewise(cmd_is_supported_ewise),
      .cmd_is_barrier(cmd_is_barrier),
      .load_done(load_done),
      .ewise_done(ewise_done),
      .compute_done(compute_done),
      .writeback_done(writeback_done),
      .active_opcode(active_opcode),
      .active_dtype_sel(active_dtype_sel),
      .active_mixed_precision(active_mixed_precision),
      .active_gemm_relu_fuse(active_gemm_relu_fuse),
      .active_mtype_sel(active_mtype_sel),
      .active_waits_for_load(active_waits_for_load),
      .active_waits_for_ewise(active_waits_for_ewise),
      .active_waits_for_writeback(active_waits_for_writeback),
      .gemm_issue_pulse(gemm_issue_pulse),
      .dma_load_issue_pulse(dma_load_issue_pulse),
      .dma_store_issue_pulse(dma_store_issue_pulse),
      .ewise_issue_pulse(ewise_issue_pulse),
      .barrier_issue_pulse(barrier_issue_pulse),
      .exec_start_pulse(exec_start_pulse),
      .exec_inflight(exec_inflight)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cmd_valid = 1'b0;
    cmd_opcode = 8'h00;
    cmd_dtype_sel = 3'b000;
    cmd_mixed_precision = 1'b0;
    cmd_gemm_relu_fuse = 1'b0;
    cmd_legacy_mtype_sel = 3'b000;
    cmd_is_dma_load = 1'b0;
    cmd_is_supported_dma_load = 1'b0;
    cmd_is_dma_store = 1'b0;
    cmd_is_supported_dma_store = 1'b0;
    cmd_is_supported_gemm = 1'b0;
    cmd_is_ewise = 1'b0;
    cmd_is_supported_ewise = 1'b0;
    cmd_is_barrier = 1'b0;
    load_done = 1'b0;
    ewise_done = 1'b0;
    compute_done = 1'b0;
    writeback_done = 1'b0;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    cmd_valid = 1'b1;
    cmd_opcode = 8'h20;
    cmd_is_barrier = 1'b1;

    @(posedge clk);
    #1;
    if (!barrier_issue_pulse) begin
      $display("ERROR: barrier_issue_pulse was not asserted");
      $finish(1);
    end
    if (exec_start_pulse) begin
      $display("ERROR: BARRIER should not drive exec_start_pulse");
      $finish(1);
    end
    if (exec_inflight) begin
      $display("ERROR: BARRIER should complete immediately without inflight state");
      $finish(1);
    end
    if (active_opcode != 8'h20) begin
      $display("ERROR: active_opcode mismatch, got %h", active_opcode);
      $finish(1);
    end
    if (active_waits_for_writeback) begin
      $display("ERROR: BARRIER should not wait for writeback");
      $finish(1);
    end
    if (active_waits_for_load || active_waits_for_ewise) begin
      $display("ERROR: BARRIER should not wait for load or ewise completion");
      $finish(1);
    end
    if (active_gemm_relu_fuse) begin
      $display("ERROR: BARRIER should not latch gemm relu fuse state");
      $finish(1);
    end

    cmd_valid = 1'b0;
    cmd_is_barrier = 1'b0;
    cmd_opcode = 8'h00;

    $display("Verification passed: BARRIER command is accepted and completes in control path.");
    $finish;
  end

endmodule
