module add_special_2in(
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
localparam DELAY_CYCLES = 6;
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

module add_FP16_2in (
    input         clk,
    input         rst_n,
    input  [15:0] a, // FP16 输入 A
    input  [15:0] b, // FP16 输入 B
    input         valid,
    input         a_is_normal,
    input         b_is_normal,
    output reg        out_valid,
    output reg [15:0] sum // FP16 结果

);

    // 解析 FP16 格式
    wire sign_a, sign_b;
    wire [4:0] exp_a, exp_b;
    wire [10:0] man_a, man_b;
    assign sign_a = a[15];
    assign sign_b = b[15];
    assign exp_a  = a_is_normal? a[14:10] : a[14:10] + 5'd1;
    assign exp_b  = b_is_normal? b[14:10] : b[14:10] + 5'd1;
    assign man_a  = a_is_normal? {1'b1, a[9:0]} : {1'b0, a[9:0]}; // 隐含的1
    assign man_b  = b_is_normal? {1'b1, b[9:0]} : {1'b0, b[9:0]}; // 隐含的1

    reg sign_a_r, sign_b_r;
    reg [4:0] exp_a_r, exp_b_r;
    reg [10:0] man_a_r, man_b_r;
    reg valid_r;
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            sign_a_r <= 0;
            sign_b_r <= 0;
            exp_a_r  <= 0;
            exp_b_r  <= 0;
            man_a_r  <= 0;
            man_b_r  <= 0;
            valid_r  <= 0;
        end else if(~valid) begin
            sign_a_r <= 0;
            sign_b_r <= 0;
            exp_a_r  <= 0;
            exp_b_r  <= 0;
            man_a_r  <= 0;
            man_b_r  <= 0;
            valid_r  <= 0;
        end else begin
            sign_a_r <= sign_a;
            sign_b_r <= sign_b;
            exp_a_r  <= exp_a;
            exp_b_r  <= exp_b;
            man_a_r  <= man_a;
            man_b_r  <= man_b;
            valid_r  <= valid;
        end
    end


    reg [4:0] aligned_exp;
    reg [10:0] aligned_man_a, aligned_man_b;
    // reg sign_res;
    reg sticky_w;
    always @(*) begin
        // 处理指数对齐和符号位
        if (exp_a_r > exp_b_r) begin
            aligned_man_a = man_a_r;
            aligned_man_b = man_b_r >> (exp_a_r - exp_b_r);
            sticky_w = |(man_b_r & ((1'b1 << (exp_a_r - exp_b_r)) - 1));
            aligned_exp = exp_a_r;
            // sign_res = sign_a_r;
        end else begin
            aligned_man_a = man_a_r >> (exp_b_r - exp_a_r);
            sticky_w = |(man_a_r & ((1'b1 << (exp_b_r - exp_a_r)) - 1));
            aligned_man_b = man_b_r;
            aligned_exp = exp_b_r;
            // sign_res = sign_b_r;
        end
    end

    reg [4:0] aligned_exp_r;
    reg [10:0] aligned_man_a_r, aligned_man_b_r;
    // reg sign_res_r;
    reg sticky_r;
    reg valid_r1;
    reg [4:0] exp_a_r1, exp_b_r1;
    reg sign_a_r1, sign_b_r1;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            aligned_exp_r <= 0;
            aligned_man_a_r <= 0;
            aligned_man_b_r <= 0;
            // sign_res_r <= 0;
            sticky_r <= 0;
            valid_r1 <= 0;
            exp_a_r1 <= 0;
            exp_b_r1 <= 0;
            sign_a_r1 <= 0;
            sign_b_r1 <= 0;
        end else if(~valid_r) begin
            aligned_exp_r <= 0;
            aligned_man_a_r <= 0;
            aligned_man_b_r <= 0;
            // sign_res_r <= 0;
            sticky_r <= 0;
            valid_r1 <= 0;
            exp_a_r1 <= 0;
            exp_b_r1 <= 0;
            sign_a_r1 <= 0;
            sign_b_r1 <= 0;
        end else begin
            aligned_exp_r <= aligned_exp;
            aligned_man_a_r <= aligned_man_a;
            aligned_man_b_r <= aligned_man_b;
            // sign_res_r <= sign_res;
            sticky_r <= sticky_w;
            valid_r1 <= valid_r;
            exp_a_r1 <= exp_a_r;
            exp_b_r1 <= exp_b_r;
            sign_a_r1 <= sign_a_r;
            sign_b_r1 <= sign_b_r;
        end
    end


    wire [12:0] mant_add; // 额外一位用于进位
    wire [11:0] mant_comp2s_a,mant_comp2s_b;//转化为12位有符号数
    wire [12:0] mant_comp2s_ext_a_w,mant_comp2s_ext_b_w;//拓展到13位

    assign mant_comp2s_a = sign_a_r1 ? ~{1'b0,aligned_man_a_r} + 12'd1 : {1'b0,aligned_man_a_r};
    assign mant_comp2s_b = sign_b_r1 ? ~{1'b0,aligned_man_b_r} + 12'd1 : {1'b0,aligned_man_b_r};
    assign mant_comp2s_ext_a_w = {mant_comp2s_a[11],mant_comp2s_a};
    assign mant_comp2s_ext_b_w = {mant_comp2s_b[11],mant_comp2s_b};

    CLA_AdderTree#(13) add_adder_tree(
        .A(mant_comp2s_ext_a_w),
        .B(mant_comp2s_ext_b_w),
        .product(mant_add)
    );

    wire sign_res;
    assign sign_res = mant_add[12];

    wire [12:0] mant_abs;
    complement2ss1#(.WIDTH(13)) comp2ss1(
        .sum(mant_add),
        .sign(mant_add[12]),
        .out(mant_abs)
    );


    reg [12:0] man_add_r;
    reg [4:0] aligned_exp_r1;
    reg valid_r2;
    reg sticky_r1;
    reg sign_res_r1;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            man_add_r <= 0;
            aligned_exp_r1 <= 0;
            valid_r2 <= 0;
            sticky_r1 <= 0;
            sign_res_r1 <= 0;
        end else if(~valid_r1) begin
            man_add_r <= 0;
            aligned_exp_r1 <= 0;
            valid_r2 <= 0;
            sticky_r1 <= 0;
            sign_res_r1 <= 0;
        end else begin
            man_add_r <= mant_abs;
            aligned_exp_r1 <= aligned_exp_r;
            valid_r2 <= valid_r1;
            sticky_r1 <= sticky_r;
            sign_res_r1 <= sign_res;
        end
    end

//规则化
    wire mant_all0; // 结果是否全为0
    assign mant_all0 = ~(|man_add_r);

    wire [3:0] num;//最高有效位的位置
    reg [4:0] exp_norm;
    reg [12:0] man_norm;//不含隐藏位
    LZD13 inst(
        .sum(man_add_r),
        .position(num)
    );

    //当前小数点处于111.1111111111
    //小数点前有3位，后有10位
    always @(*) begin
        if(mant_all0)begin
            man_norm = 0;
            exp_norm = 0;
        end else begin
            if(num <= 3)begin//小数点需要向左移动，exp要加
                if(aligned_exp_r1 > 30 - ('d3 - num))begin//上溢出
                    exp_norm = 31;
                    man_norm = 0;
                end else begin
                    exp_norm = aligned_exp_r1 + ('d3 - num);
                    man_norm = man_add_r << num;
                end
            end else begin//小数点需要向后移动，exp要减
                if(aligned_exp_r1 <= (num - 'd3))begin//非规格数
                    exp_norm = 0; 
                    man_norm = man_add_r << (aligned_exp_r1 - 1 + 3);
                end else begin
                    exp_norm = aligned_exp_r1 - (num - 'd3);
                    man_norm = man_add_r << num;
                end
            end
        end
    end
    

    reg [4:0] exp_norm_r;
    reg [12:0] man_norm_r;
    reg sticky_r2;
    reg valid_r3;
    reg sign_res_r2;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            exp_norm_r <= 0;
            man_norm_r <= 0;
            sticky_r2 <= 0;
            valid_r3 <= 0;
            sign_res_r2 <= 0;
        end else if(~valid_r2)begin
            exp_norm_r <= 0;
            man_norm_r <= 0;
            sticky_r2 <= 0;
            valid_r3 <= 0;
            sign_res_r2 <= 0;
        end else begin
            exp_norm_r <= exp_norm;
            man_norm_r <= man_norm;
            sticky_r2 <= sticky_r;
            valid_r3 <= valid_r2;
            sign_res_r2 <= sign_res_r1;
        end
    end


    // 舍入,man_res[11:2] [1:0]
    wire [9:0] man_round;
    wire [4:0] exp_round;

    wire [9:0] man_main ;
    assign man_main = man_norm_r[12:3]; // 主尾数

    //GRS
    wire       guard   ;
    wire       round   ;
    wire       sticky  ;
    assign guard    = man_norm_r[2];
    assign round    = man_norm_r[1];
    assign sticky   = man_norm_r[0] | sticky_r2; 

    wire round_up;
    assign round_up = (guard && (round | sticky)) || 
                  (guard && ~round && ~sticky && man_main[0]); 

    wire [10:0] man_rounded;// 舍入后的结果
    assign man_rounded = man_main + round_up;

    assign man_round = man_rounded[9:0];
    assign exp_round = man_rounded[10]? exp_norm_r + 1 : exp_norm_r;

    reg [9:0] man_round_r;
    reg [4:0] exp_round_r;
    reg valid_r4;
    reg sign_res_r3;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            man_round_r <= 0;
            exp_round_r <= 0;
            valid_r4 <= 0;
            sign_res_r3 <= 0;
        end else if(~valid_r3)begin
            man_round_r <= 0;
            exp_round_r <= 0;
            valid_r4 <= 0;
            sign_res_r3 <= 0;
        end else begin
            man_round_r <= man_round;
            exp_round_r <= exp_round;
            valid_r4 <= valid_r3;
            sign_res_r3 <= sign_res_r2;
        end
    end


    wire sign;
    reg [9:0] man;
    reg [4:0] exp;
    assign sign = sign_res_r3;
    //判断溢出
    wire overflow;
    // wire underflow;
    assign overflow = (exp_round_r >= 31);
    // assign underflow = (exp_round_r <= 0);

    always @(*) begin
        if(overflow)begin
            exp = 5'b11111;
            man = 10'b0000000000;
        // end else if(underflow)begin
        //     exp = 5'b00000;
        //     man = 10'b0000000000;
        end else begin
            exp = exp_round_r;
            man = man_round_r;
        end
    end
    // 输出结果
    wire [15:0] sum_w;
    assign sum_w = {sign, exp, man}; 

    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            sum <= 0;
            out_valid <= 0;
        end else if(~valid_r4)begin
            sum <= 0;
            out_valid <= 0;
        end else begin
            sum <= sum_w;
            out_valid <= valid_r4;
        end
    end

endmodule


module add_FP32_2in (
    input         clk,
    input         rst_n,
    input  [31:0] a, // FP32 输入 A
    input  [31:0] b, // FP32 输入 B
    input         valid,
    input         a_is_normal,
    input         b_is_normal,
    output reg       out_valid,
    output reg [31:0] sum // FP32 结果
);
    


    // 解析 FP32 格式
    wire sign_a, sign_b;
    wire [7:0] exp_a, exp_b;
    wire [23:0] man_a, man_b;
    assign sign_a = a[31];
    assign sign_b = b[31];
    assign exp_a  = a_is_normal ? a[30:23] : a[30:23] + 8'd1;
    assign exp_b  = b_is_normal ? b[30:23] : b[30:23] + 8'd1;
    assign man_a  = a_is_normal ? {1'b1, a[22:0]} : {1'b0, a[22:0]}; // 隐含的1
    assign man_b  = b_is_normal ? {1'b1, b[22:0]} : {1'b0, b[22:0]}; // 隐含的1

    
    reg sign_a_r, sign_b_r;
    reg [7:0] exp_a_r, exp_b_r;
    reg [23:0] man_a_r, man_b_r;
    reg valid_r;
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            sign_a_r <= 0;
            sign_b_r <= 0;
            exp_a_r  <= 0;
            exp_b_r  <= 0;
            man_a_r  <= 0;
            man_b_r  <= 0;
            valid_r  <= 0;
        end else if(~valid) begin
            sign_a_r <= 0;
            sign_b_r <= 0;
            exp_a_r  <= 0;
            exp_b_r  <= 0;
            man_a_r  <= 0;
            man_b_r  <= 0;
            valid_r  <= 0;
        end else begin
            sign_a_r <= sign_a;
            sign_b_r <= sign_b;
            exp_a_r  <= exp_a;
            exp_b_r  <= exp_b;
            man_a_r  <= man_a;
            man_b_r  <= man_b;
            valid_r  <= valid;
        end
    end
    
    // 处理指数对齐和符号位
    reg sticky_w;
    reg [7:0] aligned_exp;
    reg [23:0] aligned_man_a, aligned_man_b;
    // reg sign_res;
    always @(*) begin
        // 处理指数对齐和符号位
        if (exp_a_r > exp_b_r) begin
            aligned_man_a = man_a_r;
            aligned_man_b = man_b_r >> (exp_a_r - exp_b_r);
            sticky_w = |(man_b_r & ((1'b1 << (exp_a_r - exp_b_r)) - 1));
            aligned_exp = exp_a_r;
            // sign_res = sign_a_r;
        end else begin
            aligned_man_a = man_a_r >> (exp_b_r - exp_a_r);
            sticky_w = |(man_a_r & ((1'b1 << (exp_b_r - exp_a_r)) - 1));
            aligned_man_b = man_b_r;
            aligned_exp = exp_b_r;
            // sign_res = sign_b_r;
        end
    end


    reg [7:0] aligned_exp_r;
    reg [23:0] aligned_man_a_r, aligned_man_b_r;
    // reg sign_res_r;
    reg sticky_r;
    reg valid_r1;
    reg [7:0] exp_a_r1, exp_b_r1;
    reg sign_a_r1, sign_b_r1;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            aligned_exp_r <= 0;
            aligned_man_a_r <= 0;
            aligned_man_b_r <= 0;
            // sign_res_r <= 0;
            sticky_r <= 0;
            valid_r1 <= 0;
            exp_a_r1 <= 0;
            exp_b_r1 <= 0;
            sign_a_r1 <= 0;
            sign_b_r1 <= 0;
        end else if(~valid_r) begin
            aligned_exp_r <= 0;
            aligned_man_a_r <= 0;
            aligned_man_b_r <= 0;
            // sign_res_r <= 0;
            sticky_r <= 0;
            valid_r1 <= 0;
            exp_a_r1 <= 0;
            exp_b_r1 <= 0;
            sign_a_r1 <= 0;
            sign_b_r1 <= 0;
        end else begin
            aligned_exp_r <= aligned_exp;
            aligned_man_a_r <= aligned_man_a;
            aligned_man_b_r <= aligned_man_b;
            // sign_res_r <= sign_res;
            sticky_r <= sticky_w;
            valid_r1 <= valid_r;
            exp_a_r1 <= exp_a_r;
            exp_b_r1 <= exp_b_r;
            sign_a_r1 <= sign_a_r;
            sign_b_r1 <= sign_b_r;
        end
    end


    // 执行加法或减法
    wire [25:0] mant_add; // 额外一位用于进位
    wire [24:0] mant_comp2s_a,mant_comp2s_b;//转化为25位有符号数
    wire [25:0] mant_comp2s_ext_a_w,mant_comp2s_ext_b_w;//拓展到26位

    assign mant_comp2s_a = sign_a_r1 ? ~{1'b0,aligned_man_a_r} + 25'd1 : {1'b0,aligned_man_a_r};
    assign mant_comp2s_b = sign_b_r1 ? ~{1'b0,aligned_man_b_r} + 25'd1 : {1'b0,aligned_man_b_r};
    assign mant_comp2s_ext_a_w = {mant_comp2s_a[24],mant_comp2s_a};
    assign mant_comp2s_ext_b_w = {mant_comp2s_b[24],mant_comp2s_b};

    CLA_AdderTree#(26) add_adder_tree(
        .A(mant_comp2s_ext_a_w),
        .B(mant_comp2s_ext_b_w),
        .product(mant_add)
    );
    wire sign_res;
    assign sign_res = mant_add[25];
    wire [25:0] mant_abs;
    complement2ss1#(.WIDTH(26)) comp2ss1(
        .sum(mant_add),
        .sign(mant_add[25]),
        .out(mant_abs)
    );
    
    reg [25:0] man_add_r;
    reg [7:0] aligned_exp_r1;
    reg valid_r2;
    reg sticky_r1;
    reg sign_res_r1;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)begin
            man_add_r <= 0;
            aligned_exp_r1 <= 0;
            valid_r2 <= 0;
            sticky_r1 <= 0;
            sign_res_r1 <= 0;
        end else if(~valid_r1) begin
            man_add_r <= 0;
            aligned_exp_r1 <= 0;
            valid_r2 <= 0;
            sticky_r1 <= 0;
            sign_res_r1 <= 0;
        end else begin
            man_add_r <= mant_abs;
            aligned_exp_r1 <= aligned_exp_r;
            valid_r2 <= valid_r1;
            sticky_r1 <= sticky_r;
            sign_res_r1 <= sign_res;
        end
    end

    //规则化
    wire mant_all0; // 结果是否全为0
    assign mant_all0 = ~(|man_add_r);

    wire [4:0] num;//最高有效位的位置
    reg [7:0] exp_norm;
    reg [25:0] man_norm;//不含隐藏位
    LZD26 inst(
        .sum(man_add_r),
        .position(num)
    );
    //当前小数点处于111.1111111111
    //小数点前有3位，后有23位
    always @(*) begin
        if(mant_all0)begin
            man_norm = 0;
            exp_norm = 0;
        end else begin
            if(num <= 3)begin//小数点需要向左移动，exp要加
                if(aligned_exp_r1 > 254 - ('d3 - num))begin//上溢出
                    exp_norm = 255;
                    man_norm = 0;
                end else begin
                    exp_norm = aligned_exp_r1 + ('d3 - num);
                    man_norm = man_add_r << num;
                end
            end else begin//小数点需要向后移动，exp要减
                if(aligned_exp_r1 <= (num - 'd3))begin//非规格数
                    exp_norm = 0; 
                    man_norm = man_add_r << (aligned_exp_r1 - 1 + 3);
                end else begin
                    exp_norm = aligned_exp_r1 - (num - 'd3);
                    man_norm = man_add_r << num;
                end
            end
        end
    end

    reg [7:0] exp_norm_r;
    reg [25:0] man_norm_r;
    reg sticky_r2;
    reg valid_r3;
    reg sign_res_r2;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            exp_norm_r <= 0;
            man_norm_r <= 0;
            sticky_r2 <= 0;
            valid_r3 <= 0;
            sign_res_r2 <= 0;
        end else if(~valid_r2)begin
            exp_norm_r <= 0;
            man_norm_r <= 0;
            sticky_r2 <= 0;
            valid_r3 <= 0;
            sign_res_r2 <= 0;
        end else begin
            exp_norm_r <= exp_norm;
            man_norm_r <= man_norm;
            sticky_r2 <= sticky_r;
            valid_r3 <= valid_r2;
            sign_res_r2 <= sign_res_r1;
        end
    end

     // 舍入,man_res[24:2] [1:0]
    wire [22:0] man_round;
    wire [7:0] exp_round;
    wire [22:0] man_main ;
    assign man_main = man_norm_r[25:3]; // 主尾数
    //GRS
    wire       guard   ;
    wire       round   ;
    wire       sticky  ;
    assign guard    = man_norm_r[2];
    assign round    = man_norm_r[1];
    assign sticky   = man_norm_r[0] | sticky_r2; 

    wire round_up;
    assign round_up = (guard && (round | sticky)) || 
                  (guard && ~round && ~sticky && man_main[0]); 

    wire [23:0] man_rounded;// 舍入后的结果
    assign man_rounded = man_main + round_up;

    assign man_round = man_rounded[22:0];
    assign exp_round = man_rounded[23]? exp_norm_r + 1 : exp_norm_r;

    reg [22:0] man_round_r;
    reg [7:0] exp_round_r;
    reg valid_r4;
    reg sign_res_r3;
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            man_round_r <= 0;
            exp_round_r <= 0;
            valid_r4 <= 0;
            sign_res_r3 <= 0;
        end else if(~valid_r3)begin
            man_round_r <= 0;
            exp_round_r <= 0;
            valid_r4 <= 0;
            sign_res_r3 <= 0;
        end else begin
            man_round_r <= man_round;
            exp_round_r <= exp_round;
            valid_r4 <= valid_r3;
            sign_res_r3 <= sign_res_r2;
        end
    end

//判断溢出
    wire sign;
    reg [22:0] man;
    reg [7:0] exp;
    assign sign = sign_res_r3;
    wire overflow;
    // wire underflow;
    assign overflow = (exp_round_r >= 255);
    // assign underflow = (exp_round_r <= 0);

    always @(*) begin
        if(overflow)begin
            exp = 8'b11111111;
            man = 23'b00000000000000000000000;
        // end else if(underflow)begin
        //     exp = 8'b00000000;
        //     man = 23'b00000000000000000000000;
        end else begin
            exp = exp_round_r;
            man = man_round_r;
        end
    end
    // 输出结果
    wire [31:0] sum_w;
    assign sum_w = {sign, exp, man}; 

    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            sum <= 0;
            out_valid <= 0;
        end else if(~valid_r4)begin
            sum <= 0;
            out_valid <= 0;
        end else begin
            sum <= sum_w;
            out_valid <= valid_r4;
        end
    end

endmodule

module add_INT_2in#(parameter DATA_WIDTH = 12)//12/20
(
    input                   clk,
    input                   rst_n,
    input  [DATA_WIDTH-1:0] a, // 
    input  [DATA_WIDTH-1:0] b, // 
    input         valid,
    output  reg      out_valid,
    output reg [DATA_WIDTH-1:0] sum // 
);
    wire [DATA_WIDTH-1:0] sum_w;
    
    CLA_AdderTree#(.DATA_WIDTH(DATA_WIDTH)) add_tree(
        .A(a),
       .B(b),
       .product(sum_w)
    );
    always@(posedge clk or negedge rst_n)begin
        if(~rst_n)begin
            sum <= 0;
            out_valid <= 0;
        end else if(~valid)begin
            sum <= 0;
            out_valid <= 0;
        end else begin
            sum <= sum_w;
            out_valid <= valid;
        end
    end
endmodule

module adder(
    input clk,
    input rst_n,
    input [31:0] a,
    input [31:0] b,
    input valid,
    input [2:0] dtype_sel,
    input mixedp_sel,
    output reg out_valid,
    output [31:0] sum
);

// 数据类型模式
localparam INT4_MODE = 3'b000;  // INT4 数据类型模式
localparam INT8_MODE = 3'b001;  // INT8 数据类型模式
localparam FP16_MODE = 3'b010;  // FP16 数据类型模式
localparam FP32_MODE = 3'b011;  // FP32 数据类型模式

wire [5:0] a_property, b_property;
wire a_sign, b_sign;
wire a_is_nan, b_is_nan;
wire a_is_inf, b_is_inf;
wire a_is_zero, b_is_zero;
wire a_is_normal, b_is_normal;

judge_property judge_a(
    .data_in(a),
    .mode(dtype_sel),
    .valid(valid),
    .property_out(a_property)
);

judge_property judge_b(
    .data_in(b),
    .mode(dtype_sel),
    .valid(valid),
    .property_out(b_property)
);

assign a_sign = a_property[5];
assign b_sign = b_property[5];
assign a_is_nan = a_property[4];
assign b_is_nan = b_property[4];
assign a_is_inf = a_property[3];
assign b_is_inf = b_property[3];
assign a_is_zero = a_property[2];
assign b_is_zero = b_property[2];
assign a_is_normal = a_property[0];
assign b_is_normal = b_property[0];

wire has_nan, has_inf, has_pos_inf,has_neg_inf,has_pos_neg_inf,all_zero;
assign has_nan = a_is_nan || b_is_nan;
assign has_inf = a_is_inf || b_is_inf;
assign has_pos_inf = (a_is_inf && ~a_sign) || (b_is_inf && ~b_sign);
assign has_neg_inf = (a_is_inf && a_sign) || (b_is_inf && b_sign);
assign has_pos_neg_inf = has_pos_inf && has_neg_inf;
assign all_zero = a_is_zero && b_is_zero;

// 参数化 NaN 定义（QNaN = quiet NaN，最高位为1）
localparam [15:0] QNAN_FP16 = {1'b0, 5'b11111, 10'b1000000000}; // FP16 QNaN
localparam [31:0] QNAN_FP32 = {1'b0, 8'b11111111, 23'b10000000000000000000000}; // FP32 QNaN
localparam [4:0] EXP_MAX_FP16 = 31;
localparam [7:0] EXP_MAX_FP32 = 255;

reg use_special;
wire [31:0] sum_special;
reg  [31:0] sum_special_undelay;//特殊值处理
always@(*)begin
    use_special = 0;
    sum_special_undelay = 32'h0;
    case(dtype_sel)
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

//valid信号
wire valid_int, valid_fp16, valid_fp32,valid_special;//加法器使能
wire out_valid_int, out_valid_fp16, out_valid_fp32,out_valid_special;//加法器输出使能
// assign out_valid_special = valid_special;

wire fp16_mixed;//fp16混合精度模式
assign fp16_mixed = (dtype_sel == FP16_MODE && mixedp_sel);
assign valid_int = valid && (dtype_sel == INT4_MODE || dtype_sel == INT8_MODE );
// assign valid_int8 = valid && (dtype_sel == INT8_MODE );
assign valid_fp16 = ~use_special && valid && (dtype_sel == FP16_MODE ) && ~mixedp_sel;
assign valid_fp32 = ~use_special && valid && ((dtype_sel == FP32_MODE ) || fp16_mixed);
assign valid_special = valid && use_special && (dtype_sel == FP16_MODE || dtype_sel == FP32_MODE);

wire [31:0] sum_int;
wire [15:0] sum_fp16;
wire [31:0] sum_fp32;

//输出
reg [31:0] sum_w;
wire use_special_delay;
always@(*)begin
    out_valid = 0;
    sum_w = 32'h0;
    case(dtype_sel)
        INT4_MODE,INT8_MODE:begin
            out_valid = out_valid_int;
            sum_w = sum_int;
        end
        FP16_MODE:begin
            if(use_special_delay)begin
                out_valid = out_valid_special;
                sum_w = sum_special;
            end else begin
                if(mixedp_sel)begin
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
assign sum = out_valid? sum_w : 32'h0;

add_special_2in add_special_inst(
    .clk(clk),
    .rst_n(rst_n),
    .clean(1'b0),
    .sum_special_undelay(sum_special_undelay),
    .valid(valid_special),
    .use_special(use_special),
    .out_valid(out_valid_special),
    .use_special_delay(use_special_delay),
    .sum_special(sum_special)
);

//INT4加法器
add_INT_2in #(.DATA_WIDTH(32)) add_int(
    .clk(clk),
    .rst_n(rst_n),
    .a(a),
    .b(b),
    .valid(valid_int),
    .out_valid(out_valid_int),
    .sum(sum_int)
);

// //INT8加法器
// add_INT_2in #(.DATA_WIDTH(20)) add_int8(
//     .clk(clk),
//     .rst_n(rst_n),
//     .a(a[19:0]),
//     .b(b[19:0]),
//     .valid(valid_int8),
//     .out_valid(out_valid_int8),
//     .sum(sum_int8)
// );

//FP16加法器
add_FP16_2in add_fp16(
    .clk(clk),
    .rst_n(rst_n),
    .a(a[15:0]),
   .b(b[15:0]),
   .valid(valid_fp16),
   .a_is_normal(a_is_normal),
    .b_is_normal(b_is_normal),
   .out_valid(out_valid_fp16),
   .sum(sum_fp16)
);

//FP32加法器
add_FP32_2in add_fp32(
    .clk(clk),
    .rst_n(rst_n),
    .a(a),
    .b(b),
    .valid(valid_fp32),
    .a_is_normal(a_is_normal),
    .b_is_normal(b_is_normal),
    .out_valid(out_valid_fp32),
    .sum(sum_fp32)
);

endmodule