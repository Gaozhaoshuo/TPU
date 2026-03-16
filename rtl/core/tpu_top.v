module tpu_top #(
         parameter MAX_DATA_SIZE        = 32,    // SRAM data units
         parameter SYS_ARRAY_SIZE       = 8,     // Systolic array size
         parameter K_SIZE               = 16,    // Kernel size
         parameter DATA_WIDTH           = 32,    // Data width
         parameter DEPTH_SHARE_SRAM     = 96,    // Shared SRAM depth
         parameter DEPTH_SRAM           = 32,    // SRAM depth
         parameter SHARE_SRAM_ADDR_WIDTH = $clog2(DEPTH_SHARE_SRAM), // Shared SRAM address width
         parameter SRAM_ADDR_WIDTH      = $clog2(DEPTH_SRAM)         // SRAM address width
       )(
         // Clock and reset
         input  wire                          clk,
         input  wire                          rst_n,

         // Control signals
         input  wire                          tpu_start,
         input  wire                          cmd_valid_i,
         output wire                          cmd_ready_o,
         input  wire [127:0]                  cmd_data_i,

         // APB interface
         input  wire                          pclk,       
         input  wire                          presetn,   
         input  wire                          psel,        
         input  wire                          penable,     
         input  wire                          pwrite,    
         input  wire [6:0]                    pwdata,     
         output wire                          pready,      
         output wire                          pslverr,     

         // AXI Slave write address channel
         input  wire                          s_awvalid,
         output wire                          s_awready,
         input  wire [SHARE_SRAM_ADDR_WIDTH-1:0] s_awaddr,
         input  wire [7:0]                    s_awlen,
         input  wire [1:0]                    s_awburst,

         // AXI Slave write data channel
         input  wire                          s_wvalid,
         output wire                          s_wready,
         input  wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] s_wdata,
         input  wire                          s_wlast,

         // AXI Slave write response channel
         output wire                          s_bvalid,
         input  wire                          s_bready,
         output wire  [1:0]                   s_bresp,

         // AXI Master write address channel
         output wire                          m_awvalid,
         input  wire                          m_awready,
         output wire  [SRAM_ADDR_WIDTH-1:0]   m_awaddr,
         output wire  [7:0]                   m_awlen,
         output wire  [2:0]                   m_awsize,
         output wire  [1:0]                   m_awburst,

         // AXI Master write data channel
         output wire                          m_wvalid,
         input  wire                          m_wready,
         output wire  [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] m_wdata,
         output wire                          m_wlast,

         // AXI Master write response channel
         input  wire                          m_bvalid,
         output wire                          m_bready,
         input  wire [1:0]                    m_bresp,

         // Output signals
         output wire                          tpu_done,   // One-cycle pulse when compute stage completes
         output wire                          send_done   // One-cycle pulse when AXI write-back completes
       );

// Local parameters
localparam AXI_DATA_WIDTH = SYS_ARRAY_SIZE * DATA_WIDTH; // AXI data width (256 bits)
localparam CMD_WIDTH = 128;
localparam [7:0] OPCODE_GEMM = 8'h10;
localparam [2:0] DTYPE_FP32 = 3'b011;

// SRAM interface signals
// Write addresses
wire [SHARE_SRAM_ADDR_WIDTH-1:0] load_share_sram_addr;
wire [SRAM_ADDR_WIDTH-1:0]       load_srama_addr;
wire [SRAM_ADDR_WIDTH-1:0]       load_sramb_addr;
wire [SRAM_ADDR_WIDTH-1:0]       load_sramc_addr;
wire [SRAM_ADDR_WIDTH-1:0]       load_sramd_addr;

// Read addresses
wire [SHARE_SRAM_ADDR_WIDTH-1:0] read_share_sram_addr;
wire [SRAM_ADDR_WIDTH-1:0]       read_srama_addr;
wire [SRAM_ADDR_WIDTH-1:0]       read_sramb_addr;
wire [SRAM_ADDR_WIDTH-1:0]       read_sramc_addr;
wire  [SRAM_ADDR_WIDTH-1:0]      read_sramd_addr;

