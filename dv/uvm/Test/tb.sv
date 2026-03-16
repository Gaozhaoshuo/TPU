
interface axi_slave_intf(input bit ACLK, input bit ARESETn);
  parameter  AXI_ADDR_WIDTH= 7;
  parameter  AXI_DATA_WIDTH=256;
    // 信号定义
    logic AWVALID;
    logic AWREADY;
    logic [AXI_ADDR_WIDTH-1:0] AWADDR;
    logic [7:0] AWLEN;
    logic [1:0] AWBURST;
    logic WVALID;
    logic WREADY;
    logic [AXI_DATA_WIDTH-1:0] WDATA;
    logic WLAST;
    //响应
    logic BVALID;
    logic BREADY;
    logic [1:0] BRESP;
    logic tpu_start;

endinterface

interface axi_master_intf(input bit ACLK, input bit ARESETn);
  parameter  AXI_ADDR_WIDTH= $clog2(SRAM_DEPTH);
  parameter  AXI_DATA_WIDTH=256;
  parameter  SRAM_DEPTH    =32;
  // AXI 写地址通道
  logic                           AWVALID;
  logic                           AWREADY;
  logic  [AXI_ADDR_WIDTH-1:0]     AWADDR;
  logic  [7:0]                    AWLEN;   // 由 DUT 输出的 AWLEN
  logic  [2:0]                    AWSIZE;  // 当前 DUT 固定为 3'b101，对应 32 bytes / 256 bits
  logic  [1:0]                    AWBURST; // 当前 DUT 固定为 INCR(2'b01)
    
  // AXI 写数据通道
  logic                       WVALID;
  logic                       WREADY;
  logic  [AXI_DATA_WIDTH-1:0] WDATA;
  logic                       WLAST;
    
  // AXI 写响应通道
  logic                           BVALID;
  logic                           BREADY;
  logic  [1:0]                    BRESP;

  logic                           tpu_done; // 计算完成脉冲
  logic                           send_done; // 写回完成脉冲
  logic [2:0]                     result_matrix_type;
  /*modport master(
    input  clk, rst_n, awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid,
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready
  );*/

endinterface

interface apb_reg_intf(input bit PCLK, input bit PRESETn);

  logic PSEL;            // APB 选择信号
  logic PENABLE;         // APB 使能信号
  logic PWRITE;          // APB 写信号
  logic [6:0] PWDATA;   // APB 写数据主要控制此数据
  logic [31:0] PRDATA;  // APB 读数据
  logic PREADY;         // APB 准备好信号
  logic PSLVERR;        // APB 从设备错误信号

endinterface
`timescale 1ns/1ps
module tb();
    logic clk;
    logic rst_n;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tpu_refmod_random_pkg::*; 
    import tpu_checker_pkg::*;
    import apb_reg_pkg::*;
    import axi_rsp_pkg::*;
    import axi_data_pkg::*; 
    import tpu_pkg::*;

    axi_slave_intf  axi_sla_if(clk,rst_n);
    axi_master_intf axi_mas_if(clk,rst_n);
    apb_reg_intf    apb_reg_if(clk,rst_n);
    //generation clk;  
  initial begin 
    clk <= 0;
    forever begin
      #5 clk <= !clk;
    end
  end
    //generation rst_n;
    initial begin 
    #10 rst_n <= 0;
    repeat(2) @(posedge clk);
    rst_n <= 1;
  end                                                                                   
  
  tpu_top dut_tpu_top(
  // Clock and reset
      .clk                                (clk                       ),
      .rst_n                              (rst_n                     ),
  // Control signals
      .tpu_start                          (axi_sla_if.tpu_start                 ),
  // APB interface
      .pclk                               (apb_reg_if.PCLK                      ),
      .presetn                            (apb_reg_if.PRESETn                   ),
      .psel                               (apb_reg_if.PSEL                      ),
      .penable                            (apb_reg_if.PENABLE                   ),
      .pwrite                             (apb_reg_if.PWRITE                    ),
      .pwdata                             (apb_reg_if.PWDATA                    ),
      .pready                             (apb_reg_if.PREADY                    ),
      .pslverr                            (apb_reg_if.PSLVERR                   ),
  // AXI Slave write address channel
      .s_awvalid                          (axi_sla_if.AWVALID                 ),
      .s_awready                          (axi_sla_if.AWREADY                 ),
      .s_awaddr                           (axi_sla_if.AWADDR                  ),
      .s_awlen                            (axi_sla_if.AWLEN                   ),
      .s_awburst                          (axi_sla_if.AWBURST                 ),
  // AXI Slave write data channel
      .s_wvalid                           (axi_sla_if.WVALID                  ),
      .s_wready                           (axi_sla_if.WREADY                  ),
      .s_wdata                            (axi_sla_if.WDATA                   ),
      .s_wlast                            (axi_sla_if.WLAST                   ),
  // AXI Slave write response channel
      .s_bvalid                           (axi_sla_if.BVALID                  ),
      .s_bready                           (axi_sla_if.BREADY                  ),
      .s_bresp                            (axi_sla_if.BRESP                   ),
  // AXI Master write address channel
      .m_awvalid                          (axi_mas_if.AWVALID                 ),
      .m_awready                          (axi_mas_if.AWREADY                 ),
      .m_awaddr                           (axi_mas_if.AWADDR                  ),
      .m_awlen                            (axi_mas_if.AWLEN                   ),
      .m_awsize                           (axi_mas_if.AWSIZE                  ),
      .m_awburst                          (axi_mas_if.AWBURST                 ),
  // AXI Master write data channel
      .m_wvalid                           (axi_mas_if.WVALID                  ),
      .m_wready                           (axi_mas_if.WREADY                  ),
      .m_wdata                            (axi_mas_if.WDATA                   ),
      .m_wlast                            (axi_mas_if.WLAST                   ),
  // AXI Master write response channel
      .m_bvalid                           (axi_mas_if.BVALID                  ),
      .m_bready                           (axi_mas_if.BREADY                  ),
      .m_bresp                            (axi_mas_if.BRESP                   ),
  // Output signals
      .tpu_done                           (axi_mas_if.tpu_done                ),
      .send_done                          (axi_mas_if.send_done               )
  );

    initial begin
        //send intf to uvm_config_db's root.uvm_test_top.intf
        uvm_config_db#(virtual axi_slave_intf)::set(null,"uvm_test_top","axi_sla_vif",axi_sla_if);
        uvm_config_db#(virtual axi_master_intf)::set(null,"uvm_test_top","axi_mas_vif",axi_mas_if);
        uvm_config_db#(virtual apb_reg_intf)::set(null,"uvm_test_top","apb_reg_vif",apb_reg_if);
       run_test("tpu_case2_test");//run_test("tpu_case1_test");只需要改数字改case

    end


endmodule
//vsim -novopt -classdebug -coverage -coverstore D:/1Study_work/UVM/TPU/UVM/cover_sum work.tb 
//vsim -novopt -classdebug +UVM_TESTNAME=tpu_case0_test -coverage -coverstore D:/1Study_work/UVM/TPU/UVM/cover_sum -testname tpu_case0_test work.tb
//调用不同的case，在命令行修改即可
//合并覆盖率vcover merge -out merged_coverage.ucdb D:/1Study_work/UVM/TPU/UVM/cover_sum
// vcover merge -out D:/1Study_work/UVM/TPU/UVM/cover_sum/merged_coverage.ucdb D:/1Study_work/UVM/TPU/UVM/cover_sum
//do D:/1Study_work/UVM/TPU/UVM/Test/tpu_simulation.tcl
