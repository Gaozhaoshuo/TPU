module mant_shift#(parameter EXP_WIDTH=5,MAN_WIDTH=11)
(
    input [16*MAN_WIDTH-1:0] man,
    input [16*EXP_WIDTH-1:0] diff,
    
    output [16 - 1:0] sticky,
    output [16*MAN_WIDTH-1:0] aligned_man
);

generate
    genvar i;
    for(i=0;i<16;i=i+1) begin : shift
        assign aligned_man[i*MAN_WIDTH+:MAN_WIDTH] = man[i*MAN_WIDTH+:MAN_WIDTH] >> diff[i*EXP_WIDTH+:EXP_WIDTH];
        assign sticky[i] = |(man[i*MAN_WIDTH+:MAN_WIDTH] & ((1'b1 << diff[i*EXP_WIDTH+:EXP_WIDTH]) - 1));
    end
endgenerate


endmodule