// Multiplexed addresses
wire [SHARE_SRAM_ADDR_WIDTH-1:0] share_sram_addr;
wire [SRAM_ADDR_WIDTH-1:0]       sram_a_addr;
wire [SRAM_ADDR_WIDTH-1:0]       sram_b_addr;
wire [SRAM_ADDR_WIDTH-1:0]       sram_c_addr;
wire [SRAM_ADDR_WIDTH-1:0]       sram_d_addr;

// Write enables
wire                             share_sram_wen;
wire                             sram_a_wen;
wire                             sram_b_wen;
wire                             sram_c_wen;
wire                             sram_d_wen_raw;
wire                             sram_d_wen;

// Write data
wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] share_sram_data_in;
wire [K_SIZE*DATA_WIDTH-1:0]        sram_a_data_in;
wire [K_SIZE*DATA_WIDTH-1:0]        sram_b_data_in;
wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] sram_c_data_in;
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sram_d_data_in;

// Read data
wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] share_sram_data_out;
wire [K_SIZE*DATA_WIDTH-1:0]        sram_a_data_out;
wire [K_SIZE*DATA_WIDTH-1:0]        sram_b_data_out;
wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] sram_c_data_out;
wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] sram_d_data_out;

// Configuration outputs
wire [2:0] dtype_sel;   // Mode: INT4, INT8, FP16, FP32
wire [2:0] mtype_sel;   // Matrix type: 16x16, 32x8, 8x32
wire mixed_precision;   // Mixed precision enable

// Other control signals
wire                                tpu_busy;

// Command queue signals
wire [CMD_WIDTH-1:0]                cmd_push_data;
wire                                cmd_push_ready;
wire                                cmd_pop_valid;
wire                                cmd_pop_ready;
wire [CMD_WIDTH-1:0]                cmd_pop_data;
wire                                cmd_queue_empty;
wire                                cmd_queue_full;
wire [3:0]                          cmd_queue_level;
wire                                exec_cmd_ready;
wire                                legacy_cmd_push_valid;
wire                                direct_cmd_push_valid;
wire                                cmd_push_valid;

// Decoded command fields for the legacy GEMM bridge
wire [7:0]                          cmd_opcode;
wire [15:0]                         cmd_m;
wire [15:0]                         cmd_n;
wire [15:0]                         cmd_k;
wire                                cmd_gemm_relu_fuse;
wire [15:0]                         legacy_cfg_m;
wire [15:0]                         legacy_cfg_n;
wire [15:0]                         legacy_cfg_k;
wire [2:0]                          cmd_layout;
wire [7:0]                          cmd_dep_in;
wire [7:0]                          cmd_dep_out;
wire [2:0]                          cmd_legacy_mtype_sel;
wire [2:0]                          cmd_legacy_dtype_sel;
wire                                cmd_legacy_mixed_precision;
wire                                cmd_is_supported_gemm;
wire                                cmd_is_dma_load;
wire                                cmd_is_supported_dma_load;
wire                                cmd_is_dma_store;
wire                                cmd_is_supported_dma_store;
wire                                cmd_is_ewise;
wire                                cmd_is_supported_ewise;
wire                                cmd_is_barrier;
wire                                legacy_cfg_valid;
reg                                 sram_d_readback_active;

wire [2:0]                          active_mtype_sel;
wire [2:0]                          active_dtype_sel;
wire                                active_mixed_precision;
wire                                active_gemm_relu_fuse;
wire [7:0]                          active_opcode;
wire                                active_waits_for_load;
wire                                active_waits_for_ewise;
wire                                active_waits_for_writeback;
wire                                cmd_start_pulse;
wire                                exec_inflight;
wire                                gemm_issue_pulse;
wire                                dma_load_issue_pulse;
wire                                dma_store_issue_pulse;
wire                                ewise_issue_pulse;
wire                                barrier_issue_pulse;
wire                                dma_load_done;
wire                                ewise_done;
wire                                ewise_active;
wire                                ewise_sram_d_wen;
wire [SRAM_ADDR_WIDTH-1:0]          ewise_sram_d_addr;
wire [1:0]                          ewise_sram_d_seg_sel;
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] ewise_sram_d_data_in;
wire [1:0]                          controller_high_low_sel;
wire [1:0]                          sram_d_seg_sel;
wire                                sram_d_wen_src;
wire                                fused_ewise_start_pulse;
wire                                writeback_start_pulse;
wire                                bridge_gemm_relu_fuse;
wire                                bridge_mixed_precision;

