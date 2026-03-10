//无符号12位乘法器
module multi12bX12b(input [11:0] a, input [11:0] b, output [23:0] c);
wire [14:0] B_expand;
assign B_expand = {2'b00,b,1'b0};

reg [23:0] pp0,pp1,pp2,pp3,pp4,pp5,pp6;
wire [23:0] carry,carry_init,sum;

compressor7to2 compressor(
   .P0(pp0),
   .P1(pp1),
   .P2(pp2),
   .P3(pp3),
   .P4(pp4),
   .P5(pp5),
   .P6(pp6),
   .carry(carry_init),
   .sum(sum)
);

assign carry = carry_init << 1;

CLA_AdderTree#(.DATA_WIDTH(24)) CLA(
    .A(carry),
    .B(sum),
    .product(c)
);

always@(*)begin
    case(B_expand[2:0])//1 0 -1
        3'b000: begin
            pp0 = 24'b0;
        end
        3'b001: begin//do not exist
            pp0 = 24'b0;
        end
        3'b010: begin//2^1*a-2^0*a=a
            pp0 = {12'b0,a};
        end
        3'b011: begin//do not exist
            pp0 = 24'b0;
        end
        3'b100: begin//-2^1*a
            pp0 = {~({11'b0,a})+1,1'b0};
        end
        3'b101: begin//do not exist
            pp0 = 24'b0;
        end
        3'b110: begin//-2^0*a
            pp0 = {~({12'b0,a})+1};
        end
        3'b111: begin//do not exist
            pp0 = 24'b0;
        end
    endcase
    case(B_expand[4:2])//3 2 1
        3'b000: begin
            pp1 = 24'b0;
        end
        3'b001: begin//2^2*a
            pp1 = {10'b0,a,2'b0};
        end
        3'b010: begin//2^3*a-2^2*a = 2^2*a
            pp1 = {10'b0,a,2'b0};
        end
        3'b011: begin//2^3*a
            pp1 = {9'b0,a,3'b0};
        end
        3'b100: begin//-2^3*a
            pp1 = {~({9'b0,a})+1,3'b0};
        end
        3'b101: begin//2^2*a-2^3*a = -2^2*a
            pp1 = {~({10'b0,a})+1,2'b0};
        end
        3'b110: begin//-2^2*a
            pp1 = {~({10'b0,a})+1,2'b0};
        end
        3'b111: begin//0
            pp1 = 24'b0;
        end
    endcase
    case(B_expand[6:4])//5 4 3
        3'b000: begin
            pp2 = 24'b0;
        end
        3'b001: begin//2^4*a
            pp2 = {8'b0,a,4'b0};
        end
        3'b010: begin//2^5*a-2^4*a = 2^4*a
            pp2 = {8'b0,a,4'b0};
        end
        3'b011: begin//2^5*a
            pp2 = {7'b0,a,5'b0};
        end
        3'b100: begin//-2^5*a
            pp2 = {~({7'b0,a})+1,5'b0};
        end
        3'b101: begin//2^4*a-2^5*a = -2^4*a
            pp2 = {~({8'b0,a})+1,4'b0};
        end
        3'b110: begin//-2^4*a
            pp2 = {~({8'b0,a})+1,4'b0};
        end
        3'b111: begin//0
            pp2 = 24'b0;
        end
    endcase
    case(B_expand[8:6])//7 6 5
        3'b000: begin
            pp3 = 24'b0;
        end
        3'b001: begin//2^6*a
            pp3 = {6'b0,a,6'b0};
        end
        3'b010: begin//2^7*a-2^6*a = 2^6*a
            pp3 = {6'b0,a,6'b0};
        end
        3'b011: begin//2^7*a
            pp3 = {5'b0,a,7'b0};
        end
        3'b100: begin//-2^7*a
            pp3 = {~({5'b0,a})+1,7'b0};
        end
        3'b101: begin//2^6*a-2^7*a = -2^6*a
            pp3 = {~({6'b0,a})+1,6'b0};
        end
        3'b110: begin//-2^6*a
            pp3 = {~({6'b0,a})+1,6'b0};
        end
        3'b111: begin//0
            pp3 = 24'b0;
        end
    endcase
    case(B_expand[10:8])//9 8 7
        3'b000: begin
            pp4 = 24'b0;
        end
        3'b001: begin//2^8*a
            pp4 = {4'b0,a,8'b0};
        end
        3'b010: begin//2^9*a-2^8*a = 2^8*a
            pp4 = {4'b0,a,8'b0};
        end
        3'b011: begin//2^9*a
            pp4 = {3'b0,a,9'b0};
        end
        3'b100: begin//-2^9*a
            pp4 = {~({3'b0,a})+1,9'b0};
        end
        3'b101: begin//2^8*a-2^9*a = -2^8*a
            pp4 = {~({4'b0,a})+1,8'b0};
        end
        3'b110: begin//-2^8*a
            pp4 = {~({4'b0,a})+1,8'b0};
        end
        3'b111: begin//0
            pp4 = 24'b0;
        end
    endcase
    case(B_expand[12:10])//11 10 9
        3'b000: begin
            pp5 = 24'b0;
        end
        3'b001: begin//2^10*a
            pp5 = {2'b0,a,10'b0};
        end
        3'b010: begin//2^11*a-2^10*a = 2^10*a
            pp5 = {2'b0,a,10'b0};
        end
        3'b011: begin//2^11*a
            pp5 = {1'b0,a,11'b0};
        end
        3'b100: begin//-2^11*a
            pp5 = {~({1'b0,a})+1,11'b0};
        end
        3'b101: begin//2^10*a-2^11*a = -2^10*a
            pp5 = {~({2'b0,a})+1,10'b0};
        end
        3'b110: begin//-2^10*a
            pp5 = {~({2'b0,a})+1,10'b0};
        end
        3'b111: begin//0
            pp5 = 24'b0;
        end
    endcase
    case(B_expand[14:12])//13 12 11
        3'b000: begin
            pp6 = 24'b0;
        end
        3'b001: begin//2^12*a
            pp6 = {a,12'b0};
        end
        default://do not exist
            pp6 = 24'b0;
    endcase
end

endmodule