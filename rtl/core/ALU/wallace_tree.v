module wallace_tree_16x20 (
    input  [20*16-1:0] a,
    output [19:0] sum,
    output [19:0] carry
);
    //解包
    wire [19:0] in [15:0];
    generate
        genvar i;
        for (i = 0; i < 16; i = i + 1) begin : unpack
            assign in[i] = a[i*20 +: 20];
        end
    endgenerate

    // 一级压缩：16 → 10
    wire [19:0] sum1 [4:0];
    wire [19:0] carry1 [4:0];
    genvar i1;
    generate
        for (i1 = 0; i1 < 5; i1 = i1 + 1) begin : lvl1
            compressor3to2 #(20) c(
                .P0(in[i1*3]),
                .P1(in[i1*3+1]),
                .P2(in[i1*3+2]),
                .sum(sum1[i1]),
                .carry(carry1[i1])
            );
        end
    endgenerate
    wire [19:0] pass_through1 ;
    assign pass_through1 = in[15];

    // 二级压缩：10 → 7
    wire [19:0] sum2 [2:0];
    wire [19:0] carry2 [2:0];
    compressor3to2 #(20) c2_0 (.P0(sum1[0]), .P1(carry1[0]), .P2(sum1[1]), .sum(sum2[0]), .carry(carry2[0]));
    compressor3to2 #(20) c2_1 (.P0(carry1[1]), .P1(sum1[2]), .P2(carry1[2]), .sum(sum2[1]), .carry(carry2[1]));
    compressor3to2 #(20) c2_2 (.P0(sum1[3]), .P1(carry1[3]), .P2(sum1[4]), .sum(sum2[2]), .carry(carry2[2]));
    wire [19:0] pass_through2[1:0];
    assign pass_through2[0] = carry1[4];
    assign pass_through2[1] = pass_through1;


    // 三级压缩：7 → 5
    wire [19:0] sum3 [1:0];
    wire [19:0] carry3 [1:0];
    compressor3to2 #(20) c3_0 (.P0(sum2[0]), .P1(carry2[0]), .P2(sum2[1]), .sum(sum3[0]), .carry(carry3[0]));
    compressor3to2 #(20) c3_1 (.P0(carry2[1]), .P1(sum2[2]), .P2(carry2[2]), .sum(sum3[1]), .carry(carry3[1]));
    wire [19:0] pass_through3[1:0];
    assign pass_through3[0] = pass_through2[0];
    assign pass_through3[1] = pass_through2[1];

    // 四级压缩：5 → 4
    wire [19:0] sum4 [1:0];
    wire [19:0] carry4 [1:0];
    compressor3to2 #(20) c4_0 (.P0(sum3[0]), .P1(carry3[0]), .P2(sum3[1]), .sum(sum4[0]), .carry(carry4[0]));
    compressor3to2 #(20) c4_1 (.P0(carry3[1]), .P1(pass_through3[0]), .P2(pass_through3[1]), .sum(sum4[1]), .carry(carry4[1]));

    // 五级压缩：4 → 3
    wire [19:0] sum5, carry5;
    compressor3to2 #(20) c5 (
        .P0(sum4[0]), .P1(carry4[0]), .P2(sum4[1]),
        .sum(sum5), .carry(carry5)
    );
    wire [19:0] pass_through5;
    assign pass_through5 = carry4[1];

    // 六级压缩：3 → 2（最终输出 sum & carry）
    compressor3to2 #(20) c6 (
        .P0(sum5), .P1(carry5), .P2(pass_through5),
        .sum(sum), .carry(carry)
    );
endmodule

module wallace_tree_16x20_7to2 (
    input  [20*16-1:0] a,
    output [19:0] sum,
    output [19:0] carry
);
    //解包
    wire [19:0] in [15:0];
    generate
        genvar i;
        for (i = 0; i < 16; i = i + 1) begin : unpack
            assign in[i] = a[i*20 +: 20];
        end
    endgenerate

    //一级
    wire [19:0] sum1 [1:0];
    wire [19:0] carry1 [1:0];
    wire [19:0] carry1_shift [1:0];
    generate
        genvar j;
        for(j = 0;j<2;j=j+1) begin : lvl1
            compressor7to2#(.WIDTH(20)) inst(
                .P0(in[j*7]),
                .P1(in[j*7+1]),
                .P2(in[j*7+2]),
                .P3(in[j*7+3]),
                .P4(in[j*7+4]),
                .P5(in[j*7+5]),
                .P6(in[j*7+6]),
                .sum(sum1[j]),
                .carry(carry1[j])
            );
        end
    endgenerate
    wire [19:0] pass_through1 [1:0];
    assign pass_through1[0] = in[14];
    assign pass_through1[1] = in[15];
    assign carry1_shift[0] = {carry1[0][18:0],1'b0};
    assign carry1_shift[1] = {carry1[1][18:0],1'b0};

//二级
    wire [19:0] carry_raw;
    compressor7to2#(.WIDTH(20)) inst1(
                .P0(sum1[0]),
                .P1(carry1_shift[0]),
                .P2(sum1[1]),
                .P3(carry1_shift[1]),
                .P4(pass_through1[0]),
                .P5(pass_through1[1]),
                .P6(20'b0),
                .sum(sum),
                .carry(carry_raw)
            );
    assign carry = {carry_raw[18:0],1'b0};

endmodule
