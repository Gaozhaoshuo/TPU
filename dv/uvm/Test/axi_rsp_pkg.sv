package axi_rsp_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // 参数定义
  parameter AXI_DATA_WIDTH = 256;//采集的数据为256
  parameter AXI_ADDR_WIDTH = 5;
  parameter SRAM_DEPTH     = 32;
  parameter COMBINED_DATA_WIDTH = 1024;   // 组合后的数据宽度为 1024 位
  //parameter result_matrix_type_8x32  =1;
  //parameter result_matrix_type_16x16 =2;
  //parameter result_matrix_type_32x8  =3;

  // 数据传输类
  class rsp_data_trans extends uvm_sequence_item;
    // 延迟字段，用于配置 driver 行为
    rand int aw_delay;                          // AW 通道延迟
    rand int w_delay;                           // W 通道延迟
    rand int b_delay;                           // B 通道延迟
    rand bit [2:0] result_matrix_type;
    // 响应字段
    bit rsp;                                    // 响应标志
    constraint cstr{
        soft aw_delay inside {[0:2]};
        soft w_delay inside {[0:2]};
        soft b_delay inside {[0:2]};
        soft result_matrix_type inside {[0:7]};
    }
    // UVM 宏，用于字段注册
    `uvm_object_utils_begin(rsp_data_trans)
      `uvm_field_int(aw_delay, UVM_ALL_ON)
      `uvm_field_int(w_delay, UVM_ALL_ON)
      `uvm_field_int(b_delay, UVM_ALL_ON)
      `uvm_field_int(rsp, UVM_ALL_ON)
      `uvm_field_int(result_matrix_type, UVM_ALL_ON)
    `uvm_object_utils_end

    // 构造函数
    function new(string name = "rsp_data_trans");
      super.new(name);
    endfunction
  endclass

  // Driver 类
  /*//////////////
  //用来接收seq发来的配置awready和wready和bvalid的延迟
  //并将其模仿从机，返回响应信息
  /*//////////////
  class rsp_driver extends uvm_driver #(rsp_data_trans);
    `uvm_component_utils(rsp_driver)
    local virtual axi_master_intf intf;          // AXI 主接口

    int aw_delay;                               // AW 通道延迟
    int w_delay;                                // W 通道延迟
    int b_delay;                                // B 通道延迟
    // 构造函数
    function new(string name = "rsp_driver", uvm_component parent);
      super.new(name, parent);
    endfunction

    // 配置任务：接收 sequence 数据并发送响应
    task configure();
      rsp_data_trans req, rsp;
      `uvm_info("RSP_DRIVER", "Starting configure task", UVM_LOW)
      wait (intf.tpu_done == 1);                //等到tpudone，运算完
      `uvm_info("TPUDONE", "Waiting for tpudone==1", UVM_MEDIUM)
      forever begin
        `uvm_info("RSP_DRIVER", "Waiting for next item from sequencer", UVM_MEDIUM)
        seq_item_port.get_next_item(req);       // 获取 sequence item
        this.aw_delay = req.aw_delay;           // 配置 AW 延迟
        this.w_delay = req.w_delay;             // 配置 W 延迟
        this.b_delay = req.b_delay;             // 配置 B 延迟
        intf.result_matrix_type = req.result_matrix_type;//配置矩阵类型向接口发去

        `uvm_info("RSP_DRIVER", $sformatf("Received configuration: aw_delay=%0d, w_delay=%0d, b_delay=%0d", 
                  this.aw_delay, this.w_delay, this.b_delay), UVM_HIGH)
        void'($cast(rsp, req.clone()));         // 克隆请求对象
        rsp.rsp = 1;                            // 设置响应标志
        rsp.set_sequence_id(req.get_sequence_id()); // 设置序列 ID
        seq_item_port.item_done(rsp);           // 发送响应给 sequence
        `uvm_info("RSP_DRIVER", "Sent response to sequencer", UVM_MEDIUM)
      end
    endtask

    // 运行阶段
    task run_phase(uvm_phase phase);
      fork
        this.do_reset();                        // 复位任务
        this.configure();                       // 配置任务
        this.do_aw_channel();                   // AW 通道任务
        this.do_w_channel();                    // W 通道任务
        this.do_b_channel();                    // B 通道任务
      join 
      `uvm_info("RSP_DRIVER", "Finished run_phase", UVM_LOW)
    endtask

    // 复位任务
    task do_reset();
      forever begin
        `uvm_info("RSP_DRIVER", "Starting do_reset task", UVM_LOW)
        if(!intf.ARESETn)begin
        intf.AWREADY <= 0;
        intf.WREADY <= 0;
        intf.BVALID <= 0;
        intf.BRESP  <=2'b00;  
        end
        @(negedge intf.ARESETn);
        `uvm_info("RSP_DRIVER", "Reset detected, deasserting AWREADY, WREADY, BVALID", UVM_MEDIUM)
        intf.AWREADY <= 0;
        intf.WREADY <= 0;
        intf.BVALID <= 0;
        intf.BRESP  <=2'b00;
      end
    endtask

    // AW 通道任务
    task do_aw_channel();
      wait(intf.tpu_done == 1);//等到tpudone，运算完
      @(posedge intf.ACLK);
      `uvm_info("TPUDONE", "Waiting for tpudone==1", UVM_MEDIUM)
            wait(intf.AWVALID);  // 先等待有效信号
            `uvm_info("MASTER AWVALID", "Waiting for AWVALID==1", UVM_MEDIUM)
            repeat(this.aw_delay) @(posedge intf.ACLK);
            intf.AWREADY <= 1;
            @(posedge intf.ACLK iff (intf.AWVALID && intf.AWREADY)); // 握手成功
            intf.AWREADY <= 0;
    endtask

    // W 通道任务
    //WREADY 在整个突发传输期间保持高，直到最后一个数据传输完成后再置低。
    task do_w_channel();
      wait (intf.tpu_done == 1);//等到tpudone，运算完
      `uvm_info("TPUDONE", "Waiting for tpudone==1", UVM_MEDIUM)
      wait(intf.AWVALID==1&&intf.AWREADY==1);
      @(posedge intf.ACLK);
      intf.WREADY <= 1;  // 提前置高
      `uvm_info("RSP_DRIVER", "WREADT UP ==1 ", UVM_MEDIUM)
      forever begin
          @(posedge intf.ACLK);
          if (intf.WVALID && intf.WREADY && intf.WLAST) begin
              intf.WREADY <= 0;  // 仅在最后一个数据置低
              break;
          end
      end
    endtask
    // B 通道任务
    task do_b_channel();
      wait (intf.tpu_done == 1);//等到tpudone,运算完
      @(posedge intf.ACLK);
      `uvm_info("TPUDONE", "Waiting for tpudone==1", UVM_MEDIUM)
        wait(intf.WVALID==1 && intf.WREADY==1 && intf.WLAST==1); 
          `uvm_info("RSP_DRIVER", $sformatf("B channel: WLAST detected, starting B response with delay=%0d", 
                    this.b_delay), UVM_MEDIUM)
            repeat(this.b_delay) @(posedge intf.ACLK);  // 延迟响应
            intf.BVALID <= 1;
            intf.BRESP <= 2'b00;                        // OKAY 响应
            `uvm_info("RSP_DRIVER", "B channel: Asserting BVALID, BRESP=00 (OKAY)", UVM_MEDIUM)
            @(posedge intf.ACLK);
            wait(intf.BREADY==1&&intf.BVALID==1);
            `uvm_info("RSP_DRIVER", "B channel: BREADY detected, completing B handshake", UVM_MEDIUM)
            wait(intf.send_done ==1);
            `uvm_info("RSP_DRIVER", $sformatf("send_done asserted = %d at time=%0t",intf.send_done, $time), UVM_MEDIUM)
            repeat(2)@(posedge intf.ACLK);
            intf.BVALID <= 0;
            `uvm_info("RSP_DRIVER", $sformatf("send_done detected at time=%0t", $time), UVM_MEDIUM)
            `uvm_info("RSP_DRIVER", "B channel: Deasserting BVALID after handshake", UVM_MEDIUM)
    endtask

    // 设置接口函数
    function void set_interface(virtual axi_master_intf intf);
      if (intf == null) $error("Interface handle is NULL, please check!");
      else this.intf = intf;
    endfunction

  endclass

  // Sequencer 类
  class rsp_sequencer extends uvm_sequencer #(rsp_data_trans);
    `uvm_component_utils(rsp_sequencer)
    // 构造函数
    function new(string name = "rsp_sequencer", uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  // Sequence 类
  class rsp_sequence extends uvm_sequence #(rsp_data_trans);
    rand int aw_delay =-1;                          // AW 通道延迟
    rand int w_delay =-1;                           // W 通道延迟
    rand int b_delay =-1;                           // B 通道延迟
    rand bit [2:0] result_matrix_type;

    `uvm_object_utils_begin(rsp_sequence)
      `uvm_field_int(aw_delay, UVM_ALL_ON)
      `uvm_field_int(w_delay, UVM_ALL_ON)
      `uvm_field_int(b_delay, UVM_ALL_ON)
      `uvm_field_int(result_matrix_type, UVM_ALL_ON)
    `uvm_object_utils_end

    `uvm_declare_p_sequencer(rsp_sequencer)
    // 构造函数
    function new(string name = "rsp_sequence");
      super.new(name);
    endfunction

    // 主任务
    task body();
      `uvm_info("RSP_SEQUENCE", "Starting body task", UVM_LOW)
      send_trans();
      `uvm_info("RSP_SEQUENCE", "Finished body task", UVM_LOW)
    endtask

    // 发送事务任务
    task send_trans();
      rsp_data_trans req, rsp;
      `uvm_info("RSP_SEQUENCE", "Starting send_trans task", UVM_LOW)
      `uvm_do_with(req,{local::aw_delay >=0 ->aw_delay ==local::aw_delay;
                        local::w_delay >=0 ->w_delay ==local::w_delay;
                        local::b_delay >=0 ->b_delay ==local::b_delay;
                        local::result_matrix_type >=0 ->result_matrix_type ==local::result_matrix_type;
      })// 发送请求
      `uvm_info("RSP_SEQUENCE", $sformatf("Sent transaction: aw_delay=%0d, w_delay=%0d, b_delay=%0d", 
                req.aw_delay, req.w_delay, req.b_delay), UVM_MEDIUM)
      get_response(rsp);                        // 获取响应
      `uvm_info(get_type_name(), $sformatf("Received response: %s", rsp.sprint()), UVM_HIGH) // 打印响应
    endtask
  endclass

  class mon_data_trans extends uvm_sequence_item;
        bit [AXI_ADDR_WIDTH-1:0] awaddr;       // 写地址
        bit [7:0] awlen;                       // 突发长度始终为32
        bit [COMBINED_DATA_WIDTH-1:0] wdata[$];     // 存储采集到的 WDATA，并且合并起来
        bit [2:0] result_matrix_type ;

        `uvm_object_utils_begin(mon_data_trans)
            `uvm_field_int(awaddr, UVM_ALL_ON)
            `uvm_field_int(awlen, UVM_ALL_ON)
            `uvm_field_queue_int(wdata, UVM_ALL_ON)
            `uvm_field_int(result_matrix_type, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "mon_data_trans");
            super.new(name);
        endfunction
  endclass

  // Monitor 类
  class rsp_monitor extends uvm_monitor;
    `uvm_component_utils(rsp_monitor)
    local virtual axi_master_intf intf;          // AXI 从接口
    uvm_blocking_put_port#(mon_data_trans) mon_bp_port; // 监控端口

    // 构造函数
    function new(string name = "rsp_monitor", uvm_component parent);
      super.new(name, parent);
      mon_bp_port = new("mon_bp_port", this);
    endfunction

    // 运行阶段
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      // 监视器逻辑      
      `uvm_info("RSP_MONITOR", "Starting run_phase", UVM_LOW)
      this.mon_trans();
      `uvm_info("RSP_MONITOR", "Finished run_phase", UVM_LOW)
      phase.drop_objection(this);
    endtask

    // 监控事务任务
    task mon_trans();
      mon_data_trans t;
      bit [AXI_DATA_WIDTH-1:0] wdata_reordered;//存储256中的8个元素倒叙后
      bit [AXI_DATA_WIDTH-1:0] wdata_temp[$];//定义一个临时队列用于存储接口数据256
      bit[31:0]wdata_32bit[8];//拆分256数据用
      bit [COMBINED_DATA_WIDTH-1:0] combined;//用于组合临时队列的

      `uvm_info("RSP_MONITOR", "Starting mon_trans task", UVM_LOW)
      wait (intf.tpu_done == 1);//等待tpu结束信号,才可以进行采集
      `uvm_info("RSP_MONITOR", "Waiting for AW handshake", UVM_MEDIUM)
      wait(intf.AWVALID && intf.AWREADY);// 等待 AW 握手
      t = mon_data_trans::type_id::create("t"); // 创建对象
      t.awaddr = intf.AWADDR;
      t.awlen = intf.AWLEN;
      t.result_matrix_type = intf.result_matrix_type;//输出矩阵类型1：8x32,2:16x16,3:32x8

      `uvm_info("RSP_MONITOR", $sformatf("AW handshake completed: AWADDR=%0h, AWLEN=%0d", 
                  t.awaddr, t.awlen), UVM_MEDIUM)

      wdata_temp.delete();

        for (int i = 0; i <= t.awlen; i++) begin
          `uvm_info("RSP_MONITOR", $sformatf("Waiting for W handshake [%0d/%0d]", i, t.awlen), UVM_MEDIUM)
            forever begin//等待时钟握手
                  @(posedge intf.ACLK);            // 等待时钟上升沿
                  if (intf.WVALID && intf.WREADY) 
                      break;                 // 条件满足则跳出循环
            end
            `uvm_info("RSP_MONITOR", $sformatf("W handshake completed: WDATA[%0d]=%0h, WLAST=%0b", 
                    i, intf.WDATA, intf.WLAST), UVM_HIGH)
            // 拆分 256 位数据为 8 个 32 位元素
            for (int k = 0; k < 8; k++) begin
              wdata_32bit[k] = intf.WDATA[(k*32)+:32];
            end
           // 倒序排列 32 位元素并重新组成 256 位
            wdata_reordered = {wdata_32bit[0], wdata_32bit[1], wdata_32bit[2], wdata_32bit[3],
                              wdata_32bit[4], wdata_32bit[5], wdata_32bit[6], wdata_32bit[7]};

            wdata_temp.push_back(wdata_reordered);
            //wdata_temp.push_back(intf.WDATA);//推到临时存储的队列
            //`uvm_info("QUEUE DATA", $sformatf("queue data <- mon.intf.wdata completed: queue=%0p", t.wdata), UVM_HIGH)//输出是十进制的
            if (i < t.awlen) begin              // 最后一个数据不需要额外等待
                @(posedge intf.ACLK);           // 等待下一个时钟周期
            end
        end

        // 根据 result_matrix_type 填充 1024 位数据 

        case (t.result_matrix_type)
          1: begin // 8x32 matrix: 8 rows, each 1024 bits (4x256)
            if (wdata_temp.size() != 32) begin
              `uvm_error("MONITOR", "Type 1 requires exactly 32 WDATA beats")
            end
            for (int j = 0; j < 32; j += 4) begin
              combined = {wdata_temp[j], wdata_temp[j+1], wdata_temp[j+2], wdata_temp[j+3]};
              t.wdata.push_back(combined);
            end
            if (t.wdata.size() != 8) begin
              `uvm_error("MONITOR", $sformatf("Type 1: Expected 8 rows, got %0d", t.wdata.size()))
            end
          end
          2: begin // 16x16 matrix: 16 rows, each 512 bits valid (2x256), high 512 bits zero
            if (wdata_temp.size() != 32) begin
              `uvm_error("MONITOR", "Type 2 requires exactly 32 WDATA beats")
            end
            for (int j = 0; j < 32; j += 2) begin
              combined = {512'h0, wdata_temp[j], wdata_temp[j+1]}; // High 512 bits zero
              t.wdata.push_back(combined);
            end
            if (t.wdata.size() != 16) begin
              `uvm_error("MONITOR", $sformatf("Type 2: Expected 16 rows, got %0d", t.wdata.size()))
            end
          end
          3: begin // 32x8 matrix: 32 rows, each 256 bits valid (1x256), high 768 bits zero
            if (wdata_temp.size() != 32) begin
              `uvm_error("MONITOR", "Type 3 requires exactly 32 WDATA beats")
            end
            for (int j = 0; j < 32; j++) begin
              combined = {768'h0, wdata_temp[j]}; // High 768 bits zero
              t.wdata.push_back(combined);
            end
            if (t.wdata.size() != 32) begin
              `uvm_error("MONITOR", $sformatf("Type 3: Expected 32 rows, got %0d", t.wdata.size()))
            end
          end
          default: begin
            `uvm_error("MONITOR", $sformatf("Unknown result_matrix_type=%0d", t.result_matrix_type))
          end
        endcase

        `uvm_info("RSP_MONITOR", "Queue finished", UVM_MEDIUM)

        wait(intf.BVALID==1 && intf.BREADY==1);       // 等待 B 通道完成
         `uvm_info("RSP_MONITOR", "BVALID BREADY Handshake", UVM_MEDIUM)
        if (intf.BRESP != 2'b00) `uvm_error("RSP_ERROR", "BRESP is not OKAY");
        wait(intf.send_done==1);
        repeat(2)@(posedge intf.ACLK);
        `uvm_info("RSP_DRIVER", $sformatf("send_done asserted = %d at time=%0t",intf.send_done, $time), UVM_MEDIUM)
        mon_bp_port.put(t);                 // 发送事务到记分板
        `uvm_info("RSP_MONITOR", $sformatf("Sent transaction to scoreboard: %s", t.sprint()), UVM_HIGH)
      //end
    endtask

    // 设置接口函数
    function void set_interface(virtual axi_master_intf intf);
      if (intf == null) $error("Interface handle is NULL, please check!");
      else this.intf = intf;
    endfunction
  endclass

  // Agent 类
  class rsp_agent extends uvm_agent;
    `uvm_component_utils(rsp_agent)
    local virtual axi_master_intf vif;           // AXI 从接口
    rsp_driver    drv;                          // Driver 实例
    rsp_monitor   mon;                          // Monitor 实例
    rsp_sequencer sqr;                          // Sequencer 实例

    // 构造函数
    function new(string name = "rsp_agent", uvm_component parent);
      super.new(name, parent);
    endfunction

    // 构建阶段
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = rsp_driver::type_id::create("drv", this);
      mon = rsp_monitor::type_id::create("mon", this);
      sqr = rsp_sequencer::type_id::create("sqr", this);
    endfunction

    // 连接阶段
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(sqr.seq_item_export); // 连接 driver 和 sequencer
    endfunction

    // 设置接口函数
    function void set_interface(virtual axi_master_intf vif);
      if (vif == null) $error("agent don't get vif, please check!!!");
      else begin
        this.vif = vif;
        drv.set_interface(vif);
        mon.set_interface(vif);
      end
    endfunction
  endclass

endpackage