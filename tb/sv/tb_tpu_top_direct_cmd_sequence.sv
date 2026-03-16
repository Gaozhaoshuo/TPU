`timescale 1ns / 1ps

module tb_tpu_top_direct_cmd_sequence;

localparam MAX_DATA_SIZE         = 32;
localparam SYS_ARRAY_SIZE        = 8;
localparam K_SIZE                = 16;
localparam DATA_WIDTH            = 32;
localparam DEPTH_SHARE_SRAM      = 96;
localparam DEPTH_SRAM            = 32;
localparam SHARE_SRAM_ADDR_WIDTH = $clog2(DEPTH_SHARE_SRAM);
localparam SRAM_ADDR_WIDTH       = $clog2(DEPTH_SRAM);
localparam AXI_DATA_WIDTH        = SYS_ARRAY_SIZE * DATA_WIDTH;
localparam [7:0] OPCODE_DMA_LOAD  = 8'h01;
localparam [7:0] OPCODE_DMA_STORE = 8'h02;
localparam [7:0] OPCODE_GEMM      = 8'h10;
localparam [7:0] OPCODE_BARRIER   = 8'h20;
localparam [2:0] DTYPE_FP32       = 3'b011;

reg clk, rst_n;
reg pclk, presetn;
reg tpu_start;
reg cmd_valid_i;
wire cmd_ready_o;
reg [127:0] cmd_data_i;
reg psel, penable, pwrite;
reg [6:0] pwdata;
wire pready, pslverr;

reg s_awvalid;
wire s_awready;
reg [SHARE_SRAM_ADDR_WIDTH-1:0] s_awaddr;
reg [7:0] s_awlen;
reg [1:0] s_awburst;
reg s_wvalid;
wire s_wready;
reg [AXI_DATA_WIDTH-1:0] s_wdata;
reg s_wlast;
wire s_bvalid;
reg s_bready;
wire [1:0] s_bresp;

wire m_awvalid;
reg m_awready;
wire [SRAM_ADDR_WIDTH-1:0] m_awaddr;
wire [7:0] m_awlen;
wire [2:0] m_awsize;
wire [1:0] m_awburst;
wire m_wvalid;
reg m_wready;
wire [AXI_DATA_WIDTH-1:0] m_wdata;
wire m_wlast;
reg m_bvalid;
wire m_bready;
reg [1:0] m_bresp;
wire tpu_done;
wire send_done;

reg [31:0] matrix_A [0:255];
reg [31:0] matrix_B [0:255];
reg [31:0] matrix_C [0:255];
reg [AXI_DATA_WIDTH-1:0] data_packet_A [0:63];
reg [AXI_DATA_WIDTH-1:0] data_packet_B [0:63];
reg [AXI_DATA_WIDTH-1:0] data_packet_C [0:63];
reg [31:0] first_writeback_bits [0:255];
reg [31:0] second_writeback_bits [0:255];

integer issue_phase;
integer send_done_count;
integer aw_count;
integer tx_output_idx;
integer error_count;
integer idx;
reg [1:0] matrix_select;
reg prev_dma_load_issue;
reg prev_gemm_issue;
reg prev_barrier_issue;
reg prev_dma_store_issue;


tpu_top #(
  .MAX_DATA_SIZE(MAX_DATA_SIZE),
  .SYS_ARRAY_SIZE(SYS_ARRAY_SIZE),
  .K_SIZE(K_SIZE),
  .DATA_WIDTH(DATA_WIDTH),
  .DEPTH_SHARE_SRAM(DEPTH_SHARE_SRAM),
  .DEPTH_SRAM(DEPTH_SRAM)
) dut (
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

initial begin
  clk = 1'b0;
  pclk = 1'b0;
  forever #5 begin
    clk = ~clk;
    pclk = ~pclk;
  end
end

function automatic [127:0] build_cmd;
  input [7:0] opcode;
  input [15:0] m;
  input [15:0] n;
  input [15:0] k;
  input relu_fuse;
  begin
    build_cmd = {opcode, {1'b0, DTYPE_FP32}, 1'b0, 3'd0, 8'd0, 8'd0,
                 m, n, k, 14'd0, relu_fuse, 1'b0, 32'd0};
  end
endfunction

task pulse_reset;
  begin
    rst_n = 1'b0;
    presetn = 1'b0;
    tpu_start = 1'b0;
    cmd_valid_i = 1'b0;
    cmd_data_i = 128'd0;
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    pwdata = 7'd0;
    s_awvalid = 1'b0;
    s_awaddr = 'd0;
    s_awlen = 8'd0;
    s_awburst = 2'b00;
    s_wvalid = 1'b0;
    s_wdata = 'd0;
    s_wlast = 1'b0;
    s_bready = 1'b0;
    m_awready = 1'b1;
    m_wready = 1'b1;
    m_bvalid = 1'b0;
    m_bresp = 2'b00;
    issue_phase = 0;
    send_done_count = 0;
    aw_count = 0;
    tx_output_idx = 0;
    matrix_select = 2'd0;
    prev_dma_load_issue = 1'b0;
    prev_gemm_issue = 1'b0;
    prev_barrier_issue = 1'b0;
    prev_dma_store_issue = 1'b0;
    for (idx = 0; idx < 256; idx = idx + 1) begin
      first_writeback_bits[idx] = 32'd0;
      second_writeback_bits[idx] = 32'd0;
    end
    #20;
    rst_n = 1'b1;
    presetn = 1'b1;
    #40;
  end
endtask

task axi_write_burst;
  input [SHARE_SRAM_ADDR_WIDTH-1:0] addr;
  input [7:0] len;
  integer beat;
  begin
    @(posedge clk);
    s_awvalid <= 1'b1;
    s_awaddr <= addr;
    s_awlen <= len;
    s_awburst <= 2'b01;
    while (!s_awready) @(posedge clk);
    @(posedge clk);
    s_awvalid <= 1'b0;

    for (beat = 0; beat <= len; beat = beat + 1) begin
      @(posedge clk);
      s_wvalid <= 1'b1;
      case (matrix_select)
        2'd0: s_wdata <= data_packet_A[beat];
        2'd1: s_wdata <= data_packet_B[beat];
        default: s_wdata <= data_packet_C[beat];
      endcase
      s_wlast <= (beat == len);
      while (!s_wready) @(posedge clk);
    end
    @(posedge clk);
    s_wvalid <= 1'b0;
    s_wlast <= 1'b0;

    s_bready <= 1'b1;
    while (!s_bvalid) @(posedge clk);
    @(posedge clk);
    s_bready <= 1'b0;
  end
endtask

task load_matrices_into_share_sram;
  begin
    matrix_select <= 2'd0;
    axi_write_burst(0, 8'd63);
    matrix_select <= 2'd1;
    axi_write_burst(32, 8'd63);
    matrix_select <= 2'd2;
    axi_write_burst(64, 8'd63);
  end
endtask

task send_direct_cmd;
  input [127:0] cmd;
  reg accepted;
  begin
    accepted = 1'b0;
    @(negedge clk);
    cmd_data_i <= cmd;
    cmd_valid_i <= 1'b1;
    while (!accepted) begin
      @(posedge clk);
      if (cmd_ready_o) begin
        cmd_valid_i <= 1'b0;
        cmd_data_i <= 128'd0;
        accepted = 1'b1;
      end
    end
  end
endtask

task wait_for_two_send_done;
  integer cycles;
  begin
    cycles = 0;
    while ((send_done_count < 2) && (cycles < 12000)) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (send_done_count < 2) begin
      $display("ERROR: timeout waiting for two send_done pulses. send_done_count=%0d issue_phase=%0d active_opcode=%h exec_inflight=%0b queue_level=%0d",
               send_done_count, issue_phase, dut.active_opcode, dut.exec_inflight, dut.cmd_queue_level);
      $finish(1);
    end
  end
endtask

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    m_bvalid <= 1'b0;
    m_bresp <= 2'b00;
  end else begin
    if (m_wvalid && m_wready && m_wlast)
      m_bvalid <= 1'b1;
    else if (m_bvalid && m_bready)
      m_bvalid <= 1'b0;
  end
end

always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    send_done_count <= 0;
  else if (send_done)
    send_done_count <= send_done_count + 1;
end

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    aw_count <= 0;
    tx_output_idx <= 0;
  end else begin
    if (m_awvalid && m_awready) begin
      aw_count <= aw_count + 1;
      tx_output_idx <= 0;
    end else if (m_wvalid && m_wready) begin
      tx_output_idx <= tx_output_idx + 8;
    end
  end
end

always @(posedge clk) begin
  integer lane;
  if (m_wvalid && m_wready) begin
    for (lane = 0; lane < 8; lane = lane + 1) begin
      if ((aw_count == 1) && ((tx_output_idx + lane) < 256))
        first_writeback_bits[tx_output_idx + lane] = m_wdata[lane*32 +: 32];
      if ((aw_count == 2) && ((tx_output_idx + lane) < 256))
        second_writeback_bits[tx_output_idx + lane] = m_wdata[lane*32 +: 32];
    end
  end
end

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    prev_dma_load_issue <= 1'b0;
    prev_gemm_issue <= 1'b0;
    prev_barrier_issue <= 1'b0;
    prev_dma_store_issue <= 1'b0;
  end else begin
    if (dut.dma_load_issue_pulse && !prev_dma_load_issue) begin
      if (issue_phase != 0) begin
        $display("ERROR: DMA_LOAD issued out of order at phase %0d", issue_phase);
        $finish(1);
      end
      issue_phase = 1;
    end
    if (dut.gemm_issue_pulse && !prev_gemm_issue) begin
      if (issue_phase != 1) begin
        $display("ERROR: GEMM issued out of order at phase %0d", issue_phase);
        $finish(1);
      end
      issue_phase = 2;
    end
    if (dut.barrier_issue_pulse && !prev_barrier_issue) begin
      if (issue_phase != 2) begin
        $display("ERROR: BARRIER issued out of order at phase %0d", issue_phase);
        $finish(1);
      end
      issue_phase = 3;
    end
    if (dut.dma_store_issue_pulse && !prev_dma_store_issue) begin
      if (issue_phase != 3) begin
        $display("ERROR: DMA_STORE issued out of order at phase %0d", issue_phase);
        $finish(1);
      end
      issue_phase = 4;
    end
    prev_dma_load_issue <= dut.dma_load_issue_pulse;
    prev_gemm_issue <= dut.gemm_issue_pulse;
    prev_barrier_issue <= dut.barrier_issue_pulse;
    prev_dma_store_issue <= dut.dma_store_issue_pulse;
  end
end

initial begin : preload_and_pack
  integer row;
  integer blk;
  integer lane;

  $readmemh("data/dataset/fp32/m16n16k16/matrix_a_fp32.mem", matrix_A);
  $readmemh("data/dataset/fp32/m16n16k16/matrix_b_fp32.mem", matrix_B);
  $readmemh("data/dataset/fp32/m16n16k16/matrix_c_fp32.mem", matrix_C);

  for (row = 0; row < 16; row = row + 1) begin
    for (blk = 0; blk < 4; blk = blk + 1) begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (blk*8 + lane < 16) begin
          data_packet_A[row*4 + blk][lane*32 +: 32] = matrix_A[row*16 + (blk*8 + lane)];
          data_packet_B[row*4 + blk][lane*32 +: 32] = matrix_B[(blk*8 + lane)*16 + row];
          data_packet_C[row*4 + blk][lane*32 +: 32] = matrix_C[row*16 + (blk*8 + lane)];
        end else begin
          data_packet_A[row*4 + blk][lane*32 +: 32] = 32'd0;
          data_packet_B[row*4 + blk][lane*32 +: 32] = 32'd0;
          data_packet_C[row*4 + blk][lane*32 +: 32] = 32'd0;
        end
      end
    end
  end
end

initial begin : main_test
  pulse_reset();
  load_matrices_into_share_sram();
  #80;

  send_direct_cmd(build_cmd(OPCODE_DMA_LOAD, 16'd16, 16'd16, 16'd16, 1'b0));
  send_direct_cmd(build_cmd(OPCODE_GEMM,     16'd16, 16'd16, 16'd16, 1'b1));
  send_direct_cmd(build_cmd(OPCODE_BARRIER,  16'd16, 16'd16, 16'd16, 1'b0));
  send_direct_cmd(build_cmd(OPCODE_DMA_STORE,16'd16, 16'd16, 16'd16, 1'b0));

  wait_for_two_send_done();
  #100;

  if (issue_phase != 4) begin
    $display("ERROR: not all commands issued. issue_phase=%0d", issue_phase);
    $finish(1);
  end

  if (aw_count != 2) begin
    $display("ERROR: expected exactly 2 AXI writeback transactions, got %0d", aw_count);
    $finish(1);
  end

  error_count = 0;
  for (idx = 0; idx < 256; idx = idx + 1) begin
    if (second_writeback_bits[idx] !== first_writeback_bits[idx]) begin
      if (error_count < 16)
        $display("ERROR: writeback mismatch at idx=%0d first=0x%h second=0x%h",
                 idx, first_writeback_bits[idx], second_writeback_bits[idx]);
      error_count = error_count + 1;
    end
  end

  if (error_count != 0) begin
    $display("Verification failed: explicit DMA_STORE output mismatched fused GEMM writeback on %0d elements.", error_count);
    $finish(1);
  end

  $display("Verification passed: direct command sequence DMA_LOAD -> GEMM(relu_fuse) -> BARRIER -> DMA_STORE issued in order and both writebacks match.");
  $finish;
end

endmodule
