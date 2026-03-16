module execution_controller (
         input  wire       clk,
         input  wire       rst_n,

         input  wire       cmd_valid,
         output wire       cmd_ready,

         input  wire [7:0] cmd_opcode,
         input  wire [7:0] cmd_dep_in,
         input  wire [7:0] cmd_dep_out,
         input  wire [2:0] cmd_dtype_sel,
         input  wire       cmd_mixed_precision,
         input  wire       cmd_gemm_relu_fuse,
         input  wire [2:0] cmd_legacy_mtype_sel,
         input  wire       cmd_is_dma_load,
         input  wire       cmd_is_supported_dma_load,
         input  wire       cmd_is_dma_store,
         input  wire       cmd_is_supported_dma_store,
         input  wire       cmd_is_supported_gemm,
         input  wire       cmd_is_ewise,
         input  wire       cmd_is_supported_ewise,
         input  wire       cmd_is_barrier,
         input  wire       load_done,
         input  wire       ewise_done,
         input  wire       compute_done,
         input  wire       writeback_done,

         output reg  [7:0] active_opcode,
         output reg  [2:0] active_dtype_sel,
         output reg        active_mixed_precision,
         output reg        active_gemm_relu_fuse,
         output reg  [2:0] active_mtype_sel,
         output reg        active_waits_for_load,
         output reg        active_waits_for_ewise,
         output reg        active_waits_for_writeback,
         output reg        gemm_issue_pulse,
         output reg        dma_load_issue_pulse,
         output reg        dma_store_issue_pulse,
         output reg        ewise_issue_pulse,
         output reg        barrier_issue_pulse,
         output reg        exec_start_pulse,
         output reg        exec_inflight,
         output reg  [7:0] completed_token,
         output reg        completed_token_valid
       );

localparam [7:0] OPCODE_DMA_STORE = 8'h02;
localparam [7:0] OPCODE_GEMM = 8'h10;
localparam [7:0] OPCODE_EWISE = 8'h11;
localparam [7:0] OPCODE_BARRIER = 8'h20;

wire cmd_issue_fire;
wire exec_complete_event;
wire cmd_is_supported;
wire cmd_completes_immediately;
wire dep_satisfied;
reg  [7:0] active_dep_out;
reg  [255:0] completed_token_bitmap;

assign cmd_is_supported = cmd_is_supported_gemm || cmd_is_supported_dma_load || cmd_is_supported_dma_store || cmd_is_supported_ewise || cmd_is_barrier;
assign dep_satisfied = (cmd_dep_in == 8'h00) || completed_token_bitmap[cmd_dep_in];
assign cmd_ready = (~exec_inflight) && (~exec_start_pulse) && cmd_is_supported && dep_satisfied;
assign cmd_issue_fire = cmd_valid && cmd_ready;
assign exec_complete_event = active_waits_for_writeback ? writeback_done :
                             active_waits_for_load ? load_done :
                             active_waits_for_ewise ? ewise_done :
                             compute_done;
assign cmd_completes_immediately = cmd_is_barrier;

always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        active_opcode           <= 8'h00;
        active_dtype_sel       <= 3'b000;
        active_mixed_precision <= 1'b0;
        active_gemm_relu_fuse <= 1'b0;
        active_mtype_sel       <= 3'b000;
        active_waits_for_load  <= 1'b0;
        active_waits_for_ewise <= 1'b0;
        active_waits_for_writeback <= 1'b0;
        gemm_issue_pulse       <= 1'b0;
        dma_load_issue_pulse   <= 1'b0;
        dma_store_issue_pulse  <= 1'b0;
        ewise_issue_pulse      <= 1'b0;
        barrier_issue_pulse    <= 1'b0;
        exec_start_pulse       <= 1'b0;
        exec_inflight          <= 1'b0;
        active_dep_out         <= 8'h00;
        completed_token        <= 8'h00;
        completed_token_valid  <= 1'b0;
        completed_token_bitmap <= 256'd0;
      end
    else
      begin
        gemm_issue_pulse      <= 1'b0;
        dma_load_issue_pulse  <= 1'b0;
        dma_store_issue_pulse <= 1'b0;
        ewise_issue_pulse     <= 1'b0;
        barrier_issue_pulse   <= 1'b0;
        exec_start_pulse <= 1'b0;

        if (exec_complete_event)
          begin
            exec_inflight <= 1'b0;
            if (active_dep_out != 8'h00)
              begin
                completed_token <= active_dep_out;
                completed_token_valid <= 1'b1;
                completed_token_bitmap[active_dep_out] <= 1'b1;
              end
          end

        if (cmd_issue_fire)
          begin
            active_opcode           <= cmd_opcode;
            active_dep_out          <= cmd_dep_out;
            active_dtype_sel       <= cmd_dtype_sel;
            active_mixed_precision <= cmd_mixed_precision;
            active_gemm_relu_fuse <= cmd_gemm_relu_fuse;
            active_mtype_sel       <= cmd_legacy_mtype_sel;
            active_waits_for_load  <= (cmd_opcode == 8'h01);
            active_waits_for_ewise <= (cmd_opcode == OPCODE_EWISE);
            active_waits_for_writeback <= (cmd_opcode == OPCODE_GEMM) || (cmd_opcode == OPCODE_DMA_STORE);
            gemm_issue_pulse       <= cmd_is_supported_gemm;
            dma_load_issue_pulse   <= cmd_is_supported_dma_load;
            dma_store_issue_pulse  <= cmd_is_supported_dma_store;
            ewise_issue_pulse      <= cmd_is_supported_ewise;
            barrier_issue_pulse    <= cmd_is_barrier;
            exec_start_pulse       <= cmd_is_supported_gemm;
            exec_inflight          <= ~cmd_completes_immediately;
            if (cmd_completes_immediately && (cmd_dep_out != 8'h00))
              begin
                completed_token <= cmd_dep_out;
                completed_token_valid <= 1'b1;
                completed_token_bitmap[cmd_dep_out] <= 1'b1;
              end
          end
      end
  end

endmodule
