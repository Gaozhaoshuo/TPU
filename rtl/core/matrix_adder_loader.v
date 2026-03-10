module matrix_adder_loader #(
         parameter SYS_ARRAY_SIZE      = 8,         // 每行最大元素数量
         parameter MAX_DATA_SIZE       = 32,        // SRAMC 数据单元数量
         parameter DATA_WIDTH          = 32,        // 数据宽度
         parameter SRAM_ADDR_WIDTH     = 5          // SRAM 地址宽度
       ) (
         // 时钟和复位信号
         input  wire                             clk,                // 时钟信号
         input  wire                             rst_n,              // 异步复位信号，低电平有效

         // 阵列接口
         input  wire                             row_output_valid,   // 阵列结果有效信号
         input  wire [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] row_output,     // 阵列结果数据

         // SRAMC 接口
         output reg  [SRAM_ADDR_WIDTH-1:0]       read_sramc_addr,    // SRAMC 读地址
         input  wire [MAX_DATA_SIZE*DATA_WIDTH-1:0] sram_c_data_out, // SRAMC 数据输出

         // 矩阵加法器数据输入
         output reg                              sys_outcome_valid,  // 系统输出有效信号
         output reg  [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sys_outcome_row,// 系统输出行数据
         output reg                              c_valid,            // C 矩阵有效信号
         output reg  [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] c_row,          // C 矩阵行数据

         // 配置信号
         input  wire [2:0]                       mtype_sel           // 矩阵类型选择信号
       );

// 矩阵类型定义
localparam m16n16k16 = 3'b001;  // m16n16k16 矩阵类型
localparam m32n8k16  = 3'b010;  // m32n8k16 矩阵类型
localparam m8n32k16  = 3'b100;  // m8n32k16 矩阵类型

localparam ROW_COUNT_MAX  = 32; // 最大输出行数
localparam ROWS_PER_GROUP = 8;  // 每组行数

// 内部寄存器
reg [4:0]                           counter;            // 计数器，用于生成读地址
reg                                 sys_outcome_valid_d1, sys_outcome_valid_d2;  // 延迟一级的结果有效信号
reg [SYS_ARRAY_SIZE*DATA_WIDTH-1:0] sys_outcome_d1, sys_outcome_d2; // 延迟一级的结果数据
reg                                 c_valid_d0, c_valid_d1;         // 延迟一级的 C 有效信号
reg [1:0]                           high_low_sel,high_low_sel_d;       // 数据位选信号，用于掩码选择


// 地址和控制逻辑
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        counter         <= 5'd0;
        read_sramc_addr <= {SRAM_ADDR_WIDTH{1'b0}};
        c_valid_d0      <= 1'b0;
        high_low_sel    <= 2'b00;
      end
    else
      begin
        // 计数器逻辑：计数到 ROW_COUNT_MAX 时清零
        if (row_output_valid)
          begin
            if (counter == ROW_COUNT_MAX - 1)
              begin
                counter <= 5'd0;
              end
            else
              begin
                counter <= counter + 1'b1;
              end
            c_valid_d0 <= 1'b1;

            // 根据矩阵类型生成读地址，与 matrix_adder 的写回地址逻辑保持一致
            case (mtype_sel)
              m16n16k16:
                begin
                  if (counter < ROWS_PER_GROUP)
                    begin
                      // A0xB0 读取地址 0~7，数据位 0~255
                      read_sramc_addr <= counter;
                      high_low_sel <= 2'b00;
                    end
                  else if (counter < 2 * ROWS_PER_GROUP)
                    begin
                      // A0xB1 读取地址 0~7，数据位 256~511
                      read_sramc_addr <= counter - ROWS_PER_GROUP;
                      high_low_sel <= 2'b01;
                    end
                  else if (counter < 3 * ROWS_PER_GROUP)
                    begin
                      // A1xB0 读取地址 8~15，数据位 0~255
                      read_sramc_addr <= counter - ROWS_PER_GROUP;
                      high_low_sel <= 2'b00;
                    end
                  else if (counter < 4 * ROWS_PER_GROUP)
                    begin
                      // A1xB1 读取地址 8~15，数据位 256~511
                      read_sramc_addr <= counter - 2 * ROWS_PER_GROUP;
                      high_low_sel <= 2'b01;
                    end
                  else
                    begin
                      read_sramc_addr <= 0;
                      high_low_sel <= 2'b00;
                    end
                end
              m32n8k16:
                begin
                  read_sramc_addr <= counter;
                  high_low_sel <= 2'b00;  // 数据位 0~255
                end
              m8n32k16:
                begin
                  read_sramc_addr <= counter & 5'b00111;  // counter % 8
                  if (counter < ROWS_PER_GROUP)
                    begin
                      // AxB0 读取地址 0~7，数据位 0~255
                      high_low_sel <= 2'b00;
                    end
                  else if (counter < 2 * ROWS_PER_GROUP)
                    begin
                      // AxB1 读取地址 0~7，数据位 256~511
                      high_low_sel <= 2'b01;
                    end
                  else if (counter < 3 * ROWS_PER_GROUP)
                    begin
                      // AxB2 读取地址 0~7，数据位 512~767
                      high_low_sel <= 2'b10;
                    end
                  else if (counter < 4 * ROWS_PER_GROUP)
                    begin
                      // AxB3 读取地址 0~7，数据位 768~1023
                      high_low_sel <= 2'b11;
                    end
                  else
                    begin
                      high_low_sel <= 2'b00;
                    end
                end
              default:
                begin
                  read_sramc_addr <= 'd0;
                  high_low_sel <= 2'b00;
                end
            endcase
          end
        else
          begin
            // 当 row_output_valid 为低时，仅清零部分信号，不清零 counter
            read_sramc_addr <= {SRAM_ADDR_WIDTH{1'b0}};
            c_valid_d0      <= 1'b0;
            high_low_sel    <= 2'b00;
          end
      end
  end
// matrix_adder_loader 模块中

// 流水线寄存器，用于输出时序对齐
always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        sys_outcome_valid_d1 <= 1'b0;
        sys_outcome_valid_d2 <= 1'b0;
        sys_outcome_valid    <= 1'b0;
        sys_outcome_d1       <= {SYS_ARRAY_SIZE*DATA_WIDTH{1'b0}};
        sys_outcome_d2       <= {SYS_ARRAY_SIZE*DATA_WIDTH{1'b0}};
        sys_outcome_row      <= {SYS_ARRAY_SIZE*DATA_WIDTH{1'b0}};
        c_valid_d1 <= 1'b0;
        c_valid    <= 1'b0;
        high_low_sel_d <= 2'b00;
      end
    else
      begin
        // 三级流水线处理阵列输出
        sys_outcome_valid_d1 <= row_output_valid;
        sys_outcome_valid_d2 <= sys_outcome_valid_d1;
        sys_outcome_valid    <= sys_outcome_valid_d2;

        sys_outcome_d1       <= row_output;
        sys_outcome_d2       <= sys_outcome_d1;
        sys_outcome_row      <= sys_outcome_d2;
        // 两级流水线处理 C 有效信号
        c_valid_d1 <= c_valid_d0;
        c_valid    <= c_valid_d1;
        high_low_sel_d <= high_low_sel;
      end
  end

always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
      begin
        c_row <= {SYS_ARRAY_SIZE*DATA_WIDTH{1'b0}};
      end
    else
      begin
        case (high_low_sel_d)
          2'b00:
            c_row <= sram_c_data_out[255:0];           // 选择 0~255 位
          2'b01:
            c_row <= sram_c_data_out[511:256];         // 选择 256~511 位
          2'b10:
            c_row <= sram_c_data_out[767:512];         // 选择 512~767 位
          2'b11:
            c_row <= sram_c_data_out[1023:768];        // 选择 768~1023 位
          default:
            c_row <= {SYS_ARRAY_SIZE*DATA_WIDTH{1'b0}};
        endcase
      end
  end

endmodule
