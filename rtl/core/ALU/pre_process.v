module pre_process(
    input  wire valid,
    input  wire [2:0]     mode            ,
    input  wire [31:0]    in_a_left       ,
    input  wire [31:0]    in_b_up         ,

    output reg a_sign_w,
    output reg b_sign_w,
    output reg [7:0] a_exp_w,
    output reg [7:0] b_exp_w,
    output reg [22:0] a_mant_w,
    output reg [22:0] b_mant_w,
    output reg [6:0] a_value_w,
    output reg [6:0] b_value_w,
    output wire [4:0] a_property_w,
    output wire [4:0] b_property_w,
    output out_valid
);
assign out_valid = valid;
parameter INT4_MODE = 3'b000,
          INT8_MODE = 3'b001,
          FP16_MODE = 3'b010,
          FP32_MODE = 3'b011;
          
always@(*)begin
    a_sign_w = 0; b_sign_w = 0;
    a_exp_w = 0;b_exp_w = 0;
    a_mant_w = 0;b_mant_w = 0;
    a_value_w = 0;b_value_w = 0;
    if(valid)begin
        case(mode)
            INT4_MODE:begin
                a_sign_w = in_a_left[3];
                b_sign_w = in_b_up[3];

                a_value_w = in_a_left[2:0];
                b_value_w = in_b_up[2:0];
            end
            INT8_MODE:begin
                a_sign_w = in_a_left[7];
                b_sign_w = in_b_up[7];

                a_value_w = in_a_left[6:0];
                b_value_w = in_b_up[6:0];
            end
            FP16_MODE:begin
                a_sign_w = in_a_left[15];
                b_sign_w = in_b_up[15];

                a_exp_w = in_a_left[14:10];
                b_exp_w = in_b_up[14:10];

                a_mant_w = in_a_left[9:0];
                b_mant_w = in_b_up[9:0];
            end
            FP32_MODE:begin
                a_sign_w = in_a_left[31];
                b_sign_w = in_b_up[31];

                a_exp_w = in_a_left[30:23];
                b_exp_w = in_b_up[30:23];

                a_mant_w = in_a_left[22:0];
                b_mant_w = in_b_up[22:0];
            end
        endcase
    end 
    // else begin
    //     a_sign_w = 0; b_sign_w = 0;
    //     a_exp_w = 0;b_exp_w = 0;
    //     a_mant_w = 0;b_mant_w = 0;
    //     a_value_w = 0;b_value_w = 0;
    // end
end

localparam [4:0] EXP_MAX_FP16 = 31;
localparam [7:0] EXP_MAX_FP32 = 255;
//指数为最大值
wire a_exp_is_max = ((mode == FP16_MODE) && (a_exp_w == EXP_MAX_FP16)) || 
                    ((mode == FP32_MODE) && (a_exp_w == EXP_MAX_FP32));

// Zero: exp == 0 and mantissa == 0
wire a_is_zero      = (a_exp_w == 0)        && (a_mant_w == 0);
// Subnormal: exp == 0 but mantissa ≠ 0 (no implicit leading 1)
wire a_is_subnormal = (a_exp_w == 0)        && (a_mant_w != 0);
// Inf/NaN: exp == max, mantissa == 0 or ≠ 0 respectively
wire a_is_inf = a_exp_is_max && (a_mant_w == 0);
wire a_is_nan = a_exp_is_max && (a_mant_w != 0);

wire a_is_normal    = ~a_exp_is_max && (a_exp_w != 0);


//指数为最大值
wire b_exp_is_max = ((mode == FP16_MODE) && (b_exp_w == EXP_MAX_FP16)) || 
                    ((mode == FP32_MODE) && (b_exp_w == EXP_MAX_FP32));

// Zero: exp == 0 and mantissa == 0
wire b_is_zero      = (b_exp_w == 0)        && (b_mant_w == 0);
// Subnormal: exp == 0 but mantissa ≠ 0 (no implicit leading 1)
wire b_is_subnormal = (b_exp_w == 0)        && (b_mant_w != 0);
// Inf/NaN: exp == max, mantissa == 0 or ≠ 0 respectively
wire b_is_inf = b_exp_is_max && (b_mant_w == 0);
wire b_is_nan = b_exp_is_max && (b_mant_w != 0);

wire b_is_normal    = ~b_exp_is_max && (b_exp_w != 0);

assign a_property_w = {a_is_nan, a_is_inf, a_is_zero, a_is_subnormal, a_is_normal};
assign b_property_w = {b_is_nan, b_is_inf, b_is_zero, b_is_subnormal, b_is_normal};



endmodule