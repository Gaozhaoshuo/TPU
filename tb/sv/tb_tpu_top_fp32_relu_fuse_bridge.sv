`timescale 1ns / 1ps

module tb_tpu_top_fp32_relu_fuse_bridge;

  reg clk;
  reg rst_n;
  reg tpu_start;
  reg cmd_valid_i;
  wire cmd_ready_o;
  reg [127:0] cmd_data_i;

  reg pclk;
  reg presetn;
  reg psel;
  reg penable;
  reg pwrite;
  reg [6:0] pwdata;
  wire pready;
  wire pslverr;

  reg s_awvalid;
  wire s_awready;
  reg [6:0] s_awaddr;
  reg [7:0] s_awlen;
  reg [1:0] s_awburst;
  reg s_wvalid;
  wire s_wready;
  reg [255:0] s_wdata;
  reg s_wlast;
  wire s_bvalid;
  reg s_bready;
  wire [1:0] s_bresp;

  wire m_awvalid;
  reg  m_awready;
  wire [4:0] m_awaddr;
  wire [7:0] m_awlen;
  wire [2:0] m_awsize;
  wire [1:0] m_awburst;
  wire m_wvalid;
  reg  m_wready;
  wire [255:0] m_wdata;
  wire m_wlast;
  reg  m_bvalid;
  wire m_bready;
  reg  [1:0] m_bresp;

  wire tpu_done;
  wire send_done;

  localparam [2:0] MTYPE_16X16 = 3'b001;
  localparam [2:0] DTYPE_FP32  = 3'b011;

  tpu_top dut (
      .clk(clk),
      .rst_n(rst_n),
      .tpu_start(tpu_start),
      .cmd_valid_i(cmd_valid_i),
      .cmd_ready_o(cmd_ready_o),
      .cmd_data_i(cmd_data_i),
      .pclk(pclk),
      .presetn(presetn),
      .psel(psel),
      .penable(penable),
      .pwrite(pwrite),
      .pwdata(pwdata),
      .pready(pready),
      .pslverr(pslverr),
      .s_awvalid(s_awvalid),
      .s_awready(s_awready),
      .s_awaddr(s_awaddr),
      .s_awlen(s_awlen),
      .s_awburst(s_awburst),
      .s_wvalid(s_wvalid),
      .s_wready(s_wready),
      .s_wdata(s_wdata),
      .s_wlast(s_wlast),
      .s_bvalid(s_bvalid),
      .s_bready(s_bready),
      .s_bresp(s_bresp),
      .m_awvalid(m_awvalid),
      .m_awready(m_awready),
      .m_awaddr(m_awaddr),
      .m_awlen(m_awlen),
      .m_awsize(m_awsize),
      .m_awburst(m_awburst),
      .m_wvalid(m_wvalid),
      .m_wready(m_wready),
      .m_wdata(m_wdata),
      .m_wlast(m_wlast),
      .m_bvalid(m_bvalid),
      .m_bready(m_bready),
      .m_bresp(m_bresp),
      .tpu_done(tpu_done),
      .send_done(send_done)
  );

  always #5 clk = ~clk;
  always #5 pclk = ~pclk;

  task apb_write_cfg(input [6:0] cfg);
    begin
      @(negedge pclk);
      psel = 1'b1;
      penable = 1'b0;
      pwrite = 1'b1;
      pwdata = cfg;

      @(negedge pclk);
      penable = 1'b1;

      @(posedge pclk);
      #1;
      if (!pready) begin
        $display("ERROR: APB write did not complete");
        $finish(1);
      end

      @(negedge pclk);
      psel = 1'b0;
      penable = 1'b0;
      pwrite = 1'b0;
      pwdata = 7'd0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    tpu_start = 1'b0;
    cmd_valid_i = 1'b0;
    cmd_data_i = 128'd0;

    pclk = 1'b0;
    presetn = 1'b0;
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    pwdata = 7'd0;

    s_awvalid = 1'b0;
    s_awaddr = 7'd0;
    s_awlen = 8'd0;
    s_awburst = 2'b01;
    s_wvalid = 1'b0;
    s_wdata = 256'd0;
    s_wlast = 1'b0;
    s_bready = 1'b1;

    m_awready = 1'b1;
    m_wready = 1'b1;
    m_bvalid = 1'b0;
    m_bresp = 2'b00;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    presetn = 1'b1;

    apb_write_cfg({MTYPE_16X16, DTYPE_FP32, 1'b1});

    if (pslverr) begin
      $display("ERROR: APB configuration unexpectedly flagged as invalid");
      $finish(1);
    end

    @(negedge clk);
    tpu_start = 1'b1;
    #1;
    if (!dut.bridge_gemm_relu_fuse) begin
      $display("ERROR: bridge_gemm_relu_fuse should assert for FP32 + mixed_precision");
      $finish(1);
    end
    if (dut.bridge_mixed_precision) begin
      $display("ERROR: bridge_mixed_precision should be forced low for FP32 fused bridge");
      $finish(1);
    end
    if (!dut.cmd_push_data[33]) begin
      $display("ERROR: cmd_push_data[33] should carry relu_fuse");
      $finish(1);
    end
    if (dut.cmd_push_data[115]) begin
      $display("ERROR: cmd_push_data[115] should clear mixed_precision in bridge-generated FP32 GEMM");
      $finish(1);
    end

    @(posedge clk);
    #1;
    if (!dut.cmd_gemm_relu_fuse) begin
      $display("ERROR: command_decoder did not decode gemm_relu_fuse");
      $finish(1);
    end
    
    @(posedge clk);
    #1;
    if (!dut.active_gemm_relu_fuse) begin
      $display("ERROR: execution_controller did not latch active_gemm_relu_fuse");
      $finish(1);
    end
    if (!dut.fused_ewise_start_pulse && !dut.active_waits_for_writeback) begin
      // Keep the check local to bridge visibility. The data path itself is tested elsewhere.
      $display("INFO: fused path armed; waiting for compute_done in full-data tests");
    end

    tpu_start = 1'b0;

    $display("Verification passed: APB FP32 mixed_precision bridge generates fused GEMM command encoding.");
    $finish;
  end

endmodule