// Address multiplexing
assign share_sram_addr = share_sram_wen ? load_share_sram_addr : read_share_sram_addr;
assign sram_a_addr     = sram_a_wen ? load_srama_addr : read_srama_addr;
assign sram_b_addr     = sram_b_wen ? load_sramb_addr : read_sramb_addr;
assign sram_c_addr     = sram_c_wen ? load_sramc_addr : read_sramc_addr;
assign sram_d_addr     = ewise_active ? ewise_sram_d_addr :
                         sram_d_wen ? load_sramd_addr : read_sramd_addr;
assign sram_d_wen_src  = ewise_active ? ewise_sram_d_wen : sram_d_wen_raw;
assign sram_d_wen      = sram_d_wen_src && (~sram_d_readback_active);
assign sram_d_seg_sel  = ewise_active ? ewise_sram_d_seg_sel : controller_high_low_sel;

assign cmd_pop_ready = exec_cmd_ready;
assign cmd_ready_o = cmd_push_ready && direct_cmd_push_valid;
assign bridge_gemm_relu_fuse = (dtype_sel == DTYPE_FP32) && mixed_precision;
assign bridge_mixed_precision = (dtype_sel == DTYPE_FP32) ? 1'b0 : mixed_precision;
assign direct_cmd_push_valid = cmd_valid_i;
assign legacy_cmd_push_valid = tpu_start && (~direct_cmd_push_valid);
assign cmd_push_valid = direct_cmd_push_valid || legacy_cmd_push_valid;

