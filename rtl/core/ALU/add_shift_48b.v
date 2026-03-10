module ele4to2(input P0, input P1, input P2, input P3, input carry_in, output carry_out, output carry, output sum);
    wire w1, w2, w3;
    assign w1 = P1^P0;
    assign w2 = P2^P3;
    assign w3 = w1^w2;
    assign sum = w3^carry_in;
    assign carry = w3 ? carry_in : P0;
    assign carry_out = w2 ? P1 : P3;   
endmodule

module compressor4to2_48b(input [47:0]P0, input [47:0]P1, input [47:0]P2, input [47:0]P3, output [47:0]carry, output [47:0]sum);
    wire [48:0]carry_in;
    assign carry_in[0] = 0;
    genvar i;
    generate 
        for(i=0; i<48; i=i+1)
        begin
            ele4to2 inst(.P0(P0[i]), .P1(P1[i]), .P2(P2[i]), .P3(P3[i]), .carry_in(carry_in[i]), .carry_out(carry_in[i+1]), .carry(carry[i]), .sum(sum[i]));
        end
    endgenerate   
endmodule

module add_shift_48b(
    input [47:0] a,
    input [47:0] b,
    input [47:0] c,
    input [47:0] d,
    output [47:0] sum
);
wire [47:0] sum_compressed;
wire [47:0] carry,carry_shifted;
assign carry_shifted = carry << 1;

compressor4to2_48b inst(
    .P0(a),
   .P1(b),
   .P2(c),
   .P3(d),
   .carry(carry),
   .sum(sum_compressed)
);

CLA_AdderTree#(.DATA_WIDTH(48)) inst_AdderTree(
    .A(sum_compressed),
   .B(carry_shifted),
   .product(sum)
);

endmodule



