`timescale 1ns / 1ps

module tb_tpu_top_m32n8k16;

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
reg mixed_precision;  // Mixed precision enable signal

// Signals
reg clk, rst_n;
reg tpu_start;
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

// Data storage
reg [31:0] matrix_A [0:511];  // 32x16 matrix
reg [31:0] matrix_B [0:127];  // 16x8 matrix
reg [31:0] matrix_C [0:255];  // 32x8 matrix
reg [AXI_DATA_WIDTH-1:0] data_packet_A [0:127]; // 32x16 matrix, 128 packets
reg [AXI_DATA_WIDTH-1:0] data_packet_B [0:63];  // 16x8 matrix (transposed to 8x16), 64 packets
reg [AXI_DATA_WIDTH-1:0] data_packet_C [0:127]; // 32x8 matrix, 128 packets
real ref_result [0:255];      // Use real for reference results
real tpu_result [0:255];      // Use real to support FP32 in mixed precision
reg [31:0] ref_result_fp16 [0:255]; // Storage for FP16 reference result
reg [31:0] ref_result_fp32 [0:255]; // Storage for FP32 reference result
reg [1:0] matrix_select;
integer i, j, k;
integer tpu_idx;
integer errors;

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

// Task 1: Convert FP32 to real value
task convert_fp32_to_real;
    input [31:0] fp32_bits;           // Input 32-bit FP32 data
    output real value;                // Output decimal value
    output reg is_inf, is_nan, is_zero; // Special case flags
    output reg sign;                  // Sign bit
    reg [7:0] exp;
    reg [22:0] mant;
    real scale;
    begin
        // Initialize outputs
        value = 0.0;
        is_inf = 0;
        is_nan = 0;
        is_zero = 0;
        sign = fp32_bits[31];         // Sign bit
        exp = fp32_bits[30:23];       // Exponent
        mant = fp32_bits[22:0];       // Mantissa

        // Handle special cases
        if (exp == 8'd255) begin
            if (mant == 0) begin
                is_inf = 1;           // Infinity
            end else begin
                is_nan = 1;           // NaN
            end
        end else if (exp == 8'd0) begin
            if (mant == 0) begin
                is_zero = 1;          // Zero
            end else begin
                // Denormalized number
                value = (mant / 8388608.0) * (2.0 ** (-126));
                if (sign) value = -value;
            end
        end else begin
            // Normalized number
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

// Task 2: Print FP32 value
task print_fp32_value;
    input real value;                 // Decimal value
    input is_inf, is_nan, is_zero;    // Special case flags
    input sign;                       // Sign bit
    input [22:0] mant;                // Mantissa (to distinguish QNaN and SNaN)
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

// Task 3: Convert FP16 to real value
task convert_fp16_to_real;
    input [15:0] fp16_bits;           // Input 16-bit FP16 data
    output real value;                // Output decimal value
    output reg is_inf, is_nan, is_zero; // Special case flags
    output reg sign;                  // Sign bit
    reg [4:0] exp;
    reg [9:0] mant;
    real scale;
    begin
        // Initialize outputs
        value = 0.0;
        is_inf = 0;
        is_nan = 0;
        is_zero = 0;
        sign = fp16_bits[15];         // Sign bit
        exp = fp16_bits[14:10];       // Exponent
        mant = fp16_bits[9:0];        // Mantissa

        // Handle special cases
        if (exp == 5'd31) begin
            if (mant == 0) begin
                is_inf = 1;           // Infinity
            end else begin
                is_nan = 1;           // NaN
            end
        end else if (exp == 5'd0) begin
            if (mant == 0) begin
                is_zero = 1;          // Zero
            end else begin
                // Denormalized number
                value = (mant / 1024.0) * (2.0 ** (-14));
                if (sign) value = -value;
            end
        end else begin
            // Normalized number
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

// Task 4: Print FP16 value
task print_fp16_value;
    input real value;                 // Decimal value
    input is_inf, is_nan, is_zero;    // Special case flags
    input sign;                       // Sign bit
    begin
        if (is_inf) begin
            $display("FP16 Result: %sInfinity", sign ? "-" : "+");
        end else if (is_nan) begin
            $display("FP16 Result: NaN");
        end else if (is_zero) begin
            $display("FP16 Result: %sZero", sign ? "-" : "+");
        end else begin
            $display("FP16 Result: %.7f", value); // FP16 has lower precision, use 7 decimal places
        end
    end
endtask

// Matrix Initialization from Files
initial begin
    real a_val, b_val, c_val; // Declare variables
    dtype_sel = FP32_MODE;    // Default to INT4, can be changed to INT8, FP16, FP32
    mixed_precision = 0;      // Mixed precision disabled by default
    $display("Reading matrix data from .mem files for dtype_sel=%0b, mixed_precision=%0b...", dtype_sel, mixed_precision);
    
    // Load matrix A, B, C based on dtype_sel
    case (dtype_sel)
        INT8_MODE: begin
            if(mixed_precision) begin
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int8_int32/m32n8k16/matrix_a_int8.mem", matrix_A);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int8_int32/m32n8k16/matrix_b_int8.mem", matrix_B);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int8_int32/m32n8k16/matrix_c_int32.mem", matrix_C);
            end else begin
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int8/m32n8k16/matrix_a_int8.mem", matrix_A);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int8/m32n8k16/matrix_b_int8.mem", matrix_B);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int8/m32n8k16/matrix_c_int8.mem", matrix_C); 
            end
        end
        INT4_MODE: begin
            if(mixed_precision) begin
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int4_int32/m32n8k16/matrix_a_int4.mem", matrix_A);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int4_int32/m32n8k16/matrix_b_int4.mem", matrix_B);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int4_int32/m32n8k16/matrix_c_int32.mem", matrix_C);
            end else begin
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int4/m32n8k16/matrix_a_int4.mem", matrix_A);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int4/m32n8k16/matrix_b_int4.mem", matrix_B);
                $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/int4/m32n8k16/matrix_c_int4.mem", matrix_C); 
            end
        end
        FP16_MODE: begin
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/matrix_a_fp16.mem", matrix_A);
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/matrix_b_fp16.mem", matrix_B);
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/matrix_c_fp16.mem", matrix_C);
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/ref_result_fp16_m32n8k16.mem", ref_result_fp16);
        end
        FP32_MODE: begin
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m32n8k16/matrix_a_fp32.mem", matrix_A);
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m32n8k16/matrix_b_fp32.mem", matrix_B);
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m32n8k16/matrix_c_fp32.mem", matrix_C);
            $readmemh("D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m32n8k16/ref_result_fp32_m32n8k16.mem", ref_result_fp32);
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
        for (i = 0; i < 32; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                ref_result[i*8 + j] = 0.0;
                for (k = 0; k < 16; k = k + 1) begin
                    case (dtype_sel)
                        INT8_MODE: begin
                            a_val = $signed(matrix_A[i*16 + k][7:0]);
                            b_val = $signed(matrix_B[k*8 + j][7:0]);
                        end
                        INT4_MODE: begin
                            a_val = $signed(matrix_A[i*16 + k][3:0]);
                            b_val = $signed(matrix_B[k*8 + j][3:0]);
                        end
                    endcase
                    ref_result[i*8 + j] = ref_result[i*8 + j] + a_val * b_val;
                end
                if (mixed_precision) begin
                    c_val = $signed(matrix_C[i*8 + j]);
                end else begin
                    case (dtype_sel)
                        INT8_MODE: c_val = $signed(matrix_C[i*8 + j][7:0]);
                        INT4_MODE: c_val = $signed(matrix_C[i*8 + j][3:0]);
                    endcase
                end
                ref_result[i*8 + j] = ref_result[i*8 + j] + c_val;
            end
        end
    end else if (dtype_sel == FP16_MODE) begin
        for (i = 0; i < 32; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                ref_result[i*8 + j] = $bitstoreal(ref_result_fp16[i*8 + j]);
            end
        end
    end else if (dtype_sel == FP32_MODE) begin
        for (i = 0; i < 32; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                ref_result[i*8 + j] = $bitstoreal(ref_result_fp32[i*8 + j]);
            end
        end
    end

    // Print ref_result in matrix format (32x8) in hex
    $display("Reference result matrix (32x8) in hex:");
    for (i = 0; i < 32; i = i + 1) begin
        for (j = 0; j < 8; j = j + 1) begin
            if (mixed_precision) begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: $write("%h ", $rtoi(ref_result[i*8 + j]));
                    FP16_MODE, FP32_MODE: $write("%8h ", $realtobits(ref_result[i*8 + j]));
                endcase
            end else begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: $write("%h ", $rtoi(ref_result[i*8 + j]));
                    FP16_MODE, FP32_MODE: $write("%8h ", $realtobits(ref_result[i*8 + j]));
                endcase
            end
        end
        $display(""); // New line after each row
    end
end

// Packing matrices
initial begin
    case (dtype_sel)
        INT8_MODE: begin
            // Packing matrix A (32x16, 32 rows, 4 packets/row, 128 packets)
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = {24'b0, matrix_A[i*16 + (k*8 + j)][7:0]};
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B (8x16, 8 rows, 4 packets/row, 64 packets)
            for (i = 0; i < 8; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = {24'b0, matrix_B[(k*8 + j)*8 + i][7:0]};
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C (32x8, 32 rows, 4 packets/row, 128 packets)
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k == 0 && j < 8) begin
                            if (mixed_precision)
                                data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*8 + j];
                            else
                                data_packet_C[i*4 + k][j*32 +: 32] = {24'b0, matrix_C[i*8 + j][7:0]};
                        end else
                            data_packet_C[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
        end
        INT4_MODE: begin
            // Packing matrix A
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = {28'b0, matrix_A[i*16 + (k*8 + j)][3:0]};
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B
            for (i = 0; i < 8; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = {28'b0, matrix_B[(k*8 + j)*8 + i][3:0]};
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k == 0 && j < 8) begin
                            if (mixed_precision)
                                data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*8 + j];
                            else
                                data_packet_C[i*4 + k][j*32 +: 32] = {28'b0, matrix_C[i*8 + j][3:0]};
                        end else
                            data_packet_C[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
        end
        FP16_MODE: begin
            // Packing matrix A
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = {16'b0, matrix_A[i*16 + (k*8 + j)][15:0]};
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B
            for (i = 0; i < 8; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = {16'b0, matrix_B[(k*8 + j)*8 + i][15:0]};
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k == 0 && j < 8) begin
                            if (mixed_precision)
                                data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*8 + j];
                            else
                                data_packet_C[i*4 + k][j*32 +: 32] = {16'b0, matrix_C[i*8 + j][15:0]};
                        end else
                            data_packet_C[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
        end
        FP32_MODE: begin
            // Packing matrix A
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_A[i*4 + k][j*32 +: 32] = matrix_A[i*16 + (k*8 + j)];
                        else
                            data_packet_A[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing transposed matrix B
            for (i = 0; i < 8; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k < 2 && k*8 + j < 16)
                            data_packet_B[i*4 + k][j*32 +: 32] = matrix_B[(k*8 + j)*8 + i];
                        else
                            data_packet_B[i*4 + k][j*32 +: 32] = 32'b0;
                    end
                end
            end
            // Packing matrix C
            for (i = 0; i < 32; i = i + 1) begin
                for (k = 0; k < 4; k = k + 1) begin
                    for (j = 0; j < 8; j = j + 1) begin
                        if (k == 0 && j < 8)
                            data_packet_C[i*4 + k][j*32 +: 32] = matrix_C[i*8 + j];
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
end

always @(posedge clk) begin
    if (m_wvalid && m_wready) begin
        for (j = 0; j < 8; j = j + 1) begin
            if (tpu_idx < 256) begin
                if (mixed_precision) begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: tpu_result[tpu_idx] = $itor($signed(m_wdata[j*32 +: 32]));
                        FP16_MODE, FP32_MODE: tpu_result[tpu_idx] = $bitstoreal(m_wdata[j*32 +: 32]);
                    endcase
                end else begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: tpu_result[tpu_idx] = $itor($signed(m_wdata[j*32 +: 32]));
                        FP16_MODE: tpu_result[tpu_idx] = $bitstoreal({16'b0, m_wdata[j*32 + 15 -: 16]});
                        FP32_MODE: tpu_result[tpu_idx] = $bitstoreal(m_wdata[j*32 +: 32]);
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
        pwdata <= {3'b010, dtype, mp}; // pwdata[6:4]=mtype_sel=010, pwdata[3:1]=dtype_sel, pwdata[0]=mixed_precision
        @(posedge pclk); penable <= 1;
        while (!pready) @(posedge pclk);
        if (penable && pready && psel) begin
            psel <= 0; penable <= 0;
        end
        @(posedge pclk); psel <= 0; penable <= 0;
    end
endtask

// Test sequence
initial begin
    tpu_start <= 0; psel <= 0; penable <= 0; pwrite <= 0; pwdata <= 7'b0;
    s_awvalid <= 0; s_awaddr <= 0; s_awlen <= 0; s_awburst <= 0;
    s_wvalid <= 0; s_wdata <= 0; s_wlast <= 0; s_bready <= 0;
    matrix_select <= 0; m_awready <= 1; m_wready <= 1;
    m_bvalid <= 0; m_bresp <= 2'b00;
    errors = 0;

    wait (rst_n == 1 && presetn == 1);
    #100;

    $display("APB configuration...");
    apb_write(dtype_sel, mixed_precision); // Set dtype_sel and mixed_precision
    #20;

    $display("Sending matrix A (32x16, 128 packets, addr=0)...");
    matrix_select <= 0;
    axi_write_burst(0, 127, 2'b01);

    $display("Sending matrix B (transposed to 8x16, 64 packets, addr=32)...");
    matrix_select <= 1;
    axi_write_burst(32, 63, 2'b01);

    $display("Sending matrix C (32x8, 128 packets, addr=64)...");
    matrix_select <= 2;
    axi_write_burst(64, 127, 2'b01);

    #110;
    $display("Starting TPU...");
    tpu_start <= 1;
    repeat (3) @(posedge clk);
    tpu_start <= 0;

    wait (tpu_done == 1);
    $display("TPU computation completed at %0t", $time);

    wait (m_wvalid && m_wready && m_wlast);
    @(posedge clk);
    m_bvalid <= 1; m_bresp <= 2'b00;
    @(posedge clk);
    if (m_bready) m_bvalid <= 0;

    wait (send_done == 1);
    $display("All operations completed at %0t", $time);
end

// Verify results
initial begin
    real diff, rel_error;
    real tpu_val, ref_val;            // Used to store converted real values
    automatic real rel_tolerance;      // Relative error tolerance, set dynamically based on mode
    automatic real abs_tolerance;      // Absolute error tolerance, set dynamically based on mode
    reg tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign;
    reg ref_is_inf, ref_is_nan, ref_is_zero, ref_sign;
    reg [22:0] tpu_mant_fp32, ref_mant_fp32; // For FP32
    reg [9:0] tpu_mant_fp16, ref_mant_fp16;  // For FP16
    wait (send_done == 1);
    #100;

    $display("Verifying TPU output results...");
    errors = 0;
    for (i = 0; i < 32; i = i + 1) begin
        for (j = 0; j < 8; j = j + 1) begin
            // Set tolerances based on data type
            if (dtype_sel == FP16_MODE) begin
                rel_tolerance = 3e-1; // FP16: 0.01
                abs_tolerance = 1e-5; // FP16: 1e-5
            end else if (dtype_sel == FP32_MODE) begin
                rel_tolerance = 1e-5; // FP32: 1e-5
                abs_tolerance = 1e-10; // FP32: 1e-10
            end else begin
                rel_tolerance = 0.0; // Integer modes don't need tolerance
                abs_tolerance = 0.0;
            end

            if (mixed_precision) begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: begin
                        automatic integer ref_int = $rtoi(ref_result[i*8 + j]);
                        automatic integer tpu_int = $rtoi(tpu_result[i*8 + j]);
                        if (tpu_int != ref_int) begin
                            $display("Error: Position [%0d][%0d], TPU output=0x%h (%0d), Expected=0x%h (%0d)", 
                                     i, j, tpu_int, tpu_int, ref_int, ref_int);
                            errors = errors + 1;
                        end
                    end
                    FP16_MODE: begin
                        automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*8 + j]);
                        automatic reg [31:0] ref_bits = $realtobits(ref_result[i*8 + j]);
                        automatic reg [15:0] tpu_fp16 = tpu_bits[15:0]; // Extract lower 16 bits
                        automatic reg [15:0] ref_fp16 = ref_bits[15:0];
                        // Convert TPU output
                        convert_fp16_to_real(tpu_fp16, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                        tpu_mant_fp16 = tpu_fp16[9:0];
                        // Convert reference result
                        convert_fp16_to_real(ref_fp16, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                        ref_mant_fp16 = ref_fp16[9:0];
                        // Compare special cases
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
                            // Numerical comparison: Check both relative and absolute errors
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
                                // Reference is zero, check absolute error only
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
                        automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*8 + j]);
                        automatic reg [31:0] ref_bits = $realtobits(ref_result[i*8 + j]);
                        // Convert TPU output
                        convert_fp32_to_real(tpu_bits, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                        tpu_mant_fp32 = tpu_bits[22:0];
                        // Convert reference result
                        convert_fp32_to_real(ref_bits, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                        ref_mant_fp32 = ref_bits[22:0];
                        // Compare special cases
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
                            // Numerical comparison: Check both relative and absolute errors
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
                                // Reference is zero, check absolute error only
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
            end else begin
                case (dtype_sel)
                    INT8_MODE, INT4_MODE: begin
                        automatic integer ref_int = $rtoi(ref_result[i*8 + j]);
                        automatic integer tpu_int = $rtoi(tpu_result[i*8 + j]);
                        if (tpu_int != ref_int) begin
                            $display("Error: Position [%0d][%0d], TPU output=0x%h (%0d), Expected=0x%h (%0d)", 
                                     i, j, tpu_int, tpu_int, ref_int, ref_int);
                            errors = errors + 1;
                        end
                    end
                    FP16_MODE: begin
                        automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*8 + j]);
                        automatic reg [31:0] ref_bits = $realtobits(ref_result[i*8 + j]);
                        automatic reg [15:0] tpu_fp16 = tpu_bits[15:0];
                        automatic reg [15:0] ref_fp16 = ref_bits[15:0];
                        // Convert TPU output
                        convert_fp16_to_real(tpu_fp16, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                        tpu_mant_fp16 = tpu_fp16[9:0];
                        // Convert reference result
                        convert_fp16_to_real(ref_fp16, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                        ref_mant_fp16 = ref_fp16[9:0];
                        // Compare special cases
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
                            // Numerical comparison: Check both relative and absolute errors
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
                                // Reference is zero, check absolute error only
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
                        automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*8 + j]);
                        automatic reg [31:0] ref_bits = $realtobits(ref_result[i*8 + j]);
                        // Convert TPU output
                        convert_fp32_to_real(tpu_bits, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
                        tpu_mant_fp32 = tpu_bits[22:0];
                        // Convert reference result
                        convert_fp32_to_real(ref_bits, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
                        ref_mant_fp32 = ref_bits[22:0];
                        // Compare special cases
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
                            // Numerical comparison: Check both relative and absolute errors
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
                                // Reference is zero, check absolute error only
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

    if (errors == 0) begin
        $display("Verification passed: All %0d elements match!", 32*8);
        // Print tpu_result in matrix format (32x8) in hex
        $display("TPU result matrix (32x8) in hex:");
        for (i = 0; i < 32; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                if (mixed_precision) begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: $write("%h ", $rtoi(tpu_result[i*8 + j]));
                        FP16_MODE, FP32_MODE: $write("%8h ", $realtobits(tpu_result[i*8 + j]));
                    endcase
                end else begin
                    case (dtype_sel)
                        INT8_MODE, INT4_MODE: $write("%h ", $rtoi(tpu_result[i*8 + j]));
                        FP16_MODE, FP32_MODE: $write("%8h ", $realtobits(tpu_result[i*8 + j]));
                    endcase
                end
            end
            $display(""); // New line after each row
        end
        // // Print FP16 or FP32 decimal values and errors
        // if (dtype_sel == FP16_MODE) begin
        //     rel_tolerance = 1e-2; // FP16: 0.01
        //     abs_tolerance = 1e-5; // FP16: 1e-5
        //     $display("TPU result matrix (32x8) in decimal with error values:");
        //     for (i = 0; i < 32; i = i + 1) begin
        //         for (j = 0; j < 8; j = j + 1) begin
        //             automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*8 + j]);
        //             automatic reg [31:0] ref_bits = $realtobits(ref_result[i*8 + j]);
        //             automatic reg [15:0] tpu_fp16 = tpu_bits[15:0];
        //             automatic reg [15:0] ref_fp16 = ref_bits[15:0];
        //             // Convert TPU output and reference result
        //             convert_fp16_to_real(tpu_fp16, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
        //             tpu_mant_fp16 = tpu_fp16[9:0];
        //             convert_fp16_to_real(ref_fp16, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
        //             ref_mant_fp16 = ref_fp16[9:0];
        //             // Calculate error
        //             diff = tpu_val - ref_val;
        //             $write("Position [%0d][%0d]: TPU=", i, j);
        //             print_fp16_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
        //             $write("           Expected=");
        //             print_fp16_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
        //             // Print error
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
        //         $display(""); // New line after each row
        //     end
        // end else if (dtype_sel == FP32_MODE) begin
        //     rel_tolerance = 1e-5; // FP32: 1e-5
        //     abs_tolerance = 1e-10; // FP32: 1e-10
        //     $display("TPU result matrix (32x8) in decimal with error values:");
        //     for (i = 0; i < 32; i = i + 1) begin
        //         for (j = 0; j < 8; j = j + 1) begin
        //             automatic reg [31:0] tpu_bits = $realtobits(tpu_result[i*8 + j]);
        //             automatic reg [31:0] ref_bits = $realtobits(ref_result[i*8 + j]);
        //             // Convert TPU output and reference result
        //             convert_fp32_to_real(tpu_bits, tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign);
        //             tpu_mant_fp32 = tpu_bits[22:0];
        //             convert_fp32_to_real(ref_bits, ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign);
        //             ref_mant_fp32 = ref_bits[22:0];
        //             // Calculate error
        //             diff = tpu_val - ref_val;
        //             $write("Position [%0d][%0d]: TPU=", i, j);
        //             print_fp32_value(tpu_val, tpu_is_inf, tpu_is_nan, tpu_is_zero, tpu_sign, tpu_mant_fp32);
        //             $write("           Expected=");
        //             print_fp32_value(ref_val, ref_is_inf, ref_is_nan, ref_is_zero, ref_sign, ref_mant_fp32);
        //             // Print error
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
        //         $display(""); // New line after each row
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
            $display("Mixed precision: Enabled");
        else
            $display("Mixed precision: Disabled");
    end else begin
        $display("Verification failed: Found %0d errors!", errors);
    end

    $finish;
end

endmodule