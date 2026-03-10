//16个数累加
module accumulator(
    input  clk,
    input  rst_n,
    input  valid,
    input  clean,
    input  [16*32-1:0] add_mem,
    input  [16* 6-1:0] add_property_mem,
    input  [2:0] mode,
    input  mixed_precision,
    output reg out_valid,
    output [31:0] sum // 
);
parameter INT4_MODE = 3'b000,
          INT8_MODE = 3'b001,
          FP16_MODE = 3'b010,
          FP32_MODE = 3'b011;

reg  use_special;
//各加法器使能信号
wire valid_int;
wire valid_fp16;
wire valid_fp32;
wire valid_special;

//各数据类型输出有效信号
wire out_valid_int;
wire out_valid_int4;
wire out_valid_int8;
wire out_valid_fp16;
wire out_valid_fp32;
wire out_valid_special;

//各数据类型加法结果信号
wire [19:0] sum_int;//20,12
wire [31:0] sum_int4;
wire [31:0] sum_int8;
wire [15:0] sum_fp16;
wire [31:0] sum_fp32;
reg  [31:0] sum_special_undelay;
wire [31:0] sum_special;

assign sum_int4 = {{20{sum_int[11]}},sum_int[11:0]};
assign sum_int8 = {{12{sum_int[19]}},sum_int[19:0]};

assign out_valid_int4 = (mode == INT4_MODE) && out_valid_int;
assign out_valid_int8 = (mode == INT8_MODE) && out_valid_int;
// assign out_valid_special = valid_special;

//加法器使能
wire fp16_mixed;
assign fp16_mixed = (mode == FP16_MODE) && mixed_precision;
assign valid_int = valid && (mode == INT4_MODE || mode == INT8_MODE);
assign valid_fp16 = ~use_special && valid && (mode == FP16_MODE) && (~mixed_precision);
assign valid_fp32 = ~use_special && valid && ((mode == FP32_MODE) || fp16_mixed);
assign valid_special = valid && use_special && (mode == FP16_MODE || mode == FP32_MODE);

//use_special [16* 6-1:0] add_property_mem
wire has_pos_inf,has_neg_inf,has_nan,has_inf,has_pos_neg_inf,all_zero;
wire [15:0] property_sign, property_nan, property_inf, property_zero, property_subnormal, property_normal;
generate
    genvar k;
    for(k = 0;k < 16 ; k = k + 1)begin:gen_property
        assign property_sign[k] = add_property_mem[5+6*k];
        assign property_nan[k] = add_property_mem[4+6*k];
        assign property_inf[k] = add_property_mem[3+6*k];
        assign property_zero[k] = add_property_mem[2+6*k];
        assign property_subnormal[k] = add_property_mem[1+6*k];
        assign property_normal[k] = add_property_mem[0+6*k];
    end
endgenerate

assign has_nan = |property_nan;
assign has_inf = |property_inf;
assign has_pos_inf = |(property_inf & ~property_sign); // Inf 且 sign = 0
assign has_neg_inf = |(property_inf &  property_sign); // Inf 且 sign = 1
assign has_pos_neg_inf = has_pos_inf & has_neg_inf; // Inf 且 sign 不同
assign all_zero = &property_zero;

