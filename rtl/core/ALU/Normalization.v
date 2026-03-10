module Normalization_FP16
(
    input wire [15:0] man_add,
    input wire [5-1:0] exp_aligned,

    output reg [15:0] man_norm,
    output reg [5-1:0] exp_norm
);
    wire man_all0;//是否全为0
    assign man_all0 = ~(|man_add);

    wire [4:0] num;//man_add的二进制表示中最高有效位的位置1~16
    LZD16 LZD16_inst(
        .sum(man_add),
        .position(num)
    );
    //当前小数点处于111111.1111111111
    //小数点前有6位，后有10位
    always@(*)begin
        if(man_all0)begin
            man_norm = 0;
            exp_norm = 0;
        end else begin
            if(num <= 6 )begin//小数点需要向左移动，exp要加
                if(exp_aligned > 30 - ('d6 - num))begin
                    exp_norm = 31;
                    man_norm = 0;
                end else begin
                    exp_norm = exp_aligned + ('d6 - num);
                    man_norm = man_add << num;
                end
            end else begin//小数点需要向后移动，exp要减
                if(exp_aligned <= (num - 'd6))begin
                    exp_norm = 0;
                    man_norm = man_add << (exp_aligned - 1 + 6);//非规格数
                end else begin
                    exp_norm = exp_aligned - (num - 'd6);
                    man_norm = man_add << num;
                end
            end
            
        end
    end
endmodule

module Normalization_FP32
(
    input wire [28:0] man_add,
    input wire [7:0] exp_aligned,

    output reg [28:0] man_norm,
    output reg [7:0] exp_norm
);
    wire man_all0;//是否全为0
    assign man_all0 = ~(|man_add);

    wire [4:0] num;//man_add的二进制表示中最高有效位的位置1~29
    LZD29 LZD29_inst(
        .sum(man_add),
        .position(num)
    );
    //当前小数点处于111111.1111111111
    //小数点前有6位，后有23位
    always@(*)begin
        if(man_all0)begin
            man_norm = 0;
            exp_norm = 0;
        end else begin
            if(num <= 6 )begin//小数点需要向左移动，exp要加
                if(exp_aligned > 254 - ('d6 - num))begin
                    exp_norm = 255;
                    man_norm = 0;
                end else begin
                    exp_norm = exp_aligned + ('d6 - num);
                    man_norm = man_add << num;
                end
            end else begin//小数点需要向后移动，exp要减
                if(exp_aligned <= (num - 'd6))begin
                    exp_norm = 0;
                    man_norm = man_add << (exp_aligned - 1 + 6);//非规格数
                end else begin
                    exp_norm = exp_aligned - (num - 'd6);
                    man_norm = man_add << num;
                end
            end
        end
    end
endmodule

module Normalization_FP16_mul
(
    input clk,
    input rst_n,
    input valid,
    input clean,
    input wire [21:0] mant,
    input wire signed [5:0] exp,//-28~30  -14~15

    output reg [21:0] mant_norm,
    output reg norm_inside_valid,
    output reg [5:0] exp_norm
);
    wire [4:0] num_unsigned;
    wire signed [5:0] num;//man_add的二进制表示中最高有效位的位置1~22
    LZD22 LZD22_inst(
        .sum(mant),
        .position(num_unsigned)
    );
    assign num = {1'b0, num_unsigned};

    reg [21:0] mant_r;
    reg signed [5:0] exp_r;
    reg signed [5:0] num_r;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            mant_r <= 0;
            exp_r <= 0;
            num_r <= 0;
            norm_inside_valid <= 0;
        end else if(~valid | clean)begin
            mant_r <= 0;
            exp_r <= 0;
            num_r <= 0;
            norm_inside_valid <= 0;
        end else begin
            mant_r <= mant;
            exp_r <= exp;
            num_r <= num;
            norm_inside_valid <= valid;
        end
    end 
    //当前小数点处于11.11111111111111111111
    //小数点前有2位，后有20位
    wire mant_all0;//是否全为0
    assign mant_all0 = ~(|mant_r);
    always@(*)begin
        mant_norm = 0;
        exp_norm = -15;
        if(mant_all0)begin
            exp_norm = -15;
            mant_norm = 0;
        end else begin
            if(num_r <= 2)begin//小数点需要向左移动，尾数右移，指数要加
                if(exp_r < -14 - 21)begin//尾数移完指数都小于等于-14,比非规格数最小值还小，直接赋0
                    exp_norm = -15;
                    mant_norm = 0;
                end else if(exp_r < -14 - (2 - num_r))begin//指数太小，尾数右移后是非规格数
                    mant_norm = mant_r >> (-14 - exp_r);//使尾数右移，将指数加到-14(1)
                    exp_norm = -15;//非规格数实际指数是-14(1)，但是表示为-15(0)
                end else if(exp_r > 30 - (2 - num_r))begin//尾数右移后，指数变大，超出6位有符号数范围，截断
                    mant_norm = 0;
                    exp_norm = 30;
                end else begin
                    mant_norm = mant_r >> (2- num_r);
                    exp_norm = exp_r + (2 - num_r);
                end
            end else if(num_r > 2) begin//小数点向右移动，尾数左移，指数要减
                if(exp_r < -14 - (22 - num_r))begin//小于最小非规格数，直接赋0
                    exp_norm = -15;
                    mant_norm = 0;
                end else if(exp_r  < -14 + (num_r - 2))begin//非规格数区间
                    exp_norm = -15;//非规格数实际指数是-14(1)，但是表示为-15(0)
                    if(exp_r < -14)begin
                        mant_norm = mant_r >> (-14 - exp_r);//指数由小变大（变到-14），尾数右移
                    end else begin
                        mant_norm = mant_r << (exp_r - (-14));//指数由大变小（变到-14），尾数左移
                    end
                end else begin//正常规格化
                    exp_norm = exp_r - (num_r - 2);
                    mant_norm = mant_r << (num_r - 2);
                end
            end
        end
    end
    
    

endmodule


module Normalization_FP32_mul
(
    input clk,
    input rst_n,
    input valid,
    input clean,
    input wire [47:0] mant,
    input wire signed [8:0] exp,//-252~254 -126~127

    output reg [47:0] mant_norm,
    output reg norm_inside_valid,
    output reg signed [8:0] exp_norm
);
    wire [5:0] num_unsigned;
    wire signed [6:0] num;//man_add的二进制表示中最高有效位的位置,从最高位到最低为分别为1~48
    LZD48 LZD48_inst(
        .sum(mant),
        .position(num_unsigned)
    );
    assign num = {1'b0, num_unsigned};

    reg [47:0] mant_r;
    reg signed [8:0] exp_r;
    reg signed [6:0] num_r;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            mant_r <= 0;
            exp_r <= 0;
            num_r <= 0;
            norm_inside_valid <= 0;
        end else if(~valid | clean)begin
            mant_r <= 0;
            exp_r <= 0;
            num_r <= 0;
            norm_inside_valid <= 0;
        end else begin
            mant_r <= mant;
            exp_r <= exp;
            num_r <= num;
            norm_inside_valid <= valid;
        end
    end 
    //当前小数点处于11.11111111111111111111
    //小数点前有2位，后有46位
    wire mant_all0;//是否全为0
    reg mark;
    assign mant_all0 = ~(|mant_r);
    always@(*)begin
        mant_norm = 0;
        exp_norm = -127;
        mark = 0;
        if(mant_all0)begin
            exp_norm = -127;
            mant_norm = 0;
        end else begin
            if(num_r <= 2)begin//小数点需要向左移动，尾数右移，指数要加
                if(exp_r < -126 - 47)begin//尾数移完指数都小于等于-126,比非规格数最小值还小，直接赋0
                    
                    exp_norm = -127;
                    mant_norm = 0;
                end else if(exp_r < -126 - (2 - num_r))begin//指数太小，尾数右移后是非规格数
                    mant_norm = mant_r >> (-126 - exp_r);//使尾数右移，将指数加到-126(1)
                    exp_norm = -127;//非规格数实际指数是-126(1)，但是表示为-127(0)
                    mark = 1;
                end else if(exp_r > 254 - (2 - num_r))begin//尾数右移后，指数变大，超出9位有符号数范围，截断
                    mant_norm = 0;
                    exp_norm = 254;
                end else begin
                    mant_norm = mant_r >> (2-num_r);
                    exp_norm = exp_r + (2 - num_r);
                end
            end else if(num_r > 2) begin//小数点向右移动，尾数左移，指数要减
                if(exp_r < -126 - (48 - num_r))begin//小于最小非规格数，直接赋0
                    exp_norm = -127;
                    mant_norm = 0;
                end else if(exp_r  < -126 + (num_r - 2))begin//非规格数区间
                    exp_norm = -127;//非规格数实际指数是-126(1)，但是表示为-127(0)
                    if(exp_r < -126)begin
                        mant_norm = mant_r >> (-126 - exp_r);//指数由小变大（变到-126），尾数右移
                    end else begin
                        mant_norm = mant_r << (exp_r - (-126));//指数由大变小（变到-126），尾数左移
                    end
                end else begin//正常规格化
                    exp_norm = exp_r - (num_r - 2);
                    mant_norm = mant_r << (num_r - 2);
                end
            end
        end
    end
    

endmodule