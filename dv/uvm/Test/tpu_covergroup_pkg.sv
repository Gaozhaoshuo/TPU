package tpu_covergroup_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
class tpu_covergroup extends uvm_component;
    local virtual axi_slave_intf  axi_sla_if;
    local virtual axi_master_intf axi_mas_if;
    local virtual apb_reg_intf    apb_reg_if;

    `uvm_component_utils(tpu_covergroup)

    covergroup cg_reg_apb;//APB配置的覆盖
        //矩阵类型
        matrix_type:coverpoint apb_reg_if.PWDATA[6:4]{
            bins m_tpye[] = {3'b001,3'b010,3'b100};//m16n16k16,m32n8k16,..
        }
        //数据类型
        data_type:coverpoint apb_reg_if.PWDATA[3:1]{
            bins d_type[] = {3'b000,3'b001,3'b010,3'b011};
        }
        // 混合精度使能
        MIX_ENABLE: coverpoint apb_reg_if.PWDATA[0] {
            bins MIX_OFF = {0};
            bins MIX_ON  = {1};
        }
    endgroup

    covergroup cg_sla_axi;//slave接口配置的覆盖
        //突发长度
        sla_awlen:coverpoint axi_sla_if.AWLEN{
            bins s_awlen[] = {7'd31,7'd63,7'd127};//8*4-1/16*4-1/32*4-1
        }
        //突发地址,三个矩阵存储地址
        sla_addr:coverpoint axi_sla_if.AWADDR{
            bins s_awaddr[] = {7'd0,7'd32,7'd64};//A矩阵起始地址0。。。
        }
        // 突发方式
        sla_burst: coverpoint axi_sla_if.AWBURST {
           bins INCR = {2'b01}; // 仅支持 INCR
        }
        // TPU 控制信号
        tpu_start: coverpoint axi_sla_if.tpu_start {
            bins START_UP = (0 => 1); // 触发并拉低
            bins START_DOWN = (1 => 0); // 触发并拉低
        }
    endgroup

    covergroup cg_mas_axi;//master接口的覆盖
        // TPU 控制信号
        TPU_DONE: coverpoint axi_mas_if.tpu_done {
            bins DONE_TRANSITION_UP= (0 => 1); // 从 0 到 1 的转换
            bins DONE_TRANSITION_DOWN= (1 => 0); // 从 1 到 0 的转换
        }
        SEND_DONE: coverpoint axi_mas_if.send_done {
            bins DONE_SEND = (0 => 1 ); // 触发发送完
        }
    endgroup

    function new (string name ="tpu_covergroup",uvm_component parent);
        super.new(name,parent);
        cg_mas_axi = new();
        cg_reg_apb = new();
        cg_sla_axi = new();
    endfunction

    task run_phase(uvm_phase phase);
        fork
            this.do_mas_sample();
            this.do_reg_sample();
            this.do_sla_sample();
        join
    endtask

    function void set_interface(virtual axi_slave_intf axi_sla_if,
                                virtual axi_master_intf axi_mas_if,
                                virtual apb_reg_intf    apb_reg_if
    );
    this.axi_sla_if = axi_sla_if;
    this.axi_mas_if = axi_mas_if;
    this.apb_reg_if = apb_reg_if;
        if(axi_sla_if ==null)begin
            `uvm_error("TPU_COUVER_INTF","axi_sla_if = null")
         end   
        if(axi_mas_if ==null)begin
            `uvm_error("TPU_COUVER_INTF","axi_mas_if = null")
         end   
        if(apb_reg_if ==null)begin
            `uvm_error("TPU_COUVER_INTF","apb_reg_if = null")
         end   
    endfunction


    task do_reg_sample();//寄存器的采样
      forever begin
        @(posedge apb_reg_if.PCLK iff apb_reg_if.PRESETn);
        this.cg_reg_apb.sample();
      end
    endtask

    task do_sla_sample();//从接口的采样
      forever begin
        @(posedge axi_sla_if.ACLK iff axi_sla_if.ARESETn);
                this.cg_sla_axi.sample();
      end
    endtask

    task do_mas_sample();//从接口的采样
      forever begin
        @(posedge axi_mas_if.ACLK iff axi_mas_if.ARESETn);
                this.cg_mas_axi.sample();
      end
    endtask


endclass
endpackage