// 参数化 NaN 定义（QNaN = quiet NaN，最高位为1）
localparam [15:0] QNAN_FP16 = {1'b0, 5'b11111, 10'b1000000000}; // FP16 QNaN
localparam [31:0] QNAN_FP32 = {1'b0, 8'b11111111, 23'b10000000000000000000000}; // FP32 QNaN
localparam [4:0] EXP_MAX_FP16 = 31;
localparam [7:0] EXP_MAX_FP32 = 255;
always@(*)begin
    use_special = 0;
    sum_special_undelay = 32'h0;
    case(mode)
        FP16_MODE:begin
            if(has_nan) begin
                use_special = 1;
                sum_special_undelay = QNAN_FP16;
            end else if(has_pos_neg_inf) begin
                use_special = 1;
                sum_special_undelay = QNAN_FP16;
            end else if(has_pos_inf || has_neg_inf) begin
                use_special = 1;
                sum_special_undelay = {has_neg_inf, EXP_MAX_FP16, 10'd0};
            end else if(all_zero) begin
                use_special = 1;
                sum_special_undelay = {1'b0, 5'b0, 10'b0};
            end else begin
                use_special = 0;
            end
        end
        FP32_MODE:begin
            if(has_nan) begin
                use_special = 1;
                sum_special_undelay = QNAN_FP32;
            end else if(has_pos_neg_inf) begin
                use_special = 1;
                sum_special_undelay = QNAN_FP32;
            end else if(has_pos_inf || has_neg_inf) begin
                use_special = 1;
                sum_special_undelay = {has_neg_inf, EXP_MAX_FP32, 23'd0};
            end else if(all_zero) begin
                use_special = 1;
                sum_special_undelay = {1'b0, 8'd0, 23'd0};
            end else begin
                use_special = 0;
                sum_special_undelay = 32'h0;
            end
        end
    endcase
end


//输出
reg [31:0] sum_w;
wire use_special_delay;
always@(*)begin
    out_valid = 0;
    sum_w = 32'h0;
    case(mode)
        INT4_MODE:begin
            out_valid = out_valid_int4;
            sum_w = sum_int4;
        end
        INT8_MODE:begin
            out_valid = out_valid_int8;
            sum_w = sum_int8;
        end
        FP16_MODE:begin
            if(use_special_delay)begin
                out_valid = out_valid_special;
                sum_w = sum_special;
            end else begin
                if(mixed_precision)begin
                    out_valid = out_valid_fp32;
                    sum_w = sum_fp32;
                end else begin
                    out_valid = out_valid_fp16;
                    sum_w = sum_fp16;
                end
            end
        end
        FP32_MODE:begin
            if(use_special_delay)begin
                out_valid = out_valid_special;
                sum_w = sum_special;
            end else begin
                out_valid = out_valid_fp32;
                sum_w = sum_fp32;
            end
        end
    endcase
end
assign sum = (out_valid_int4 | out_valid_int8 | out_valid_fp16 | out_valid_fp32 | out_valid_special)? sum_w : 32'h0;


wire int_mode;
localparam INT4 = 1'b0,
            INT8 = 1'b1;
assign int_mode = (mode == INT4_MODE)? INT4 : INT8;

wire [16*16-1:0] add_int_pack;//取add_mem每32位数据的低16位打包
generate
    genvar j;
    for(j = 0;j < 16 ; j = j + 1)begin:gen_pack
        assign add_int_pack[16*j +: 16] = add_mem[32*j +: 16];
    end
endgenerate


//添加流水
reg  [31:0] sum_special_undelay_r;
reg  valid_special_r;
reg  use_special_r;
reg [16*32-1:0] add_mem_r;
reg valid_fp16_r;
reg [15:0] property_normal_r;
reg valid_fp32_r;
always@(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        sum_special_undelay_r <= 0;
        valid_special_r <= 0;
        use_special_r <= 0;
        add_mem_r <= 0;
        valid_fp16_r <= 0;
        property_normal_r <= 0;
        valid_fp32_r <= 0;
    end else if(~valid | clean)begin
        sum_special_undelay_r <= 0;
        valid_special_r <= 0;
        use_special_r <= 0;
        add_mem_r <= 0;
        valid_fp16_r <= 0;
        property_normal_r <= 0;
        valid_fp32_r <= 0;
    end else begin
        sum_special_undelay_r   <= sum_special_undelay  ;
        valid_special_r         <= valid_special        ;
        use_special_r           <= use_special          ;
        add_mem_r               <= add_mem              ;
        valid_fp16_r            <= valid_fp16           ;
        property_normal_r       <= property_normal      ;
        valid_fp32_r            <= valid_fp32           ;
    end
end

//加法器
add_special add_special_inst(
    .clk(clk),
    .rst_n(rst_n),
    .clean(clean),
    .sum_special_undelay(sum_special_undelay_r),
    .valid(valid_special_r),
    .use_special(use_special_r),
    .use_special_delay(use_special_delay),
    .out_valid(out_valid_special),
    .sum_special(sum_special)
);

add_INT_signed add_INT_signed(
    .clk(clk),
    .rst_n(rst_n),
    .clean(clean),
    .valid(valid_int),
    .mode(int_mode),
    .a(add_int_pack),
    .out_valid(out_valid_int),
    .sum(sum_int)
);

wire [31:0] add [15:0];
generate
    genvar i;
    for(i = 0;i < 16 ; i = i + 1)begin:gen
        assign add[i] = add_mem_r[32*i +: 32];
    end
endgenerate
add_FP16 add_FP16(
    .clk(clk),
    .rst_n(rst_n),
    .clean(clean),
    .valid(valid_fp16_r),
    .property_normal(property_normal_r),
    .a1   (add[0][15:0])  ,
    .a2   (add[1][15:0])  ,
    .a3   (add[2][15:0])  ,
    .a4   (add[3][15:0])  ,
    .a5   (add[4][15:0])  ,
    .a6   (add[5][15:0])  ,
    .a7   (add[6][15:0])  ,
    .a8   (add[7][15:0])  ,
    .a9   (add[8][15:0])  ,
    .a10  (add[9][15:0])  ,
    .a11  (add[10][15:0])  ,
    .a12  (add[11][15:0])  ,
    .a13  (add[12][15:0])  ,
    .a14  (add[13][15:0])  ,
    .a15  (add[14][15:0])  ,
    .a16  (add[15][15:0])  ,
    .out_valid(out_valid_fp16),
    .sum  (sum_fp16) 
);

add_FP32 add_FP32(
    .clk(clk),
    .rst_n(rst_n),
    .clean(clean),
    .valid(valid_fp32_r),
    .property_normal(property_normal_r),
    .a1   (add[0][31:0])  ,
    .a2   (add[1][31:0])  ,
    .a3   (add[2][31:0])  ,
    .a4   (add[3][31:0])  ,
    .a5   (add[4][31:0])  ,
    .a6   (add[5][31:0])  ,
    .a7   (add[6][31:0])  ,
    .a8   (add[7][31:0])  ,
    .a9   (add[8][31:0])  ,
    .a10  (add[9][31:0])  ,
    .a11  (add[10][31:0])  ,
    .a12  (add[11][31:0])  ,
    .a13  (add[12][31:0])  ,
    .a14  (add[13][31:0])  ,
    .a15  (add[14][31:0])  ,
    .a16  (add[15][31:0])  ,
    .out_valid(out_valid_fp32),
    .sum  (sum_fp32) 
);

endmodule


module add_INT4_signed(
    input valid,
    input  [7:0]  a1     , 
    input  [7:0]  a2     , 
    input  [7:0]  a3     ,
    input  [7:0]  a4     ,
    input  [7:0]  a5     ,
    input  [7:0]  a6     ,
    input  [7:0]  a7     ,
    input  [7:0]  a8     ,
    input  [7:0]  a9     ,
    input  [7:0]  a10    ,
    input  [7:0]  a11    ,
    input  [7:0]  a12    ,
    input  [7:0]  a13    ,
    input  [7:0]  a14    ,
    input  [7:0]  a15    ,
    input  [7:0]  a16    ,
    output [11:0] sum    ,// 
    output out_valid
);
    wire [11:0] sum_w;
    assign sum = valid? sum_w : 12'h0;
    assign out_valid = valid;

    wire [11:0] a1_expand, a2_expand, a3_expand, a4_expand, a5_expand, a6_expand, a7_expand, a8_expand, a9_expand,
                a10_expand, a11_expand, a12_expand, a13_expand, a14_expand, a15_expand, a16_expand;
    assign a1_expand = {{4{a1[7]}},a1};
    assign a2_expand = {{4{a2[7]}},a2};
    assign a3_expand = {{4{a3[7]}},a3};
    assign a4_expand = {{4{a4[7]}},a4};
    assign a5_expand = {{4{a5[7]}},a5};
    assign a6_expand = {{4{a6[7]}},a6};
    assign a7_expand = {{4{a7[7]}},a7};
    assign a8_expand = {{4{a8[7]}},a8};
    assign a9_expand = {{4{a9[7]}},a9};
    assign a10_expand = {{4{a10[7]}},a10};
    assign a11_expand = {{4{a11[7]}},a11};
    assign a12_expand = {{4{a12[7]}},a12};
    assign a13_expand = {{4{a13[7]}},a13};
    assign a14_expand = {{4{a14[7]}},a14};
    assign a15_expand = {{4{a15[7]}},a15};
    assign a16_expand = {{4{a16[7]}},a16};

    wire [11:0] carry_out1, carry_out2, sum1, sum2;
    wire [11:0] carry1, carry2;
//华莱士树
//一级
    compressor7to2 #(12) compressor_inst1(
        .P0(a1_expand),
        .P1(a2_expand),
        .P2(a3_expand),
        .P3(a4_expand),
        .P4(a5_expand),
        .P5(a6_expand),
        .P6(a7_expand),
        .carry(carry_out1),
        .sum(sum1)
    );
    compressor7to2 #(12) compressor_inst2(
        .P0(a8_expand),
        .P1(a9_expand),
        .P2(a10_expand),
        .P3(a11_expand),
        .P4(a12_expand),
        .P5(a13_expand),
        .P6(a14_expand),
        .carry(carry_out2),
        .sum(sum2)
    );

assign carry1 = carry_out1 << 1;
assign carry2 = carry_out2 << 1;


//二级
wire [11:0] carry_out, sum_out;
wire [11:0] carry_shift;
    compressor7to2 #(12) compressor_inst3(
        .P0(a15_expand),
        .P1(a16_expand),
        .P2(sum1),
        .P3(sum2),
        .P4(carry1),
        .P5(carry2),
        .P6(12'b0),
        .carry(carry_out),
        .sum(sum_out)
    );

    assign carry_shift = carry_out << 1;

    
    CLA_AdderTree#(.DATA_WIDTH(12)) add_tree(
        .A(carry_shift),
       .B(sum_out),
       .product(sum_w)
    );
    //assign sum = a_expand + b_expand;//此处可以CLA优化
endmodule

module add_INT8_signed(
    input  valid,
    input  [15:0]  a1     , 
    input  [15:0]  a2     , 
    input  [15:0]  a3     ,
    input  [15:0]  a4     ,
    input  [15:0]  a5     ,
    input  [15:0]  a6     ,
    input  [15:0]  a7     ,
    input  [15:0]  a8     ,
    input  [15:0]  a9     ,
    input  [15:0]  a10    ,
    input  [15:0]  a11    ,
    input  [15:0]  a12    ,
    input  [15:0]  a13    ,
    input  [15:0]  a14    ,
    input  [15:0]  a15    ,
    input  [15:0]  a16    ,
    output out_valid,
    output [19:0] sum // 
);
    wire [19:0] sum_w;
    assign sum = valid? sum_w : 20'h0;
    assign out_valid = valid;


    wire [19:0] a1_expand, a2_expand, a3_expand, a4_expand, a5_expand, a6_expand, a7_expand, a8_expand, a9_expand,
                a10_expand, a11_expand, a12_expand, a13_expand, a14_expand, a15_expand, a16_expand;
    assign a1_expand = {{4{a1[15]}},a1};
    assign a2_expand = {{4{a2[15]}},a2};
    assign a3_expand = {{4{a3[15]}},a3};
    assign a4_expand = {{4{a4[15]}},a4};
    assign a5_expand = {{4{a5[15]}},a5};
    assign a6_expand = {{4{a6[15]}},a6};
    assign a7_expand = {{4{a7[15]}},a7};
    assign a8_expand = {{4{a8[15]}},a8};
    assign a9_expand = {{4{a9[15]}},a9};
    assign a10_expand = {{4{a10[15]}},a10};
    assign a11_expand = {{4{a11[15]}},a11};
    assign a12_expand = {{4{a12[15]}},a12};
    assign a13_expand = {{4{a13[15]}},a13};
    assign a14_expand = {{4{a14[15]}},a14};
    assign a15_expand = {{4{a15[15]}},a15};
    assign a16_expand = {{4{a16[15]}},a16};

wire [19:0] carry_out1, carry_out2, sum1, sum2;
wire [19:0] carry1, carry2;
//华莱士树
//一级
    compressor7to2 #(20) compressor_inst1(
        .P0(a1_expand),
        .P1(a2_expand),
        .P2(a3_expand),
        .P3(a4_expand),
        .P4(a5_expand),
        .P5(a6_expand),
        .P6(a7_expand),
        .carry(carry_out1),
        .sum(sum1)
    );
    compressor7to2 #(20) compressor_inst2(
        .P0(a8_expand),
        .P1(a9_expand),
        .P2(a10_expand),
        .P3(a11_expand),
        .P4(a12_expand),
        .P5(a13_expand),
        .P6(a14_expand),
        .carry(carry_out2),
        .sum(sum2)
    );

assign carry1 = carry_out1 << 1;
assign carry2 = carry_out2 << 1;


//二级
wire [19:0] carry_out, sum_out;
wire [19:0] carry_shift;
    compressor7to2 #(20) compressor_inst3(
        .P0(a15_expand),
        .P1(a16_expand),
        .P2(sum1),
        .P3(sum2),
        .P4(carry1),
        .P5(carry2),
        .P6(20'b0),
        .carry(carry_out),
        .sum(sum_out)
    );

    assign carry_shift = carry_out << 1;

    
    CLA_AdderTree#(.DATA_WIDTH(20)) add_tree(
        .A(carry_shift),
       .B(sum_out),
       .product(sum_w)
    );
    
endmodule


module add_FP16(
    input          clk     ,
    input          rst_n   ,
    input           clean,
    input  valid,
    input  [15:0] property_normal,
    input  [15:0]  a1     , 
    input  [15:0]  a2     , 
    input  [15:0]  a3     ,
    input  [15:0]  a4     ,
    input  [15:0]  a5     ,
    input  [15:0]  a6     ,
    input  [15:0]  a7     ,
    input  [15:0]  a8     ,
    input  [15:0]  a9     ,
    input  [15:0]  a10    ,
    input  [15:0]  a11    ,
    input  [15:0]  a12    ,
    input  [15:0]  a13    ,
    input  [15:0]  a14    ,
    input  [15:0]  a15    ,
    input  [15:0]  a16    ,
    output reg out_valid,
    output reg [15:0] sum // 
);
    
//整合
    wire [15:0] a [15:0];
    assign a[0] = a1;assign a[1] = a2;assign a[2] = a3;assign a[3] = a4;
    assign a[4] = a5;assign a[5] = a6;assign a[6] = a7;assign a[7] = a8;
    assign a[8] = a9;assign a[9] = a10;assign a[10] = a11;assign a[11] = a12;
    assign a[12] = a13;assign a[13] = a14;assign a[14] = a15;assign a[15] = a16;

//解析FP16
    wire [15:0] sign_w;
    wire [16*5-1:0] exp_w;
    wire [16*11-1:0] man_w;
    generate
        genvar i;
        for(i=0;i<16;i=i+1)
        begin:fp16_parser
            assign sign_w[i] = a[i][15];
            assign exp_w[5*i+:5] = property_normal[i] ? a[i][14:10] : a[i][14:10] + 5'd1;
            assign man_w[11*i+:11] = property_normal[i] ? {1'b1,a[i][9:0]} : {1'b0,a[i][9:0]};
        end
    endgenerate

//指数对齐
    wire [4:0] aligned_exp_w ;
    wire [16*5-1:0] exp_diff_w;
    wire valid_cec;

    CEC CEC_inst(
       .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .clean(clean),
        .exp(exp_w),
        .out_valid(valid_cec),
       .aligned_exp(aligned_exp_w),
       .diff(exp_diff_w)
    );

    reg [15:0] sign_r;
    reg [16*11-1:0] man_r;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            sign_r <= 0;
            man_r <= 0;
        end else if(~valid | clean)begin
            sign_r <= 0;
            man_r <= 0;
        end else begin
            sign_r <= sign_w;
            man_r <= man_w;
        end
    end
    //现在的sign_r，man_r，valid_cec，aligned_exp_w，exp_diff_w都是在同一个时钟周期下的

//寄存器
    reg [15:0] sign;
    reg [16*11-1:0] man;
    reg valid_exp_aligned;
    reg  [4:0] aligned_exp ;
    reg  [16*5-1:0] exp_diff;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            aligned_exp <= 0;
            exp_diff <= 0;
            valid_exp_aligned <= 0;
            sign <= 0;
            man <= 0;
        end else if(~valid_cec | clean) begin
            aligned_exp <= 0;
            exp_diff <= 0;
            valid_exp_aligned <= 0;
            sign <= 0;
            man <= 0;
        end else begin
            aligned_exp <= aligned_exp_w;
            exp_diff <= exp_diff_w;
            valid_exp_aligned <= valid_cec;
            sign <= sign_r;
            man <= man_r;
        end
    end

//////////////////////////////////////stage1 end/////////////////////////////////////////////////////

//尾数对齐
    wire [16-1:0] sticky_w;
    wire [16*11-1:0] aligned_man;
    mant_shift #(.EXP_WIDTH(5),.MAN_WIDTH(11))mant_shift_inst
    (
        .man(man),
        .diff(exp_diff),
        .sticky(sticky_w),
       .aligned_man(aligned_man)
    );

//尾数取补码，并拓展为16位
    wire [16*12-1:0] man_comp2s;//要拓展1位表示符号位，成12位
    wire [16*16-1:0] man_comp2s_ext_w;
    
    generate
        genvar j;
        for(j=0;j<16;j=j+1)begin:man_comp2s_gen
            assign man_comp2s[12*j+:12] = sign[j]? ~{1'b0,aligned_man[11*j+:11]} + 12'd1 : {1'b0,aligned_man[11*j+:11]};
            assign man_comp2s_ext_w[16*j+:16] = {{4{man_comp2s[12*j+11]}},man_comp2s[12*j+:12]};
        end
    endgenerate

//寄存器
    reg valid_man_comp2s;
    reg  [16*16-1:0] man_comp2s_ext;
    reg  [16-1:0] sticky;
    reg  [4:0] aligned_exp_1 ;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            man_comp2s_ext <= 0;
            sticky <= 0;
            aligned_exp_1 <= 0;
            valid_man_comp2s <= 0;
        end else if(~valid_exp_aligned | clean)begin
            man_comp2s_ext <= 0;
            sticky <= 0;
            aligned_exp_1 <= 0;
            valid_man_comp2s <= 0;
        end else begin
            man_comp2s_ext <= man_comp2s_ext_w;
            sticky <= sticky_w;
            aligned_exp_1 <= aligned_exp;
            valid_man_comp2s <= valid_exp_aligned;
        end
    end

//////////////////////////////////////stage2 end/////////////////////////////////////////////////////////

//尾数相加,结果为16位尾数
    wire [15:0] man_add_w;
    mant_add#(.DATA_WIDTH(16),.CLA_WIDTH(16)) mant_add_FP16_inst(
        .man(man_comp2s_ext),
        .sum(man_add_w)
    );

    reg valid_mant_add;
    reg [16-1:0] sticky_mant_add;
    reg  [4:0] aligned_exp_mant_add ;
    reg [15:0] man_add;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            valid_mant_add <= 0;
            sticky_mant_add <= 0;
            aligned_exp_mant_add <= 0;
            man_add <= 0;
        end else if(~valid_man_comp2s | clean)begin
            valid_mant_add <= 0;
            sticky_mant_add <= 0;
            aligned_exp_mant_add <= 0;
            man_add <= 0;
        end else begin
            valid_mant_add <= valid_man_comp2s;
            sticky_mant_add <= sticky;
            aligned_exp_mant_add <= aligned_exp_1;
            man_add <= man_add_w;
        end
    end


//判断符号位并取绝对值
    wire sum_sign_w;
    wire [15:0] man_abs_w;
    assign sum_sign_w = man_add[15];
    complement2ss1#(.WIDTH(16)) comp2ss1(
        .sum(man_add),
        .sign(man_add[15]),
        .out(man_abs_w)
    );

//寄存器
    reg valid_man_abs;
    reg [15:0] man_abs;
    reg sum_sign;
    reg  [16-1:0] sticky_1;
    reg  [4:0] aligned_exp_2 ;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            man_abs <= 0;
            sum_sign <= 0;
            sticky_1 <= 0;
            aligned_exp_2 <= 0;
            valid_man_abs <= 0;
        end else if(~valid_mant_add | clean)begin
            man_abs <= 0;
            sum_sign <= 0;
            sticky_1 <= 0;
            aligned_exp_2 <= 0;
            valid_man_abs <= 0;
        end else begin
            man_abs <= man_abs_w;
            sum_sign <= sum_sign_w;
            sticky_1 <= sticky_mant_add;
            aligned_exp_2 <= aligned_exp_mant_add;
            valid_man_abs <= valid_mant_add;
        end
    end


//////////////////////////////////////stage3 end/////////////////////////////////////////////////////////

//规则化
    wire [15:0] man_norm_w;
    wire [4:0] exp_norm_w;
    Normalization_FP16 norm_fp16_inst(
        .man_add(man_abs),
        .exp_aligned(aligned_exp_2),
        .man_norm(man_norm_w),
        .exp_norm(exp_norm_w)
    );

//寄存器
    reg valid_norm;
    reg [15:0] man_norm;
    reg [4:0] exp_norm;
    reg sum_sign_r;
    reg  [16-1:0] sticky_r;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            valid_norm <= 0;
            man_norm <= 0;
            exp_norm <= 0;
            sum_sign_r <= 0;
            sticky_r <= 0;
        end else if(~valid_man_abs | clean)begin
            valid_norm <= 0;
            man_norm <= 0;
            exp_norm <= 0;
            sum_sign_r <= 0;
            sticky_r <= 0;
        end else begin
            valid_norm <= valid_man_abs;
            man_norm <= man_norm_w;
            exp_norm <= exp_norm_w;
            sum_sign_r <= sum_sign;
            sticky_r <= sticky_1;
        end
    end

//尾数舍入
    wire [9:0] man_round_w;
    wire [4:0] exp_round_w;
    Rounding_FP16 round_fp16_inst(
        .mant_norm(man_norm),
        .exp_norm(exp_norm),
        .sticky_in(sticky_r),
        .mant_round(man_round_w),
        .exp_round(exp_round_w)
    );

//寄存器
    reg valid_round;
    reg sum_sign_1;
    reg [9:0] man_round;
    reg [4:0] exp_round;

    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            sum_sign_1 <= 0;
            man_round <= 0;
            exp_round <= 0;
            valid_round <= 0;
        end else if(~valid_norm | clean) begin
            sum_sign_1 <= 0;
            man_round <= 0;
            exp_round <= 0;
            valid_round <= 0;
        end else begin
            sum_sign_1 <= sum_sign_r;
            man_round <= man_round_w;
            exp_round <= exp_round_w;
            valid_round <= valid_norm;
        end
    end


////////////////////////////////////stage4 end///////////////////////////////////////////////////////////

//溢出处理,舍入时已将下溢处理为非规格数和0
    wire overflow;
    // wire underflow;
    assign overflow = (exp_round >= 31);
    // assign underflow = (exp_round <= 0);
    
    
    reg [4:0] sum_exp;
    reg [9:0] sum_man;

    always @(*) begin
        if(overflow)begin
            sum_exp = 5'b11111;
            sum_man = 10'b0000000000;
        // end 
        // else if(underflow)begin
        //     sum_exp = 5'b00000;
        //     sum_man = 10'b0000000000;
        end else begin
            sum_exp = exp_round;
            sum_man = man_round;
        end 
    end 
    wire [15:0] sum_w;
    assign sum_w = {sum_sign_1,sum_exp,sum_man};

//寄存器
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
             sum <= 0;
             out_valid <= 0;
        end else if(~valid_round | clean) begin
            sum <= 0;
            out_valid <= 0;
        end else begin
            sum <= sum_w;
            out_valid <= valid_round;
        end
    end
///////////////////////////////////stage5 end////////////////////////////////////////////////////////////
  
endmodule

module add_FP32(
    input          clk     ,
    input          rst_n   ,
    input           clean,
    input  valid,
    input  [15:0] property_normal,
    input  [31:0]  a1     , 
    input  [31:0]  a2     , 
    input  [31:0]  a3     ,
    input  [31:0]  a4     ,
    input  [31:0]  a5     ,
    input  [31:0]  a6     ,
    input  [31:0]  a7     ,
    input  [31:0]  a8     ,
    input  [31:0]  a9     ,
    input  [31:0]  a10    ,
    input  [31:0]  a11    ,
    input  [31:0]  a12    ,
    input  [31:0]  a13    ,
    input  [31:0]  a14    ,
    input  [31:0]  a15    ,
    input  [31:0]  a16    ,
    output reg out_valid,
    output reg [31:0] sum // 
);


//整合
    wire [31:0] a [15:0];
    assign a[0] = a1;assign a[1] = a2;assign a[2] = a3;assign a[3] = a4;
    assign a[4] = a5;assign a[5] = a6;assign a[6] = a7;assign a[7] = a8;
    assign a[8] = a9;assign a[9] = a10;assign a[10] = a11;assign a[11] = a12;
    assign a[12] = a13;assign a[13] = a14;assign a[14] = a15;assign a[15] = a16;

//解析FP32
    wire [15:0] sign_w;
    wire [16*8-1:0] exp_w;
    wire [16*24-1:0] man_w;
    generate
        genvar i;
        for(i=0;i<16;i=i+1)
        begin:fp32_parser
            assign sign_w[i] = a[i][31];
            assign exp_w[8*i+:8] = property_normal[i] ? a[i][30:23] : a[i][30:23] + 8'd1;
            assign man_w[24*i+:24] = property_normal[i] ? {1'b1,a[i][22:0]} : {1'b0,a[i][22:0]};
        end
    endgenerate

//指数对齐
    wire [7:0] aligned_exp_w ;
    wire [16*8-1:0] exp_diff_w;
    wire valid_cec;
    CEC #(.EXP_WIDTH(8)) CEC_inst(//里面有一级流水,对exp_diff_w和valid、aligned_exp_w打了一拍
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .clean(clean),
        .exp(exp_w),
        .out_valid(valid_cec),
       .aligned_exp(aligned_exp_w),
       .diff(exp_diff_w)
    );

    reg [15:0] sign_r;
    reg [16*24-1:0] man_r;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            sign_r <= 0;
            man_r <= 0;
        end else if(~valid | clean)begin
            sign_r <= 0;
            man_r <= 0;
        end else begin
            sign_r <= sign_w;
            man_r <= man_w;
        end
    end
    //现在的sign_r，man_r，valid_cec，aligned_exp_w，exp_diff_w都是在同一个时钟周期下的

