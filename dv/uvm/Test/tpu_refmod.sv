package tpu_refmod_random_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_reg_pkg::*;
    import axi_rsp_pkg::*;
    import axi_data_pkg::*;

    typedef enum {
        COMP_INT4,       // 4-bit integer computation
        COMP_INT8,       // 8-bit integer computation
        COMP_FP16,       // Half-precision floating-point
        COMP_FP32        // Single-precision floating-point
    } compute_mode_e;

    typedef struct {
        bit [31:0]  elements[][];  // Store 32-bit data
        int         rows;
        int         cols;
        compute_mode_e precision;  // Element precision
        int         stored_bitwidth; // Actual stored bit width 32为存储
        bit         is_filled;     // New flag to track matrix completion
    } matrix_t;

    class tpu_refmod_random extends uvm_component;

        `uvm_component_utils(tpu_refmod_random)
        local virtual apb_reg_intf intf;
        compute_mode_e  comp_mode;
        bit             mix_enable;  // Mixed precision enable
        bit             result_matrix_type; 
        int A_rows=0, A_cols=0;
        int B_rows=0, B_cols=0;
        int C_rows=0, C_cols=0;

        matrix_t A, B, C;
        bit [31:0] result_matrix[][];  // Computation result as 32-bit data

        bit [1023:0] result_data[$];
        uvm_blocking_get_port#(reg_data_trans)  reg_port;
        uvm_blocking_get_peek_port#(mon_data_t) data_port;
        uvm_tlm_fifo#(mon_data_trans)           result_fifo;//fifo
        
        function new(string name="tpu_refmod_random", uvm_component parent=null);
            super.new(name, parent);
            reg_port = new("reg_port", this);
            data_port = new("data_port", this);
            result_fifo = new("result_fifo", this);
            `uvm_info("REFMOD NEW", "new success", UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            `uvm_info("REFMOD", "Started run_phase", UVM_LOW)
            fork
                process_reg_config();
                process_data_input();
            join
            `uvm_info("REFMOD", "Finished run_phase", UVM_LOW)
        endtask

        task process_reg_config();
            reg_data_trans cfg;
            forever begin
                reg_port.get(cfg);
                `uvm_info("CFG", $sformatf("Received register configuration: PWDATA[6:0]=%b", cfg.pwdata[6:0]), UVM_LOW)

                case(cfg.pwdata[6:4])
                    3'b001: begin  // Mode 001: 16x16x16
                        A_rows = 16; A_cols = 16;
                        B_rows = 16; B_cols = 16;
                        C_rows = 16; C_cols = 16;
                        result_matrix_type = 2;//输出矩阵类型1：8x32,2:16x16,3:32x8
                    end
                    3'b010: begin  // Mode 010: 32x16-16x8-32x8
                        A_rows = 32; A_cols = 16;
                        B_rows = 16; B_cols = 8;
                        C_rows = 32; C_cols = 8;
                        result_matrix_type = 3;
                    end
                    3'b100: begin  // Mode 100: 8x16-16x32-8x32
                        A_rows = 8;  A_cols = 16;
                        B_rows = 16; B_cols = 32;
                        C_rows = 8;  C_cols = 32;
                        result_matrix_type = 1;
                    end
                    default: `uvm_error("CFG_ERR", "Invalid matrix mode")
                endcase
                
                case(cfg.pwdata[3:1])
                    3'b000: comp_mode = COMP_INT4;
                    3'b001: comp_mode = COMP_INT8;
                    3'b010: comp_mode = COMP_FP16;
                    3'b011: comp_mode = COMP_FP32;
                    default: `uvm_error("CFG_ERR", "Invalid compute mode")
                endcase
                
                mix_enable = cfg.pwdata[0];
                
                `uvm_info("CFG_UPDATE", $sformatf(
                    "Updated configuration: A:%0dx%0d, B:%0dx%0d, C:%0dx%0d, Compute:%s, Mix:%b",
                    A_rows, A_cols, B_rows, B_cols, C_rows, C_cols,
                    comp_mode.name(), mix_enable), UVM_MEDIUM)
            end
        endtask

        task process_data_input();
            bit config_done;
            mon_data_t pkt;
            bit all_matrices_stored;
            string file_path;
            config_done = 0;
            all_matrices_stored = 0;
            forever begin
                if (!config_done) begin
                    wait (A_rows != 0 && B_rows != 0);
                    config_done = 1;
                    `uvm_info("CFG_SYNC", "Configuration ready, start processing data", UVM_MEDIUM)
                    // 由于sv精度问题，在fp16和fp32情况下，采用动态生成文件路径并加载结果矩阵
                    if (comp_mode == COMP_FP16 || comp_mode == COMP_FP32) begin
                        file_path = $sformatf("D:/1Study_work/UVM/TPU/UVM/Test/result_fp16_fp32/ref_result_%s_m%0dn%0dk%0d.mem", 
                            (comp_mode == COMP_FP16 ? "fp16" : "fp32"), A_rows, B_cols,B_rows);
                        load_result_matrix_from_mem(file_path, comp_mode);
                    end
                end
                data_port.peek(pkt);
                `uvm_info("DATA_IN", $sformatf("Received data packet: awaddr=0x%0h, awlen=%0d", pkt.awaddr, pkt.awlen), UVM_LOW)
                data_port.get(pkt);
                case(pkt.awaddr)
                    7'd0   : store_matrix(A, pkt);
                    7'd32  : store_matrix(B, pkt);
                    7'd64  : store_matrix(C, pkt);
                    default: `uvm_error("ADDR_ERR", $sformatf("Invalid address: 0x%0h", pkt.awaddr))
                endcase
                config_done = 0;
                if (verify_matrix_completion()) begin
                    all_matrices_stored = 1;
                    check_compatibility();
                    compute_product();
                    pack_results();
                    send_results();
                    clear_matrices();
                    all_matrices_stored = 0;
                end
            end
        endtask

        // 从 .mem 文件加载结果矩阵，mem为一行一个元素
        function void load_result_matrix_from_mem(string file_path, compute_mode_e precision);
            bit [31:0] data_array[];  // 存储 32 位扩展数据
            bit [15:0] fp16_data_array[];  // 临时存储 FP16 数据
            int file_size;
            int i, j, idx;

            // 计算文件大小
            file_size = A_rows * B_cols;

            // 分配数组空间
            if (precision == COMP_FP16) begin
                fp16_data_array = new[file_size];
                $readmemh(file_path, fp16_data_array);
            end else begin
                data_array = new[file_size];
                $readmemh(file_path, data_array);
            end

            // 填充 result_matrix
            result_matrix = new[A_rows];
            idx = 0;
            for (i = 0; i < A_rows; i++) begin
                result_matrix[i] = new[B_cols];
                for (j = 0; j < B_cols; j++) begin
                    if (precision == COMP_FP16) begin
                        // FP16 数据扩展为 32 位
                        result_matrix[i][j] = {16'b0, fp16_data_array[idx]};
                    end else begin
                        // FP32 数据直接存储
                        result_matrix[i][j] = data_array[idx];
                    end
                    idx++;
                end
            end
            `uvm_info("LOAD_MEM", $sformatf("Loaded result matrix from %s, precision=%s, size=%0dx%0d", 
                file_path, precision.name(), A_rows, B_cols), UVM_MEDIUM)
        endfunction

        function void store_matrix(ref matrix_t mat, mon_data_t pkt);
            bit [1023:0] raw;
            int expected_transfers;
            int max_cols;
            int bit_offset_B;//每行的中存储矩阵时的偏移量
            int bit_offset_AC;
            int i, j;
            int start_idx_B=0;//256组成1024
            int start_idx_AC=0;

            case(pkt.awaddr)
                7'd0:   begin 
                    mat.rows = A_rows; 
                    mat.cols = A_cols; 
                end
                7'd32:  begin 
                    mat.rows = B_rows;
                    mat.cols = B_cols;
                end
                7'd64:  begin 
                    mat.rows = C_rows; 
                    mat.cols = C_cols; 
                end
            endcase

            mat.precision = comp_mode;
            mat.stored_bitwidth = 32;
            mat.is_filled = 0;
            `uvm_info("STORE_MATRIX", $sformatf("Storing matrix at addr=0x%0h with precision=%s, stored_bitwidth=%0d", 
                pkt.awaddr, mat.precision.name(), mat.stored_bitwidth), UVM_LOW)

            max_cols = (pkt.awaddr == 7'd32) ? B_rows : mat.cols;
            if (max_cols > 1024 / 32) begin
                `uvm_error("COLS_ERR", $sformatf("Matrix cols (%0d) exceeds maximum (32) for 1024-bit raw data", max_cols))
            end

            if (pkt.awaddr == 7'd32) begin
                expected_transfers = B_cols;
                if (((pkt.awlen + 1)/4) != expected_transfers) begin
                    `uvm_error("LEN_ERR", $sformatf("Expected %0d transfers for B^T rows, got %0d", expected_transfers, (pkt.awlen + 1)/4))
                end
            end else begin
                expected_transfers = mat.rows;
                if (((pkt.awlen + 1)/4) != expected_transfers) begin
                    `uvm_error("LEN_ERR", $sformatf("Expected %0d transfers for rows, got %0d", expected_transfers, (pkt.awlen + 1)/4))
                end
            end

            mat.elements = new[mat.rows];
            if (pkt.awaddr == 7'd32) begin
                foreach (mat.elements[i]) begin
                    mat.elements[i] = new[mat.cols];
                    foreach (mat.elements[i][j]) begin
                        mat.elements[i][j] = 0;
                    end
                end
                for (i = 0; i < B_cols; i++) begin
                    start_idx_B = i * 4;
                    raw = {pkt.wdata[start_idx_B + 3], pkt.wdata[start_idx_B + 2], pkt.wdata[start_idx_B + 1], pkt.wdata[start_idx_B + 0]};
                    for (j = 0; j < B_rows; j++) begin
                        bit_offset_B = j * 32;
                        if (bit_offset_B + 31 >= $bits(raw)) begin
                            `uvm_error("DATA_ERR", $sformatf("Insufficient bits for B^T[%0d][%0d]", i, j))
                        end
                        mat.elements[j][i] = raw[bit_offset_B +: 32];
                    end
                end
            end else begin
                foreach (mat.elements[i]) begin
                    mat.elements[i] = new[mat.cols];
                    foreach (mat.elements[i][j]) begin
                        mat.elements[i][j] = 0;
                    end
                    start_idx_AC = i * 4;
                    raw = {pkt.wdata[start_idx_AC + 3], pkt.wdata[start_idx_AC + 2], pkt.wdata[start_idx_AC + 1], pkt.wdata[start_idx_AC + 0]};//四个256，从高到低组成1024位
                    for (j = 0; j < mat.cols; j++) begin
                        bit_offset_AC = j * 32;
                        if (bit_offset_AC + 31 >= $bits(raw)) begin
                            `uvm_error("DATA_ERR", $sformatf("Insufficient bits for matrix[%0d][%0d]", i, j))
                        end
                        mat.elements[i][j] = raw[bit_offset_AC +: 32];//将矩阵填充
                    end
                end
            end
            mat.is_filled = 1;
            `uvm_info("MAT_STORE", $sformatf("Stored matrix: rows=%0d, cols=%0d, precision=%s, stored_bitwidth=%0d, filled=%b", 
                mat.rows, mat.cols, mat.precision.name(), mat.stored_bitwidth, mat.is_filled), UVM_LOW)
        endfunction

        function void compute_int4();
            int i, j, k;
            bit [31:0] a_bits, b_bits, c_bits;
            bit [3:0] a_int4, b_int4;
            bit [31:0] acc_int32;
            bit [3:0] c_int4;

            result_matrix = new[A.rows];
            foreach(result_matrix[i]) result_matrix[i] = new[B.cols];

            for(i = 0; i < A.rows; i++) begin
                for(j = 0; j < B.cols; j++) begin
                    acc_int32 = 0;
                    for(k = 0; k < A.cols; k++) begin
                        a_bits = A.elements[i][k];
                        b_bits = B.elements[k][j];
                        a_int4 = a_bits[3:0];
                        b_int4 = b_bits[3:0];
                        acc_int32 += $signed({{28{a_int4[3]}}, a_int4}) * $signed({{28{b_int4[3]}}, b_int4});
                    end
                    if(C.elements.size() > 0) begin
                        c_bits = C.elements[i][j];
                        if(mix_enable) begin
                            acc_int32 += $signed(c_bits);
                        end else begin
                            c_int4 = c_bits[3:0];
                            acc_int32 += $signed({{28{c_int4[3]}}, c_int4});
                        end
                    end
                    result_matrix[i][j] = acc_int32;
                end
            end
            `uvm_info("COMPUTE_INT4", $sformatf("INT4 matrix multiplication completed, mix_enable=%b", mix_enable), UVM_MEDIUM)
        endfunction

        function void compute_int8();
            int i, j, k;
            bit [31:0] a_bits, b_bits, c_bits;
            bit [7:0] a_int8, b_int8;
            bit [31:0] acc_int32;
            bit [7:0] c_int8;

            result_matrix = new[A.rows];
            foreach(result_matrix[i]) result_matrix[i] = new[B.cols];

            for(i = 0; i < A.rows; i++) begin
                for(j = 0; j < B.cols; j++) begin
                    acc_int32 = 0;
                    for(k = 0; k < A.cols; k++) begin
                        a_bits = A.elements[i][k];
                        b_bits = B.elements[k][j];
                        a_int8 = a_bits[7:0];
                        b_int8 = b_bits[7:0];
                        acc_int32 += $signed({{24{a_int8[7]}}, a_int8}) * $signed({{24{b_int8[7]}}, b_int8});
                    end
                    if(C.elements.size() > 0) begin
                        c_bits = C.elements[i][j];
                        if(mix_enable) begin
                            acc_int32 += $signed(c_bits);
                        end else begin
                            c_int8 = c_bits[7:0];
                            acc_int32 += $signed({{24{c_int8[7]}}, c_int8});
                        end
                    end
                    result_matrix[i][j] = acc_int32;
                end
            end
            `uvm_info("COMPUTE_INT8", $sformatf("INT8 matrix multiplication completed, mix_enable=%b", mix_enable), UVM_MEDIUM)
        endfunction

        // 移除 FP16 运算逻辑
        function void compute_fp16();
            // 无需计算，直接使用已加载的 result_matrix
            `uvm_info("COMPUTE_FP16", "FP16 matrix loaded from file, no computation needed", UVM_MEDIUM)
        endfunction

        // 移除 FP32 运算逻辑
        function void compute_fp32();
            // 无需计算，直接使用已加载的 result_matrix
            `uvm_info("COMPUTE_FP32", "FP32 matrix loaded from file, no computation needed", UVM_MEDIUM)
        endfunction

        task compute_product();
            compute_mode_e target_precision;
            target_precision = A.precision;

            case(target_precision)
                COMP_INT4: compute_int4();
                COMP_INT8: compute_int8();
                COMP_FP16: compute_fp16();
                COMP_FP32: compute_fp32();
                default: `uvm_error("PREC_ERR", $sformatf("Invalid precision: %s", target_precision.name()))
            endcase
        endtask

        task send_results();//将计算结果发送到checker
            mon_data_trans res;
            res = new("result");
            res.awaddr = 7'd128;
            res.awlen = (A.rows)*4-1;
            res.wdata = result_data;
            res.result_matrix_type = result_matrix_type;
            `uvm_info("RESULT", $sformatf("Sending result: awaddr=0x%0h, awlen=%0d", res.awaddr, res.awlen), UVM_LOW)
            result_fifo.put(res);//将数据包发送到checker
            `uvm_info("RESULT", $sformatf(" Refmod sent transaction to scoreboard: %s", res.sprint()), UVM_HIGH)
        endtask

        function void pack_results();//将计算出来的结果矩阵打包成队列的形式，以便于checker接收
            bit [1023:0] packed_data;
            int i, j;
            bit [31:0] elem;
            int max_elems_per_row;

            max_elems_per_row = 1024 / 32;//每行存1024位，32个
            if (B.cols > max_elems_per_row) begin
                `uvm_error("PACK_ERR", $sformatf("B.cols (%0d) exceeds maximum (%0d) for 1024-bit packed data", B.cols, max_elems_per_row))
            end

            result_data.delete();
            foreach(result_matrix[i]) begin
                packed_data = 0;
                for(j = 0; j < B.cols; j++) begin
                    elem = result_matrix[i][j];
                    packed_data[(B.cols-1-j)*32 +: 32] = elem;//将矩阵结果打包
                    `uvm_info("PACK_ELEM", $sformatf("Packed result_matrix[%0d][%0d] = 0x%h at bits [%0d:%0d]", 
                        i, j, elem, j*32+31, j*32), UVM_HIGH)
                end
                result_data.push_back(packed_data);//将打包的结果，推到队列中
                `uvm_info("PACK_DATA_RESULTS", $sformatf("Packed data %h",packed_data), UVM_MEDIUM)
            end
            `uvm_info("PACK_RESULTS", $sformatf("Packed %0d rows, each with %0d 32-bit elements", A.rows, B.cols), UVM_MEDIUM)
        endfunction

        function bit matrices_ready();
            return (A.elements.size() == A.rows) &&
                   (B.elements.size() == B.rows) &&
                   (C.elements.size() == C.rows);
        endfunction

        function bit verify_matrix_completion();//监测矩阵都填满
            bit all_filled;
            all_filled = A.is_filled && B.is_filled && C.is_filled;
            if (!all_filled) begin
                `uvm_info("MATRIX_WAIT", $sformatf("Waiting for matrices: A=%b, B=%b, C=%b", 
                    A.is_filled, B.is_filled, C.is_filled), UVM_MEDIUM)
                return 0;
            end
            return 1;
        endfunction

        function void check_compatibility();
            // 保留空函数，仅用于兼容性检查的占位
        endfunction

        function void clear_matrices();//清空矩阵
            A.elements.delete();
            B.elements.delete();
            C.elements.delete();
            result_matrix.delete();
            A.is_filled = 0;
            B.is_filled = 0;
            C.is_filled = 0;
        endfunction

        function void set_interface(virtual apb_reg_intf intf);
            if(intf == null)
                $error("interface handle is NULL, please check if target interface has been instantiated");
            else
                this.intf = intf;
            `uvm_info("INTERFACE", "Interface set successfully", UVM_LOW)
        endfunction

    endclass

endpackage