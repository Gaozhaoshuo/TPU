module matrix_adder #(
    parameter SYS_ARRAY_SIZE      = 8,          // Number of elements per row, fixed to 8
    parameter MAX_DATA_SIZE       = 32,        // SRAMC 数据单元数量
    parameter DATA_WIDTH      = 32,         // Data width
    parameter SRAM_ADDR_WIDTH = 5           // SRAM address width
) (
    // Clock and reset
    input  wire                             clk,                // Clock signal
    input  wire                             rst_n,              // Asynchronous reset, active low

    // Systolic array interface
    input  wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sys_outcome_row,    // Systolic array result input row
    input  wire                             sys_outcome_valid,  // Systolic array result valid signal

    // Matrix C interface
    input  wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] c_row,          // Matrix C input row
    input  wire                             c_valid,            // Matrix C valid signal

    // Output interface
    output reg  [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sum_row,            // Output sum matrix row
    output reg                              sum_valid,          // Output sum matrix valid signal
    output reg                              compute_done,       // Computation done signal
    output reg  [SRAM_ADDR_WIDTH-1:0]       write_addr,         // Write-back address
    output reg  [1:0]                       high_low_sel,       // Address high/low selection signal

    // Configuration signals
    input  wire [2:0]                       dtype_sel,          // Data type selection signal
    input  wire                             mixed_precision,    // Mixed precision mode signal
    input  wire [2:0]                       mtype_sel           // Matrix type selection signal
);

// Data type modes
localparam INT4_MODE = 3'b000;
localparam INT8_MODE = 3'b001;
localparam FP16_MODE = 3'b010;
localparam FP32_MODE = 3'b011;

localparam ROW_COUNT_MAX  = 32; // Maximum number of output rows

// Valid signal
wire data_valid;
assign data_valid = sys_outcome_valid && c_valid;

// Sign extension for INT types
localparam INT4_WIDTH = 4;
localparam INT8_WIDTH = 8;
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] c_int4_ext;
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] c_int8_ext;
reg  [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] c_ext;

// Adder generation
reg  [SYS_ARRAY_SIZE-1:0] adder_valid;
wire [SYS_ARRAY_SIZE-1:0] adder_out_valid;
wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sum;

generate
    genvar i;
    for (i = 0; i < SYS_ARRAY_SIZE; i = i + 1) begin : gen_expand_c_row
        assign c_int4_ext[i*DATA_WIDTH +: DATA_WIDTH] = {{(DATA_WIDTH-INT4_WIDTH){c_row[i*DATA_WIDTH + INT4_WIDTH - 1]}}, c_row[i*DATA_WIDTH +: INT4_WIDTH]};
        assign c_int8_ext[i*DATA_WIDTH +: DATA_WIDTH] = {{(DATA_WIDTH-INT8_WIDTH){c_row[i*DATA_WIDTH + INT8_WIDTH - 1]}}, c_row[i*DATA_WIDTH +: INT8_WIDTH]};
    end
endgenerate

reg [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] c_ext_w;
always @(*) begin
    c_ext_w = c_row;
    case(dtype_sel)
            INT4_MODE: if(~mixed_precision) c_ext_w = c_int4_ext ;
            INT8_MODE: if(~mixed_precision) c_ext_w = c_int8_ext ;
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        c_ext <= 0;
    else begin
        c_ext <= c_ext_w;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        adder_valid <= 0;
    else
        adder_valid <= {(SYS_ARRAY_SIZE){data_valid}};
end

reg [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sys_outcome_row_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        sys_outcome_row_d <= 0;
    else
        sys_outcome_row_d <= sys_outcome_row; // 延迟一个周期
end

generate
    genvar j;
    for (j = 0; j < SYS_ARRAY_SIZE; j = j + 1) begin : gen_row_adder
        adder adder_inst (
            .clk        (clk),
            .rst_n      (rst_n),
            .a          (sys_outcome_row_d[j*DATA_WIDTH +: DATA_WIDTH]),
            .b          (c_ext[j*DATA_WIDTH +: DATA_WIDTH]),
            .valid      (adder_valid[j]),
            .dtype_sel  (dtype_sel),
            .mixedp_sel (mixed_precision),
            .out_valid  (adder_out_valid[j]),
            .sum        (sum[j*DATA_WIDTH +: DATA_WIDTH])
        );
    end
endgenerate

// Internal registers
reg [SRAM_ADDR_WIDTH-1:0] row_counter;  // Row processing counter
reg                       sum_valid_d;  // Delayed sum_valid for detecting falling edge
wire [SRAM_ADDR_WIDTH-1:0] mapped_write_addr;
wire [1:0]                 mapped_high_low_sel;
wire [2:0]                 unused_bursts_per_row;
wire [5:0]                 unused_max_rows;

legacy_shape_mapper #(
    .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
    .ROW_INDEX_WIDTH(SRAM_ADDR_WIDTH + 1)
) u_legacy_shape_mapper (
    .mtype_sel(mtype_sel),
    .logical_row_idx({1'b0, row_counter}),
    .mapped_addr(mapped_write_addr),
    .seg_sel(mapped_high_low_sel),
    .bursts_per_row(unused_bursts_per_row),
    .max_rows(unused_max_rows)
);

// Output logic and write-back address generation
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sum_row       <= {SYS_ARRAY_SIZE*DATA_WIDTH{1'b0}};
        sum_valid     <= 1'b0;
        row_counter   <= {SRAM_ADDR_WIDTH{1'b0}};
        compute_done  <= 1'b0;
        sum_valid_d   <= 1'b0;
        write_addr    <= {SRAM_ADDR_WIDTH{1'b0}};
        high_low_sel  <= 2'b00;
    end else begin
        // Update outputs
        sum_row     <= sum;
        sum_valid   <= |adder_out_valid;
        sum_valid_d <= sum_valid;

        // Update row counter
        if (|adder_out_valid) begin
            if (row_counter < ROW_COUNT_MAX-1) begin
                row_counter <= row_counter + 1'b1;
            end
        end else if (compute_done) begin
            row_counter <= {SRAM_ADDR_WIDTH{1'b0}};
        end

        // compute_done logic: Set when sum_valid falls and maximum row count is reached
        if (sum_valid_d && !sum_valid && (row_counter == ROW_COUNT_MAX-1)) begin
            compute_done <= 1'b1;
        end else begin
            compute_done <= 1'b0;
        end

        // Shared legacy mapper keeps the SRAM-D packing rule in one place.
        write_addr   <= mapped_write_addr;
        high_low_sel <= mapped_high_low_sel;
    end
end

endmodule