assign cmd_push_data =
  direct_cmd_push_valid ? cmd_data_i :
  legacy_cfg_valid ? {OPCODE_GEMM, {1'b0, dtype_sel}, bridge_mixed_precision, 3'd0, 8'd0, 8'd0, legacy_cfg_m, legacy_cfg_n, legacy_cfg_k, 14'd0, bridge_gemm_relu_fuse, 1'b0, 32'd0} :
  {CMD_WIDTH{1'b0}};

always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        sram_d_readback_active <= 1'b0;
      end
    else
      begin
        if (writeback_start_pulse)
          sram_d_readback_active <= 1'b1;
        else if (send_done)
          sram_d_readback_active <= 1'b0;
      end
  end

// APB config register instance
apb_config_reg  apb_config_reg_inst (
                  .pclk(pclk),
                  .presetn(presetn),
                  .psel(psel),
                  .penable(penable),
                  .pwrite(pwrite),
                  .pwdata(pwdata),
                  .pready(pready),
                  .pslverr(pslverr),
                  .dtype_sel(dtype_sel),
                  .mtype_sel(mtype_sel),
                  .mixed_precision(mixed_precision)
                );

// Minimal internal command path:
// pack the current APB-programmed mode into a GEMM command, then issue it
// through command_queue before driving the legacy controller.
legacy_shape_codec legacy_shape_codec_inst (
                     .mtype_sel(mtype_sel),
                     .m(legacy_cfg_m),
                     .n(legacy_cfg_n),
                     .k(legacy_cfg_k),
                     .mtype_valid(legacy_cfg_valid),
                     .decode_m(16'd0),
                     .decode_n(16'd0),
                     .decode_k(16'd0),
                     .decoded_mtype_sel(),
                     .mnk_valid()
                   );

command_queue #(
                .CMD_WIDTH(CMD_WIDTH),
                .DEPTH(8)
              ) command_queue_inst (
                .clk(clk),
                .rst_n(rst_n),
                .push_valid(cmd_push_valid),
                .push_ready(cmd_push_ready),
                .push_data(cmd_push_data),
                .pop_valid(cmd_pop_valid),
                .pop_ready(cmd_pop_ready),
                .pop_data(cmd_pop_data),
                .empty(cmd_queue_empty),
                .full(cmd_queue_full),
                .level(cmd_queue_level)
              );

command_decoder #(
                  .CMD_WIDTH(CMD_WIDTH)
                ) command_decoder_inst (
                  .cmd_data(cmd_pop_data),
                  .opcode(cmd_opcode),
                  .dtype_sel(cmd_legacy_dtype_sel),
                  .mixed_precision(cmd_legacy_mixed_precision),
                  .layout(cmd_layout),
                  .dep_in(cmd_dep_in),
                  .dep_out(cmd_dep_out),
                  .m(cmd_m),
                  .n(cmd_n),
                  .k(cmd_k),
                  .gemm_relu_fuse(cmd_gemm_relu_fuse),
                  .legacy_mtype_sel(cmd_legacy_mtype_sel),
                  .is_dma_load(cmd_is_dma_load),
                  .is_supported_dma_load(cmd_is_supported_dma_load),
                  .is_dma_store(cmd_is_dma_store),
                  .is_supported_dma_store(cmd_is_supported_dma_store),
                  .is_gemm(),
                  .is_ewise(cmd_is_ewise),
                  .is_supported_ewise(cmd_is_supported_ewise),
                  .is_barrier(cmd_is_barrier),
                  .is_supported_gemm(cmd_is_supported_gemm)
                );

execution_controller execution_controller_inst (
                       .clk(clk),
                       .rst_n(rst_n),
                       .cmd_valid(cmd_pop_valid),
                       .cmd_ready(exec_cmd_ready),
                       .cmd_opcode(cmd_opcode),
                       .cmd_dep_in(cmd_dep_in),
                       .cmd_dep_out(cmd_dep_out),
                       .cmd_dtype_sel(cmd_legacy_dtype_sel),
                       .cmd_mixed_precision(cmd_legacy_mixed_precision),
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
                       .load_done(dma_load_done),
                       .ewise_done(ewise_done),
                       .compute_done(tpu_done),
                       .writeback_done(send_done),
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
                       .exec_start_pulse(cmd_start_pulse),
                       .exec_inflight(exec_inflight),
                       .completed_token(),
                       .completed_token_valid()
                     );

post_op_controller post_op_controller_inst (
                   .active_opcode(active_opcode),
                   .active_gemm_relu_fuse(active_gemm_relu_fuse),
                   .compute_done(tpu_done),
                   .ewise_done(ewise_done),
                   .dma_store_issue_pulse(dma_store_issue_pulse),
                   .fused_ewise_start_pulse(fused_ewise_start_pulse),
                   .writeback_start_pulse(writeback_start_pulse)
                 );

ewise_unit #(
            .SYS_ARRAY_SIZE(SYS_ARRAY_SIZE),
            .DATA_WIDTH(DATA_WIDTH),
            .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH)
          ) ewise_unit_inst (
            .clk(clk),
            .rst_n(rst_n),
            .start(ewise_issue_pulse || fused_ewise_start_pulse),
            .dtype_sel(active_dtype_sel),
            .mixed_precision(active_mixed_precision),
            .mtype_sel(active_mtype_sel),
            .sram_d_data_out(sram_d_data_out),
            .active(ewise_active),
            .done(ewise_done),
            .sram_d_wen(ewise_sram_d_wen),
            .sram_d_addr(ewise_sram_d_addr),
            .sram_d_seg_sel(ewise_sram_d_seg_sel),
            .sram_d_data_in(ewise_sram_d_data_in)
          );

// AXI Master instance
axi_master #(
             .MAX_DATA_SIZE(MAX_DATA_SIZE),
             .DATA_WIDTH(DATA_WIDTH),
             .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
             .DEPTH_SRAM(DEPTH_SRAM)
           ) axi_master_inst (
             .aclk(clk),
             .aresetn(rst_n),
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
             .read_sramd_addr(read_sramd_addr),
             .sram_d_data_out(sram_d_data_out),
             .send_start(writeback_start_pulse),
             .axi_target_addr(5'd0), // Current implementation always writes back from base address 0
             .axi_lens(8'd31),       // Current implementation uses a fixed 32-beat AXI burst
             .mtype_sel(active_mtype_sel),
             .send_done(send_done)
           );

// AXI Slave instance
axi_slave #(
            .MAX_DATA_SIZE(MAX_DATA_SIZE),
            .DATA_WIDTH(DATA_WIDTH),
            .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
            .DEPTH_SHARE_SRAM(DEPTH_SHARE_SRAM)
          ) axi_slave_inst (
            .aclk(clk),
            .aresetn(rst_n),
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
            .tpu_busy(tpu_busy),
            .share_sram_wen(share_sram_wen),
            .share_sram_wdata(share_sram_data_in),
            .load_share_sram_addr(load_share_sram_addr)
          );

// Share SRAM
sram #(
       .DEPTH(DEPTH_SHARE_SRAM),
       .SIZE(MAX_DATA_SIZE),
       .DATA_WIDTH(DATA_WIDTH)
     ) share_sram (
       .clk(clk),
       .we(share_sram_wen),
       .addr(share_sram_addr),
       .data_in(share_sram_data_in),
       .data_out(share_sram_data_out)
     );

// SRAM A
sram #(
       .DEPTH(DEPTH_SRAM),
       .SIZE(K_SIZE),
       .DATA_WIDTH(DATA_WIDTH)
     ) sram_a (
       .clk(clk),
       .we(sram_a_wen),
       .addr(sram_a_addr),
       .data_in(sram_a_data_in),
       .data_out(sram_a_data_out)
     );

// SRAM B
sram #(
       .DEPTH(DEPTH_SRAM),
       .SIZE(K_SIZE),
       .DATA_WIDTH(DATA_WIDTH)
     ) sram_b (
       .clk(clk),
       .we(sram_b_wen),
       .addr(sram_b_addr),
       .data_in(sram_b_data_in),
       .data_out(sram_b_data_out)
     );

