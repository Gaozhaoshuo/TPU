package apb_reg_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class reg_data_trans extends uvm_sequence_item;
        // AXI4-Lite 协议字段（简化版）
        rand bit [6:0] pwdata;       // 写数据（配置值）
                                    //matrix_mode_reg = PWDATA[6:4];
                                    //mode_reg = PWDATA[3:1];                                                               
                                    //mix_enable_reg = PWDATA[0];
        bit rsp;
        // 约束
        constraint addr_data_range { 
            soft pwdata[6:4] inside {[0:3'b111]}; // matrix_mode_reg 为 3bit
            soft pwdata[3:1] inside {[0:3'b111]}; // mode_reg 为 3bit
            soft pwdata[0]   inside {0,1};        // mix_enable_reg 为 1bit
        }

            `uvm_object_utils_begin(reg_data_trans)
                `uvm_field_int(pwdata,UVM_ALL_ON)
            `uvm_object_utils_end

        function new(string name = "reg_data_trans");
            super.new(name);
        endfunction


    endclass

    class reg_driver extends uvm_driver#(reg_data_trans);
        `uvm_component_utils(reg_driver)
        local virtual apb_reg_intf intf;

        function new(string name ="reg_driver",uvm_component parent);
            super.new(name,parent);
        endfunction
        
        task run_phase(uvm_phase phase);
            `uvm_info("REG_DRIVER", "Starting run_phase", UVM_LOW)
            fork
                do_drive();
                do_reset();
            join
            `uvm_info("REG_DRIVER", "Finished run_phase", UVM_LOW)
            endtask

        task do_reset();
            `uvm_info("REG_DRIVER", "Starting do_reset task", UVM_LOW)
            forever begin
                @(negedge intf.PRESETn);
                `uvm_info("REG_DRIVER", "Reset detected, resetting interface signals", UVM_MEDIUM)
                intf.PSEL =0;
                intf.PENABLE =0;
                intf.PWDATA =0;
                intf.PWRITE =0;
                `uvm_info("REG_DRIVER", "Interface signals reset: PSEL=0, PENABLE=0,  PWDATA=0, PWRITE=0", UVM_HIGH)
            end

        endtask

        task do_drive();
            reg_data_trans req,rsp;
            `uvm_info("REG_DRIVER", "Starting do_drive task", UVM_LOW)
            @(posedge intf.PRESETn);//只要复位拉高
            `uvm_info("REG_DRIVER", "Reset deasserted, starting to drive transactions", UVM_MEDIUM)
            forever begin
                `uvm_info("REG_DRIVER", "Waiting for next transaction", UVM_HIGH)
                seq_item_port.get_next_item(req);
                `uvm_info("REG_DRIVER", $sformatf("Received transaction: %s", req.sprint()), UVM_HIGH)
                this.reg_write(req);
                void'($cast(rsp,req.clone()));
                rsp.rsp=1;
                rsp.set_sequence_id(req.get_sequence_id());//拿到ID并返回
                `uvm_info("REG_DRIVER", $sformatf("Sending response: %s", rsp.sprint()), UVM_HIGH)
                seq_item_port.item_done(rsp);//给seq回应
            end
        endtask

        task reg_write(reg_data_trans t);
            `uvm_info("REG_DRIVER", "Starting reg_write task", UVM_LOW)
            @(posedge intf.PCLK );//SET UP阶段
            `uvm_info("REG_DRIVER", "Entering SETUP phase", UVM_MEDIUM)
                intf.PSEL =1'b1;
                intf.PWRITE =1'b1;
                intf.PENABLE =1'b0;
                intf.PWDATA = t.pwdata;
                `uvm_info("REG_DRIVER", $sformatf("Driving SETUP signals: PSEL=%0b, PWRITE=%0b, PENABLE=%0b,  PWDATA=%0b", 
                    intf.PSEL, intf.PWRITE, intf.PENABLE, intf.PWDATA), UVM_HIGH)
            @(posedge intf.PCLK);//ACCESS;
                intf.PENABLE =1'b1;
                `uvm_info("REG_DRIVER", $sformatf("Driving ACCESS signals: PENABLE=%0b", intf.PENABLE), UVM_HIGH)
            // 等待 PREADY
            while (!intf.PREADY) @(posedge intf.PCLK);//等待从机接收成功         
            if (intf.PENABLE&&intf.PREADY&&intf.PSEL) begin
                intf.PSEL = 0;
                intf.PENABLE = 0;
                intf.PWRITE =1'b0;
                `uvm_info("REG_DRIVER", "Deasserting PSEL and PENABLE after handshake", UVM_MEDIUM)
                end
            // 结束传输
            @(posedge intf.PCLK);
                intf.PSEL = 0;
                intf.PENABLE = 0;
                `uvm_info("REG_DRIVER", "Ending transaction, final deassertion: PSEL=0, PENABLE=0", UVM_MEDIUM)
                `uvm_info("REG_DRIVER", "Finished reg_write task", UVM_LOW)
        endtask

        function void set_interface(virtual apb_reg_intf intf);
            if(intf ==null)begin
                $error("drv intf =null,please checker!!!");
            end
            else begin
                this.intf = intf;
            end
        endfunction

    endclass

    class reg_sequencer extends uvm_sequencer#(reg_data_trans);
        `uvm_component_utils(reg_sequencer)
        function new(string name = "reg_sequencer",uvm_component parent);
            super.new(name,parent);
        endfunction
    endclass

    class reg_sequence extends uvm_sequence#(reg_data_trans);
        rand bit [6:0]pwdata = -1;
        constraint cstr{
                soft pwdata ==-1;
        }
        `uvm_declare_p_sequencer(reg_sequencer)

        `uvm_object_utils_begin(reg_sequence)
        `uvm_field_int(pwdata,UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name="reg_sequence");
            super.new(name);
        endfunction

        task body();
            send_trans();
        endtask

        task send_trans();
            reg_data_trans req,rsp;
            `uvm_info("REG_SEQUENCE", "Starting send_trans task", UVM_LOW)
            `uvm_info("REG_SEQUENCE", $sformatf("Preparing to send transaction with constraints: pwdata=%0b", 
                    pwdata), UVM_LOW)
            //创建trans,随机化，并发送
            `uvm_do_with(req,{
                            local::pwdata >= 0 -> pwdata == local::pwdata;
                            })//
            `uvm_info(get_type_name(), req.sprint(), UVM_HIGH)
            `uvm_info("REG_SEQUENCE", $sformatf("Sent transaction: %s", req.sprint()), UVM_HIGH)
            `uvm_info("REG_SEQUENCE", "Waiting for response", UVM_MEDIUM)
            get_response(rsp);
            `uvm_info(get_type_name(), rsp.sprint(), UVM_HIGH)
            rsp_check: assert (rsp.rsp) else
                $error("Assertion rsp_check failed!");
            `uvm_info("REG_SEQUENCE", "Finished send_trans task", UVM_LOW)
        endtask

    endclass

    class reg_monitor extends uvm_monitor;
        `uvm_component_utils(reg_monitor)
        local virtual apb_reg_intf  intf;
        uvm_blocking_put_port#(reg_data_trans) mon_bp_port;
        function new(string name ="reg_monitor",uvm_component parent);
            super.new(name,parent);
            mon_bp_port=new("mon_bp_port",this);
        endfunction

        task run_phase(uvm_phase phase);
            `uvm_info("REG_MONITOR", "Starting run_phase", UVM_LOW)
            mon_trans();
        endtask

        task mon_trans();
            reg_data_trans m;
            forever begin
                wait(intf.PSEL && intf.PENABLE && intf.PREADY &&intf.PWRITE);//采集接口数据
                m=reg_data_trans::type_id::create("m");
                `uvm_info("REG_MONITOR", "create reg_data_trans m", UVM_LOW)
                `uvm_info("REG_MONITOR", $sformatf("sample intf.PWDATA-> %b",intf.PWDATA), UVM_LOW)
                m.pwdata = intf.PWDATA;
                `uvm_info("REG_MONITOR", $sformatf("sample ->m.pwdata %b",m.pwdata), UVM_LOW)
                @(posedge intf.PCLK);
                mon_bp_port.put(m);//发给scb
                `uvm_info(get_type_name(), $sformatf("reg monitored  data to scb  %b",  m.pwdata), UVM_LOW)
            end
        endtask

        function void set_interface(virtual apb_reg_intf intf);
            if(intf ==null)begin
                $error("drv intf =null,please checker!!!");
            end
            else begin
                this.intf = intf;
            end
        endfunction

    endclass

    class reg_agent extends uvm_agent;
        `uvm_component_utils(reg_agent)
        local virtual apb_reg_intf vif;
        reg_driver    drv;
        reg_monitor   mon;
        reg_sequencer sqr;

        function new(string name = "reg_agent",uvm_component parent);
            super.new(name,parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            drv=reg_driver::type_id::create("drv",this);
            mon=reg_monitor::type_id::create("mon",this);
            sqr=reg_sequencer::type_id::create("sqr",this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            this.drv.seq_item_port.connect(this.sqr.seq_item_export);
        endfunction

        function void set_interface(virtual apb_reg_intf vif);
            if(vif==null)begin
                $error("agent don't get vif,please check!!!");
            end
            else begin
                this.vif = vif;
                drv.set_interface(vif);
                mon.set_interface(vif);
            end
        endfunction

    endclass

    /*class custom_reg_sequence extends reg_sequence;
        `uvm_object_utils(custom_reg_sequence)
        
        matrix_data data;  // 数据对象
        
        function new(string name = "custom_reg_sequence");
            super.new(name);
        endfunction
        
        task body();
            reg_data_trans req;
            // 配置寄存器
            `uvm_create(req)
            req.pwaddr = 32'h0;
            req.pwdata[6:4] = get_precision_code(data.precision_mode_a);
            req.pwdata[9:7] = get_precision_code(data.precision_mode_b);
            req.pwdata[12:10] = get_precision_code(data.precision_mode_c);
            req.pwdata[0] = data.mix_enable;
            req.is_write = 1;
            `uvm_send(req)
        endtask
        
        // 获取精度编码
        function bit [2:0] get_precision_code(string mode);
            case (mode)
                "INT4":  return 3'b000;
                "INT8":  return 3'b001;
                "FP16":  return 3'b010;
                "FP32":  return 3'b011;
                default: `uvm_fatal("PRECISION_ERROR", $sformatf("Unknown precision: %s", mode))
            endcase
        endfunction
    endclass*/

endpackage
