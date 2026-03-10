module judge_property(
    input [31:0] data_in,
    input [2:0] mode,
    input valid,
    output  [5:0] property_out//sign nan inf zero subnormal normal
);
    

    localparam [4:0] EXP_MAX_FP16 = 31;
    localparam [7:0] EXP_MAX_FP32 = 255;

    localparam INT4_MODE = 3'b000,
                INT8_MODE = 3'b001,
                FP16_MODE = 3'b010,
                FP32_MODE = 3'b011;
    reg sign;
    reg [7:0] exp;
    reg [22:0] mant;

    always @(*) begin
        sign = 0;
        exp = 0;
        mant = 0;
        case (mode)
            FP16_MODE: begin
                sign = data_in[15];
                exp = data_in[14:10];
                mant = data_in[9:0];
            end
            FP32_MODE: begin
                sign = data_in[31];
                exp = data_in[30:23];
                mant = data_in[22:0];
            end
        endcase
    end

    //指数为最大值
    wire data_exp_is_max = ((mode == FP16_MODE) && (exp == EXP_MAX_FP16)) || 
                        ((mode == FP32_MODE) && (exp == EXP_MAX_FP32));

    // Zero: exp == 0 and mantissa == 0
    wire data_is_zero      = (exp == 0)        && (mant == 0);
    // Subnormal: exp == 0 but mantissa ≠ 0 (no implicit leading 1)
    wire data_is_subnormal = (exp == 0)        && (mant != 0);
    // Inf/NaN: exp == max, mantissa == 0 or ≠ 0 respectively
    wire data_is_inf = data_exp_is_max && (mant == 0);
    wire data_is_nan = data_exp_is_max && (mant != 0);

    wire data_is_normal    = ~data_exp_is_max && (exp != 0);
    reg [5:0] property_out_w;
    always@(*)begin
        property_out_w = 0;
        case(mode)
            FP16_MODE, FP32_MODE:begin
                property_out_w = {sign, data_is_nan, data_is_inf, data_is_zero, data_is_subnormal, data_is_normal};
            end
        endcase
    end
    assign property_out = valid ? property_out_w : 6'b0;
endmodule