`timescale 1ns / 1ps

module tb_tpu_top_m16n16k16_fp32_relu_fuse_min;

localparam MAX_DATA_SIZE         = 32;
localparam SYS_ARRAY_SIZE        = 8;
localparam K_SIZE                = 16;
localparam DATA_WIDTH            = 32;
localparam DEPTH_SHARE_SRAM      = 96;
localparam DEPTH_SRAM            = 32;
localparam SHARE_SRAM_ADDR_WIDTH = $clog2(DEPTH_SHARE_SRAM);
localparam SRAM_ADDR_WIDTH       = $clog2(DEPTH_SRAM);
localparam AXI_DATA_WIDTH        = SYS_ARRAY_SIZE * DATA_WIDTH;
localparam FP32_MODE             = 3'b011;

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
reg [31:0] baseline_bits [0:255];
reg [31:0] fused_bits [0:255];
reg [31:0] observed_bits [0:255];

integer output_idx;
integer error_count;
integer sram_d_errors;
integer ewise_trace_count;
reg send_done_seen;
reg capture_enable;
reg [1:0] matrix_select;

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
    m_bvalid = 1'b0;
    m_bresp = 2'b00;
    send_done_seen = 1'b0;
    capture_enable = 1'b0;
    output_idx = 0;
    ewise_trace_count = 0;
    #20;
    rst_n = 1'b1;
    presetn = 1'b1;
    #40;
  end
endtask

task apb_write_fp32;
  input mp;
  begin
    @(posedge pclk);
    psel <= 1'b1;
    penable <= 1'b0;
    pwrite <= 1'b1;
    pwdata <= {3'b001, FP32_MODE, mp};
    @(posedge pclk);
    penable <= 1'b1;
    while (!pready) @(posedge pclk);
    psel <= 1'b0;
    penable <= 1'b0;
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

task wait_for_send_done;
  integer cycles;
  begin
    cycles = 0;
    while (!send_done_seen && cycles < 4000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (!send_done_seen) begin
      $display("ERROR: timeout waiting send_done. active_opcode=%h exec_inflight=%0b writeback_start=%0b ewise_done=%0b axi_state=%0d",
               dut.active_opcode, dut.exec_inflight, dut.writeback_start_pulse, dut.ewise_done, dut.axi_master_inst.state);
      $finish(1);
    end
  end
endtask

task run_case;
  input mp;
  integer idx;
  begin
    send_done_seen = 1'b0;
    capture_enable = 1'b1;
    output_idx = 0;
    for (idx = 0; idx < 256; idx = idx + 1)
      observed_bits[idx] = 32'd0;

    apb_write_fp32(mp);
    #20;
    load_matrices_into_share_sram();
    #110;

    tpu_start <= 1'b1;
    repeat (3) @(posedge clk);
    tpu_start <= 1'b0;

    if (mp) begin
      wait (dut.ewise_unit_inst.active == 1'b1);
      $display("EWISE config: bursts_per_row=%0d max_rows=%0d active_mtype_sel=%0b",
               dut.ewise_unit_inst.bursts_per_row,
               dut.ewise_unit_inst.max_rows,
               dut.active_mtype_sel);
    end

    wait_for_send_done();
    capture_enable = 1'b0;
    #100;
  end
endtask

always @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    send_done_seen <= 1'b0;
  else if (send_done)
    send_done_seen <= 1'b1;
end

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

always @(posedge clk) begin
  integer lane;
  if (capture_enable && m_wvalid && m_wready) begin
    for (lane = 0; lane < 8; lane = lane + 1) begin
      if (output_idx < 256) begin
        observed_bits[output_idx] = m_wdata[lane*32 +: 32];
        output_idx = output_idx + 1;
      end
    end
  end
end

always @(posedge clk) begin
  if (dut.ewise_unit_inst.active && dut.ewise_unit_inst.sram_d_wen && ewise_trace_count < 12) begin
    $display("EWISE write trace[%0d]: addr=%0d seg=%0d data[31:0]=%h data[63:32]=%h",
             ewise_trace_count,
             dut.ewise_unit_inst.sram_d_addr,
             dut.ewise_unit_inst.sram_d_seg_sel,
             dut.ewise_unit_inst.sram_d_data_in[31:0],
             dut.ewise_unit_inst.sram_d_data_in[63:32]);
    ewise_trace_count = ewise_trace_count + 1;
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
  integer idx;
  integer row;
  integer col;
  reg [31:0] ref_bits;

  m_awready = 1'b1;
  m_wready = 1'b1;

  pulse_reset();
  run_case(1'b0);
  for (idx = 0; idx < 256; idx = idx + 1)
    baseline_bits[idx] = observed_bits[idx];

  pulse_reset();
  run_case(1'b1);
  for (idx = 0; idx < 256; idx = idx + 1)
    fused_bits[idx] = observed_bits[idx];

  error_count = 0;
  sram_d_errors = 0;

  for (row = 0; row < 16; row = row + 1) begin
    for (col = 0; col < 16; col = col + 1) begin
      ref_bits = baseline_bits[row*16 + col][31] ? 32'h00000000 : baseline_bits[row*16 + col];
      if (fused_bits[row*16 + col] !== ref_bits) begin
        $display("Error: Position [%0d][%0d], fused=0x%h expected=0x%h",
                 row, col, fused_bits[row*16 + col], ref_bits);
        error_count = error_count + 1;
      end
    end
  end

  for (row = 0; row < 16; row = row + 1) begin
    if (dut.sram_d.memory[row][255:0] !== {(baseline_bits[row*16+7][31] ? 32'h0 : baseline_bits[row*16+7]),
                                           (baseline_bits[row*16+6][31] ? 32'h0 : baseline_bits[row*16+6]),
                                           (baseline_bits[row*16+5][31] ? 32'h0 : baseline_bits[row*16+5]),
                                           (baseline_bits[row*16+4][31] ? 32'h0 : baseline_bits[row*16+4]),
                                           (baseline_bits[row*16+3][31] ? 32'h0 : baseline_bits[row*16+3]),
                                           (baseline_bits[row*16+2][31] ? 32'h0 : baseline_bits[row*16+2]),
                                           (baseline_bits[row*16+1][31] ? 32'h0 : baseline_bits[row*16+1]),
                                           (baseline_bits[row*16+0][31] ? 32'h0 : baseline_bits[row*16+0])})
      sram_d_errors = sram_d_errors + 1;

    if (dut.sram_d.memory[row][511:256] !== {(baseline_bits[row*16+15][31] ? 32'h0 : baseline_bits[row*16+15]),
                                             (baseline_bits[row*16+14][31] ? 32'h0 : baseline_bits[row*16+14]),
                                             (baseline_bits[row*16+13][31] ? 32'h0 : baseline_bits[row*16+13]),
                                             (baseline_bits[row*16+12][31] ? 32'h0 : baseline_bits[row*16+12]),
                                             (baseline_bits[row*16+11][31] ? 32'h0 : baseline_bits[row*16+11]),
                                             (baseline_bits[row*16+10][31] ? 32'h0 : baseline_bits[row*16+10]),
                                             (baseline_bits[row*16+9][31] ? 32'h0 : baseline_bits[row*16+9]),
                                             (baseline_bits[row*16+8][31] ? 32'h0 : baseline_bits[row*16+8])})
      sram_d_errors = sram_d_errors + 1;
  end

  if (sram_d_errors == 0)
    $display("SRAM D physical rows match baseline-output RELU expectation.");
  else
    $display("SRAM D physical rows do not match expectation. mismatch_rows=%0d", sram_d_errors);

  if (error_count == 0)
    $display("Verification passed: fused FP32 RELU output matches baseline-output RELU over all 256 elements.");
  else
    $display("Verification failed: Found %0d element mismatches.", error_count);

  $finish;
end

endmodule
