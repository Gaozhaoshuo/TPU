// module complement2ss1#(parameter WIDTH = 15)
// (
//     sum, 
//     sign, 
//     out
// );
//     input[WIDTH-1:0]sum;
//     input sign;
//     output [WIDTH-1:0]out;
    
//     wire [WIDTH-1:0]usum;
//     wire [WIDTH-1:0]check;
    
//     assign usum[0] = sum[0];
//     assign check[0] = sum[0];
//     genvar i;
//     generate
//         for(i=1; i<WIDTH; i = i+1)
//         begin
//             assign usum[i] = check[i-1]?(~sum[i]):sum[i];
//             assign check[i] = check[i-1]|sum[i];
//         end 
//     endgenerate
    
//     assign out = sign?usum:sum;
// endmodule

module complement2ss1#(parameter WIDTH = 15)(
    input  [WIDTH-1:0] sum,
    input              sign,
    output [WIDTH-1:0] out
);
    assign out = sign ? (~sum + 1'b1) : sum;
endmodule
