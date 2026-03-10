package axi_data_pkg;
    import uvm_pkg::*;
  `include "uvm_macros.svh"
    parameter AXI_ADDR_WIDTH = 7;
    parameter AXI_DATA_WIDTH =256;

    class data_trans extends uvm_sequence_item;//发送到interface(dut)上的数据
        // AXI4 协议字段
        rand bit [AXI_ADDR_WIDTH-1:0] awaddr;      // 写地址（写入 SRAM）
        rand bit [7:0] awlen;        // 写突发长度 8、16、32
        rand bit [1:0] awburst;      // 写突发类型 01->INCR
        rand bit [AXI_DATA_WIDTH-1:0] wdata[];       // 写数据（一整个矩阵元素）
        bit       wlast;//发送终止信号C 
        bit rsp;

        // 约束
        constraint addr_range { soft awaddr inside {7'd0,7'd32,7'd64}; }//A,B,C地址起始
        constraint len_range  { soft awlen inside {7,15,31};}//突发长度
        constraint burst_type { soft awburst inside {1};}
        constraint wdata_cst      {
                                soft wdata.size() == awlen+1;//wdata这个数组被定义为awlen+1长度，awlen+1=突发长度
                                // (wdata[i]) //确定数据
                                //wdata[i] == (i+1)<<2;//(trans数据产生)
        }

        function new(string name = "data_trans");
            super.new(name);
            wdata = new[0];
            `uvm_info("DATA_TRANS", $sformatf("Created data_trans instance: %s", name), UVM_MEDIUM)
        endfunction

        `uvm_object_utils_begin(data_trans)
        `uvm_field_int(awaddr, UVM_ALL_ON)
        `uvm_field_array_int(wdata, UVM_ALL_ON)
        `uvm_field_int(awlen, UVM_ALL_ON)
        `uvm_field_int(awburst, UVM_ALL_ON) 
        `uvm_field_int(wlast, UVM_ALL_ON) 
        `uvm_field_int(rsp, UVM_ALL_ON) 
        `uvm_object_utils_end

    endclass

    class data_driver extends uvm_driver#(data_trans);
        `uvm_component_utils(data_driver)
        local virtual axi_slave_intf intf;
        bit is_tpu_done = 0; // 新增状态标志
        function new(string name ="data_driver",uvm_component parent);
            super.new(name,parent);
        endfunction
        
        task run_phase(uvm_phase phase);
            `uvm_info("DATA_DRIVER", "Starting run_phase", UVM_LOW)
            fork
            this.do_drive();//将数据驱动到interface
            this.do_reset();//复位接口信号
            this.monitor_tpu_done();
            join
            `uvm_info("DATA_DRIVER", "Finished run_phase", UVM_LOW)
        endtask
        
        task do_reset();
            `uvm_info("DATA_DRIVER", "Starting do_reset task", UVM_LOW)
            forever begin
                // 检查当前状态，如果已经是 0，则立即复位
            if (intf.ARESETn == 0) begin
                `uvm_info("DATA_DRIVER", "Reset signal is already low, resetting interface signals", UVM_MEDIUM)
                intf.AWVALID <= 0;
                intf.AWADDR <= 0;
                intf.AWLEN <= 0;
                intf.AWBURST <= 0;
                intf.WVALID <= 0;
                intf.WDATA <= 0;
                intf.WLAST <= 0;
                intf.tpu_start <= 0;
                is_tpu_done = 0; // 复位时重置状态
            end
            //出现下降沿也立即复位
            @(negedge intf.ARESETn); 
                `uvm_info("DATA_DRIVER", "Reset detected, resetting interface signals", UVM_MEDIUM)    
                intf.AWVALID <= 0;//仿
                intf.AWADDR <= 0;
                intf.AWLEN <= 0;
                intf.AWBURST <= 0;
                intf.WVALID <= 0;
                intf.WDATA <= 0;
                intf.WLAST <= 0;
                intf.tpu_start <= 0;
                is_tpu_done = 0; // 复位时重置状态
            end
        endtask
        
        task monitor_tpu_done();
            forever begin
                @(posedge intf.ACLK);
                if (intf.tpu_start == 1'b1) begin
                    @(negedge intf.tpu_start); // 等待tpu_start拉低
                    is_tpu_done = 1; // TPU计算完成
                    `uvm_info("DATA_DRIVER", "TPU computation done, stopping further transactions", UVM_MEDIUM)
                end
            end
        endtask

        task do_drive();
            data_trans req, rsp;
            `uvm_info("DATA_DRIVER", "Starting do_drive task", UVM_LOW)
            @(posedge intf.ARESETn);
            `uvm_info("DATA_DRIVER", "Reset deasserted, starting to drive transactions", UVM_MEDIUM)
            forever begin
                if (is_tpu_done) begin
                    `uvm_info("DATA_DRIVER", "TPU done, stopping do_drive", UVM_MEDIUM)
                    break; // TPU计算完成后退出循环
                end
                `uvm_info("DATA_DRIVER", "Waiting for next transaction", UVM_HIGH)
                seq_item_port.get_next_item(req);//driver主动拿去数据
                `uvm_info("DATA_DRIVER", $sformatf("Received transaction: %s", req.sprint()), UVM_HIGH)
                this.data_write(req);//写入interface
                void'($cast(rsp, req.clone()));//克隆一个
                rsp.rsp = 1;//将rsp置1
                rsp.set_sequence_id(req.get_sequence_id());
                `uvm_info("DATA_DRIVER", $sformatf("Sending response: %s", rsp.sprint()), UVM_HIGH)
                seq_item_port.item_done(rsp);
            end
        endtask

        task data_write(data_trans t);
            `uvm_info("DATA_DRIVER", "Starting data_write task", UVM_LOW)
            begin
                // 断言检查 wdata 数组大小是否等于 awlen + 1
                assert (t.wdata.size() == t.awlen + 1)
                else $error("wdata size (%0d) does not match awlen + 1 (%0d) at time %0t", 
                        t.wdata.size(), t.awlen + 1, $time);
                @(posedge intf.ACLK);
                `uvm_info("DATA_DRIVER", "Driving AW channel signals", UVM_MEDIUM)
                intf.AWVALID <= 1'b1;
                intf.AWADDR  <= t.awaddr;//发送过来的地址，提前把三个矩阵的地址约束好
                /*if(t.awaddr==7'd64)begin
                    tpu_start_s<=1'b1;
                end 
                else begin
                    tpu_start_s <=1'b0;
                end*/
                intf.AWLEN <= t.awlen;
                intf.AWBURST <= t.awburst;
                `uvm_info("DATA_DRIVER", $sformatf("AWADDR=%0h, AWLEN=%0d, AWBURST=%0b", 
                            intf.AWADDR, intf.AWLEN, intf.AWBURST), UVM_HIGH)
                wait(intf.AWREADY&&intf.AWVALID);//地址握手成功
                `uvm_info("DATA_DRIVER", "AW handshake completed", UVM_MEDIUM)
                @(posedge intf.ACLK);
                intf.AWVALID <=1'b0;//地址已经握手成功，就可拉低
                //下个周期发送数据
                foreach(t.wdata[i]) begin
                    @(posedge intf.ACLK);//下个周期再发数据
                    intf.WVALID <=1'b1;
                    intf.WDATA <= t.wdata[i];
                    intf.WLAST <= (i==(t.wdata.size()-1));  //wlast信号，在一次突发的最后一个数据来的时候发出
                    `uvm_info("DATA_DRIVER", $sformatf("Driving WDATA[%0d]=%0h, WLAST=%0b", 
                                i, intf.WDATA, intf.WLAST), UVM_HIGH)
                    wait(intf.WREADY&&intf.WVALID);//数据握手成功
                    while (!intf.WREADY)@(posedge intf.ACLK);
                            // 保持数据直到握手完成
                    `uvm_info("DATA_DRIVER", $sformatf("W handshake completed for WDATA[%0d]", i), UVM_HIGH)
                end
                //数据发送完毕，下个周期拉低
                @(posedge intf.ACLK);//下个周期
                intf.WVALID <=0;
                intf.WLAST <=0;
                `uvm_info("DATA_DRIVER", "Finished driving data, deasserting WVALID and WLAST", UVM_MEDIUM)
                // 接收写响应 (B)
                intf.BREADY <= 1;
                `uvm_info("DATA_DRIVER", "Waiting for B channel response", UVM_MEDIUM)
                // 新增TPU启动控制逻辑启动tpu_start
                if(t.awaddr == 7'd64) begin
                            begin
                                `uvm_info("TPU_CTRL", "检测到地址64的B响应完成，启动TPU信号", UVM_MEDIUM)
                                @(posedge intf.ACLK);  // 等待下一周期
                                intf.tpu_start <= 1'b1;
                                `uvm_info("TPU_CTRL", $sformatf("TPU_START拉高 @%0t", $time), UVM_HIGH)
                                repeat(2) @(posedge intf.ACLK); // 保持2周期
                                intf.tpu_start <= 1'b0;
                                `uvm_info("TPU_CTRL", $sformatf("TPU_START拉低 @%0t", $time), UVM_HIGH)
                            end
                end
                else begin
                    intf.tpu_start <= 1'b0;
                end
                while (!intf.BVALID) @(posedge intf.ACLK);  // 等待响应
                `uvm_info("DATA_DRIVER", "B channel response received", UVM_MEDIUM)
                @(posedge intf.ACLK);
                intf.BREADY <= 0;
               /* @(posedge intf.ACLK);
                if(intf.tpu_start)begin
                    repeat(2)@(posedge intf.ACLK);
                    intf.tpu_start<=0;
                    tpu_start_s <=0;
                end
                else begin
                    @(posedge intf.ACLK);
                    intf.tpu_start<=tpu_start_s;
                end*/
            end
            `uvm_info("DATA_DRIVER", "Finished data_write task", UVM_LOW)
        endtask

        function void set_interface(virtual axi_slave_intf intf);

            if(intf ==null)begin
                $error("drv intf =null,please checker!!!");
            end
            else begin
                this.intf = intf;
            end

        endfunction

    endclass

    class data_sequencer extends uvm_sequencer#(data_trans);
        `uvm_component_utils(data_sequencer)
        function new(string name = "data_sequencer",uvm_component parent);
            super.new(name,parent);
        endfunction
    endclass


    class data_sequence extends uvm_sequence#(data_trans);
        //define rand data
        //constraint data
        rand bit [AXI_ADDR_WIDTH-1:0] awaddr =-1;     // 写地址（写入 SRAM）
        rand bit [7:0] awlen =-1;        // 写突发长度 ,可通过外部控制data_sequence在传递到trans,来控制wdata[]数据产生
        rand bit [1:0] awburst =-1;      // 写突发类型 01->INCR
        rand bit [AXI_DATA_WIDTH-1:0] wdata[];//向dut发送的数据

        rand bit [1023:0] matrix_data[];//从外部传进来矩阵的形式是每行1024位一共rows行，每个元素占32位
                                  //将矩阵的数据拆成四份，每份256
        constraint matrix_cst      { soft matrix_data.size()==awlen+1;
                                     soft wdata.size()==(awlen+1)*4;
        }

        `uvm_declare_p_sequencer(data_sequencer)//声明seqr 
        //域的自动化
        `uvm_object_utils_begin(data_sequence)
        `uvm_field_int(awaddr, UVM_ALL_ON)
        `uvm_field_int(awlen, UVM_ALL_ON)
        `uvm_field_int(awburst, UVM_ALL_ON) 
        `uvm_field_array_int(wdata, UVM_ALL_ON)
        `uvm_field_array_int(matrix_data, UVM_ALL_ON)     
        `uvm_object_utils_end

        function new(string name="data_sequence");
            super.new(name);
            wdata=new[0];
            matrix_data=new[0];
        endfunction

        task body();
            `uvm_info("DATA_SEQUENCE", "Starting body task", UVM_LOW)
            divide_matrix();
            send_trans();
            `uvm_info("DATA_SEQUENCE", "Finished body task", UVM_LOW)
        endtask

        task send_trans();
            data_trans req,rsp;
            `uvm_info("DATA_SEQUENCE", "Starting send_trans task", UVM_LOW)
            //创建transaction，随机化，发送item
            `uvm_do_with(req, {local::awaddr >= 0 -> awaddr == local::awaddr; 
                            local::awlen >= 0 -> awlen == 4*(local::awlen+1)-1;//外部传进来的awlen需要乘4倍才为实际的awlen突发长度
                            local::awburst >= 0 -> awburst == local::awburst;
                            local::wdata.size()>=0 -> wdata.size()== local::wdata.size;
                            foreach (local::wdata[i]) wdata[i] == local::wdata[i];
                            })//等待driver的get_item才能完成整个
            `uvm_info("DATA_SEQUENCE", $sformatf("Sent transaction: %s", req.sprint()), UVM_HIGH)
            `uvm_info(get_type_name(), req.sprint(), UVM_HIGH)
            get_response(rsp);//得到driver返回的response
            `uvm_info(get_type_name(), rsp.sprint(), UVM_HIGH)
            rsp_check: assert (rsp.rsp)//插入断言
                else $error("[RSPERROR] %0t,seq receiver rsp failed!",$time);
            `uvm_info("DATA_SEQUENCE", "Finished send_trans task", UVM_LOW)
        endtask
        
        task divide_matrix();//将1024位宽的行,拆分成四块256位,因为每次突发传输突发256位宽
            int num_rows;
            int wdata_idx;
            // 检查 matrix_data 是否为空
            if (matrix_data.size() == 0) begin
                `uvm_error("DATA_SEQUENCE", "matrix_data is empty, cannot split!")
            end
            // 计算行数和 wdata 大小
            num_rows = matrix_data.size();//分配好的行
            wdata = new[num_rows * 4]; // 每行 1024 位拆成 4 个 256 位,所以是四倍
            // 遍历每一行，拆分数据
            wdata_idx = 0;
            foreach (matrix_data[i]) begin//matrix_data每一行即1024位
                // 确保 matrix_data[i] 是 1024 位宽
                if ($bits(matrix_data[i]) != 1024) begin
                    `uvm_error("DATA_SEQUENCE", $sformatf("matrix_data[%0d] width is %0d, expected 1024 bits", i, $bits(matrix_data[i])))
                end

                // 拆分 1024 位为 4 个 256 位
                wdata[wdata_idx]     = matrix_data[i][255:0];      // 第 1 个 256 位
                wdata[wdata_idx + 1] = matrix_data[i][511:256];    // 第 2 个 256 位
                wdata[wdata_idx + 2] = matrix_data[i][767:512];    // 第 3 个 256 位
                wdata[wdata_idx + 3] = matrix_data[i][1023:768];   // 第 4 个 256 位
                wdata_idx += 4;
                `uvm_info("DATA_SEQUENCE", $sformatf("Split matrix_data[%0d]: %0h into wdata[%0d:%0d]: %0h, %0h, %0h, %0h",
                    i, matrix_data[i],
                    wdata_idx-4, wdata_idx-1,
                    wdata[wdata_idx-4], wdata[wdata_idx-3], wdata[wdata_idx-2], wdata[wdata_idx-1]), UVM_HIGH)
            end

            // 验证 wdata 大小
            if (wdata.size() != num_rows * 4) begin
                `uvm_error("DATA_SEQUENCE", $sformatf("wdata size is %0d, expected %0d", wdata.size(), num_rows * 4))
            end
        endtask


    endclass

    class mon_data_t extends uvm_sequence_item;
            bit [AXI_ADDR_WIDTH-1:0] awaddr;       // 写地址
            bit [7:0] awlen;                       // 突发长度
            bit       wlast;                       //记录一个矩阵发送完毕
            bit [AXI_DATA_WIDTH-1:0] wdata[];      // 动态数组，存储采集到的 WDATA

            `uvm_object_utils_begin(mon_data_t)
                `uvm_field_int(awaddr, UVM_ALL_ON)
                `uvm_field_int(awlen, UVM_ALL_ON)
                `uvm_field_array_int(wdata, UVM_ALL_ON)
            `uvm_object_utils_end

            function new(string name = "mon_data_trans");
                super.new(name);
            endfunction
    endclass

    class data_monitor extends uvm_monitor;
        `uvm_component_utils(data_monitor)
        local virtual axi_slave_intf  intf;
        uvm_blocking_put_port#(mon_data_t) mon_bp_port;
        function new(string name ="data_monitor",uvm_component parent);
            super.new(name,parent);
            mon_bp_port=new("mon_bp_port",this);
        endfunction

        task run_phase(uvm_phase phase);
            `uvm_info("DATA_MONITOR", "Starting run_phase", UVM_LOW)
            this.mon_trans();
            `uvm_info("DATA_MONITOR", "Finished run_phase", UVM_LOW)
        endtask

        /*task mon_trans();
        mon_data_t m;
        forever begin
            @(posedge intf.ACLK iff (intf.WVALID==='b1 && intf.WREADY==='b1));//握手成功，采集信息
            m=mon_data_t::type_id::create("m",this);
            //m.data = intf.WDATA;
            m.awaddr  = intf.AWADDR;
            m.awlen   = intf.AWLEN;
            m.awburst = intf.AWBURST;
            mon_bp_port.put(m);//发送到scb
            `uvm_info(get_type_name(), $sformatf("monitored channel data 'h%8x", m.data), UVM_HIGH)
        end
        endtask*/
        task mon_trans();
            mon_data_t t;
            `uvm_info("DATA_MONITOR", "Starting mon_trans task", UVM_LOW)
            forever begin
                `uvm_info("DATA_MONITOR", "Waiting for AW handshake", UVM_MEDIUM)
                wait(intf.AWVALID && intf.AWREADY);// 等待 AW 握手
                t = mon_data_t::type_id::create("t"); // 创建对象
                t.awaddr =  intf.AWADDR;
                t.awlen =   intf.AWLEN;
                `uvm_info("DATA_MONITOR", $sformatf("Captured AWADDR=%0h, AWLEN=%0d", t.awaddr, t.awlen), UVM_HIGH)
                // 分配数组存储所有 WDATA
                t.wdata = new[t.awlen + 1];     // awlen+1 个数据
                // 采集 awlen+1 个数据
                for (int i = 0; i <= t.awlen; i++) begin
                    @(posedge intf.ACLK iff (intf.WVALID==='b1 && intf.WREADY==='b1));//握手成功，采集信息
                    t.wdata[i] = intf.WDATA;                // 存储 WDATA
                    t.wlast    = intf.WLAST;
                    `uvm_info("DATA_MONITOR", $sformatf("Captured WDATA[%0d]=%0h, WLAST=%0b", 
                                i, t.wdata[i], t.wlast), UVM_HIGH)
                end
                `uvm_info("DATA_MONITOR", "Waiting for B channel response", UVM_MEDIUM)
                wait(intf.BVALID && intf.BREADY);       // 等待 B 通道完成
                if (intf.BRESP != 2'b00) `uvm_error("RSP_ERROR", "BRESP is not OKAY");
                mon_bp_port.put(t);                 // 发送事务到记分板
                `uvm_info(get_type_name(), $sformatf("Monitored transaction: %s", t.sprint()), UVM_HIGH) // 打印事务
            end
        endtask


        function void set_interface(virtual axi_slave_intf intf);
            if(intf ==null)begin
                $error("drv intf =null,please checker!!!");
            end
            else begin
                this.intf = intf;
            end
        endfunction

    endclass

    class data_agent extends uvm_agent;
        `uvm_component_utils(data_agent)
        local virtual axi_slave_intf vif;
        data_driver    drv;
        data_monitor   mon;
        data_sequencer sqr;

        function new(string name = "data_agent",uvm_component parent);
            super.new(name,parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            drv=data_driver::type_id::create("drv",this);
            mon=data_monitor::type_id::create("mon",this);
            sqr=data_sequencer::type_id::create("sqr",this);
            `uvm_info("DATA_AGENT", "Finished build_phase", UVM_LOW)
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            this.drv.seq_item_port.connect(this.sqr.seq_item_export);
            `uvm_info("DATA_AGENT", "Finished connect_phase", UVM_LOW)
        endfunction

        function void set_interface(virtual axi_slave_intf vif);
            if(vif==null)begin
                $error("agent don't get vif,please check!!!");
            end
            else begin
                this.vif = vif;
                drv.set_interface(vif);
                mon.set_interface(vif);
                `uvm_info("DATA_AGENT", "Interface set successfully", UVM_MEDIUM)
            end
        endfunction

    endclass
    
endpackage

    //burst 传输三次;

    /*class multi_burst_sequence extends data_sequence#(data_trans);
        `uvm_object_utils(multi_burst_sequence)
        
        function new(string name = "multi_burst_sequence");
            super.new(name);
        endfunction

        task body();
            // 第一次突发：awlen=7（传输8次），awaddr=0
            `uvm_do_with(req, {
                awaddr == 0;
                awlen  == 7;    // AXI协议中，awlen=实际传输次数-1
                awburst == 1;   // INCR模式
            })

            // 第二次突发：awlen=15（传输16次），awaddr=32
            `uvm_do_with(req, {
                awaddr == 32;
                awlen  == 15;
                awburst == 1;
            })

            // 第三次突发：awlen=31（传输32次），awaddr=64
            `uvm_do_with(req, {
                awaddr == 64;
                awlen  == 31;
                awburst == 1;
            })
        endtask
    endclass*/

    //自定义数据集sequence
    /*class custom_data_sequence extends data_sequence;
        `uvm_object_utils(custom_data_sequence)
        
        matrix_data data;  // 数据对象
        
        function new(string name = "custom_data_sequence");
            super.new(name);
        endfunction
        
        task body();
            // 发送矩阵 A、B、C
            send_matrix("A", 7'd0, data.packed_A, data.m_a);
            send_matrix("B", 7'd32, data.packed_B, data.k_b);
            send_matrix("C", 7'd64, data.packed_C, data.m_c);
        endtask
        
        task send_matrix(string matrix_name, bit [6:0] base_addr, bit [1023:0] packed_data[], int num_rows);
            data_trans req;
            
            for (int row = 0; row < num_rows; row++) begin
                `uvm_create(req)
                req.awaddr = base_addr + 1;             // 地址递增
                req.awlen = 0;                          // 单块传输
                req.awburst = 1;                        // INCR 模式
                req.wdata = new[1];
                req.wdata[0] = packed_data[row];
                req.wlast = 1;
                `uvm_send(req)
            end
            
        endtask
    endclass*/

