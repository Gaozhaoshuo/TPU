`timescale 1ns / 1ps

module tb_tpu_top_m16n16k16_fp32_relu_fuse;

// Parameters
localparam MAX_DATA_SIZE        = 32;
localparam SYS_ARRAY_SIZE       = 8;
localparam K_SIZE               = 16;
localparam DATA_WIDTH           = 32;
localparam DEPTH_SHARE_SRAM     = 96;
localparam DEPTH_SRAM           = 32;
localparam SHARE_SRAM_ADDR_WIDTH = $clog2(DEPTH_SHARE_SRAM);
localparam SRAM_ADDR_WIDTH      = $clog2(DEPTH_SRAM);
localparam AXI_DATA_WIDTH       = SYS_ARRAY_SIZE * DATA_WIDTH;

// Data type selection
localparam INT4_MODE = 3'b000;  // INT4 data type mode
localparam INT8_MODE = 3'b001;  // INT8 data type mode
localparam FP16_MODE = 3'b010;  // FP16 data type mode
localparam FP32_MODE = 3'b011;  // FP32 data type mode
reg [2:0] dtype_sel;
reg mixed_precision;  // For this test: APB bridge uses FP32+mixed_precision=1 as relu_fuse=1

// Signals
reg clk, rst_n;
reg tpu_start;
reg cmd_valid_i;
wire cmd_ready_o;
reg [127:0] cmd_data_i;
reg pclk, presetn, psel, penable, pwrite;
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
wire tpu_done, send_done;
reg send_done_seen;

// Data storage
reg [31:0] matrix_A [0:255];  // 16x16 matrix
reg [31:0] matrix_B [0:255];  // 16x16 matrix
reg [31:0] matrix_C [0:255];  // 16x16 matrix
reg [AXI_DATA_WIDTH-1:0] data_packet_A [0:63];
reg [AXI_DATA_WIDTH-1:0] data_packet_B [0:63];
reg [AXI_DATA_WIDTH-1:0] data_packet_C [0:63];
real ref_result [0:255];      // Use real for reference results
real tpu_result [0:255];      // Use real to support FP32 in mixed precision
reg [31:0] ref_result_fp16 [0:255]; // Storage for FP16 reference result
reg [31:0] ref_result_fp32 [0:255]; // Storage for FP32 reference result
reg [31:0] ref_result_fp32_relu [0:255];
reg [31:0] tpu_result_fp32_bits [0:255];
reg [31:0] baseline_tpu_fp32_bits [0:255];
reg [1:0] matrix_select;
integer i, j, k;
integer tpu_idx;
integer errors;
reg verify_start;
integer ewise_trace_count;
reg test_done;

// Instantiate DUT
tpu_top #(
    .MAX_DATA_SIZE(MAX_DATA_SIZE),
    .SYS_ARRAY_SIZE(SYS_ARRAY_SIZE),
    .K_SIZE(K_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH_SHARE_SRAM(DEPTH_SHARE_SRAM),
    .DEPTH_SRAM(DEPTH_SRAM)
) tpu_top (
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

// Clock & Reset
initial begin
    clk <= 0; pclk <= 0;
    forever #5 begin clk <= ~clk; pclk <= ~pclk; end
end

initial begin
    rst_n <= 0; presetn <= 0;
    #20; rst_n <= 1; presetn <= 1;
end

// Matrix Initialization from Files
initial begin
    real a_val, b_val, c_val; // Declare variables
    dtype_sel = FP32_MODE;    // Default to INT4, can be changed to INT8, FP16, FP32
    mixed_precision = 0;
    verify_start = 1'b0;
    test_done = 1'b0;
    $display("Reading matrix data from .mem files for dtype_sel=%0b...", dtype_sel);
    
    // Load matrix A, B, C based on dtype_sel
    case (dtype_sel)
        INT8_MODE: begin
            if(mixed_precision) begin
                $readmemh("data/dataset/int8_int32/m16n16k16/matrix_a_int8.mem", matrix_A);
                $readmemh("data/dataset/int8_int32/m16n16k16/matrix_b_int8.mem", matrix_B);
                $readmemh("data/dataset/int8_int32/m16n16k16/matrix_c_int32.mem", matrix_C);
            end else begin
                $readmemh("data/dataset/int8/m16n16k16/matrix_a_int8.mem", matrix_A);
                $readmemh("data/dataset/int8/m16n16k16/matrix_b_int8.mem", matrix_B);
                $readmemh("data/dataset/int8/m16n16k16/matrix_c_int8.mem", matrix_C); 
            end
        end
        INT4_MODE: begin
            if(mixed_precision) begin
                $readmemh("data/dataset/int4_int32/m16n16k16/matrix_a_int4.mem", matrix_A);
                $readmemh("data/dataset/int4_int32/m16n16k16/matrix_b_int4.mem", matrix_B);
                $readmemh("data/dataset/int4_int32/m16n16k16/matrix_c_int32.mem", matrix_C);
            end else begin
                $readmemh("data/dataset/int4/m16n16k16/matrix_a_int4.mem", matrix_A);
                $readmemh("data/dataset/int4/m16n16k16/matrix_b_int4.mem", matrix_B);
                $readmemh("data/dataset/int4/m16n16k16/matrix_c_int4.mem", matrix_C); 
            end
        end
        FP16_MODE: begin
            $readmemh("data/dataset/fp16/m16n16k16/matrix_a_fp16.mem", matrix_A);
            $readmemh("data/dataset/fp16/m16n16k16/matrix_b_fp16.mem", matrix_B);
            $readmemh("data/dataset/fp16/m16n16k16/matrix_c_fp16.mem", matrix_C);
            $readmemh("data/dataset/fp16/m16n16k16/ref_result_fp16_m16n16k16.mem", ref_result_fp16);
        end
        FP32_MODE: begin
            $readmemh("data/dataset/fp32/m16n16k16/matrix_a_fp32.mem", matrix_A);
            $readmemh("data/dataset/fp32/m16n16k16/matrix_b_fp32.mem", matrix_B);
            $readmemh("data/dataset/fp32/m16n16k16/matrix_c_fp32.mem", matrix_C);
            $readmemh("data/dataset/fp32/m16n16k16/ref_result_fp32_m16n16k16.mem", ref_result_fp32);
        end
    endcase

    // Check if matrices are loaded correctly
    if (matrix_A[0] === 32'bx || matrix_B[0] === 32'bx || matrix_C[0] === 32'bx) begin
        $display("Error: Failed to load one or more .mem files. Check file paths.");
        $finish;
    end else if (dtype_sel == FP32_MODE && ref_result_fp32[0] === 32'bx) begin
        $display("Error: Failed to load ref_result_fp32.mem. Check file path.");
        $finish;
    end else if (dtype_sel == FP16_MODE && ref_result_fp16[0] === 32'bx) begin
        $display("Error: Failed to load ref_result_fp16.mem. Check file path.");
        $finish;
    end else begin
        $display("Matrix data loaded successfully.");
    end

    // Compute reference result for INT4, INT8; load FP16, FP32 from .mem
    if (dtype_sel == INT4_MODE || dtype_sel == INT8_MODE) begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                ref_result[i*16 + j] = 0.0;
                for (k = 0; k < 16; k = k + 1) begin
                    case (dtype_sel)
                        INT8_MODE: begin
                            a_val = $signed(matrix_A[i*16 + k][7:0]);
                            b_val = $signed(matrix_B[k*16 + j][7:0]);
                        end
                        INT4_MODE: begin
                            a_val = $signed(matrix_A[i*16 + k][3:0]);
                            b_val = $signed(matrix_B[k*16 + j][3:0]);
                        end
                    endcase
                    ref_result[i*16 + j] = ref_result[i*16 + j] + a_val * b_val;
                end
                if (mixed_precision) begin
                    c_val = $signed(matrix_C[i*16 + j]);
                end else begin
                    case (dtype_sel)
                        INT8_MODE: c_val = $signed(matrix_C[i*16 + j][7:0]);
                        INT4_MODE: c_val = $signed(matrix_C[i*16 + j][3:0]);
                    endcase
                end
                ref_result[i*16 + j] = ref_result[i*16 + j] + c_val;
            end
        end
    end else if (dtype_sel == FP16_MODE) begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                ref_result[i*16 + j] = $bitstoreal(ref_result_fp16[i*16 + j]);
            end
        end
    end else if (dtype_sel == FP32_MODE) begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                ref_result_fp32_relu[i*16 + j] = ref_result_fp32[i*16 + j][31] ? 32'h00000000 : ref_result_fp32[i*16 + j];
                ref_result[i*16 + j] = 0.0;
            end
        end
    end

    // Print ref_result in matrix format (16x16) in hex
    $display("Reference result matrix (16x16) in hex:");
    for (i = 0; i < 16; i = i + 1) begin
        for (j = 0; j < 16; j = j + 1) begin
            if (dtype_sel == FP32_MODE)
                $write("%8h ", ref_result_fp32_relu[i*16 + j]);
            else if (mixed_precision) begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: $write("%h ", $rtoi(ref_result[i*16 + j]));
                    FP16_MODE: $write("%8h ", $realtobits(ref_result[i*16 + j]));
                endcase
            end else begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: $write("%h ", $rtoi(ref_result[i*16 + j]));
                    FP16_MODE: $write("%8h ", $realtobits(ref_result[i*16 + j]));
                endcase
            end
        end
        $display(""); // New line after each row
    end

    // Packing matrices
    case (dtype_sel)
        INT8_MODE: begin
            // Packing matrix A
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = {24'b0, matrix_A[i*16 + (k*8 + j)][7:0]};
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = {24'b0, matrix_B[(k*8 + j)*16 + i][7:0]};
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16) begin
                            if (mixed_precision)
                                data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*16 + (k*8 + j)];
                            else
                                data_packet_C[i*4 + k][j*32 +: 32] = {24'b0, matrix_C[i*16 + (k*8 + j)][7:0]};
                        end else
                            data_packet_C[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
        end
        INT4_MODE: begin
            // Packing matrix A
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = {28'b0, matrix_A[i*16 + (k*8 + j)][3:0]};
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = {28'b0, matrix_B[(k*8 + j)*16 + i][3:0]};
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16) begin
                            if (mixed_precision)
                                data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*16 + (k*8 + j)];
                            else
                                data_packet_C[i*4 + k][j*32 +: 32] = {28'b0, matrix_C[i*16 + (k*8 + j)][3:0]};
                        end else
                            data_packet_C[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
        end
        FP16_MODE: begin
            // Packing matrix A
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = {16'b0, matrix_A[i*16 + (k*8 + j)][15:0]};
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = {16'b0, matrix_B[(k*8 + j)*16 + i][15:0]};
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16) begin
                            if (mixed_precision)
                                data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*16 + (k*8 + j)];
                            else
                                data_packet_C[i*4 + k][j*32 +: 32] = {16'b0, matrix_C[i*16 + (k*8 + j)][15:0]};
                        end else
                            data_packet_C[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
        end
        FP32_MODE: begin
            // Packing matrix A
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = matrix_A[i*16 + (k*8 + j)];
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = matrix_B[(k*8 + j)*16 + i];
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C
            for (i = 0; i < 16; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k*8 + j < 16)
                            data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*16 + (k*8 + j)];
                        else
                            data_packet_C[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
        end
    endcase
end

// Capture TPU output
initial begin
    tpu_idx = 0;
    ewise_trace_count = 0;
    send_done_seen = 1'b0;
    for (i = 0; i < 256; i = i + 1)
        tpu_result_fp32_bits[i] = 32'd0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        send_done_seen <= 1'b0;
    else if (send_done)
        send_done_seen <= 1'b1;
end

always @(posedge clk) begin
    if (tpu_top.ewise_unit_inst.active && tpu_top.ewise_unit_inst.sram_d_wen && ewise_trace_count < 12) begin
        $display("EWISE write trace[%0d]: addr=%0d seg=%0d data[31:0]=%h data[63:32]=%h",
                 ewise_trace_count,
                 tpu_top.ewise_unit_inst.sram_d_addr,
                 tpu_top.ewise_unit_inst.sram_d_seg_sel,
                 tpu_top.ewise_unit_inst.sram_d_data_in[31:0],
                 tpu_top.ewise_unit_inst.sram_d_data_in[63:32]);
        ewise_trace_count = ewise_trace_count + 1;
    end
end

always @(posedge clk) begin
    if (m_wvalid && m_wready) begin
        for (j = 0; j < 8; j = j + 1) begin
            if (tpu_idx < 256) begin
                if (mixed_precision) begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: tpu_result[tpu_idx] = $itor($signed(m_wdata[j*32 +: 32]));
                        FP16_MODE: tpu_result[tpu_idx] = $bitstoreal(m_wdata[j*32 +: 32]);
                        FP32_MODE: begin
                            tpu_result_fp32_bits[tpu_idx] = m_wdata[j*32 +: 32];
                            tpu_result[tpu_idx] = 0.0;
                        end
                    endcase
                end else begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: tpu_result[tpu_idx] = $itor($signed(m_wdata[j*32 +: 32]));
                        FP16_MODE: tpu_result[tpu_idx] = $bitstoreal({16'b0, m_wdata[j*32 + 15 -: 16]});
                        FP32_MODE: begin
                            tpu_result_fp32_bits[tpu_idx] = m_wdata[j*32 +: 32];
                            tpu_result[tpu_idx] = 0.0;
                        end
                    endcase
                end
                tpu_idx = tpu_idx + 1;
            end
        end
        if (m_wlast) begin
            $display("Captured TPU output burst at address %0d", m_awaddr);
        end
    end
end

// AXI write task
task axi_write_burst;
    input [SHARE_SRAM_ADDR_WIDTH-1:0] addr;
    input [7:0] len;
    input [1:0] burst_type;
    begin
        @(posedge clk);
        s_awvalid <= 1; s_awaddr <= addr;
        s_awlen <= len; s_awburst <= burst_type;
        while (!s_awready) @(posedge clk);
        @(posedge clk); s_awvalid <= 0;

        for (i = 0; i <= len; i = i + 1) begin
            @(posedge clk);
            s_wvalid <= 1;
            case (matrix_select)
                0: s_wdata <= data_packet_A[i];
                1: s_wdata <= data_packet_B[i];
                2: s_wdata <= data_packet_C[i];
                default: s_wdata <= data_packet_A[i];
            endcase
            s_wlast <= (i == len);
            while (!s_wready) @(posedge clk);
        end
        @(posedge clk); s_wvalid <= 1; s_wlast <= 0;
        @(posedge clk); s_wvalid <= 0;

        s_bready <= 1;
        while (!s_bvalid) @(posedge clk);
        @(posedge clk); s_bready <= 0;
    end
endtask

// APB write task
task apb_write;
    input [2:0] dtype;
    input mp;  // Mixed precision bit
    begin
        @(posedge pclk);
        psel <= 1; penable <= 0; pwrite <= 1;
        pwdata <= {3'b001, dtype, mp}; // pwdata[3:1]=dtype_sel, pwdata[0]=mixed_precision
        @(posedge pclk); penable <= 1;
        while (!pready) @(posedge pclk);
        if (penable && pready && psel) begin
            psel <= 0; penable <= 0;
        end
        @(posedge pclk); psel <= 0; penable <= 0;
    end
endtask

task clear_capture_buffer;
    begin
        tpu_idx = 0;
        for (i = 0; i < 256; i = i + 1)
            tpu_result_fp32_bits[i] = 32'd0;
    end
endtask

task pulse_reset;
    begin
        rst_n <= 0;
        presetn <= 0;
        tpu_start <= 0;
        psel <= 0;
        penable <= 0;
        pwrite <= 0;
        pwdata <= 7'b0;
        s_awvalid <= 0;
        s_wvalid <= 0;
        s_wlast <= 0;
        s_bready <= 0;
        m_bvalid <= 0;
        #20;
        rst_n <= 1;
        presetn <= 1;
        #40;
    end
endtask

task wait_for_send_done;
    integer wait_cycles;
    begin
        wait_cycles = 0;
        while (send_done_seen !== 1'b1 && wait_cycles < 2000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (send_done_seen !== 1'b1) begin
            $display("ERROR: timeout waiting send_done in fused test.");
            $display("  active_opcode=%h exec_inflight=%0b active_waits_for_load=%0b active_waits_for_ewise=%0b active_waits_for_writeback=%0b",
                     tpu_top.active_opcode, tpu_top.exec_inflight, tpu_top.active_waits_for_load,
                     tpu_top.active_waits_for_ewise, tpu_top.active_waits_for_writeback);
            $display("  fused_ewise_start_pulse=%0b ewise_active=%0b ewise_done=%0b writeback_start_pulse=%0b sram_d_readback_active=%0b",
                     tpu_top.fused_ewise_start_pulse, tpu_top.ewise_active, tpu_top.ewise_done,
                     tpu_top.writeback_start_pulse, tpu_top.sram_d_readback_active);
            $display("  axi_master.state=%0d m_awvalid=%0b m_awready=%0b m_wvalid=%0b m_wready=%0b m_wlast=%0b m_bvalid=%0b m_bready=%0b send_done=%0b",
                     tpu_top.axi_master_inst.state, m_awvalid, m_awready, m_wvalid, m_wready,
                     m_wlast, m_bvalid, m_bready, send_done);
            $finish(1);
        end
    end
endtask

task run_fp32_case;
    input mp;
    begin
        mixed_precision = mp;
        send_done_seen = 1'b0;
        clear_capture_buffer();
        ewise_trace_count = 0;

        $display("APB configuration...");
        apb_write(dtype_sel, mixed_precision);
        #20;

        $display("Sending matrix A...");
        matrix_select <= 0;
        axi_write_burst(0, 63, 2'b01);

        $display("Sending matrix B (transpose)...");
        matrix_select <= 1;
        axi_write_burst(32, 63, 2'b01);

        $display("Sending matrix C...");
        matrix_select <= 2;
        axi_write_burst(64, 63, 2'b01);

        #110;
        if (mp)
            $display("Starting TPU fused GEMM -> RELU -> DMA_STORE...");
        else
            $display("Starting TPU baseline GEMM...");
        tpu_start <= 1;
        repeat (3) @(posedge clk);
        tpu_start <= 0;

        if (mp) begin
            wait (tpu_top.ewise_unit_inst.active == 1'b1);
            $display("EWISE config: bursts_per_row=%0d max_rows=%0d active_mtype_sel=%0b",
                     tpu_top.ewise_unit_inst.bursts_per_row,
                     tpu_top.ewise_unit_inst.max_rows,
                     tpu_top.active_mtype_sel);
        end

        wait (tpu_done == 1);
        $display("TPU computation completed at %0t", $time);

        wait (m_wvalid && m_wready && m_wlast);
        @(posedge clk);
        m_bvalid <= 1; m_bresp <= 2'b00;
        @(posedge clk);
        if (m_bready) m_bvalid <= 0;

        wait_for_send_done();
        $display("All operations completed at %0t", $time);
        #100;
    end
endtask

// Test sequence
initial begin
    tpu_start <= 0; psel <= 0; penable <= 0; pwrite <= 0; pwdata <= 7'b0;
    cmd_valid_i <= 1'b0; cmd_data_i <= 128'd0;
    s_awvalid <= 0; s_awaddr <= 0; s_awlen <= 0; s_awburst <= 0;
    s_wvalid <= 0; s_wdata <= 0; s_wlast <= 0; s_bready <= 0;
    matrix_select <= 0; m_awready <= 1; m_wready <= 1;
    m_bvalid <= 0; m_bresp <= 2'b00;
    errors = 0;

    wait (rst_n == 1 && presetn == 1);
    #100;

    run_fp32_case(1'b0);
    for (i = 0; i < 256; i = i + 1)
        baseline_tpu_fp32_bits[i] = tpu_result_fp32_bits[i];

    $display("Captured baseline FP32 output. Re-running with fused RELU bridge...");
    pulse_reset();
    run_fp32_case(1'b1);
    verify_start = 1'b1;
end

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

// 任务3：将 FP16 转换为 real 值
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
                is_nan = 1;           // NaN
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
            end
            value = (1.0 + mant / 1024.0) * scale;
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

// Verification section: Check both relative and absolute errors, pass if either is within tolerance
initial begin
    real diff, rel_error;
    real tpu_val, ref_val;            // 用于存储转换后的 real 值
    automatic real rel_tolerance;      // 相对误差容差，根据模式动态设置
    automatic real abs_tolerance;      // 绝对误差容差，根据模式动态设置
    reg tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign;
    reg ref_is_inf, ref_is_nan, ref_is_zero, ref_sign;
    reg [22:0] tpu_mant_fp32, ref_mant_fp32; // 用于 FP32
    reg [9:0] tpu_mant_fp16, ref_mant_fp16;  // 用于 FP16
    integer sram_d_errors;
    wait (verify_start == 1);

    if (dtype_sel == FP32_MODE && mixed_precision) begin : fp32_fused_fast_check
        integer row_idx;
        integer col_idx;
        reg [31:0] tpu_bits;
        reg [31:0] ref_bits;

        $display("Verifying TPU output results...");
        errors = 0;
        sram_d_errors = 0;

        for (row_idx = 0; row_idx < 16; row_idx = row_idx + 1) begin
            for (col_idx = 0; col_idx < 16; col_idx = col_idx + 1) begin
                tpu_bits = tpu_result_fp32_bits[row_idx*16 + col_idx];
                ref_bits = baseline_tpu_fp32_bits[row_idx*16 + col_idx][31] ? 32'h00000000 :
                           baseline_tpu_fp32_bits[row_idx*16 + col_idx];
                if (tpu_bits != ref_bits) begin
                    $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h",
                             row_idx, col_idx, tpu_bits, ref_bits);
                    errors = errors + 1;
                end
            end
        end

        for (row_idx = 0; row_idx < 16; row_idx = row_idx + 1) begin
            if (tpu_top.sram_d.memory[row_idx][255:0] !== {baseline_tpu_fp32_bits[row_idx*16+7], baseline_tpu_fp32_bits[row_idx*16+6], baseline_tpu_fp32_bits[row_idx*16+5], baseline_tpu_fp32_bits[row_idx*16+4],
                                                           baseline_tpu_fp32_bits[row_idx*16+3], baseline_tpu_fp32_bits[row_idx*16+2], baseline_tpu_fp32_bits[row_idx*16+1], baseline_tpu_fp32_bits[row_idx*16+0]} &&
                tpu_top.sram_d.memory[row_idx][255:0] !== {(baseline_tpu_fp32_bits[row_idx*16+7][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+7]),
                                                           (baseline_tpu_fp32_bits[row_idx*16+6][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+6]),
                                                           (baseline_tpu_fp32_bits[row_idx*16+5][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+5]),
                                                           (baseline_tpu_fp32_bits[row_idx*16+4][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+4]),
                                                           (baseline_tpu_fp32_bits[row_idx*16+3][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+3]),
                                                           (baseline_tpu_fp32_bits[row_idx*16+2][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+2]),
                                                           (baseline_tpu_fp32_bits[row_idx*16+1][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+1]),
                                                           (baseline_tpu_fp32_bits[row_idx*16+0][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+0])}) begin
                sram_d_errors = sram_d_errors + 1;
            end
            if (tpu_top.sram_d.memory[row_idx][511:256] !== {baseline_tpu_fp32_bits[row_idx*16+15], baseline_tpu_fp32_bits[row_idx*16+14], baseline_tpu_fp32_bits[row_idx*16+13], baseline_tpu_fp32_bits[row_idx*16+12],
                                                             baseline_tpu_fp32_bits[row_idx*16+11], baseline_tpu_fp32_bits[row_idx*16+10], baseline_tpu_fp32_bits[row_idx*16+9], baseline_tpu_fp32_bits[row_idx*16+8]} &&
                tpu_top.sram_d.memory[row_idx][511:256] !== {(baseline_tpu_fp32_bits[row_idx*16+15][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+15]),
                                                             (baseline_tpu_fp32_bits[row_idx*16+14][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+14]),
                                                             (baseline_tpu_fp32_bits[row_idx*16+13][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+13]),
                                                             (baseline_tpu_fp32_bits[row_idx*16+12][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+12]),
                                                             (baseline_tpu_fp32_bits[row_idx*16+11][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+11]),
                                                             (baseline_tpu_fp32_bits[row_idx*16+10][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+10]),
                                                             (baseline_tpu_fp32_bits[row_idx*16+9][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+9]),
                                                             (baseline_tpu_fp32_bits[row_idx*16+8][31] ? 32'h0 : baseline_tpu_fp32_bits[row_idx*16+8])}) begin
                sram_d_errors = sram_d_errors + 1;
            end
        end

        if (sram_d_errors == 0)
            $display("SRAM D physical rows match baseline-output RELU expectation.");
        else
            $display("SRAM D physical rows do not match expectation. mismatch_rows=%0d", sram_d_errors);

        if (errors == 0)
            $display("Verification passed: fused FP32 RELU output matches baseline-output RELU over all %0d elements!", 16*16);
        else
            $display("Verification failed: Found %0d errors!", errors);
        test_done = 1'b1;
        $finish;
    end

    $display("Verifying TPU output results...");
    errors = 0;
    sram_d_errors = 0;
    for (i = 0; i < 16; i = i + 1) begin
        for (j = 0; j < 16; j = j + 1) begin
            // 根据数据类型设置容差
            if (dtype_sel == FP16_MODE) begin
                rel_tolerance = 2e-1; // FP16: 0.01
                abs_tolerance = 1e-5; // FP16: 1e-5
            end else if (dtype_sel == FP32_MODE) begin
                rel_tolerance = 1e-4; // FP32: 1e-5
                abs_tolerance = 1e-10; // FP32: 1e-10
            end else begin
                rel_tolerance = 0.0; // 整数模式无需容差
                abs_tolerance = 0.0;
            end

            if (mixed_precision) begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: begin
                        automatic integer ref_int = $rtoi(ref_result[i*16 + j]);
                        automatic integer tpu_int = $rtoi(tpu_result[i*16 + j]);
                        if (tpu_int != ref_int) begin
                            $display("Error: Position [%0d][%0d], TPU output=0x%h (%0d), Expected=0x%h (%0d)", 
                                     i, j, tpu_int, tpu_int, ref_int, ref_int);
                            errors = errors + 1;
                        end
                    end
                    FP16_MODE: begin
                        automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*16 + j]);
                        automatic reg [31:0] ref_bits = $realtobits(ref_result[i*16 + j]);
                        automatic reg [15:0] tpu_fp16 = tpu_bits[15:0]; // 提取低 16 位
                        automatic reg [15:0] ref_fp16 = ref_bits[15:0];
                        // 转换 TPU 输出
                        convert_fp16_to_real(tpu_fp16, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                        tpu_mant_fp16 = tpu_fp16[9:0];
                        // 转换参考结果
                        convert_fp16_to_real(ref_fp16, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                        ref_mant_fp16 = ref_fp16[9:0];
                        // 比较特殊情况
                        if (tpu_is_inf || tpu_is_nan || ref_is_inf || ref_is_nan) begin
                            if (tpu_is_inf != ref_is_inf || tpu_is_nan != ref_is_nan || 
                                (tpu_is_inf && tpu_sign != ref_sign)) begin
                                $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h", 
                                         i, j, tpu_fp16, ref_fp16);
                                $write("TPU: ");
                                print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                $write("Expected: ");
                                print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                errors = errors + 1;
                            end
                        end else if (tpu_is_zero && ref_is_zero) begin
                            if (tpu_sign != ref_sign) begin
                                $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h", 
                                         i, j, tpu_fp16, ref_fp16);
                                $write("TPU: ");
                                print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                $write("Expected: ");
                                print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                errors = errors + 1;
                            end
                        end else begin
                            // 数值比较：检查相对误差和绝对误差
                            diff = tpu_val - ref_val;
                            if (ref_val != 0.0) begin
                                rel_error = diff / ref_val;
                                if ((rel_error < -rel_tolerance || rel_error > rel_tolerance) &&
                                    (diff < -abs_tolerance || diff > abs_tolerance)) begin
                                    $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h, Relative Error=%.2e, Absolute Error=%.2e", 
                                             i, j, tpu_fp16, ref_fp16, rel_error, diff);
                                    $write("TPU: ");
                                    print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                    $write("Expected: ");
                                    print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                    errors = errors + 1;
                                end
                            end else begin
                                // 参考值为零，仅检查绝对误差
                                if (diff < -abs_tolerance || diff > abs_tolerance) begin
                                    $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h, Absolute Error=%.2e", 
                                             i, j, tpu_fp16, ref_fp16, diff);
                                    $write("TPU: ");
                                    print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                    $write("Expected: ");
                                    print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                    errors = errors + 1;
                                end
                            end
                        end
                    end
                    FP32_MODE: begin
                        automatic reg [31:0] tpu_bits = tpu_result_fp32_bits[i*16 + j];
                        automatic reg [31:0] ref_bits = baseline_tpu_fp32_bits[i*16 + j][31] ? 32'h00000000 :
                                                        baseline_tpu_fp32_bits[i*16 + j];
                        if (tpu_bits != ref_bits) begin
                            $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h", 
                                     i, j, tpu_bits, ref_bits);
                            errors = errors + 1;
                        end
                    end
                endcase
            end else begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: begin
                        automatic integer ref_int = $rtoi(ref_result[i*16 + j]);
                        automatic integer tpu_int = $rtoi(tpu_result[i*16 + j]);
                        if (tpu_int != ref_int) begin
                            $display("Error: Position [%0d][%0d], TPU output=0x%h (%0d), Expected=0x%h (%0d)", 
                                     i, j, tpu_int, tpu_int, ref_int, ref_int);
                            errors = errors + 1;
                        end
                    end
                    FP16_MODE: begin
                        automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*16 + j]);
                        automatic reg [31:0] ref_bits = $realtobits(ref_result[i*16 + j]);
                        automatic reg [15:0] tpu_fp16 = tpu_bits[15:0];
                        automatic reg [15:0] ref_fp16 = ref_bits[15:0];
                        // 转换 TPU 输出
                        convert_fp16_to_real(tpu_fp16, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                        tpu_mant_fp16 = tpu_fp16[9:0];
                        // 转换参考结果
                        convert_fp16_to_real(ref_fp16, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                        ref_mant_fp16 = ref_fp16[9:0];
                        // 比较特殊情况
                        if (tpu_is_inf || tpu_is_nan || ref_is_inf || ref_is_nan) begin
                            if (tpu_is_inf != ref_is_inf || tpu_is_nan != ref_is_nan || 
                                (tpu_is_inf && tpu_sign != ref_sign)) begin
                                $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h", 
                                         i, j, tpu_fp16, ref_fp16);
                                $write("TPU: ");
                                print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                $write("Expected: ");
                                print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                errors = errors + 1;
                            end
                        end else if (tpu_is_zero && ref_is_zero) begin
                            if (tpu_sign != ref_sign) begin
                                $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h", 
                                         i, j, tpu_fp16, ref_fp16);
                                $write("TPU: ");
                                print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                $write("Expected: ");
                                print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                errors = errors + 1;
                            end
                        end else begin
                            // 数值比较：检查相对误差和绝对误差
                            diff = tpu_val - ref_val;
                            if (ref_val != 0.0) begin
                                rel_error = diff / ref_val;
                                if ((rel_error < -rel_tolerance || rel_error > rel_tolerance) &&
                                    (diff < -abs_tolerance || diff > abs_tolerance)) begin
                                    $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h, Relative Error=%.2e, Absolute Error=%.2e", 
                                             i, j, tpu_fp16, ref_fp16, rel_error, diff);
                                    $write("TPU: ");
                                    print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                    $write("Expected: ");
                                    print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                    errors = errors + 1;
                                end
                            end else begin
                                // 参考值为零，仅检查绝对误差
                                if (diff < -abs_tolerance || diff > abs_tolerance) begin
                                    $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h, Absolute Error=%.2e", 
                                             i, j, tpu_fp16, ref_fp16, diff);
                                    $write("TPU: ");
                                    print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                                    $write("Expected: ");
                                    print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                                    errors = errors + 1;
                                end
                            end
                        end
                    end
                    FP32_MODE: begin
                        automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*16 + j]);
                        automatic reg [31:0] ref_bits = $realtobits(ref_result[i*16 + j]);
                        // 转换 TPU 输出
                        convert_fp32_to_real(tpu_bits, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                        tpu_mant_fp32 = tpu_bits[22:0];
                        // 转换参考结果
                        convert_fp32_to_real(ref_bits, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                        ref_mant_fp32 = ref_bits[22:0];
                        // 比较特殊情况
                        if (tpu_is_inf || tpu_is_nan || ref_is_inf || ref_is_nan) begin
                            if (tpu_is_inf != ref_is_inf || tpu_is_nan != ref_is_nan || 
                                (tpu_is_nan && tpu_mant_fp32[22] != ref_mant_fp32[22]) || 
                                (tpu_is_inf && tpu_sign != ref_sign)) begin
                                $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h", 
                                         i, j, tpu_bits, ref_bits);
                                $write("TPU: ");
                                print_fp32_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign, tpu_mant_fp32);
                                $write("Expected: ");
                                print_fp32_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32);
                                errors = errors + 1;
                            end
                        end else if (tpu_is_zero && ref_is_zero) begin
                            if (tpu_sign != ref_sign) begin
                                $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h", 
                                         i, j, tpu_bits, ref_bits);
                                $write("TPU: ");
                                print_fp32_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign, tpu_mant_fp32);
                                $write("Expected: ");
                                print_fp32_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32);
                                errors = errors + 1;
                            end
                        end else begin
                            // 数值比较：检查相对误差和绝对误差
                            diff = tpu_val - ref_val;
                            if (ref_val != 0.0) begin
                                rel_error = diff / ref_val;
                                if ((rel_error < -rel_tolerance || rel_error > rel_tolerance) &&
                                    (diff < -abs_tolerance || diff > abs_tolerance)) begin
                                    $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h, Relative Error=%.2e, Absolute Error=%.2e", 
                                             i, j, tpu_bits, ref_bits, rel_error, diff);
                                    $write("TPU: ");
                                    print_fp32_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign, tpu_mant_fp32);
                                    $write("Expected: ");
                                    print_fp32_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32);
                                    errors = errors + 1;
                                end
                            end else begin
                                // 参考值为零，仅检查绝对误差
                                if (diff < -abs_tolerance || diff > abs_tolerance) begin
                                    $display("Error: Position [%0d][%0d], TPU output=0x%h, Expected=0x%h, Absolute Error=%.2e", 
                                             i, j, tpu_bits, ref_bits, diff);
                                    $write("TPU: ");
                                    print_fp32_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign, tpu_mant_fp32);
                                    $write("Expected: ");
                                    print_fp32_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32);
                                    errors = errors + 1;
                                end
                            end
                        end
                    end
                endcase
            end
        end
    end

    for (i = 0; i < 16; i = i + 1) begin
        if (tpu_top.sram_d.memory[i][255:0] !== {baseline_tpu_fp32_bits[i*16+7], baseline_tpu_fp32_bits[i*16+6], baseline_tpu_fp32_bits[i*16+5], baseline_tpu_fp32_bits[i*16+4],
                                                 baseline_tpu_fp32_bits[i*16+3], baseline_tpu_fp32_bits[i*16+2], baseline_tpu_fp32_bits[i*16+1], baseline_tpu_fp32_bits[i*16+0]} &&
            tpu_top.sram_d.memory[i][255:0] !== {(baseline_tpu_fp32_bits[i*16+7][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+7]),
                                                 (baseline_tpu_fp32_bits[i*16+6][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+6]),
                                                 (baseline_tpu_fp32_bits[i*16+5][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+5]),
                                                 (baseline_tpu_fp32_bits[i*16+4][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+4]),
                                                 (baseline_tpu_fp32_bits[i*16+3][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+3]),
                                                 (baseline_tpu_fp32_bits[i*16+2][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+2]),
                                                 (baseline_tpu_fp32_bits[i*16+1][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+1]),
                                                 (baseline_tpu_fp32_bits[i*16+0][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+0])}) begin
            sram_d_errors = sram_d_errors + 1;
        end
        if (tpu_top.sram_d.memory[i][511:256] !== {baseline_tpu_fp32_bits[i*16+15], baseline_tpu_fp32_bits[i*16+14], baseline_tpu_fp32_bits[i*16+13], baseline_tpu_fp32_bits[i*16+12],
                                                   baseline_tpu_fp32_bits[i*16+11], baseline_tpu_fp32_bits[i*16+10], baseline_tpu_fp32_bits[i*16+9], baseline_tpu_fp32_bits[i*16+8]} &&
            tpu_top.sram_d.memory[i][511:256] !== {(baseline_tpu_fp32_bits[i*16+15][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+15]),
                                                   (baseline_tpu_fp32_bits[i*16+14][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+14]),
                                                   (baseline_tpu_fp32_bits[i*16+13][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+13]),
                                                   (baseline_tpu_fp32_bits[i*16+12][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+12]),
                                                   (baseline_tpu_fp32_bits[i*16+11][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+11]),
                                                   (baseline_tpu_fp32_bits[i*16+10][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+10]),
                                                   (baseline_tpu_fp32_bits[i*16+9][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+9]),
                                                   (baseline_tpu_fp32_bits[i*16+8][31] ? 32'h0 : baseline_tpu_fp32_bits[i*16+8])}) begin
            sram_d_errors = sram_d_errors + 1;
        end
    end

    if (sram_d_errors == 0)
        $display("SRAM D physical rows match baseline-output RELU expectation.");
    else
        $display("SRAM D physical rows do not match expectation. mismatch_rows=%0d", sram_d_errors);

    if (errors == 0) begin
        $display("Verification passed: fused FP32 RELU output matches baseline-output RELU over all %0d elements!", 16*16);
        // 打印 TPU 结果矩阵（十六进制）
        $display("TPU result matrix (16x16) in hex:");
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                if (mixed_precision) begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: $write("%h ", $rtoi(tpu_result[i*16 + j]));
                        FP16_MODE: $write("%8h ", $realtobits(tpu_result[i*16 + j]));
                        FP32_MODE: $write("%8h ", tpu_result_fp32_bits[i*16 + j]);
                    endcase
                end else begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: $write("%h ", $rtoi(tpu_result[i*16 + j]));
                        FP16_MODE: $write("%8h ", $realtobits(tpu_result[i*16 + j]));
                        FP32_MODE: $write("%8h ", tpu_result_fp32_bits[i*16 + j]);
                    endcase
                end
            end
            $display(""); // 每行结束后换行
        end
        
        // // 打印 FP16 或 FP32 的十进制值和相对误差
        // if (dtype_sel == FP16_MODE) begin
        //     rel_tolerance = 1e-2; // FP16: 0.01
        //     abs_tolerance = 1e-5; // FP16: 1e-5
        //     $display("TPU result matrix (16x16) in decimal with error values:");
        //     for (i = 0; i < 16; i = i + 1) begin
        //         for (j = 0; j < 16; j = j + 1) begin
        //             automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*16 + j]);
        //             automatic reg [31:0] ref_bits = $realtobits(ref_result[i*16 + j]);
        //             automatic reg [15:0] tpu_fp16 = tpu_bits[15:0];
        //             automatic reg [15:0] ref_fp16 = ref_bits[15:0];
        //             // 转换 TPU 输出和参考结果
        //             convert_fp16_to_real(tpu_fp16, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
        //             tpu_mant_fp16 = tpu_fp16[9:0];
        //             convert_fp16_to_real(ref_fp16, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
        //             ref_mant_fp16 = ref_fp16[9:0];
        //             // 计算误差
        //             diff = tpu_val - ref_val;
        //             $write("Position [%0d][%0d]: TPU=", i, j);
        //             print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
        //             $write("           Expected=");
        //             print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
        //             // 打印误差
        //             if (tpu_is_inf || tpu_is_nan || ref_is_inf || ref_is_nan) begin
        //                 $display("           Error: N/A (Special value)");
        //             end else if (tpu_is_zero && ref_is_zero) begin
        //                 $display("           Error: 0.00e+00 (Both zero)");
        //             end else if (ref_val == 0.0) begin
        //                 $display("           Absolute Error: %.2e", diff);
        //             end else begin
        //                 rel_error = diff / ref_val;
        //                 $display("           Relative Error: %.2e, Absolute Error: %.2e", rel_error, diff);
        //             end
        //         end
        //         $display(""); // 每行结束后换行
        //     end
        // end else if (dtype_sel == FP32_MODE) begin
        //     rel_tolerance = 1e-5; // FP32: 1e-5
        //     abs_tolerance = 1e-10; // FP32: 1e-10
        //     $display("TPU result matrix (16x16) in decimal with error values:");
        //     for (i = 0; i < 16; i = i + 1) begin
        //         for (j = 0; j < 16; j = j + 1) begin
        //             automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*16 + j]);
        //             automatic reg [31:0] ref_bits = $realtobits(ref_result[i*16 + j]);
        //             // 转换 TPU 输出和参考结果
        //             convert_fp32_to_real(tpu_bits, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
        //             tpu_mant_fp32 = tpu_bits[22:0];
        //             convert_fp32_to_real(ref_bits, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
        //             ref_mant_fp32 = ref_bits[22:0];
        //             // 计算误差
        //             diff = tpu_val - ref_val;
        //             $write("Position [%0d][%0d]: TPU=", i, j);
        //             print_fp32_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign, tpu_mant_fp32);
        //             $write("           Expected=");
        //             print_fp32_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32);
        //             // 打印误差
        //             if (tpu_is_inf || tpu_is_nan || ref_is_inf || ref_is_nan) begin
        //                 $display("           Error: N/A (Special value)");
        //             end else if (tpu_is_zero && ref_is_zero) begin
        //                 $display("           Error: 0.00e+00 (Both zero)");
        //             end else if (ref_val == 0.0) begin
        //                 $display("           Absolute Error: %.2e", diff);
        //             end else begin
        //                 rel_error = diff / ref_val;
        //                 $display("           Relative Error: %.2e, Absolute Error: %.2e", rel_error, diff);
        //             end
        //         end
        //         $display(""); // 每行结束后换行
        //     end
        // end

        case (dtype_sel)
            INT4_MODE: $write("Data type: INT4, ");
            INT8_MODE: $write("Data type: INT8, ");
            FP16_MODE: $write("Data type: FP16, ");
            FP32_MODE: $write("Data type: FP32, ");
            default: $write("Data type: Unknown, ");
        endcase
        if (mixed_precision)
            $display("Mixed precision: Enabled (interpreted by bridge as fused RELU for FP32)");
        else
            $display("Mixed precision: Disabled");
    end else begin
        $display("Verification failed: Found %0d errors!", errors);
    end

    test_done = 1'b1;
    $finish;
end

initial begin : timeout_block
    repeat (4000) @(posedge clk);
    if (test_done)
        disable timeout_block;
    $display("ERROR: fused heavyweight testbench timeout.");
    $display("  verify_start=%0b send_done_seen=%0b output_idx=%0d",
             verify_start, send_done_seen, tpu_idx);
    $display("  active_opcode=%h exec_inflight=%0b active_waits_for_ewise=%0b active_waits_for_writeback=%0b",
             tpu_top.active_opcode, tpu_top.exec_inflight, tpu_top.active_waits_for_ewise, tpu_top.active_waits_for_writeback);
    $display("  ewise_active=%0b ewise_done=%0b writeback_start_pulse=%0b send_done=%0b",
             tpu_top.ewise_active, tpu_top.ewise_done, tpu_top.writeback_start_pulse, send_done);
    $finish(1);
end
endmodule