//寄存器
    reg [15:0] sign;
    reg [16*24-1:0] man;
    reg valid_exp_aligned;
    reg  [7:0] aligned_exp ;
    reg  [16*8-1:0] exp_diff;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            aligned_exp <= 0;
            exp_diff <= 0;
            valid_exp_aligned <= 0;
            sign <= 0;
            man <= 0;
        end else if(~valid_cec | clean) begin
            aligned_exp <= 0;
            exp_diff <= 0;
            valid_exp_aligned <= 0;
            sign <= 0;
            man <= 0;
        end else begin
            aligned_exp <= aligned_exp_w;
            exp_diff <= exp_diff_w;
            valid_exp_aligned <= valid_cec;
            sign <= sign_r;
            man <= man_r;
        end
    end
//////////////////////////////////////stage1 end/////////////////////////////////////////////////////

//尾数对齐
    wire [16-1:0] sticky_w;
    wire [16*24-1:0] aligned_man;
    mant_shift #(.EXP_WIDTH(8),.MAN_WIDTH(24))mant_shift_inst
    (
        .man(man),
        .diff(exp_diff),
        .sticky(sticky_w),
       .aligned_man(aligned_man)
    );

//尾数取补码，并拓展为29位
    wire [16*25-1:0] man_comp2s;//要拓展1位表示符号位，成25位
    wire [16*29-1:0] man_comp2s_ext_w;
    generate
        genvar j;
        for(j=0;j<16;j=j+1)begin:man_comp2s_gen
            assign man_comp2s[25*j+:25] = sign[j]? ~{1'b0,aligned_man[24*j+:24]} + 25'd1 : {1'b0,aligned_man[24*j+:24]};
            assign man_comp2s_ext_w[29*j+:29] = {{4{man_comp2s[25*j+24]}},man_comp2s[25*j+:25]};
        end
    endgenerate

//寄存器
    reg valid_man_comp2s;
    reg  [16*29-1:0] man_comp2s_ext;
    reg  [16-1:0] sticky;
    reg  [7:0] aligned_exp_1 ;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            man_comp2s_ext <= 0;
            sticky <= 0;
            aligned_exp_1 <= 0;
            valid_man_comp2s <= 0;
        end else if(~valid_exp_aligned | clean)begin
            man_comp2s_ext <= 0;
            sticky <= 0;
            aligned_exp_1 <= 0;
            valid_man_comp2s <= 0;
        end else begin
            man_comp2s_ext <= man_comp2s_ext_w;
            sticky <= sticky_w;
            aligned_exp_1 <= aligned_exp;
            valid_man_comp2s <= valid_exp_aligned;
        end
    end

//////////////////////////////////////stage2 end/////////////////////////////////////////////////////////


//尾数相加,结果为29位尾数
    wire [28:0] man_add_w;
    mant_add#(.DATA_WIDTH(29),.CLA_WIDTH(32)) mant_add_FP32_inst(
        .man(man_comp2s_ext),
        .sum(man_add_w)
    );

    reg valid_mant_add;
    reg [16-1:0] sticky_mant_add;
    reg  [7:0] aligned_exp_mant_add ;
    reg [28:0] man_add;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            valid_mant_add <= 0;
            sticky_mant_add <= 0;
            aligned_exp_mant_add <= 0;
            man_add <= 0;
        end else if(~valid_man_comp2s | clean)begin
            valid_mant_add <= 0;
            sticky_mant_add <= 0;
            aligned_exp_mant_add <= 0;
            man_add <= 0;
        end else begin
            valid_mant_add <= valid_man_comp2s;
            sticky_mant_add <= sticky;
            aligned_exp_mant_add <= aligned_exp_1;
            man_add <= man_add_w;
        end
    end


//判断符号位并取绝对值
    wire sum_sign_w;
    wire [28:0] man_abs_w;
    assign sum_sign_w = man_add[28];
    complement2ss1#(.WIDTH(29)) comp2ss1(
        .sum(man_add),
        .sign(man_add[28]),
        .out(man_abs_w)
    );

