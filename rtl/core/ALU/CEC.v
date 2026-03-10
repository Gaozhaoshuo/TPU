module CEC#(parameter EXP_WIDTH=5)
(
    input                    clk,
    input                   rst_n,
    input                   valid,
    input                   clean,
    input [16*EXP_WIDTH-1:0] exp,
    output  reg              out_valid,
    output [EXP_WIDTH-1:0] aligned_exp,
    output [16*EXP_WIDTH-1:0] diff
);

wire [4*EXP_WIDTH-1:0] Emax_temp_w;
reg  [4*EXP_WIDTH-1:0] Emax_temp;
reg  [16*EXP_WIDTH-1:0] exp_r;
generate
    genvar i;
    for(i = 0; i < 4;i=i+1) begin : comp
        four_input_ec#(EXP_WIDTH) 
            four_input_ec_inst(
                .E0(exp[(4*i + 0)*EXP_WIDTH +: EXP_WIDTH]),
                .E1(exp[(4*i + 1)*EXP_WIDTH +: EXP_WIDTH]),
                .E2(exp[(4*i + 2)*EXP_WIDTH +: EXP_WIDTH]),
                .E3(exp[(4*i + 3)*EXP_WIDTH +: EXP_WIDTH]),
                .Emax(Emax_temp_w[i*EXP_WIDTH +: EXP_WIDTH])
        );
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        Emax_temp <= 0;
        out_valid <= 0;
        exp_r <= 0;
    end else if(~valid | clean) begin
        Emax_temp <= 0;
        out_valid <= 0;
        exp_r <= 0;
    end else begin
        Emax_temp <= Emax_temp_w;
        out_valid <= valid;
        exp_r <= exp;
    end
end


wire [EXP_WIDTH-1:0] Emax;
four_input_ec#(EXP_WIDTH) 
    four_input_ec_inst(
        .E0(Emax_temp[0*EXP_WIDTH +: EXP_WIDTH]),
        .E1(Emax_temp[1*EXP_WIDTH +: EXP_WIDTH]),
        .E2(Emax_temp[2*EXP_WIDTH +: EXP_WIDTH]),
        .E3(Emax_temp[3*EXP_WIDTH +: EXP_WIDTH]),
        .Emax(Emax)
);
assign aligned_exp = Emax;

generate
    genvar j;
    for(j = 0; j < 16;j=j+1) begin : diff_comp
        assign diff[j*EXP_WIDTH +: EXP_WIDTH] = Emax - exp_r[j*EXP_WIDTH +: EXP_WIDTH];
    end
endgenerate

endmodule

module four_input_ec #(parameter EXP_WIDTH=5)
(
    input [EXP_WIDTH-1:0] E0, E1, E2, E3,
    output [EXP_WIDTH-1:0] Emax
);
    wire [EXP_WIDTH-1:0] max01, max23;

    // 并行计算 E0 vs E1 和 E2 vs E3
    assign max01 = (E0 > E1) ? E0 : E1;
    assign max23 = (E2 > E3) ? E2 : E3;

    // 再次比较，选出最大值
    assign Emax = (max01 > max23) ? max01 : max23;

endmodule
