module mul(
    input clk,
    input rst_n,
    input valid,
    input clean,
    input [2:0] mode,
    input mixed_precision,
    input a_sign,
    input b_sign,
    input [7:0] a_exp,
    input [7:0] b_exp,
    input [22:0] a_mant,
    input [22:0] b_mant,
    input [6:0] a_value,
    input [6:0] b_value,
    input [4:0] a_property,
    input [4:0] b_property,
    output reg [31:0] mul,
    output reg [5:0] result_property,
    // output reg [21:0] final_mant_saved,//用于混合精度运算
    output reg out_valid,
    output reg [2:0] mode_out,
    output reg mixed_precision_out
);
parameter INT4_MODE = 3'b000,
          INT8_MODE = 3'b001,
          FP16_MODE = 3'b010,
          FP32_MODE = 3'b011;

//属性解包
wire a_is_nan       = a_property[4];
wire a_is_inf       = a_property[3];
wire a_is_zero      = a_property[2];
wire a_is_subnormal = a_property[1];
wire a_is_normal    = a_property[0];

wire b_is_nan       = b_property[4];
wire b_is_inf       = b_property[3];
wire b_is_zero      = b_property[2];
wire b_is_subnormal = b_property[1];
wire b_is_normal    = b_property[0];

// 参数化 NaN 定义（QNaN = quiet NaN，最高位为1）
localparam [15:0] QNAN_FP16 = {1'b0, 5'b11111, 10'b1000000000}; // FP16 QNaN
localparam [31:0] QNAN_FP32 = {1'b0, 8'b11111111, 23'b10000000000000000000000}; // FP32 QNaN
localparam [4:0] EXP_MAX_FP16 = 31;
localparam [7:0] EXP_MAX_FP32 = 255;

reg [31:0] result_special_w;
reg        use_special_result_w;

wire result_sign = (a_sign ^ b_sign);
always @(*) begin
    use_special_result_w = 0;
    result_special_w = 32'd0;
    case(mode)
        FP16_MODE:begin
            if (a_is_nan || b_is_nan || (a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
                use_special_result_w = 1;
                result_special_w = QNAN_FP16;  // 自定义常量，带 quiet bit 的 NaN
            end else if (a_is_inf || b_is_inf) begin
                use_special_result_w = 1;
                result_special_w = {result_sign, EXP_MAX_FP16, 10'd0};  // ±∞
            end else if (a_is_zero || b_is_zero) begin
                use_special_result_w = 1;
                result_special_w = {result_sign, 5'd0, 10'd0};  // ±0
            end
        end
        FP32_MODE:begin
            if (a_is_nan || b_is_nan || (a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
                use_special_result_w = 1;
                result_special_w = QNAN_FP32;  // 自定义常量，带 quiet bit 的 NaN
            end else if (a_is_inf || b_is_inf) begin
                use_special_result_w = 1;
                result_special_w = {result_sign, EXP_MAX_FP32, 23'd0};  // ±∞
            end else if (a_is_zero || b_is_zero) begin
                use_special_result_w = 1;
                result_special_w = {result_sign, 8'd0, 23'd0};  // ±0
            end
        end
    endcase
end

/****************mul*******************/

/****符号位****/
wire mul_sign_w;
assign mul_sign_w = a_sign ^ b_sign;


/****指数部分****/
//对FP16,6位有效[5:0],对FP32,9位有效[8:0]
wire signed [8:0] exp_sum_w;//-252~254 -28~30
//对FP16，0< exp_FP16 -15 < 31，对FP32，0< exp_FP32 -127 < 255
localparam signed [8:0] FP16_BIAS = 15;
localparam signed [8:0] FP32_BIAS = 127;

//去偏置的指数
//对FP32,8位有效[7:0],对FP16,5位有效[4:0]
reg signed [7:0] a_exp_unbias,b_exp_unbias;//-126~127
always@(*)begin
    a_exp_unbias = 0;
    b_exp_unbias = 0;
    case(mode)
        FP16_MODE:begin
            a_exp_unbias = a_is_subnormal? (1 - FP16_BIAS) : ($signed(a_exp) - FP16_BIAS);
            b_exp_unbias = b_is_subnormal? (1 - FP16_BIAS) : ($signed(b_exp) - FP16_BIAS);
        end
        FP32_MODE:begin
            a_exp_unbias = a_is_subnormal? (1 - FP32_BIAS) : ($signed(a_exp) - FP32_BIAS);
            b_exp_unbias = b_is_subnormal? (1 - FP32_BIAS) : ($signed(b_exp) - FP32_BIAS);
        end
    endcase
end
assign exp_sum_w = a_exp_unbias + b_exp_unbias;


/****尾数部分****/
//对FP16，11位有效[10:0]，对FP32，24位有效[23:0]
reg [23:0] a_mul_mant_w;
reg [23:0] b_mul_mant_w;

always@(*)begin
    a_mul_mant_w = 0;
    b_mul_mant_w = 0;
    case(mode)
        FP16_MODE:begin
            if(a_is_subnormal)begin
                a_mul_mant_w = {1'b0,a_mant[9:0]};
            end else begin
                a_mul_mant_w = {1'b1,a_mant[9:0]};
            end
            if(b_is_subnormal)begin
                b_mul_mant_w = {1'b0,b_mant[9:0]};
            end else begin
                b_mul_mant_w = {1'b1,b_mant[9:0]};
            end
        end
        FP32_MODE:begin 
            if(a_is_subnormal)begin
                a_mul_mant_w = {1'b0,a_mant[22:0]};
            end else begin
                a_mul_mant_w = {1'b1,a_mant[22:0]};
            end
            if(b_is_subnormal)begin
                b_mul_mant_w = {1'b0,b_mant[22:0]};
            end else begin
                b_mul_mant_w = {1'b1,b_mant[22:0]};
            end
        end
    endcase
end

/****value部分****/
//对INT4,4位有效[3:0],对INT8,8位有效[7:0]
reg [7:0] a_mul_value_w;
reg [7:0] b_mul_value_w;

always@(*)begin
    a_mul_value_w = 0;
    b_mul_value_w = 0;
    case(mode)
        INT4_MODE:begin
            if(~a_sign)begin
                a_mul_value_w = a_value[2:0];
            end else begin
                a_mul_value_w = ~({a_sign,a_value[2:0]}) + 4'd1;
            end
            if(~b_sign)begin
                b_mul_value_w = b_value[2:0];
            end else begin
                b_mul_value_w = ~({b_sign,b_value[2:0]}) + 4'd1;
            end
        end
        INT8_MODE:begin
            if(~a_sign)begin
                a_mul_value_w = a_value[6:0];
            end else begin
                a_mul_value_w = ~({a_sign,a_value[6:0]}) + 8'd1;
            end
            if(~b_sign)begin
                b_mul_value_w = b_value[6:0];
            end else begin
                b_mul_value_w = ~({b_sign,b_value[6:0]}) + 8'd1;
            end
        end
    endcase
end

//寄存器
reg         [2:0] mode_pre;
reg  mixed_precision_pre;
reg         pre_valid   ;
reg         mul_sign    ;
reg signed [8:0]   exp_sum     ;
reg [23:0]  a_mul_mant  ;
reg [23:0]  b_mul_mant  ;
reg [7:0]   a_mul_value ;
reg [7:0]   b_mul_value ;
reg [31:0] result_special;
reg        use_special_result;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_pre    <=  0;
        mul_sign    <=  0;
        exp_sum     <=  0;
        a_mul_mant  <=  0;
        b_mul_mant  <=  0;
        a_mul_value <=  0;
        b_mul_value <=  0;
        pre_valid   <=  0;
        result_special <= 0;
        use_special_result <= 0;
        mixed_precision_pre <= 0;
    end else if(~valid | clean)begin
        // mode_pre    <=  0;
        mul_sign    <=  0;
        exp_sum     <=  0;
        a_mul_mant  <=  0;
        b_mul_mant  <=  0;
        a_mul_value <=  0;
        b_mul_value <=  0;
        pre_valid   <=  0;
        result_special <= 0;
        use_special_result <= 0;
        // mixed_precision_pre <= 0;
    end else begin
        mode_pre    <=  mode;
        mul_sign    <=  mul_sign_w;
        exp_sum     <=  exp_sum_w;
        a_mul_mant  <=  a_mul_mant_w;
        b_mul_mant  <=  b_mul_mant_w;
        a_mul_value <=  a_mul_value_w;
        b_mul_value <=  b_mul_value_w;
        pre_valid   <=  valid;
        result_special <=  result_special_w;
        use_special_result <=  use_special_result_w;
        mixed_precision_pre <= mixed_precision;
    end
end
/////////////////////////////////////////////////////////////////////////////////////////////

/****尾数乘法****/
reg [11:0] a0_w,a1_w,b0_w,b1_w;

//确定乘数
always@(*)begin
    a0_w = 0;a1_w = 0;b0_w = 0;b1_w = 0;
    case(mode_pre)
        INT4_MODE:begin
            a0_w = a_mul_value[3:0];//对INT4，取低四位有效位
            b0_w = b_mul_value[3:0];
        end
        INT8_MODE:begin
            a0_w = a_mul_value[7:0];//对INT8，取低八位有效位
            b0_w = b_mul_value[7:0];
        end
        FP16_MODE:begin
            a0_w = a_mul_mant[10:0];//对FP16，取低11位有效位
            b0_w = b_mul_mant[10:0];
        end
        FP32_MODE:begin
            {a1_w,a0_w} =  a_mul_mant;
            {b1_w,b0_w} =  b_mul_mant;
        end
    endcase
end

//寄存器
reg         [2:0] mode_tomul;
reg               mixed_precision_tomul;
reg         tomul_valid   ;
reg         mul_sign_r    ;
reg signed [8:0]   exp_sum_r     ;
reg [31:0] result_special_r;
reg        use_special_result_r;
reg [11:0] a0_r,a1_r,b0_r,b1_r;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_tomul <=  0;
        mixed_precision_tomul <= 0;
        tomul_valid   <=  0;
        mul_sign_r    <=  0;
        exp_sum_r     <=  0;
        result_special_r <= 0;
        use_special_result_r <= 0;
        a0_r <=  0;a1_r <=  0;b0_r <=  0;b1_r <=  0;
    end else if(~pre_valid | clean)begin
        // mode_tomul <=  0;
        // mixed_precision_tomul <= 0;
        tomul_valid   <=  0;
        mul_sign_r    <=  0;
        exp_sum_r     <=  0;
        result_special_r <= 0;
        use_special_result_r <= 0;
        a0_r <=  0;a1_r <=  0;b0_r <=  0;b1_r <=  0;
    end else begin
        mode_tomul <=  mode_pre;
        mixed_precision_tomul <= mixed_precision_pre;
        tomul_valid   <=  pre_valid;
        mul_sign_r    <=  mul_sign;
        exp_sum_r     <=  exp_sum;
        result_special_r <= result_special;
        use_special_result_r <= use_special_result;
        a0_r <=  a0_w;a1_r <=  a1_w;b0_r <=  b0_w;b1_r <=  b1_w;
    end
end

//调用乘法器相乘
wire [23:0] mul0_w, mul1_w, mul2_w, mul3_w;
multi12bX12b mult1(.a(a0_r),.b(b0_r),.c(mul0_w));
multi12bX12b mult2(.a(a0_r),.b(b1_r),.c(mul1_w));
multi12bX12b mult3(.a(a1_r),.b(b0_r),.c(mul2_w));
multi12bX12b mult4(.a(a1_r),.b(b1_r),.c(mul3_w));

//寄存器
reg         [2:0] mode_mant_mul;
reg               mixed_precision_mant_mul;
reg         mulx_valid   ;
reg         mul_sign_1    ;
reg signed [8:0]   exp_sum_1     ;
reg [23:0] mul0, mul1, mul2, mul3;
reg [31:0] result_special_1;
reg        use_special_result_1;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_mant_mul <=  0;
        mixed_precision_mant_mul <= 0;
        mulx_valid   <=  0;
        mul_sign_1    <=  0;
        exp_sum_1     <=  0;
        mul0 <=  0;mul1 <=  0;mul2 <=  0;mul3 <=  0;
        result_special_1 <= 0;
        use_special_result_1 <= 0;
    end else if(~tomul_valid | clean)begin
        // mode_mant_mul <=  0;
        // mixed_precision_mant_mul <= 0;
        mulx_valid   <=  0;
        mul_sign_1    <=  0;
        exp_sum_1     <=  0;
        mul0 <=  0;mul1 <=  0;mul2 <=  0;mul3 <=  0;
        result_special_1 <= 0;
        use_special_result_1 <= 0;
    end else begin
        mode_mant_mul <=  mode_tomul;
        mixed_precision_mant_mul <= mixed_precision_tomul;
        mulx_valid   <=  tomul_valid;
        mul_sign_1    <=  mul_sign_r;
        exp_sum_1     <=  exp_sum_r;
        mul0 <=  mul0_w; mul1 <=  mul1_w; mul2 <=  mul2_w; mul3 <=  mul3_w;
        result_special_1 <=  result_special_r;
        use_special_result_1 <=  use_special_result_r;
    end
end

////////////////////////////////////////////////////////////////////////////////////////////

//移位
reg [47:0] mul0_shift_w, mul1_shift_w, mul2_shift_w, mul3_shift_w;
always@(*)begin
    mul0_shift_w = 0;
    mul1_shift_w = 0;
    mul2_shift_w = 0;
    mul3_shift_w = 0;
    case(mode_mant_mul)
        INT4_MODE:begin
            mul0_shift_w = mul0;
        end
        INT8_MODE:begin
            mul0_shift_w = mul0;
        end
        FP16_MODE:begin
            mul0_shift_w = mul0;
        end
        FP32_MODE:begin
            mul0_shift_w = mul0;
            mul1_shift_w = mul1 << 12;
            mul2_shift_w = mul2 << 12;
            mul3_shift_w = mul3 << 24;
        end
    endcase
end
wire [47:0] mul_shift_w;//移位相加后的结果
//移位后相加
add_shift_48b add_shift(
    .a(mul0_shift_w),
    .b(mul1_shift_w),
    .c(mul2_shift_w),
    .d(mul3_shift_w),
    .sum(mul_shift_w)
);

//对FP16,11位相乘，结果22位有效，[21:0].对FP32,24位相乘，结果48位有效，[47:0]
reg [47:0] mul_mant_w;
//对INT4，有效位数为7位[6:0].对INT8,有效位数为15位[14:0]
reg [14:0] mul_value_w;

always@(*)begin
    mul_mant_w = 0;
    mul_value_w = 0;
    case(mode_mant_mul)
        INT4_MODE:begin
            mul_value_w = mul_shift_w[6:0];
        end
        INT8_MODE:begin
            mul_value_w = mul_shift_w[14:0];
        end
        FP16_MODE:begin
            mul_mant_w = mul_shift_w[21:0];
        end
        FP32_MODE:begin
            mul_mant_w = mul_shift_w;
        end
    endcase
end

//寄存器
reg         [2:0] mode_shift_add;
reg             mixed_precision_shift_add;
reg         mul_mant_valid   ;
reg         mul_sign_2    ;
reg signed [8:0]   exp_sum_2     ;
reg [14:0] mul_value;
reg [47:0] mul_mant;
reg [31:0] result_special_2;
reg        use_special_result_2;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_shift_add <=  0;
        mixed_precision_shift_add <= 0;
        mul_mant_valid   <=  0;
        mul_sign_2 <= 0;
        exp_sum_2 <= 0;
        mul_value <= 0;
        mul_mant <= 0;
        result_special_2 <= 0;
        use_special_result_2 <= 0;
    end else if(~mulx_valid | clean)begin
        // mode_shift_add <=  0;
        // mixed_precision_shift_add <= 0;
        mul_mant_valid   <=  0;
        mul_sign_2 <= 0;
        exp_sum_2 <= 0;
        mul_value <= 0;
        mul_mant <= 0;
        result_special_2 <= 0;
        use_special_result_2 <= 0;
    end else begin
        mode_shift_add <=  mode_mant_mul;
        mixed_precision_shift_add <= mixed_precision_mant_mul;
        mul_mant_valid   <=  mulx_valid;
        mul_sign_2 <= mul_sign_1;
        exp_sum_2 <= exp_sum_1;
        mul_value <= mul_value_w;
        mul_mant <= mul_mant_w;
        result_special_2 <= result_special_1;
        use_special_result_2 <= use_special_result_1;
    end
end
///////////////////////////////////////////////////////////////////////////////////////

/****规则化****/
//对FP16,有效位6位[5:0]，对FP32,有效位9位[8:0]
reg  signed [8:0] exp_norm_w;
wire signed [8:0] exp_norm_fp32;
wire signed [5:0] exp_norm_fp16;
//对FP16,有效位22位[21:0]，对FP32,有效位48位[47:0]
reg  [47:0] mant_norm_w;
wire [21:0] mant_norm_fp16;
wire [47:0] mant_norm_fp32;

wire signed [8:0] exp_sum_fp32;
wire signed [5:0] exp_sum_fp16;
wire [47:0] mant_sum_fp32;
wire [21:0] mant_sum_fp16;
assign mant_sum_fp32 = mode_shift_add == FP32_MODE? mul_mant : 0;
assign mant_sum_fp16 = mode_shift_add == FP16_MODE? mul_mant[21:0] : 0;
assign exp_sum_fp32 = exp_sum_2;
assign exp_sum_fp16 = exp_sum_2[5:0];

wire norm_inside_valid,norm_inside_valid_fp32,norm_inside_valid_fp16;
reg norm_inside_valid_int;
wire mul_mant_valid_fp32,mul_mant_valid_fp16,mul_mant_valid_int;
assign mul_mant_valid_fp32 = mode_shift_add == FP32_MODE && mul_mant_valid;
assign mul_mant_valid_fp16 = mode_shift_add == FP16_MODE && mul_mant_valid;
assign mul_mant_valid_int = (mode_shift_add == INT4_MODE || mode_shift_add == INT8_MODE) && mul_mant_valid;
assign norm_inside_valid = norm_inside_valid_fp32 || norm_inside_valid_fp16 || norm_inside_valid_int;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        norm_inside_valid_int <= 0;
    end else if(~mul_mant_valid_int | clean)begin
        norm_inside_valid_int <= 0;
    end else begin
        norm_inside_valid_int <= mul_mant_valid_int;
    end
end
Normalization_FP32_mul norm_fp32_mul(
    .clk(clk),
    .rst_n(rst_n),
    .valid(mul_mant_valid_fp32),
    .clean(clean),
    .mant(mant_sum_fp32),
   .exp(exp_sum_fp32),
   .norm_inside_valid(norm_inside_valid_fp32),
   .exp_norm(exp_norm_fp32),
   .mant_norm(mant_norm_fp32)
);

Normalization_FP16_mul norm_fp16_mul(
    .clk(clk),
    .rst_n(rst_n),
    .valid(mul_mant_valid_fp16),
    .clean(clean),
    .mant(mant_sum_fp16),
   .exp(exp_sum_fp16),
   .norm_inside_valid(norm_inside_valid_fp16),
   .exp_norm(exp_norm_fp16),
   .mant_norm(mant_norm_fp16)
);

//对其他信号打拍
reg [2:0] mode_norm_inside;
reg   mixed_precision_norm_inside;
reg         mul_sign_norm_inside;
reg [14:0] mul_value_norm_inside;
reg [31:0] result_special_norm_inside;
reg        use_special_result_norm_inside;

always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_norm_inside <=  0;
        mixed_precision_norm_inside <= 0;
        mul_sign_norm_inside <= 0;
        mul_value_norm_inside <= 0;
        result_special_norm_inside <= 0;
        use_special_result_norm_inside <= 0;
    end else if(~mul_mant_valid | clean)begin
        // mode_norm_inside <=  0;
        // mixed_precision_norm_inside <= 0;
        mul_sign_norm_inside <= 0;
        mul_value_norm_inside <= 0;
        result_special_norm_inside <= 0;
        use_special_result_norm_inside <= 0;
    end else begin
        mode_norm_inside <=  mode_shift_add;
        mixed_precision_norm_inside <= mixed_precision_shift_add;
        mul_sign_norm_inside <= mul_sign_2;
        mul_value_norm_inside <= mul_value;
        result_special_norm_inside <= result_special_2;
        use_special_result_norm_inside <= use_special_result_2;
    end
end
always@(*)begin
     exp_norm_w = -127;
     mant_norm_w = 0;
     case(mode_shift_add)
         FP16_MODE: begin
             exp_norm_w = {{3{exp_norm_fp16[5]}}, exp_norm_fp16};
             mant_norm_w = mant_norm_fp16;
         end
         FP32_MODE: begin
             exp_norm_w = exp_norm_fp32;
             mant_norm_w = mant_norm_fp32;
         end
     endcase
end
//寄存器
reg [2:0] mode_norm;
reg   mixed_precision_norm;
reg         norm_valid   ;
reg         mul_sign_3    ;
reg [14:0] mul_value_1;
reg  signed [8:0] exp_norm;
reg  [47:0] mant_norm;
reg [31:0] result_special_3;
reg        use_special_result_3;

always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_norm <=  0;
        mixed_precision_norm <= 0;
        norm_valid   <=  0;
        mul_sign_3 <= 0;
        exp_norm <= -127;
        mant_norm <= 0;
        result_special_3 <= 0;
        use_special_result_3 <= 0;
        mul_value_1 <= 0;
    end else if(~norm_inside_valid | clean)begin
        // mode_norm <=  0;
        // mixed_precision_norm <= 0;
        norm_valid   <=  0;
        mul_sign_3 <= 0;
        exp_norm <= -127;
        mant_norm <= 0;
        result_special_3 <= 0;
        use_special_result_3 <= 0;
        mul_value_1 <= 0;
    end else begin
        mode_norm <=  mode_norm_inside;
        mixed_precision_norm <= mixed_precision_norm_inside;
        norm_valid   <=  norm_inside_valid;
        mul_sign_3 <= mul_sign_norm_inside;
        exp_norm <= exp_norm_w;
        mant_norm <= mant_norm_w;
        result_special_3 <= result_special_norm_inside;
        use_special_result_3 <= use_special_result_norm_inside;
        mul_value_1 <= mul_value_norm_inside;
    end
end


///////////////////////////////////////////////////////////////////////////

/****舍入****/
//对FP16,6位有效[5:0],对FP32,9位有效[8:0]
reg signed [8:0] exp_round_w;
wire signed [8:0] exp_round_fp32;
wire signed [5:0] exp_round_fp16;
//对FP16,10位有效[9:0]，对FP32,23位有效[22:0]
//对FP16,10位有效[9:0]，对FP32,23位有效[22:0]
reg [22:0] mant_round_w;
wire [22:0] mant_round_fp32;
wire [9:0] mant_round_fp16;

wire signed [8:0] exp_fp32;
wire signed [5:0] exp_fp16;
assign exp_fp32 = exp_norm;
assign exp_fp16 = exp_norm[5:0];
wire [47:0] mant_fp32;
wire [21:0] mant_fp16;
assign mant_fp32 = mant_norm;
assign mant_fp16 = mant_norm[21:0];
//保留尾数，用于混合精度
// wire [21:0] mant_saved_w;
// assign mant_saved_w = mixed_precision_norm ? {mant_norm[19:0],2'd0} : 22'b0;

Rounding_FP32_mul round_fp32(
    .mant_norm(mant_fp32),
    .exp_norm(exp_fp32),
    .mant_round(mant_round_fp32),
    .exp_round(exp_round_fp32)
);
Rounding_FP16_mul round_fp16(
    .mant_norm(mant_fp16),
    .exp_norm(exp_fp16),
    .mant_round(mant_round_fp16),
    .exp_round(exp_round_fp16)
);
always@(*)begin
    exp_round_w = -127;
    mant_round_w = 0;
    case(mode_norm)
        FP16_MODE: begin
            exp_round_w = {{3{exp_round_fp16[5]}}, exp_round_fp16};
            mant_round_w = mant_round_fp16;
        end
        FP32_MODE: begin
            exp_round_w = exp_round_fp32;
            mant_round_w = mant_round_fp32;
        end
    endcase
end


//寄存器
reg [2:0] mode_round;
reg mixed_precision_round;
reg         round_valid   ;
reg         mul_sign_4    ;
reg signed [8:0]   exp_round      ;
reg [22:0]  mant_round      ;
// reg [21:0] mant_saved      ;
reg [14:0] mul_value_2;
reg [31:0] result_special_4;
reg        use_special_result_4;

always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_round <=  0;
        mixed_precision_round <= 0;
        round_valid <= 0;
        mul_sign_4 <= 0;
        exp_round  <= 0;
        mant_round <= 0;
        // mant_saved <= 0;
        mul_value_2 <= 0;
        result_special_4 <= 0;
        use_special_result_4 <= 0;
    end else if(~norm_valid | clean)begin
        // mode_round <=  0;
        // mixed_precision_round <= 0;
        round_valid <= 0;
        mul_sign_4 <= 0;
        exp_round  <= 0;
        mant_round <= 0;
        // mant_saved <= 0;
        mul_value_2 <= 0;
        result_special_4 <= 0;
        use_special_result_4 <= 0;
    end else begin
        mode_round <=  mode_norm;
        mixed_precision_round <= mixed_precision_norm;
        round_valid <= norm_valid;
        mul_sign_4 <= mul_sign_3;
        exp_round  <= exp_round_w;
        mant_round <= mant_round_w;
        // mant_saved <= mant_saved_w;
        mul_value_2 <= mul_value_1;
        result_special_4 <= result_special_3;
        use_special_result_4 <= use_special_result_3;
    end
end
////////////////////////////////////////////////////////////////////////////////////////////////
/****判断溢出****/
reg overflow_w  ;
//-14 <= exp_FP16 <= 15
//-126 <= exp_FP32 <= 127

always@(*)begin
    overflow_w  = 0;
    case(mode_round)
        FP16_MODE: begin
            if(exp_round > 15) begin
                overflow_w = 1;
            end
        end
        FP32_MODE: begin
            if(exp_round >  127) begin
                overflow_w = 1;
            end 
        end
    endcase
end


/****最终赋值****/
//对FP16,5位有效[4:0]，对FP32,8位有效[7:0]
reg [7:0] final_exp_w;
//对FP16，10位有效[9:0]，对FP32,23位有效[22:0]
reg [22:0] final_mant_w;
//INT4,7位有效位[6:0],INT8,15位有效位[14:0]
reg [14:0] final_value_w;//根据符号位确定要不要取补码
// reg [21:0] final_mant_saved_w;
always@(*)begin
    final_exp_w = 0;
    final_mant_w = 0;
    final_value_w = 0;
    // final_mant_saved_w = 0;
    case(mode_round)
        INT4_MODE: begin
            if(mul_sign_4)begin
                final_value_w = ~mul_value_2[6:0] + 7'd1;
            end else begin
                final_value_w = mul_value_2[6:0];
            end
        end
        INT8_MODE: begin
            if(mul_sign_4)begin
                final_value_w = ~mul_value_2[14:0] + 15'd1;
            end else begin
                final_value_w = mul_value_2[14:0];
            end
        end
        FP16_MODE: begin
            if(overflow_w)begin
                final_exp_w = 5'b11111;
                final_mant_w = 10'b0;
                // final_mant_saved_w = 22'b0;
            end else begin
                final_exp_w = $unsigned(exp_round + 15);
                final_mant_w = mant_round[9:0];
                // final_mant_saved_w = mant_saved;
            end
        end
        FP32_MODE: begin
            if(overflow_w) begin
                final_exp_w = 8'b11111111;
                final_mant_w = 23'b0000000000000000000000;
            end else begin
                final_exp_w = $unsigned(exp_round + 127);
                final_mant_w = mant_round[22:0];
            end
        end
    endcase
end

//INT4,8位有效[7:0],INT8,16位有效[15:0]
//FP16,16位有效[15:0],FP32,32位有效[31:0]
reg [31:0] mul_w;

always@(*)begin
    mul_w = 0;
    case(mode_round)
        INT4_MODE: begin
            mul_w = {24'd0,{mul_sign_4,final_value_w[6:0]}&{8{|final_value_w[6:0]}}};//8位
        end
        INT8_MODE: begin
            mul_w = {16'd0,{mul_sign_4,final_value_w[14:0]}&{16{|final_value_w[14:0]}}};
        end
        FP16_MODE: begin
            if(use_special_result_4)begin
                mul_w = {16'd0,result_special_4[15:0]};
            end else begin
                mul_w = {16'd0,mul_sign_4,final_exp_w[4:0],final_mant_w[9:0]};
            end
        end
        FP32_MODE: begin
            if(use_special_result_4)begin
                mul_w = result_special_4;
            end else begin
                mul_w = {mul_sign_4,final_exp_w[7:0],final_mant_w[22:0]};
            end
        end
    endcase
end

//寄存器
reg [2:0] mode_assign;
reg mixed_precision_assign;
reg         assign_valid   ;
reg [31:0] mul_assign;

always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_assign <= 0;
        mixed_precision_assign <= 0;
        assign_valid <= 0;
        mul_assign <= 0;
    end else if(~round_valid | clean)begin
        // mode_assign <= 0;
        // mixed_precision_assign <= 0;
        assign_valid <= 0;
        mul_assign <= 0;
    end else begin
        mode_assign <= mode_round;
        mixed_precision_assign <= mixed_precision_round;
        assign_valid <= round_valid;
        mul_assign <= mul_w;
    end
end

//根据mixed_precision_assign判断需不需要格式转换
wire convert_enable;
wire [31:0] mul_final;
wire [15:0] mul_to_convert;
wire [31:0] mul_converted;
assign convert_enable = assign_valid && mixed_precision_assign & (mode_assign == FP16_MODE);
assign mul_to_convert = convert_enable ? mul_assign[15:0] : 16'b0;
assign mul_final = convert_enable ? mul_converted : mul_assign;

converter converter_inst(
    .enable(convert_enable),
    .mul_16b(mul_to_convert),
    .mul_converted(mul_converted)
);

//判断输出结果属性
wire [5:0] mul_property;
wire [2:0] judge_mode;
assign judge_mode = (mixed_precision_assign & (mode_assign == FP16_MODE)) ? FP32_MODE : mode_assign;
judge_property judge_mul(
    .data_in(mul_final),
    .mode(judge_mode),
    .valid(assign_valid),
    .property_out(mul_property)
);


//寄存器
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        out_valid <= 0;
        mul <= 0;
        // final_mant_saved <= 0;
        mode_out <= 0;
        mixed_precision_out <= 0;
        result_property <= 0;
    end else if(~assign_valid | clean)begin
        // mode_out <= 0;
        // mixed_precision_out <= 0;
        out_valid <= 0;
        mul <= 0;
        // final_mant_saved <= 0;
        result_property <= 0;
    end else begin
        mode_out <= mode_assign;
        mixed_precision_out <= mixed_precision_assign;
        out_valid <= assign_valid;
        mul <= mul_final;
        // final_mant_saved <= final_mant_saved_w;
        result_property <= mul_property;
    end
end

endmodule