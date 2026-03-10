module LZD3(sum, position, zero_flag);
    input [2:0] sum;
    output [1:0] position;
    output zero_flag;

    // 直接判断最高 1 位
    assign position = (sum[2]) ? 2'd1 :
                      (sum[1]) ? 2'd2 :
                      (sum[0]) ? 2'd3 :
                      2'd0; // 全 0
    
    assign zero_flag = ~(|sum);  // sum 是否全 0

endmodule

module LZD4(sum, position, zero_flag);
    input [3:0] sum;
    output [2:0] position;
    output zero_flag;

    // 直接判断最高 1 位
    assign position = (sum[3]) ? 3'd1 :
                      (sum[2]) ? 3'd2 :
                      (sum[1]) ? 3'd3 :
                      (sum[0]) ? 3'd4 :
                      2'd0; // 全 0
    
    assign zero_flag = ~(|sum);  // sum 是否全 0

endmodule

module LZD6(sum, position, zero_flag);
    input [5:0] sum;
    output [2:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [1:0] posL, posR;

    // 递归拆分 6-bit 成 3-bit 两部分
    LZD3 LZD_left (sum[5:3], posL, zfL);
    LZD3 LZD_right(sum[2:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 3;
    assign zero_flag = zfL & zfR;

endmodule

module LZD7(sum, position, zero_flag);
    input [6:0] sum;
    output [2:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [1:0] posL;
    wire [2:0] posR;

    // 递归拆分 6-bit 成 3 4-bit 两部分
    LZD3 LZD_left (sum[6:4], posL, zfL);
    LZD4 LZD_right(sum[3:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 3;
    assign zero_flag = zfL & zfR;

endmodule

module LZD8(sum, position, zero_flag);
    input [7:0] sum;
    output [3:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [2:0] posL;
    wire [2:0]  posR;
    
    // 递归拆分 8-bit 成 4-bit 4-bit 两部分
    LZD4 LZD_left(sum[7:4], posL, zfL);
    LZD4 LZD_right (sum[3:0], posR, zfR);
    

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 4;
    assign zero_flag = zfL & zfR;

endmodule

module LZD10(sum, position, zero_flag);
    input [9:0] sum;
    output [3:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [2:0] posL, posR;

    // 递归拆分 6-bit 成 4-bit 两部分
    LZD6 LZD_left (sum[9:4], posL, zfL);
    LZD4 LZD_right(sum[3:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 6;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1

endmodule

module LZD12(sum, position, zero_flag);
    input [11:0] sum;
    output [3:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [2:0] posL, posR;

    // 递归拆分 12-bit 成 6-bit 两部分
    LZD6 LZD_left (sum[11:6], posL, zfL);
    LZD6 LZD_right(sum[5:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 6;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1

endmodule

module LZD13(sum, position, zero_flag);
    input [12:0] sum;
    output [3:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [2:0] posL, posR;

    // 递归拆分 13-bit 成 6 7 -bit 两部分
    LZD6 LZD_left (sum[12:7], posL, zfL);
    LZD7 LZD_right(sum[6:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 6;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1

endmodule

module LZD16(sum, position,zero_flag);
    input [15:0] sum;
    output [4:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [3:0] posL;
    wire [3:0]  posR;
    
    // 递归拆分 16-bit 成 8-bit 8-bit 两部分
    LZD8 LZD_left(sum[15:8], posL, zfL);
    LZD8 LZD_right (sum[7:0], posR, zfR);
    
    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 8;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1


endmodule

module LZD22(sum, position,zero_flag);
    input [21:0] sum;
    output [4:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [4:0] posL;
    wire [2:0] posR;

    LZD16 LZD_left (sum[21:6], posL, zfL);
    LZD6 LZD_right(sum[5:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 16;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1

endmodule

module LZD26(sum, position,zero_flag);
    input [25:0] sum;
    output [4:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [3:0] posL, posR;

    LZD13 LZD_left (sum[25:13], posL, zfL);
    LZD13 LZD_right(sum[12:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 13;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1

endmodule

module LZD24(sum, position,zero_flag);
    input [23:0] sum;
    output [4:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [3:0] posL, posR;

    // 递归拆分 24-bit 成 12-bit 两部分
    LZD12 LZD_left (sum[23:12], posL, zfL);
    LZD12 LZD_right(sum[11:0], posR, zfR);

    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 12;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1

endmodule


module LZD29(sum, position,zero_flag);
    input [28:0] sum;
    output [4:0] position;
    output zero_flag;
    
    wire zfL, zfR;
    wire [3:0] posL;
    wire [4:0] posR;

    // 递归拆分 29-bit 成 13 16-bit 两部分
    LZD13 LZD_left (sum[28:16], posL, zfL);
    LZD16 LZD_right(sum[15:0], posR, zfR);
    // 选择正确的最高位
    assign position = (~zfL) ?  posL :  posR + 13;
    assign zero_flag = zfL & zfR;  // 只有两部分全零时，zero_flag 才为 1

endmodule

module LZD48(sum, position);
    input [47:0] sum;
    output [5:0] position;

    wire [4:0] posL, posR;
    wire zfL, zfR;

    LZD24 left(sum[47:24], posL, zfL);
    LZD24 right(sum[23:0], posR, zfR);

    assign position = ~zfL ? posL : posR + 24;
endmodule