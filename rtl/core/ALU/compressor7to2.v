`timescale 1ns / 1ps

module ele7to2(I0, I1, I2, I3, I4, I5, I6, Cin1, Cin2, Cout1, Cout2, Sum, Carry);
    input I0, I1, I2, I3, I4, I5, I6, Cin1, Cin2;
    output Cout1, Cout2, Sum, Carry;
    wire w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, w16, w17, w18, w19, w20, PA, PB, S, A, B, C, D;
    
    assign w1 = I0^I1;                  //1
    assign w2 = I2^I3;                  //2
    assign PA = w1^w2;                  //3
    assign w3 = I4^I5;                  //4
    assign PB = w3^I6;                  //5
    assign S = PA^PB;                   //6
    assign w4 = Cin1^S;                 //7
    assign Sum = w4^Cin2;               //8  
    
    assign w5 = Cin1^S;                 //9
    assign w6 = ~(w5&Cin2);             //10
    assign w7 = ~(Cin1&S);              //11
    assign Carry = ~(w6&w7);            //12
    
    assign w15 = ~(I0&I1);              //13
    assign w16 = ~(I2&I3);              //14
    assign w19 = w15&w16;               //15
    assign w17 = ~(I0|I1);              //16
    assign w18 = ~(I2|I3);              //17
    assign w20 = w17|w18;               //18
    assign A = ~(w19&w20);              //19
    //A:I0-I3 有两个及以上的1

    assign w10 = ~(I0&I1&I2&I3);        //20
    assign w11 = ~(PA&PB);              //21
    assign C = ~(w10&w11);              //22
    //C:I0-I3均为1，或I0-I3和I4-I6中1的个数均为奇数
    
    assign w12 = I5|I4;                 //23
    assign w13 = ~(w12&I6);             //24
    assign w14 = ~(I4&I5);              //25
    assign B = ~(w13&w14);              //26
    //B:I4-I6 有两个及以上的1
    
    assign D = A^B;                     //27
    //D:A和B只有一个成立
    assign w8 = ~(D&C);                 //28
    assign w9 = ~(A&B);                 //29
    assign Cout2 = ~(w8&w9);            //30
    
    assign Cout1 = D^C;                 //31
        
endmodule



module compressor7to2#(parameter WIDTH = 24)
(input [WIDTH-1:0]P0, input [WIDTH-1:0]P1, input [WIDTH-1:0]P2, input [WIDTH-1:0]P3, input [WIDTH-1:0]P4, input [WIDTH-1:0]P5, input [WIDTH-1:0]P6,
                      output [WIDTH-1:0]carry, output [WIDTH-1:0]sum);
    
    wire gndd;
    wire [WIDTH-1:0]Cout1, Cout2;
    
    assign gndd = 1'b0;
    ele7to2 u0(P0[0], P1[0], P2[0], P3[0], P4[0], P5[0], P6[0], gndd, gndd, Cout1[0], Cout2[0], sum[0], carry[0]);
    ele7to2 u1(P0[1], P1[1], P2[1], P3[1], P4[1], P5[1], P6[1], gndd, Cout1[0], Cout1[1], Cout2[1], sum[1], carry[1]); 
    generate
        genvar i;
        for(i=2; i<WIDTH; i=i+1) begin : gen_ele
            ele7to2 u(P0[i], P1[i], P2[i], P3[i], P4[i], P5[i], P6[i], Cout2[i-2], Cout1[i-1], Cout1[i], Cout2[i], sum[i], carry[i]);
        end
    endgenerate
endmodule

module ele3to2 (
    input A, input B, input C,
    output sum, output carry
);
    assign sum   = A ^ B ^ C;
    assign carry = (A & B) | (B & C) | (A & C);
endmodule

module compressor3to2#(parameter WIDTH = 24)
(
    input  [WIDTH-1:0] P0,
    input  [WIDTH-1:0] P1,
    input  [WIDTH-1:0] P2,
    output [WIDTH-1:0] sum,
    output [WIDTH-1:0] carry // 左移后的 carry（已对齐）
);
    wire [WIDTH:0] carry_raw;
    assign carry_raw[0] = 1'b0;

    generate
        genvar i;
        for(i = 0; i < WIDTH; i = i + 1) begin : gen_ele
            ele3to2 u(
                .A(P0[i]),
                .B(P1[i]),
                .C(P2[i]),
                .sum(sum[i]),
                .carry(carry_raw[i+1])
            );
        end
    endgenerate
    assign carry = carry_raw[WIDTH-1:0];
endmodule

