module Rounding_FP16(
    input [15:0] mant_norm,
    input [4:0] exp_norm,
    input [15:0]sticky_in,
    output [9:0] mant_round,
    output [4:0] exp_round

);


    wire [9:0] mant_main ;
    assign mant_main = mant_norm[15:6]; // 主尾数

    //GRS
    wire       guard   ;
    wire       round   ;
    wire       sticky  ;
    assign guard    = mant_norm[5];
    assign round    = mant_norm[4];
    assign sticky   = (|mant_norm[3:0]) | (|sticky_in); 

    wire round_up;
    assign round_up = (guard && (round | sticky)) || 
                  (guard && ~round && ~sticky && mant_main[0]); 

    wire [10:0] mant_rounded;// 舍入后的结果
    assign mant_rounded = mant_main + round_up;

    assign mant_round = mant_rounded[9:0];
    assign exp_round = mant_rounded[10]? exp_norm + 1 : exp_norm;

endmodule

module Rounding_FP32(
    input [28:0] mant_norm,
    input [7:0] exp_norm,
    input [15:0]sticky_in,
    output [22:0] mant_round,
    output [7:0] exp_round

);


    wire [22:0] mant_main ;
    assign mant_main = mant_norm[28:6]; // 主尾数

    //GRS
    wire       guard   ;
    wire       round   ;
    wire       sticky  ;
    assign guard    = mant_norm[5];
    assign round    = mant_norm[4];
    assign sticky   = (|mant_norm[3:0]) | (|sticky_in); 

    wire round_up;
    assign round_up = (guard && (round | sticky)) || 
                  (guard && ~round && ~sticky && mant_main[0]); 

    wire [23:0] mant_rounded;// 舍入后的结果
    assign mant_rounded = mant_main + round_up;

    assign mant_round = mant_rounded[22:0];
    assign exp_round = mant_rounded[23]? exp_norm + 1 : exp_norm;

endmodule

module Rounding_FP32_mul(
    input [47:0] mant_norm,
    input signed [8:0] exp_norm,
    output [22:0] mant_round,
    output signed [8:0] exp_round

);


    wire [22:0] mant_main ;
    assign mant_main = mant_norm[45:23]; // 主尾数

    //GRS
    wire       guard   ;
    wire       round   ;
    wire       sticky  ;
    assign guard    = mant_norm[22];
    assign round    = mant_norm[21];
    assign sticky   = |mant_norm[20:0] ; 

    wire round_up;
    assign round_up = (guard && (round | sticky)) || 
                  (guard && ~round && ~sticky && mant_main[0]); 

    wire [23:0] mant_rounded;// 舍入后的结果
    assign mant_rounded = mant_main + round_up;

    assign mant_round = mant_rounded[22:0];
    assign exp_round = mant_rounded[23]? exp_norm + 1 : exp_norm;

endmodule

module Rounding_FP16_mul(
    input [21:0] mant_norm,
    input signed [5:0] exp_norm,
    output [9:0] mant_round,
    output signed [5:0] exp_round

);


    wire [9:0] mant_main ;
    assign mant_main = mant_norm[19:10]; // 主尾数

    //GRS
    wire       guard   ;
    wire       round   ;
    wire       sticky  ;
    assign guard    = mant_norm[9];
    assign round    = mant_norm[8];
    assign sticky   = |mant_norm[7:0] ; 

    wire round_up;
    assign round_up = (guard && (round | sticky)) || 
                  (guard && ~round && ~sticky && mant_main[0]); 

    wire [10:0] mant_rounded;// 舍入后的结果
    assign mant_rounded = mant_main + round_up;

    assign mant_round = mant_rounded[9:0];
    assign exp_round = mant_rounded[10]? exp_norm + 1 : exp_norm;

endmodule