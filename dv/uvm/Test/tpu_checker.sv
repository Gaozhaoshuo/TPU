package tpu_checker_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import tpu_refmod_random_pkg::*;
    import apb_reg_pkg::*;
    import axi_rsp_pkg::*;
    import axi_data_pkg::*;
    
    `uvm_blocking_put_imp_decl(_data)
    `uvm_blocking_put_imp_decl(_reg)
    `uvm_blocking_put_imp_decl(_rsp)

    `uvm_blocking_get_peek_imp_decl(_data)
    `uvm_blocking_get_imp_decl(_reg)
    
    class tpu_checker extends uvm_scoreboard;
        
        local virtual apb_reg_intf intf;
        local int err_count;
        local int total_count;
        // 参考模型
        tpu_refmod_random refmod;

        // Three boxes will store monitor 
        mailbox#(reg_data_trans) reg_mb;
        mailbox#(mon_data_t)     data_mb;
        mailbox#(mon_data_trans) rsp_mb;
        
        `uvm_component_utils_begin(tpu_checker)
            `uvm_field_int(err_count, UVM_ALL_ON)
            `uvm_field_int(total_count, UVM_ALL_ON)
        `uvm_component_utils_end
        // TLM port
        uvm_blocking_put_imp_reg#(reg_data_trans,tpu_checker)   reg_bp_imp;
        uvm_blocking_put_imp_data#(mon_data_t,tpu_checker)      data_bp_imp;
        uvm_blocking_put_imp_rsp#(mon_data_trans,tpu_checker)   rsp_bp_imp;

        uvm_blocking_get_peek_imp_data#(mon_data_t,tpu_checker) data_bgpk_imp; // 发往refmod
        uvm_blocking_get_imp_reg#(reg_data_trans, tpu_checker)  reg_bg_imp;   // 发往refmod
        uvm_blocking_get_port#(mon_data_trans)                  rsp_bg_ports; // 主动从refmodel取数据，连接out_tlm_fifo

        function new(string name="tpu_checker", uvm_component parent);
            super.new(name, parent);
            this.err_count = 0;
            this.total_count = 0;
            reg_bp_imp = new("reg_bp_imp", this);
            data_bp_imp = new("data_bp_imp", this);
            rsp_bp_imp = new("rsp_bp_imp", this);
            data_bgpk_imp = new("data_bgpk_imp", this);
            reg_bg_imp = new("reg_bg_imp", this);
            rsp_bg_ports = new("rsp_bg_ports", this);
            `uvm_info("CHECKER_INIT", $sformatf("CHECKER: Component %s created at time %0t", name, $time), UVM_LOW)
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            reg_mb = new();
            data_mb = new();
            rsp_mb = new();
            refmod = tpu_refmod_random::type_id::create("refmod", this);
            `uvm_info("CHECKER_BUILD", $sformatf("CHECKER: Mailboxes and refmod created at time %0t", $time), UVM_LOW)
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            // 连接refmod和checker
            this.refmod.reg_port.connect(this.reg_bg_imp);
            this.refmod.data_port.connect(this.data_bgpk_imp);
            this.rsp_bg_ports.connect(this.refmod.result_fifo.blocking_get_export);
            `uvm_info("CHECKER_CONNECT", "CHECKER: TLM ports connected: refmod.reg_port, refmod.data_port, and rsp_bg_ports", UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            `uvm_info("CHECKER_RUN", $sformatf("CHECKER: Starting run_phase at time %0t", $time), UVM_LOW)
            this.do_data_compare();
        endtask

        // 任务3：将 FP16 转换为 real 值 拆分fp16的符号位等等
        task convert_fp16_to_real;
            input [15:0] fp16_bits;           // 输入的 16 位 FP16 数据
            output real value;                // 输出的十进制值
            output reg is_inf, is_nan, is_zero; // 特殊情况标志
            output reg sign;                  // 符号位
            reg [4:0] exp;
            reg [9:0] mant;
            real scale;
            begin
                // 初始化输出
                value = 0.0;
                is_inf = 0;
                is_nan = 0;
                is_zero = 0;
                sign = fp16_bits[15];         // 符号位
                exp = fp16_bits[14:10];       // 指数
                mant = fp16_bits[9:0];        // 尾数

                // 处理特殊情况
                if (exp == 5'd31) begin
                    if (mant == 0) begin
                        is_inf = 1;           // 无穷大
                    end else begin
                        is_nan = 1;           // NaN not a num
                    end
                end else if (exp == 5'd0) begin
                    if (mant == 0) begin
                        is_zero = 1;          // 零
                    end else begin
                        // 非规格化数
                        value = (mant / 1024.0) * (2.0 ** (-14));
                        if (sign) value = -value;
                    end
                end else begin
                    // 规格化数
                    if (exp >= 15) begin
                        scale = 2.0 ** (exp - 15);
                    end else begin
                        scale = 1.0 / (2.0 ** (15 - exp));
                    value = (1.0 + mant / 1024.0) * scale;
                    if (sign) value = -value;
                end
                end end
        endtask

        // 任务1：将 FP32 转换为 real 值
        task convert_fp32_to_real;
            input [31:0] fp32_bits;           // 输入的 32 位 FP32 数据
            output real value;                // 输出的十进制值
            output reg is_inf, is_nan, is_zero; // 特殊情况标志
            output reg sign;                  // 符号位
            reg [7:0] exp;
            reg [22:0] mant;
            real scale;
            begin
                // 初始化输出
                value = 0.0;
                is_inf = 0;
                is_nan = 0;
                is_zero = 0;
                sign = fp32_bits[31];         // 符号位
                exp = fp32_bits[30:23];       // 指数
                mant = fp32_bits[22:0];       // 尾数

                // 处理特殊情况
                if (exp == 8'd255) begin
                    if (mant == 0) begin
                        is_inf = 1;           // 无穷大
                    end else begin
                        is_nan = 1;           // NaN
                    end
                end else if (exp == 8'd0) begin
                    if (mant == 0) begin
                        is_zero = 1;          // 零
                    end else begin
                        // 非规格化数
                        value = (mant / 8388608.0) * (2.0 ** (-126));
                        if (sign) value = -value;
                    end
                end else begin
                    // 规格化数
                    if (exp >= 127) begin
                        scale = 2.0 ** (exp - 127);
                    end else begin
                        scale = 1.0 / (2.0 ** (127 - exp));
                    end
                    value = (1.0 + mant / 8388608.0) * scale;
                    if (sign) value = -value;
                end
            end
        endtask

        // 任务4：打印 FP16 值
        task print_fp16_value;
            input real value;                 // 十进制值
            input is_inf, is_nan, is_zero;    // 特殊情况标志
            input sign;                       // 符号位
            begin
                if (is_inf) begin
                    $display("FP16 Result: %sInfinity", sign ? "-" : "+");
                end else if (is_nan) begin
                    $display("FP16 Result: NaN");
                end else if (is_zero) begin
                    $display("FP16 Result: %sZero", sign ? "-" : "+");
                end else begin
                    $display("FP16 Result: %.7f", value); // FP16 精度较低，保留 7 位小数
                end
            end
        endtask
        // 任务2：打印 FP32 值
        task print_fp32_value;
            input real value;                 // 十进制值
            input is_inf, is_nan, is_zero;    // 特殊情况标志
            input sign;                       // 符号位
            input [22:0] mant;                // 尾数（用于区分 QNaN 和 SNaN）
            begin
                if (is_inf) begin
                    $display("FP32 Result: %sInfinity", sign ? "-" : "+");
                end else if (is_nan) begin
                    if (mant[22] == 1)
                        $display("FP32 Result: QNaN (Quiet NaN)");
                    else
                        $display("FP32 Result: SNaN (Signaling NaN)");
                end else if (is_zero) begin
                    $display("FP32 Result: %sZero", sign ? "-" : "+");
                end else begin
                    $display("FP32 Result: %.15f", value);
                end
            end
        endtask

        //在int4和int8情况下，直接对比来自dut和refmod两个队列的值
        //在fp16和fp32情况下，需要将队列的值拆分到矩阵，之后对比每一个矩阵的值(加入误差容量)
        task do_data_compare();
            mon_data_trans ref_out, mont_out;            // 定义参考模型 (ref_out) 和 DUT (mont_out) 的输出事务对象
            bit cmp;                                    // 比较结果标志，1 表示成功，0 表示失败
            int rows=0, cols=0;                         // 矩阵的行数和列数，动态从接口获取
            bit [31:0] ref_result_matrix[][];           // 参考模型的矩阵，动态分配，每个元素为 32 位
            bit [31:0] tpu_result_matrix[][];           // DUT 的矩阵，动态分配，每个元素为 32 位
            int elements_per_wdata = 1024 / 32;         // 每个 wdata 块包含的 32 位元素数量，固定为 32（1024 位 / 32 位）
            int total_elements;                         // 矩阵总元素数，计算为 rows * cols
            int matrix_index;                           // 矩阵填充时的索引，用于跟踪元素位置
            compute_mode_e precision;                   // 当前计算模式，从参考模型获取
            bit [1023:0] wdata_block;                   // 每个 wdata 块的 1024 位数据
            int i, j;                                   // 循环变量，用于遍历 wdata 和矩阵
            bit [31:0] dut_elem, ref_elem;              // DUT 和参考模型的 32 位矩阵元素
            real diff, rel_error;                       // 绝对和相对误差
            real dut_val, ref_val;                      // 用于存储转换后的 real 值
            real rel_tolerance;                         // 相对误差容差，根据模式动态设置
            real abs_tolerance;                         // 绝对误差容差，根据模式动态设置
            bit dut_is_inf, dut_is_nan, dut_is_zero, dut_sign; // DUT 特殊标志
            bit ref_is_inf, ref_is_nan, ref_is_zero, ref_sign; // 参考特殊标志
            bit [22:0] dut_mant_fp32, ref_mant_fp32;   // 用于 FP32 尾数
            bit [9:0] dut_mant_fp16, ref_mant_fp16;    // 用于 FP16 尾数
            bit [15:0] dut_fp16_bits, ref_fp16_bits;   // 用于存储 FP16 位
            bit [31:0] dut_fp32_bits, ref_fp32_bits;   // 用于存储 FP16 位

            int failed_elements;                        // 计数有多少个失败的元素
            string result_category;                     // 比较结果类别

            forever begin
                // 从响应邮箱中获取 DUT 的输出数据
                this.rsp_mb.get(mont_out);
                `uvm_info("CHECKER_RSP", $sformatf("CHECKER: Received DUT response: awaddr=0x%0h, awlen=%0d, wdata.size=%0d at time %0t", 
                    mont_out.awaddr, mont_out.awlen, mont_out.wdata.size(), $time), UVM_MEDIUM)
                `uvm_info("CHECKER_RSP", $sformatf(" CHECKER: Received DUT response: %s", mont_out.sprint()), UVM_HIGH)
                
                // 从参考模型的响应端口获取参考数据
                this.rsp_bg_ports.get(ref_out);
                `uvm_info("CHECKER_REF", $sformatf("CHECKER: Received refmod response: awaddr=0x%0h, awlen=%0d, wdata.size=%0d at time %0t", 
                    ref_out.awaddr, ref_out.awlen, ref_out.wdata.size(), $time), UVM_MEDIUM)
                `uvm_info("CHECKER_RSP", $sformatf(" CHECKER: Received refmod response: %s", ref_out.sprint()), UVM_HIGH)

                // 获取当前计算模式，从参考模型中获取
                precision = refmod.comp_mode;
                `uvm_info("CHECKER_REF_PRE",$sformatf("precision = %s,refmod.comp_mode = %s",precision.name(),refmod.comp_mode.name()),UVM_LOW)

                // 初始化失败元素计数
                failed_elements = 0;
                cmp = 1; // 初始化比较结果为成功

                // 根据计算模式选择不同的比较逻辑///////////////////////////////////////
                if (precision inside {COMP_INT4, COMP_INT8}) begin
                    // INT4 和 INT8 模式：直接比较 wdata 队列的每个 1024 位块
                    if (mont_out.wdata.size() != ref_out.wdata.size()) begin
                        cmp = 0;                            // 如果 wdata 队列大小不一致，直接标记为失败
                        `uvm_info("CHECKER_SIZE_MISMATCH", $sformatf("CHECKER: Size mismatch - DUT wdata.size=%0d, Ref wdata.size=%0d", 
                            mont_out.wdata.size(), ref_out.wdata.size()), UVM_MEDIUM)
                    end else begin
                        cmp = 1;                            // 初始化比较结果为成功
                        for (i = 0; i < mont_out.wdata.size(); i++) begin
                            if (mont_out.wdata[i] != ref_out.wdata[i]) begin
                                cmp = 0;                    // 如果发现任何不匹配，标记失败并退出循环
                                failed_elements++;//失败个数+1；
                                `uvm_error("CHECKER_INT_COMPARE_ERROR", $sformatf("CHECKER: Mismatch at index %0d: DUT=0x%0h, Ref=0x%0h", 
                                    i, mont_out.wdata[i], ref_out.wdata[i]))
                                break;
                            end
                        end
                    end
                end 
                else if (precision inside {COMP_FP16, COMP_FP32}) begin
                    // 根据 intf.pwdata[6:4] 确定矩阵维度
                    case (intf.PWDATA[6:4])
                        3'b001: begin rows = 16; cols = 16; end // 16x16
                        3'b010: begin rows = 32; cols = 8;  end // 32x8
                        3'b100: begin rows = 8;  cols = 32; end // 8x32
                        default: begin
                            `uvm_error("CHECKER_MATRIX_DIM_ERROR", $sformatf("CHECKER: Undefined intf.pwdata[6:4]=%b, using default 16x16", intf.PWDATA[6:4]))
                            rows = 16; cols = 16; // 默认值
                        end
                    endcase

                    // 动态分配矩阵内存
                    ref_result_matrix = new[rows];//将refmod和dut发送过来的数据包在fp16和fp32情况下拆分为矩阵
                    tpu_result_matrix = new[rows];
                    `uvm_info("REF AND TPU RESULT",$sformatf("ref and tpu rows = %d",rows),UVM_LOW)
                    for (i = 0; i < rows; i++) begin
                        ref_result_matrix[i] = new[cols];
                        tpu_result_matrix[i] = new[cols];
                    end
                    `uvm_info("REF AND TPU RESULT",$sformatf("ref and tpu cols = %d",cols),UVM_LOW)

                    // 拆分 ref_out.wdata[$] 到 ref_result_matrix，从高位填充，矩阵填充
                    matrix_index = 0;
                    for (i = 0; i < ref_out.wdata.size() && matrix_index < rows * cols; i++) begin
                        wdata_block = ref_out.wdata[i]; // 获取当前 wdata 块

                        `uvm_info("REF_OUT.WDATA", $sformatf("Packed data %h",ref_out.wdata[i]), UVM_MEDIUM)//打印每行
                        `uvm_info("WDATA_BLOCK", $sformatf("Packed data %h",wdata_block), UVM_MEDIUM)//打印每行

                        for (j = 0; j < cols && matrix_index < rows * cols; j++) begin
                            int row = matrix_index / cols;  // 计算行索引
                            int col = matrix_index % cols;  // 计算列索引
                            //bit[31:0] elem = wdata_block[(elements_per_wdata-1-j)*32 +: 32];
                            int start_bit = (cols-1-j) * 32; // 从 [cols*32-1] 开始，递减
                            bit[31:0] elem = wdata_block[start_bit +: 32]; // 提取 32 位元素
                            ref_result_matrix[row][col] = elem; // 从高位填充 32 位元素
                            `uvm_info("REF_result_matrix", $sformatf("Unpacked REF_result_matrix[%0d][%0d] = 0x%h", 
                            row, col, elem), UVM_HIGH)
                            matrix_index++;
                        end
                    end

                    // 拆分 mont_out.wdata[$] 到 tpu_result_matrix，从高位填充，矩阵填充
                    matrix_index = 0;
                    for (i = 0; i < mont_out.wdata.size() && matrix_index < rows * cols; i++) begin
                        wdata_block = mont_out.wdata[i]; // 获取当前 wdata 块
                        for (j = 0; j < cols && matrix_index < rows * cols; j++) begin
                            int row = matrix_index / cols;  // 计算行索引
                            int col = matrix_index % cols;  // 计算列索引
                            //bit[31:0] elem = wdata_block[(elements_per_wdata-1-j)*32 +: 32]; //矩阵中元素
                            int start_bit = (cols-1-j) * 32; // 从 [cols*32-1] 开始，递减
                            bit[31:0] elem = wdata_block[start_bit +: 32]; // 提取 32 位元素
                            tpu_result_matrix[row][col] = elem; // 从高位填充 32 位元素
                            `uvm_info("TPU_result_matrix", $sformatf("Unpacked TPU_result_matrix[%0d][%0d] = 0x%h", 
                            row, col, elem), UVM_HIGH)
                            matrix_index++;
                        end
                    end

                    total_elements = rows * cols;

                    // 设置误差容差
                    if (precision == COMP_FP16) begin
                        rel_tolerance = 1e-1;  // FP16: 0.01
                        abs_tolerance = 1e-1;  // FP16: 统计两种情况-2和-3的情况，大部分都在-3以内少数-2
                    end else if (precision == COMP_FP32) begin
                        rel_tolerance = 1e-5;  // FP32: 1e-5
                        abs_tolerance = 1e-10; // FP32: 1e-10
                    end

                    // 比较矩阵元素
                    cmp = 1;                                // 初始化比较结果为成功,如果对比失败就会cmp=0;

                    for (i = 0; i < rows; i++) begin
                        for (j = 0; j < cols; j++) begin
                            dut_elem = tpu_result_matrix[i][j]; // 获取 DUT 矩阵元素
                            ref_elem = ref_result_matrix[i][j]; // 获取参考矩阵元素

                            `uvm_info("TPU_result_elem", $sformatf("Unpacked dut_elem[%0d][%0d] = 0x%h", 
                            i, j, dut_elem), UVM_HIGH)
                            `uvm_info("REF_result_elem", $sformatf("Unpacked ref_elem[%0d][%0d] = 0x%h", 
                            i, j, ref_elem), UVM_HIGH)
                            //fp16的对比情况/////////////////////////////////////////////////////////////////////////////
                            if (precision == COMP_FP16) begin
                                // 提取低 16 位
                                dut_fp16_bits = dut_elem[15:0];
                                ref_fp16_bits = ref_elem[15:0];
                                // 转换 DUT 输出
                                convert_fp16_to_real(dut_fp16_bits, dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign);//将fp16拆分，得到实际的数值
                                dut_mant_fp16 = dut_fp16_bits[9:0];//尾数
                                `uvm_info("dut_mant_fp16", $sformatf("dut_mant_fp16 = 0x%h", 
                                    dut_mant_fp16), UVM_HIGH)
                                // 转换参考结果
                                convert_fp16_to_real(ref_fp16_bits, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                ref_mant_fp16 = ref_fp16_bits[9:0];
                                `uvm_info("ref_mant_fp16", $sformatf("ref_mant_fp16 = 0x%h", 
                                    ref_mant_fp16), UVM_HIGH)

                                // 比较特殊情况 是否是无穷大或者nan
                                if (dut_is_inf || dut_is_nan || ref_is_inf || ref_is_nan) begin
                                    if (dut_is_inf != ref_is_inf || dut_is_nan != ref_is_nan || 
                                        (dut_is_inf && dut_sign != ref_sign)) begin
                                        `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h", 
                                            i, j, dut_fp16_bits, ref_fp16_bits))
                                        // 假设 print_fp16_value 已定义，这里仅打印日志
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                            dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign), UVM_MEDIUM)
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                            ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign), UVM_MEDIUM)
                                        cmp = 0;
                                        failed_elements++;//失败元素+1；
 
                                        //break;
                                    end
                                end else if (dut_is_zero && ref_is_zero) begin//是否是0
                                    if (dut_sign != ref_sign) begin
                                        `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h", 
                                            i, j, dut_fp16_bits, ref_fp16_bits))
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                            dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign), UVM_MEDIUM)
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                            ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign), UVM_MEDIUM)
                                        cmp = 0;
                                        //break;
                                    end
                                end else begin
                                    // 数值比较利用绝对误差和相对误差
                                    diff = dut_val - ref_val;
                                    if (ref_val != 0.0) begin
                                        rel_error = diff / ref_val;
                                        if ((rel_error < -rel_tolerance || rel_error > rel_tolerance)&&(diff < -abs_tolerance || diff > abs_tolerance)) begin
                                            `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h, Relative Error=%.2e,Absolute Error= %.2e", 
                                                i, j, dut_fp16_bits, ref_fp16_bits, rel_error,diff))
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                                dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign), UVM_MEDIUM)
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                                ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign), UVM_MEDIUM)
                                            cmp = 0;
                                            failed_elements++;//失败元素+1；
                                            //break;
                                        end
                                    end else begin
                                        // 参考值为零，使用绝对误差
                                        //rel_error = diff / ref_val;
                                        if (diff < -abs_tolerance || diff > abs_tolerance) begin
                                            `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h, Relative Error=%.2e,Absolute Error=%.2e", 
                                                i, j, dut_fp16_bits, ref_fp16_bits, rel_error,diff))
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                                dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign), UVM_MEDIUM)
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b", 
                                                ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign), UVM_MEDIUM)
                                            cmp = 0;
                                            failed_elements++;//失败元素+1；
                                            //break;
                                        end
                                    end
                                    `uvm_info("CHECKER 16 value",$sformatf("Position [%0d][%0d]: TPU=", i, j),UVM_LOW);
                                    print_fp16_value(dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign);
                                    `uvm_info("CHECKER 16 value","EXPECTED",UVM_LOW);
                                    print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                end
                               //fp32的对比情况//////////////////////////////////////////////////////////////////
                            end else if (precision == COMP_FP32) begin
                                dut_fp32_bits = dut_elem;
                                ref_fp32_bits = ref_elem;
                                // 转换 DUT 输出
                                convert_fp32_to_real(dut_fp32_bits, dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign);
                                dut_mant_fp32 = dut_fp32_bits[22:0];
                                // 转换参考结果
                                convert_fp32_to_real(ref_fp32_bits, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                ref_mant_fp32 = ref_fp32_bits[22:0];
                                // 比较特殊情况 nan或者无穷大
                                if (dut_is_inf || dut_is_nan || ref_is_inf || ref_is_nan) begin
                                    if (dut_is_inf != ref_is_inf || dut_is_nan != ref_is_nan || 
                                        (dut_is_nan && dut_mant_fp32[22] != ref_mant_fp32[22]) || 
                                        (dut_is_inf && dut_sign != ref_sign)) begin
                                        `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h", 
                                            i, j, dut_fp32_bits, ref_fp32_bits))
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                            dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign, dut_mant_fp32), UVM_MEDIUM)
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                            ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32), UVM_MEDIUM)
                                        cmp = 0;
                                        failed_elements++;//失败元素+1；
                                        //break;
                                    end
                                end else if (dut_is_zero && ref_is_zero) begin//特殊模式
                                    if (dut_sign != ref_sign) begin
                                        `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h", 
                                            i, j, dut_fp32_bits, ref_fp32_bits))
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                            dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign, dut_mant_fp32), UVM_MEDIUM)
                                        `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                            ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32), UVM_MEDIUM)
                                        cmp = 0;
                                        failed_elements++;//失败元素+1；
                                        //break;
                                    end
                                end else begin
                                    // 数值比较
                                    diff = dut_val - ref_val;
                                    if (ref_val != 0.0) begin
                                        rel_error = diff / ref_val;
                                        if ((rel_error < -rel_tolerance || rel_error > rel_tolerance)&&(diff < -abs_tolerance || diff > abs_tolerance)) begin
                                            `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h, Relative Error=%.2e,Absolute Error= %.2e", 
                                                i, j, dut_fp32_bits, ref_fp32_bits, rel_error,diff))
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                                dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign, dut_mant_fp32), UVM_MEDIUM)
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                                ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32), UVM_MEDIUM)
                                            cmp = 0;
                                            failed_elements++;//失败元素+1；
                                            //break;
                                        end
                                    end else begin
                                        // 参考值为零，使用绝对误差
                                        if (diff < -abs_tolerance || diff > abs_tolerance) begin
                                            `uvm_error("CHECKER_MATRIX_ERROR", $sformatf("CHECKER: Error at [%0d][%0d], DUT=0x%h, Ref=0x%h, Relative Error=%.2e,Absolute Error=%.2e", 
                                                i, j, dut_fp32_bits, ref_fp32_bits, rel_error,diff))
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: DUT: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                                dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign, dut_mant_fp32), UVM_MEDIUM)
                                            `uvm_info("CHECKER_MATRIX_DETAIL", $sformatf("CHECKER: Ref: val=%0f, inf=%0b, nan=%0b, zero=%0b, sign=%0b, mant=0x%h", 
                                                ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32), UVM_MEDIUM)
                                            cmp = 0;
                                            failed_elements++;//失败元素+1；
                                            //break;
                                        end
                                    end
                                end
                                `uvm_info("CHECKER 32 value",$sformatf("Position [%0d][%0d]: TPU=", i, j),UVM_LOW);
                                print_fp32_value(dut_val, dut_is_inf, dut_is_nan, dut_is_zero, dut_sign, dut_mant_fp32);//打印fp32位的值
                                `uvm_info("CHECKER 32 value","EXPECTED",UVM_LOW);
                                print_fp32_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32);
                            end
                        end
                        //if (cmp == 0) break;                    // 如果已失败，退出内层循环,
                                                                //如果想要出现错误立即退出，应该将break全都释放
                    end
                end else begin
                    cmp = 0;                                // 未知模式，比较失败
                    failed_elements = 1;                    // 标记为失败
                    total_elements = 1;
                end

                // 根据错误计数，确定比较结果类别 三种，一种全错，一种全对，一种部分对///////////////////////////////////////////////////////
                if (failed_elements == 0) begin
                    result_category = "all_succeeded";
                end else if (failed_elements == total_elements) begin
                    result_category = "all_failed";
                end else begin
                    result_category = "part_failed";
                end

                //cmp = mont_out.compare(ref_out);//因为dut输出是awlen一直设置为31，而refmod是根据矩阵输出得来的，所以调用compare函数有问题
                this.total_count++;
                if(cmp == 0) begin
                    this.err_count++;
                    //`uvm_error("CHECKER_CMPERR", $sformatf("CHECKER: %0dth comparison failed! TPU monitored output differs from reference model output (err_count=%0d)", 
                      //  this.total_count, this.err_count))
                        `uvm_error("CHECKER_CMPERR", $sformatf("CHECKER: %0dth comparison %s! TPU monitored output differs from reference model output (err_count=%0d, failed_elements=%0d/%0d)", 
                    this.total_count, result_category, this.err_count, failed_elements, total_elements))
                    // 打印差异数据
                    `uvm_info("CHECKER_CMPERR_DETAIL", $sformatf("CHECKER: DUT: awaddr=0x%0h, awlen=%0d, wdata[0]=%0h; Ref: awaddr=0x%0h, awlen=%0d, wdata[0]=%0h", 
                        mont_out.awaddr, mont_out.awlen, mont_out.wdata.size() > 0 ? mont_out.wdata[0] : 0, 
                        ref_out.awaddr, ref_out.awlen, ref_out.wdata.size() > 0 ? ref_out.wdata[0] : 0), UVM_HIGH)

                end else begin
                    //`uvm_info("CHECKER_CMPSUC", $sformatf("CHECKER: %0dth comparison succeeded! TPU monitored output matches reference model output (total_count=%0d)", 
                       // this.total_count, this.total_count), UVM_LOW)
                       `uvm_info("CHECKER_CMPSUC", $sformatf("CHECKER: %0dth comparison %s! TPU monitored output matches reference model output (total_count=%0d)", 
                    this.total_count, result_category, this.total_count), UVM_LOW)
                end
            end
        endtask

        task put_data(mon_data_t t);
            data_mb.put(t);
            `uvm_info("CHECKER_PUT_DATA", $sformatf("CHECKER: Put data to data_mb: awaddr=0x%0h, awlen=%0d at time %0t", t.awaddr, t.awlen, $time), UVM_MEDIUM)
        endtask

        task put_reg(reg_data_trans t);
            reg_mb.put(t);
            `uvm_info("CHECKER_PUT_REG", $sformatf("CHECKER: Put reg to reg_mb: pwdata=%07b at time %0t", t.pwdata[6:0], $time), UVM_MEDIUM)
        endtask

        task put_rsp(mon_data_trans t);
            rsp_mb.put(t);
            `uvm_info("CHECKER_PUT_RSP", $sformatf("CHECKER: Put response to rsp_mb: awaddr=0x%0h, awlen=%0d, wdata.size=%0d at time %0t", 
                t.awaddr, t.awlen, t.wdata.size(), $time), UVM_MEDIUM)
        endtask

        task get_data(output mon_data_t t);
            data_mb.get(t);
            `uvm_info("CHECKER_GET_DATA", $sformatf("CHECKER: Got data from data_mb: awaddr=0x%0h, awlen=%0d at time %0t", t.awaddr, t.awlen, $time), UVM_MEDIUM)
        endtask

        task peek_data(output mon_data_t t);
            data_mb.peek(t);
            `uvm_info("CHECKER_PEEK_DATA", $sformatf("CHECKER: Peeked data from data_mb: awaddr=0x%0h, awlen=%0d at time %0t", t.awaddr, t.awlen, $time), UVM_MEDIUM)
        endtask

        task get_reg(output reg_data_trans t);
            reg_mb.get(t);
            `uvm_info("CHECKER_GET_REG", $sformatf("CHECKER: Got reg from reg_mb: pwdata=%07b at time %0t", t.pwdata[6:0], $time), UVM_MEDIUM)
        endtask

        function void set_interface(virtual apb_reg_intf intf);
            if(intf == null) begin
                $error("interface handle is NULL, please check if target interface has been instantiated");
                `uvm_error("CHECKER_INTF_ERR", "CHECKER: Interface handle is NULL")
            end else begin
                this.intf = intf;
                this.refmod.set_interface(intf);
                `uvm_info("CHECKER_SET_INTF", $sformatf("CHECKER: Interface set successfully at time %0t", $time), UVM_LOW)
            end
        endfunction
    endclass
endpackage