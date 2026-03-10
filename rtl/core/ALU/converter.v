module converter(
    input enable,
    input [15:0] mul_16b,
    output reg [31:0] mul_converted
);

wire sign;
wire [4:0] exp_fp16;
wire [9:0] mant_fp16;

assign sign = mul_16b[15];
assign exp_fp16 = mul_16b[14:10];
assign mant_fp16 = mul_16b[9:0];

localparam [4:0] EXP_MAX_FP16 = 31;
localparam [7:0] EXP_MAX_FP32 = 255;
wire is_nan,is_inf,is_zero,is_subnormal;
wire exp_is_max = exp_fp16 == EXP_MAX_FP16;

assign is_nan = exp_is_max && (mant_fp16 != 0);
assign is_inf = exp_is_max && (mant_fp16 == 0);
assign is_zero = exp_fp16 == 0 && mant_fp16 == 0;
assign is_subnormal = exp_fp16 == 0 && mant_fp16 != 0;

wire [3:0] position;
LZD10 lzd10_inst(
    .sum(mant_fp16),
    .position(position)
);
always @(*) begin
    if (!enable) begin
        mul_converted = 32'b0;
    end else if (is_nan) begin
        mul_converted = {sign, EXP_MAX_FP32, {1'b1, 22'b0}}; // quiet NaN
    end else if (is_inf) begin
        mul_converted = {sign, EXP_MAX_FP32, 23'b0};
    end else if (is_zero) begin// 零
        mul_converted = {sign, 8'b0, 23'b0};
    end else if (is_subnormal) begin
        mul_converted = {sign, 127-14-position,mant_fp16 << position, 13'b0}; // 尾数左对齐
    end else begin
        // 正常数，指数需要调整偏移量
        // 新指数 = 原指数 - 15 + 127 = exp_fp16 + 112
        mul_converted = {sign, exp_fp16 + 8'd112, mant_fp16, 13'b0}; // 尾数左对齐
    end
end
endmodule