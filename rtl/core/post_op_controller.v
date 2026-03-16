module post_op_controller (
         input  wire [7:0] active_opcode,
         input  wire       active_gemm_relu_fuse,
         input  wire       compute_done,
         input  wire       ewise_done,
         input  wire       dma_store_issue_pulse,
         output wire       fused_ewise_start_pulse,
         output wire       writeback_start_pulse
       );

localparam [7:0] OPCODE_GEMM = 8'h10;

assign fused_ewise_start_pulse = compute_done && (active_opcode == OPCODE_GEMM) && active_gemm_relu_fuse;
assign writeback_start_pulse = dma_store_issue_pulse ||
                               (compute_done && ((active_opcode != OPCODE_GEMM) || (~active_gemm_relu_fuse))) ||
                               (ewise_done && (active_opcode == OPCODE_GEMM) && active_gemm_relu_fuse);

endmodule