//寄存器
    reg valid_man_abs;
    reg [28:0] man_abs;
    reg sum_sign;
    reg  [16-1:0] sticky_1;
    reg  [7:0] aligned_exp_2 ;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            man_abs <= 0;
            sum_sign <= 0;
            sticky_1 <= 0;
            aligned_exp_2 <= 0;
            valid_man_abs <= 0;
        end else if(~valid_mant_add | clean)begin
            man_abs <= 0;
            sum_sign <= 0;
            sticky_1 <= 0;
            aligned_exp_2 <= 0;
            valid_man_abs <= 0;
        end else begin
            man_abs <= man_abs_w;
            sum_sign <= sum_sign_w;
            sticky_1 <= sticky_mant_add;
            aligned_exp_2 <= aligned_exp_mant_add;
            valid_man_abs <= valid_mant_add;
        end
    end


//////////////////////////////////////stage3 end/////////////////////////////////////////////////////////

//规则化
    wire [28:0] man_norm_w;
    wire [7:0] exp_norm_w;
    Normalization_FP32 norm_fp32_inst(
        .man_add(man_abs),
        .exp_aligned(aligned_exp_2),
        .man_norm(man_norm_w),
        .exp_norm(exp_norm_w)
    );

    //寄存器
    reg valid_norm;
    reg [28:0] man_norm;
    reg [7:0] exp_norm;
    reg sum_sign_r;
    reg  [16-1:0] sticky_r;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            valid_norm <= 0;
            man_norm <= 0;
            exp_norm <= 0;
            sum_sign_r <= 0;
            sticky_r <= 0;
        end else if(~valid_man_abs | clean)begin
            valid_norm <= 0;
            man_norm <= 0;
            exp_norm <= 0;
            sum_sign_r <= 0;
            sticky_r <= 0;
        end else begin
            valid_norm <= valid_man_abs;
            man_norm <= man_norm_w;
            exp_norm <= exp_norm_w;
            sum_sign_r <= sum_sign;
            sticky_r <= sticky_1;
        end
    end

