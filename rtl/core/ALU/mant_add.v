module mant_add#(parameter DATA_WIDTH = 16,CLA_WIDTH = 16)//29,32
(
    input [16*DATA_WIDTH-1:0] man,
    output [DATA_WIDTH-1:0] sum
);

wire [DATA_WIDTH-1 :0 ] carry_out1, carry_out2, sum1, sum2;
wire [DATA_WIDTH-1:0] carry1, carry2;
//华莱士树
//第一级
    compressor7to2 #(DATA_WIDTH) compressor1(
        .P0(man[0*DATA_WIDTH +: DATA_WIDTH]),
        .P1(man[1*DATA_WIDTH +: DATA_WIDTH]),
        .P2(man[2*DATA_WIDTH +: DATA_WIDTH]),
        .P3(man[3*DATA_WIDTH +: DATA_WIDTH]),
        .P4(man[4*DATA_WIDTH +: DATA_WIDTH]),
        .P5(man[5*DATA_WIDTH +: DATA_WIDTH]),
        .P6(man[6*DATA_WIDTH +: DATA_WIDTH]),
        .carry(carry_out1),
        .sum(sum1)
    );

    compressor7to2 #(DATA_WIDTH) compressor2(
        .P0(man[ 7*DATA_WIDTH +: DATA_WIDTH] ),
        .P1(man[ 8*DATA_WIDTH +: DATA_WIDTH] ),
        .P2(man[ 9*DATA_WIDTH +: DATA_WIDTH] ),
        .P3(man[10*DATA_WIDTH +: DATA_WIDTH]),
        .P4(man[11*DATA_WIDTH +: DATA_WIDTH]),
        .P5(man[12*DATA_WIDTH +: DATA_WIDTH]),
        .P6(man[13*DATA_WIDTH +: DATA_WIDTH]),
        .carry(carry_out2),
        .sum(sum2)
    );
assign carry1 = carry_out1 << 1;
assign carry2 = carry_out2 << 1;

//二级
wire [DATA_WIDTH-1:0] carry_out, sum_out;
wire [DATA_WIDTH-1:0] carry_shift;
compressor7to2 #(DATA_WIDTH) compressor3(
    .P0(man[14*DATA_WIDTH +: DATA_WIDTH]),
    .P1(man[15*DATA_WIDTH +: DATA_WIDTH]),
    .P2(sum1),
    .P3(sum2),
    .P4(carry1),
    .P5(carry2),
    .P6({DATA_WIDTH{1'b0}}),
    .carry(carry_out),
    .sum(sum_out)
);
    assign carry_shift = carry_out << 1;
    wire [CLA_WIDTH-1:0] sum_w;
    CLA_AdderTree#(CLA_WIDTH) add_adder_tree(
        .A({{(CLA_WIDTH-DATA_WIDTH){carry_shift[DATA_WIDTH-1]}},carry_shift}),
        .B({{(CLA_WIDTH-DATA_WIDTH){sum_out[DATA_WIDTH-1]}},sum_out}),
        .product(sum_w)
    );
    assign sum = sum_w[DATA_WIDTH-1:0];
endmodule

// module mant_add_FP16
// (
//     input [16*16-1:0] man,
//     output [15:0] sum
// );

// wire [15 :0 ] carry_out1, carry_out2, sum1, sum2;
// wire [15:0] carry1, carry2;
// //华莱士树
// //第一级
//     compressor7to2 #(16) compressor1(
//         .P0(man[0*16 +: 16]),
//         .P1(man[1*16 +: 16]),
//         .P2(man[2*16 +: 16]),
//         .P3(man[3*16 +: 16]),
//         .P4(man[4*16 +: 16]),
//         .P5(man[5*16 +: 16]),
//         .P6(man[6*16 +: 16]),
//         .carry(carry_out1),
//         .sum(sum1)
//     );

//     compressor7to2 #(16) compressor2(
//         .P0(man[ 7*16 +: 16] ),
//         .P1(man[ 8*16 +: 16] ),
//         .P2(man[ 9*16 +: 16] ),
//         .P3(man[10*16 +: 16]),
//         .P4(man[11*16 +: 16]),
//         .P5(man[12*16 +: 16]),
//         .P6(man[13*16 +: 16]),
//         .carry(carry_out2),
//         .sum(sum2)
//     );
// assign carry1 = carry_out1 << 1;
// assign carry2 = carry_out2 << 1;

// //二级
// wire [15:0] carry_out, sum_out;
// wire [15:0] carry_shift;
// compressor7to2 #(16) compressor3(
//     .P0(man[14*16 +: 16]),
//     .P1(man[15*16 +: 16]),
//     .P2(sum1),
//     .P3(sum2),
//     .P4(carry1),
//     .P5(carry2),
//     .P6(16'b0),
//     .carry(carry_out),
//     .sum(sum_out)
// );
//     assign carry_shift = carry_out << 1;
//     wire [15:0] sum_w;
//     CLA_AdderTree#(.DATA_WIDTH(16)) add_adder_tree(
//         .A(carry_shift),
//         .B(sum_out),
//         .product(sum_w)
//     );
//     assign sum = sum_w;

// endmodule

// module mant_add_FP32
// (
//     input [16*29-1:0] man,
//     output [28:0] sum
// );

// wire [28:0] carry_out1, carry_out2, sum1, sum2;
// wire [28:0] carry1, carry2;
// //华莱士树
// //第一级
//     compressor7to2 #(29) compressor1(
//         .P0(man[0*29 +: 29]),
//         .P1(man[1*29 +: 29]),
//         .P2(man[2*29 +: 29]),
//         .P3(man[3*29 +: 29]),
//         .P4(man[4*29 +: 29]),
//         .P5(man[5*29 +: 29]),
//         .P6(man[6*29 +: 29]),
//         .carry(carry_out1),
//         .sum(sum1)
//     );

//     compressor7to2 #(29) compressor2(
//         .P0(man[ 7*29 +: 29] ),
//         .P1(man[ 8*29 +: 29] ),
//         .P2(man[ 9*29 +: 29] ),
//         .P3(man[10*29 +: 29]),
//         .P4(man[11*29 +: 29]),
//         .P5(man[12*29 +: 29]),
//         .P6(man[13*29 +: 29]),
//         .carry(carry_out2),
//         .sum(sum2)
//     );
// assign carry1 = carry_out1 << 1;
// assign carry2 = carry_out2 << 1;

// //二级
// wire [28:0] carry_out, sum_out;
// wire [28:0] carry_shift;
// compressor7to2 #(29) compressor3(
//     .P0(man[14*29 +: 29]),
//     .P1(man[15*29 +: 29]),
//     .P2(sum1),
//     .P3(sum2),
//     .P4(carry1),
//     .P5(carry2),
//     .P6(29'b0),
//     .carry(carry_out),
//     .sum(sum_out)
// );
//     assign carry_shift = carry_out << 1;
//     wire [31:0] sum_w;
//     CLA_AdderTree#(.DATA_WIDTH(32)) add_adder_tree(
//         .A({{3{carry_shift[28]}},carry_shift}),
//        .B({{3{sum_out[28]}},sum_out}),
//        .product(sum_w)
//     );
//     assign sum = sum_w[28:0];

// endmodule

