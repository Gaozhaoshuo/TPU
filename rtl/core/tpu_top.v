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
         output wire                          tpu_done,
         output wire                          send_done
       );

// Local parameters
localparam AXI_DATA_WIDTH = SYS_ARRAY_SIZE * DATA_WIDTH; // AXI data width (256 bits)

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
wire [1:0]                          high_low_sel;
wire                                tpu_busy;

// Address multiplexing
assign share_sram_addr = share_sram_wen ? load_share_sram_addr : read_share_sram_addr;
assign sram_a_addr     = sram_a_wen ? load_srama_addr : read_srama_addr;
assign sram_b_addr     = sram_b_wen ? load_sramb_addr : read_sramb_addr;
assign sram_c_addr     = sram_c_wen ? load_sramc_addr : read_sramc_addr;
assign sram_d_addr     = sram_d_wen ? load_sramd_addr : read_sramd_addr;

// APB config register instance
apb_config_reg  apb_config_reg_inst (
                  .pclk(clk),
                  .presetn(rst_n),
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
             .send_start(tpu_done),
             .axi_target_addr(5'd0),
             .axi_lens(8'd31),
             .mtype_sel(mtype_sel),
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
              .seg_sel(high_low_sel),
              .data_in(sram_d_data_in),
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
                      .tpu_start(tpu_start),
                      .mtype_sel(mtype_sel),
                      .dtype_sel(dtype_sel),
                      .mixed_precision(mixed_precision),
                      .read_share_sram_addr(read_share_sram_addr),
                      .share_sram_data_out(share_sram_data_out),
                      .sram_a_wen(sram_a_wen),
                      .sram_b_wen(sram_b_wen),
                      .sram_c_wen(sram_c_wen),
                      .sram_d_wen(sram_d_wen),
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
                      .high_low_sel(high_low_sel),
                      .tpu_busy(tpu_busy),
                      .tpu_done(tpu_done)
                    );

endmodule