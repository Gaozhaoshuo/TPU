module alu(
    input  wire           clk             ,
    input  wire           rst_n           ,   

    input  wire           valid           ,
    input  wire [31:0]    in_a_left       ,
    input  wire [31:0]    in_b_up         ,

    input  wire [2:0]     mode            ,
    input  wire           clean           ,
    input  wire           mixed_precision ,

    output reg           out_valid       ,
    output reg [31:0]    sum
);

/****************mode*******************/
parameter INT4_MODE = 3'b000,
          INT8_MODE = 3'b001,
          FP16_MODE = 3'b010,
          FP32_MODE = 3'b011;

/****************预处理*******************/
wire a_sign_w,b_sign_w;
wire [7:0] a_exp_w,b_exp_w;
wire [22:0] a_mant_w,b_mant_w;
wire [6:0] a_value_w,b_value_w;//for INT4 INT8
wire pre_valid_w;
wire [4:0] a_property_w,b_property_w;
pre_process pre_process_inst(
    .valid(valid),
    .mode(mode),
    .in_a_left(in_a_left),
    .in_b_up(in_b_up),
    .a_sign_w(a_sign_w),
    .b_sign_w(b_sign_w),
    .a_exp_w(a_exp_w),
    .b_exp_w(b_exp_w),
    .a_mant_w(a_mant_w),
    .b_mant_w(b_mant_w),
    .a_value_w(a_value_w),
    .b_value_w(b_value_w),
    .a_property_w(a_property_w),
    .b_property_w(b_property_w),
    .out_valid(pre_valid_w)
);


//一级流水寄存器
reg a_sign,b_sign;
reg [7:0] a_exp,b_exp;
reg [22:0] a_mant,b_mant;
reg [6:0] a_value,b_value;//for INT4 INT8
reg [4:0] a_property,b_property;
reg pre_valid;

always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        pre_valid <= 0;
        a_sign <= 0; b_sign <= 0;
        a_exp <= 0;b_exp <= 0;
        a_mant <= 0;b_mant <= 0;
        a_value <= 0;b_value <= 0;
        a_property <= 0;b_property <= 0;
    end else if(~pre_valid_w | clean)begin
        pre_valid <= 0;
        a_sign <= 0; b_sign <= 0;
        a_exp <= 0;b_exp <= 0;
        a_mant <= 0;b_mant <= 0;
        a_value <= 0;b_value <= 0;
        a_property <= 0;b_property <= 0;
    end else begin
        a_sign <= a_sign_w; b_sign <= b_sign_w;
        a_exp <= a_exp_w;b_exp <= b_exp_w;
        a_mant <= a_mant_w;b_mant <= b_mant_w;
        a_value <= a_value_w;b_value <= b_value_w;
        pre_valid <= pre_valid_w;
        a_property <= a_property_w;b_property <= b_property_w;
    end
end

//信号打拍
reg [2:0] mode_stage_1;
reg mixed_precision_stage_1;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_stage_1 <= 0;
        mixed_precision_stage_1 <= 0;
    end else if(clean)begin
        // mode_stage_1 <= 0;
        // mixed_precision_stage_1 <= 0;
    end else begin
        mode_stage_1 <= mode;
        mixed_precision_stage_1 <= mixed_precision;
    end
end


/****************mul*******************/
wire [31:0] mul_w;
// wire [21:0] final_mant_saved_w;
wire mul_valid_w;
wire [2:0] mode_mul;
wire mixed_precision_stage_mul;
wire [5:0] mul_property_w;
mul mul_inst(
    .clk(clk),
    .rst_n(rst_n),
    .clean(clean),
    .valid(pre_valid),
    .mode(mode_stage_1),
    .mixed_precision(mixed_precision_stage_1),
    .a_sign(a_sign),
    .b_sign(b_sign),
    .a_exp(a_exp),
    .b_exp(b_exp),
    .a_mant(a_mant),
    .b_mant(b_mant),
    .a_value(a_value),
    .b_value(b_value),
    .a_property(a_property),
    .b_property(b_property),
    .mul(mul_w),
    // .final_mant_saved(final_mant_saved_w),
    .out_valid(mul_valid_w),
    .result_property(mul_property_w),
    .mode_out(mode_mul),
    .mixed_precision_out(mixed_precision_stage_mul)
);

/*******二级流水线输出********/
reg [2:0] mode_stage_2;
reg mixed_precision_stage_2;
reg [31:0] mul;
// reg [21:0] final_mant_saved;
reg mul_valid;
reg [5:0] mul_property;

always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mul <= 32'b0;
        // final_mant_saved <= 22'b0;
        mul_valid <= 0;
        mul_property <= 0;
    end else if(~mul_valid_w | clean)begin
        mul <= 32'b0;
        // final_mant_saved <= 22'b0;
        mul_valid <= 0;
        mul_property <= 0;
    end else begin
        mul <= mul_w;
        // final_mant_saved <= final_mant_saved_w;
        mul_valid <= mul_valid_w;
        mul_property <= mul_property_w;
    end
end


always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        mode_stage_2 <= 0;
        mixed_precision_stage_2 <= 0;
    end else if(~mul_valid_w |clean)begin
        // mode_stage_2 <= 0;
        // mixed_precision_stage_2 <= 0;
    end else begin
        mode_stage_2 <= mode_mul;
        mixed_precision_stage_2 <= mixed_precision_stage_mul;
    end
end


//缓存16个加数用于累加
reg [16*32 - 1 : 0] add_mem;
reg [16*6  - 1 : 0] add_property_mem;
reg [3:0] cnt;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        add_mem <= 0;
        cnt <= 0;
        add_property_mem <= 0;
    end else if(clean)begin
        add_mem <= 0;
        cnt <= 0;
        add_property_mem <= 0;
    end else if(mul_valid) begin
        add_mem <= {add_mem[(16 - 1) * 32 - 1 : 0] , mul};
        add_property_mem <= {add_property_mem[(16 - 1) * 6 - 1 : 0] , mul_property};
        cnt <= cnt + 1;
    end
end

wire add_valid_ahead;//早1T的有效信号
reg add_valid;//真正的有效信号
assign add_valid_ahead = (cnt == 15) && mul_valid;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        add_valid <= 0;
    end else if(clean)begin
        add_valid <= 0;
    end else begin
        add_valid <= add_valid_ahead;
    end
end
wire [16*32 - 1 : 0] add_mem_ready;
wire [16* 6 - 1 : 0] add_property_mem_ready;
assign add_mem_ready = add_valid? add_mem : 0;
assign add_property_mem_ready = add_valid? add_property_mem : 0;
/******************加******************/
//累加器
wire [31:0] sum_w;
accumulator accumulator_inst(
    .clk(clk),
    .rst_n(rst_n),
    .valid(add_valid),
    .clean(clean),
    .add_mem(add_mem_ready),
    .add_property_mem(add_property_mem_ready),
    .mode(mode_stage_2),
    .mixed_precision(mixed_precision_stage_2),
    .sum(sum_w),
    .out_valid(accu_valid)
);

//输出
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        sum <= 0;
        out_valid <= 0;
    end else if(~accu_valid | clean)begin
        sum <= 0;
        out_valid <= 0;
    end else begin
        sum <= sum_w;
        out_valid <= accu_valid;
    end
end

endmodule