//尾数舍入
    wire [22:0] man_round_w;
    wire [7:0] exp_round_w;
    Rounding_FP32 round_fp32_inst(
        .mant_norm(man_norm),
        .exp_norm(exp_norm),
        .sticky_in(sticky_r),
        .mant_round(man_round_w),
        .exp_round(exp_round_w)
    );

//寄存器
    reg valid_round;
    reg sum_sign_1;
    reg [22:0] man_round;
    reg [7:0] exp_round;

    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            sum_sign_1 <= 0;
            man_round <= 0;
            exp_round <= 0;
            valid_round <= 0;
        end else if(~valid_norm | clean) begin
            sum_sign_1 <= 0;
            man_round <= 0;
            exp_round <= 0;
            valid_round <= 0;
        end else begin
            sum_sign_1 <= sum_sign_r;
            man_round <= man_round_w;
            exp_round <= exp_round_w;
            valid_round <= valid_norm;
        end
    end


////////////////////////////////////stage4 end///////////////////////////////////////////////////////////


//溢出处理,不考虑非规格数
    wire overflow;
    // wire underflow;
    assign overflow = (exp_round >= 255);
    // assign underflow = (exp_round <= 0);
    
    
    reg [7:0] sum_exp;
    reg [22:0] sum_man;

    always @(*) begin
        if(overflow)begin
            sum_exp = 8'b11111111;
            sum_man = 23'b00000000000000000000000;
        // end else if(underflow)begin
        //     sum_exp = 8'b00000000;
        //     sum_man = 23'b00000000000000000000000;
        end else begin
            sum_exp = exp_round;
            sum_man = man_round;
        end 
    end 
    wire [31:0] sum_w;
    assign sum_w = {sum_sign_1,sum_exp,sum_man};

