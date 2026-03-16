module command_decoder #(
         parameter CMD_WIDTH = 128
       ) (
         input  wire [CMD_WIDTH-1:0] cmd_data,

         output wire [7:0]           opcode,
         output wire [2:0]           dtype_sel,
         output wire                 mixed_precision,
         output wire [2:0]           layout,
         output wire [7:0]           dep_in,
         output wire [7:0]           dep_out,
         output wire [15:0]          m,
         output wire [15:0]          n,
         output wire [15:0]          k,
         output wire                 gemm_relu_fuse,
         output wire [2:0]           legacy_mtype_sel,
         output wire                 is_dma_load,
         output wire                 is_supported_dma_load,
         output wire                 is_dma_store,
         output wire                 is_supported_dma_store,
         output wire                 is_gemm,
         output wire                 is_ewise,
         output wire                 is_supported_ewise,
         output wire                 is_barrier,
         output wire                 is_supported_gemm
       );

localparam [7:0] OPCODE_DMA_LOAD  = 8'h01;
localparam [7:0] OPCODE_DMA_STORE = 8'h02;
localparam [7:0] OPCODE_GEMM = 8'h10;
localparam [7:0] OPCODE_EWISE = 8'h11;
localparam [7:0] OPCODE_BARRIER = 8'h20;
wire shape_mnk_valid;

assign opcode = cmd_data[127:120];
assign dtype_sel = cmd_data[118:116];
assign mixed_precision = cmd_data[115];
assign layout = cmd_data[114:112];
assign dep_in = cmd_data[111:104];
assign dep_out = cmd_data[103:96];
assign m = cmd_data[95:80];
assign n = cmd_data[79:64];
assign k = cmd_data[63:48];
assign gemm_relu_fuse = cmd_data[33];

assign is_dma_load = (opcode == OPCODE_DMA_LOAD);
assign is_supported_dma_load = is_dma_load && shape_mnk_valid;
assign is_dma_store = (opcode == OPCODE_DMA_STORE);
assign is_supported_dma_store = is_dma_store && shape_mnk_valid;
assign is_gemm = (opcode == OPCODE_GEMM);
assign is_ewise = (opcode == OPCODE_EWISE);
assign is_supported_ewise = is_ewise && shape_mnk_valid && (dtype_sel == 3'b011) && (~mixed_precision);
assign is_barrier = (opcode == OPCODE_BARRIER);
assign is_supported_gemm = is_gemm && shape_mnk_valid;

legacy_shape_codec legacy_shape_codec_inst (
                     .mtype_sel(3'b000),
                     .m(),
                     .n(),
                     .k(),
                     .mtype_valid(),
                     .decode_m(m),
                     .decode_n(n),
                     .decode_k(k),
                     .decoded_mtype_sel(legacy_mtype_sel),
                     .mnk_valid(shape_mnk_valid)
                   );

endmodule
