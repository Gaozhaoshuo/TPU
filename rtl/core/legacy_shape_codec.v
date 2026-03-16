module legacy_shape_codec (
         input  wire [2:0]  mtype_sel,
         output reg  [15:0] m,
         output reg  [15:0] n,
         output reg  [15:0] k,
         output reg         mtype_valid,

         input  wire [15:0] decode_m,
         input  wire [15:0] decode_n,
         input  wire [15:0] decode_k,
         output reg  [2:0]  decoded_mtype_sel,
         output reg         mnk_valid
       );

localparam [2:0] MTYPE_M16N16K16 = 3'b001;
localparam [2:0] MTYPE_M32N8K16  = 3'b010;
localparam [2:0] MTYPE_M8N32K16  = 3'b100;

always @(*)
  begin
    m = 16'd0;
    n = 16'd0;
    k = 16'd0;
    mtype_valid = 1'b0;

    case (mtype_sel)
      MTYPE_M16N16K16:
        begin
          m = 16'd16;
          n = 16'd16;
          k = 16'd16;
          mtype_valid = 1'b1;
        end
      MTYPE_M32N8K16:
        begin
          m = 16'd32;
          n = 16'd8;
          k = 16'd16;
          mtype_valid = 1'b1;
        end
      MTYPE_M8N32K16:
        begin
          m = 16'd8;
          n = 16'd32;
          k = 16'd16;
          mtype_valid = 1'b1;
        end
      default:
        begin
          m = 16'd0;
          n = 16'd0;
          k = 16'd0;
          mtype_valid = 1'b0;
        end
    endcase
  end

always @(*)
  begin
    decoded_mtype_sel = 3'b000;
    mnk_valid = 1'b0;

    if ((decode_m == 16) && (decode_n == 16) && (decode_k == 16))
      begin
        decoded_mtype_sel = MTYPE_M16N16K16;
        mnk_valid = 1'b1;
      end
    else if ((decode_m == 32) && (decode_n == 8) && (decode_k == 16))
      begin
        decoded_mtype_sel = MTYPE_M32N8K16;
        mnk_valid = 1'b1;
      end
    else if ((decode_m == 8) && (decode_n == 32) && (decode_k == 16))
      begin
        decoded_mtype_sel = MTYPE_M8N32K16;
        mnk_valid = 1'b1;
      end
  end

endmodule
