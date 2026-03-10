`timescale 1ns / 1ps
module CLA_tail #(parameter WIDTH = 1)(
    input [WIDTH-1:0] a,
    input [WIDTH-1:0] b,
    input c0,
    output [WIDTH-1:0] sum,
    output cout
);
    wire [WIDTH:0] carry;
    assign carry[0] = c0;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : tail_add
            assign sum[i] = a[i] ^ b[i] ^ carry[i];
            assign carry[i+1] = (a[i] & b[i]) | (a[i] & carry[i]) | (b[i] & carry[i]);
        end
    endgenerate

    assign cout = carry[WIDTH];
endmodule


module CLA_4bit(input [3:0]a, input [3:0]b, input c0, output [3:0]Sum, output Cout);
    wire P0, P1, P2, P3, G0, G1, G2, G3, c1, c2, c3;
    
    assign P0 = a[0]^b[0];
    assign P1 = a[1]^b[1];
    assign P2 = a[2]^b[2];
    assign P3 = a[3]^b[3];
    
    assign G0 = a[0]&b[0];
    assign G1 = a[1]&b[1];
    assign G2 = a[2]&b[2];
    assign G3 = a[3]&b[3];
    
    assign Sum[0] = P0^c0;
    assign Sum[1] = P1^c1;
    assign Sum[2] = P2^c2;
    assign Sum[3] = P3^c3;
    
    assign c1 = (c0&P0)|G0;
    assign c2 = (c1&P1)|G1;
    assign c3 = (c2&P2)|G2;
    assign Cout = (c3&P3)|G3;
    
endmodule

module CLA_AdderTree #(parameter DATA_WIDTH=13)
(
    input [DATA_WIDTH-1:0] A,
    input [DATA_WIDTH-1:0] B,
    output [DATA_WIDTH-1:0] product
);
    localparam FULL_CLA_NUM = DATA_WIDTH / 4;
    localparam REMAIN = DATA_WIDTH % 4;

    wire [FULL_CLA_NUM:0] carry;  // 支持 N个 CLA + 1尾部
    assign carry[0] = 1'b0;

    genvar i;
    generate
        for(i = 0; i < FULL_CLA_NUM; i = i + 1) begin: cla_main
            CLA_4bit cla(
                .a(A[4*i +: 4]),
                .b(B[4*i +: 4]),
                .c0(carry[i]),
                .Sum(product[4*i +: 4]),
                .Cout(carry[i+1])
            );
        end
        if (REMAIN != 0) begin: tail
            CLA_tail #(.WIDTH(REMAIN)) cla_tail (
                .a(A[DATA_WIDTH - REMAIN +: REMAIN]),
                .b(B[DATA_WIDTH - REMAIN +: REMAIN]),
                .c0(carry[FULL_CLA_NUM]),
                .sum(product[DATA_WIDTH - REMAIN +: REMAIN]),
                .cout() // 可以输出总进位或忽略
            );
        end
    endgenerate
endmodule


// module CLA_AdderTree_24b(input [23:0]A, input [23:0]B, output [23:0]product);
//     wire gndd, c1, c2, c3, c4, c5, c6;
//     assign gndd = 1'b0;
//     CLA_4bit a1(A[3:0], B[3:0], gndd, product[3:0], c1);
//     CLA_4bit a2(A[7:4], B[7:4], c1, product[7:4], c2);
//     CLA_4bit a3(A[11:8], B[11:8], c2, product[11:8], c3);
//     CLA_4bit a4(A[15:12], B[15:12], c3, product[15:12], c4);
//     CLA_4bit a5(A[19:16], B[19:16], c4, product[19:16], c5);
//     CLA_4bit a6(A[23:20], B[23:20], c5, product[23:20], c6);
// endmodule