//寄存器
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
             sum <= 0;
             out_valid <= 0;
        end else if(~valid_round | clean) begin
            sum <= 0;
            out_valid <= 0;
        end else begin
            sum <= sum_w;
            out_valid <= valid_round;
        end
    end
///////////////////////////////////stage5 end////////////////////////////////////////////////////////////
 
  
endmodule

// add_INT_signed
// 支持 16 个输入的有符号整数加法器
// - 支持 INT4 模式（8-bit）和 INT8 模式（16-bit）
// - 输入打包为 256-bit 向量
// - 输出为 20-bit 加和结果
// - 支持 valid 信号和 clean 同步清空
module add_INT_signed(
    input          clk     ,
    input          rst_n   ,
    input           clean,
    input  valid,
    input mode,
    input  [16*16-1:0] a , 
    output reg out_valid,
    output reg [19:0] sum // 
);
    localparam INT4 = 1'b0,
               INT8 = 1'b1;

    //对INT4 8位有效[7:0] 对INT8 16位有效[15:0]
    wire [15:0] a_main [15:0];
    wire a_sign [15:0];
    generate
        genvar i;
        for(i=0;i<16;i=i+1)begin:expand_gen
            assign a_main[i] = (mode == INT4)? a[i*16 +: 8] : a[i*16 +: 16];
            assign a_sign[i] = (mode == INT4)? a[i*16+7] : a[i*16+15];
        end
    endgenerate

    //将INT4 和INT8 扩展为20位
    wire [19:0] a_expand [15:0];
    generate
        genvar j;
        for(j=0;j<16;j=j+1)begin:a_expand_gen
            assign a_expand[j] = (mode == INT4)? {{12{a_sign[j]}},a_main[j][7:0]} : {{4{a_sign[j]}},a_main[j]};
        end
    endgenerate

    //华莱士树
    wire [20*16-1:0] a_expand_pack;
    generate
        genvar k;
        for(k=0;k<16;k=k+1)begin:pack_gen
            assign a_expand_pack[20*k+:20] = a_expand[k];
        end
    endgenerate

    //加法器
    reg [20*16-1:0] a_expand_pack_r;
    reg              valid_r;
    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            a_expand_pack_r <= 0;
            valid_r <= 0;
        end else if(~valid | clean)begin
            a_expand_pack_r <= 0;
            valid_r <= 0;
        end else begin
            a_expand_pack_r <= a_expand_pack;
            valid_r <= valid;
        end
    end


    wire [19:0] sum_wallace;
    wire [19:0] carry_wallace;
    wallace_tree_16x20 wallace_tree_16x20_inst(
    .a(a_expand_pack_r),
    .sum(sum_wallace),
    .carry(carry_wallace)
    );
    // wallace_tree_16x20_7to2 wallace_tree_16x20_7to2(
    // .a(a_expand_pack),
    // .sum(sum_wallace),
    // .carry(carry_wallace)
    // );

    //对INT4 12位有效[11:0] 对INT8 20位有效[19:0]
    wire [19:0] sum_w; 
    CLA_AdderTree#(.DATA_WIDTH(20)) add_tree(
        .A(sum_wallace),
       .B(carry_wallace),
       .product(sum_w)
    );

    always @(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
             sum <= 0;
             out_valid <= 0;
        end else if(~valid_r | clean) begin
             sum <= 0;
             out_valid <= 0;
        end else begin
             sum <= sum_w;
             out_valid <= valid_r;
        end
    end
endmodule

module add_special(
    input          clk     ,
    input          rst_n   ,
    input           clean,
    input  valid,
    input  [31:0]  sum_special_undelay,
    input     use_special,
    output  out_valid,
    output  use_special_delay,
    output  [31:0] sum_special // 
);
localparam DELAY_CYCLES = 5 + 1 + 1 + 1;
reg [DELAY_CYCLES * 32-1:0] sum_shift;
reg [DELAY_CYCLES-1:0] valid_shift,use_special_shift;

always @(posedge clk or negedge rst_n)begin
    if(~rst_n)begin
        sum_shift <= 0;
        valid_shift <= 0;
    end else if(clean)begin
        sum_shift   <= 0;
        valid_shift <= 0;
    end else begin
        sum_shift   <= {sum_shift[32*(DELAY_CYCLES-1)-1:0], sum_special_undelay};
        valid_shift <= {valid_shift[DELAY_CYCLES-2:0], valid};
        use_special_shift <= {use_special_shift[DELAY_CYCLES-2:0], use_special};
    end
end

assign sum_special = sum_shift[32*DELAY_CYCLES-1:32*DELAY_CYCLES-32];
assign out_valid = valid_shift[DELAY_CYCLES-1];
assign use_special_delay  = use_special_shift[DELAY_CYCLES-1];

endmodule