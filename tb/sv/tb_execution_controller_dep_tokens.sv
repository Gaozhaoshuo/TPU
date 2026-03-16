`timescale 1ns / 1ps

module tb_execution_controller_dep_tokens;

  reg         clk;
  reg         rst_n;
  reg         cmd_valid;
  wire        cmd_ready;
  reg  [7:0]  cmd_opcode;
  reg  [7:0]  cmd_dep_in;
  reg  [7:0]  cmd_dep_out;
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
  wire        barrier_issue_pulse;
  wire        dma_store_issue_pulse;
  wire        exec_inflight;
  wire [7:0]  completed_token;
  wire        completed_token_valid;

  execution_controller dut (
      .clk(clk),
      .rst_n(rst_n),
      .cmd_valid(cmd_valid),
      .cmd_ready(cmd_ready),
      .cmd_opcode(cmd_opcode),
      .cmd_dep_in(cmd_dep_in),
      .cmd_dep_out(cmd_dep_out),
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
      .active_dtype_sel(),
      .active_mixed_precision(),
      .active_gemm_relu_fuse(),
      .active_mtype_sel(),
      .active_waits_for_load(),
      .active_waits_for_ewise(),
      .active_waits_for_writeback(),
      .gemm_issue_pulse(),
      .dma_load_issue_pulse(),
      .dma_store_issue_pulse(dma_store_issue_pulse),
      .ewise_issue_pulse(),
      .barrier_issue_pulse(barrier_issue_pulse),
      .exec_start_pulse(),
      .exec_inflight(exec_inflight),
      .completed_token(completed_token),
      .completed_token_valid(completed_token_valid)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cmd_valid = 1'b0;
    cmd_opcode = 8'h00;
    cmd_dep_in = 8'h00;
    cmd_dep_out = 8'h00;
    cmd_dtype_sel = 3'b011;
    cmd_mixed_precision = 1'b0;
    cmd_gemm_relu_fuse = 1'b0;
    cmd_legacy_mtype_sel = 3'b001;
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
    cmd_opcode = 8'h02;
    cmd_dep_in = 8'h33;
    cmd_dep_out = 8'h44;
    cmd_is_dma_store = 1'b1;
    cmd_is_supported_dma_store = 1'b1;
    #1;
    if (cmd_ready) begin
      $display("ERROR: DMA_STORE should not be ready before dependency token 0x33 is produced");
      $finish(1);
    end

    @(negedge clk);
    cmd_valid = 1'b1;
    cmd_opcode = 8'h20;
    cmd_dep_in = 8'h00;
    cmd_dep_out = 8'h33;
    cmd_is_dma_store = 1'b0;
    cmd_is_supported_dma_store = 1'b0;
    cmd_is_barrier = 1'b1;

    @(posedge clk);
    #1;
    if (!barrier_issue_pulse) begin
      $display("ERROR: dependency-seeding BARRIER did not issue");
      $finish(1);
    end
    if (!completed_token_valid || (completed_token != 8'h33)) begin
      $display("ERROR: BARRIER did not publish completion token 0x33, got valid=%0b token=%h",
               completed_token_valid, completed_token);
      $finish(1);
    end

    @(negedge clk);
    cmd_opcode = 8'h20;
    cmd_dep_in = 8'h00;
    cmd_dep_out = 8'h55;
    cmd_is_barrier = 1'b1;
    cmd_is_dma_store = 1'b0;
    cmd_is_supported_dma_store = 1'b0;

    @(posedge clk);
    #1;
    if (!barrier_issue_pulse) begin
      $display("ERROR: second token-seeding BARRIER did not issue");
      $finish(1);
    end
    if (!completed_token_valid || (completed_token != 8'h55)) begin
      $display("ERROR: second BARRIER did not publish completion token 0x55, got valid=%0b token=%h",
               completed_token_valid, completed_token);
      $finish(1);
    end

    @(negedge clk);
    cmd_opcode = 8'h02;
    cmd_dep_in = 8'h33;
    cmd_dep_out = 8'h44;
    cmd_is_barrier = 1'b0;
    cmd_is_dma_store = 1'b1;
    cmd_is_supported_dma_store = 1'b1;
    #1;
    if (!cmd_ready) begin
      $display("ERROR: DMA_STORE should become ready after dependency token 0x33 is available");
      $finish(1);
    end

    @(posedge clk);
    #1;
    if (!dma_store_issue_pulse) begin
      $display("ERROR: DMA_STORE did not issue after dependency token was satisfied");
      $finish(1);
    end
    if (!exec_inflight) begin
      $display("ERROR: DMA_STORE should enter inflight state after issue");
      $finish(1);
    end

    cmd_valid = 1'b0;
    cmd_is_dma_store = 1'b0;
    cmd_is_supported_dma_store = 1'b0;
    cmd_opcode = 8'h00;
    cmd_dep_in = 8'h00;
    cmd_dep_out = 8'h00;

    @(negedge clk);
    writeback_done = 1'b1;
    @(posedge clk);
    #1;
    if (exec_inflight) begin
      $display("ERROR: DMA_STORE should retire after writeback_done");
      $finish(1);
    end
    if (!completed_token_valid || (completed_token != 8'h44)) begin
      $display("ERROR: DMA_STORE did not publish completion token 0x44, got valid=%0b token=%h",
               completed_token_valid, completed_token);
      $finish(1);
    end

    $display("Verification passed: execution_controller enforces dep_in/dep_out tokens.");
    $finish;
  end

endmodule