// SRAM C
sram #(
       .DEPTH(DEPTH_SRAM),
       .SIZE(MAX_DATA_SIZE),
       .DATA_WIDTH(DATA_WIDTH)
     ) sram_c (
       .clk(clk),
       .we(sram_c_wen),
       .addr(sram_c_addr),
       .data_in(sram_c_data_in),
       .data_out(sram_c_data_out)
     );

// SRAM D with segment selection
sram_segsel sram_d (
              .clk(clk),
              .wr_en(sram_d_wen),
              .addr(sram_d_addr),
              .seg_sel(sram_d_seg_sel),
              .data_in(ewise_active ? ewise_sram_d_data_in : sram_d_data_in),
              .data_out(sram_d_data_out)
            );

// Systolic controller
systolic_controller #(
                      .MAX_DATA_SIZE(MAX_DATA_SIZE),
                      .SYS_ARRAY_SIZE(SYS_ARRAY_SIZE),
                      .K_SIZE(K_SIZE),
                      .DATA_WIDTH(DATA_WIDTH),
                      .SHARE_SRAM_ADDR_WIDTH(SHARE_SRAM_ADDR_WIDTH),
                      .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH)
                    ) systolic_controller_inst (
                      .clk(clk),
                      .rst_n(rst_n),
                      .tpu_start(cmd_start_pulse),
                      .dma_load_start(dma_load_issue_pulse),
                      .mtype_sel(active_mtype_sel),
                      .dtype_sel(active_dtype_sel),
                      .mixed_precision(active_mixed_precision),
                      .read_share_sram_addr(read_share_sram_addr),
                      .share_sram_data_out(share_sram_data_out),
                      .sram_a_wen(sram_a_wen),
                      .sram_b_wen(sram_b_wen),
                      .sram_c_wen(sram_c_wen),
                      .sram_d_wen(sram_d_wen_raw),
                      .sram_a_data_in(sram_a_data_in),
                      .sram_b_data_in(sram_b_data_in),
                      .sram_c_data_in(sram_c_data_in),
                      .sram_d_data_in(sram_d_data_in),
                      .load_srama_addr(load_srama_addr),
                      .load_sramb_addr(load_sramb_addr),
                      .load_sramc_addr(load_sramc_addr),
                      .load_sramd_addr(load_sramd_addr),
                      .read_srama_addr(read_srama_addr),
                      .read_sramb_addr(read_sramb_addr),
                      .read_sramc_addr(read_sramc_addr),
                      .sram_a_data_out(sram_a_data_out),
                      .sram_b_data_out(sram_b_data_out),
                      .sram_c_data_out(sram_c_data_out),
                      .high_low_sel(controller_high_low_sel),
                      .tpu_busy(tpu_busy),
                      .tpu_done(tpu_done),
                      .load_done(dma_load_done)
                    );

endmodule
