`timescale 1ns / 1ps

module axi_master #(
         parameter MAX_DATA_SIZE   = 32,    // SRAM data units
         parameter DATA_WIDTH      = 32,    // Data unit width
         parameter AXI_DATA_WIDTH  = 256,   // AXI data width (256 bits)
         parameter DEPTH_SRAM      = 32     // SRAM depth (32 rows)
       )(
         // AXI global signals
         input                           aclk,
         input                           aresetn,

         // AXI Master write address channel
         output reg                      m_awvalid,
         input                           m_awready,
         output reg [$clog2(DEPTH_SRAM)-1:0] m_awaddr,
         output reg [7:0]                m_awlen,   // Burst length (fixed 32 transfers)
         output reg [2:0]                m_awsize,  // Size: 101 = 32 bytes (256 bits)
         output reg [1:0]                m_awburst, // Burst type: 01 = INCR

         // AXI Master write data channel
         output reg                      m_wvalid,
         input                           m_wready,
         output reg [AXI_DATA_WIDTH-1:0] m_wdata,   // 256-bit data
         output reg                      m_wlast,

         // AXI Master write response channel
         input                           m_bvalid,
         output reg                      m_bready,
         input  [1:0]                    m_bresp,

         // SRAM interface
         output reg [$clog2(DEPTH_SRAM)-1:0] read_sramd_addr, // SRAM read address
         input  [MAX_DATA_SIZE*DATA_WIDTH-1:0] sram_d_data_out, // 1024-bit SRAM data

         // Control signals
         input                           send_start,       // Start write request
         input  [$clog2(DEPTH_SRAM)-1:0] axi_target_addr, // AXI target write address
         input  [7:0]                    axi_lens,        // Unused (fixed 32 transfers)
         input  [2:0]                    mtype_sel,       // Matrix type
         output reg                      send_done        // Write completion flag
       );

// Matrix types
localparam
  M16N16K16 = 3'b001,  // 16x16 matrix, 16 rows, lower 512 bits
  M32N8K16  = 3'b010,  // 32x8 matrix, 32 rows, lower 256 bits
  M8N32K16  = 3'b100;  // 8x32 matrix, 8 rows, 1024 bits

// State definitions
localparam [2:0]
           IDLE      = 3'b000,
           SEND_AW   = 3'b001,
           READ_SRAM = 3'b010,
           WAIT_READ_SRAM = 3'b011,
           SEND_W    = 3'b100,
           WAIT_B    = 3'b101;

// Registers
reg [2:0] state, next_state;
reg [7:0] burst_cnt;              // Burst counter (0 to 31)
reg [2:0] split_count;            // Slice counter
reg [MAX_DATA_SIZE*DATA_WIDTH-1:0] data_buffer; // 1024-bit data buffer
reg [2:0] bursts_per_row;         // AXI transfers per SRAM row
reg [5:0] row_count;              // SRAM row counter (0 to 31)
reg [5:0] max_rows;               // Max rows (8, 16, or 32)

// State transition
always @(posedge aclk or negedge aresetn)
  begin
    if (!aresetn)
      state <= IDLE;
    else
      state <= next_state;
  end

// Next state logic
always @(*)
  begin
    next_state = state;
    case (state)
      IDLE:
        if (send_start)
          next_state = SEND_AW;

      SEND_AW:
        if (m_awvalid && m_awready)
          next_state = READ_SRAM;

      READ_SRAM:
        next_state = WAIT_READ_SRAM; // Wait for SRAM data

      WAIT_READ_SRAM:
        next_state = SEND_W;

      SEND_W:
        begin
          if (m_wvalid && m_wready)
            begin
              if (m_wlast && split_count == bursts_per_row - 1)
                next_state = WAIT_B;
              else if (split_count == bursts_per_row - 1)
                next_state = READ_SRAM;  // 完成当前行后，发下一行数据（需采样新的SRAM数据）
            end
        end

      WAIT_B:
        if (m_bvalid && m_bready)
          next_state = IDLE;

      default:
        next_state = IDLE;
    endcase
  end

// 根据矩阵类型在IDLE阶段设定每行传输次数和最大行数
always @(posedge aclk or negedge aresetn)
  begin
    if (!aresetn)
      begin
        bursts_per_row <= 0;
        max_rows       <= 0;
      end
    else if (state == IDLE && send_start)
      begin
        case (mtype_sel)
          M16N16K16:
            begin
              bursts_per_row <= 2;   // 每行2次传输：低256和高256 bits（共512bits）
              max_rows       <= 16;
            end
          M32N8K16:
            begin
              bursts_per_row <= 1;   // 每行仅1次传输：取低256bits
              max_rows       <= 32;
            end
          M8N32K16:
            begin
              bursts_per_row <= 4;   // 每行4次传输：整行1024bits
              max_rows       <= 8;
            end
          default:
            begin
              bursts_per_row <= 1;
              max_rows       <= 16;
            end
        endcase
      end
  end


// Main control logic
always @(posedge aclk or negedge aresetn)
  begin
    if (!aresetn)
      begin
        // Reset AXI signals
        // AXI write address channel
        m_awvalid <= 1'b0;
        m_awaddr  <= 0;
        m_awlen   <= 8'd0;
        m_awsize  <= 3'b101; // 32 bytes (256 bits)
        m_awburst <= 2'b01;  // INCR

        // AXI write data channel
        m_wvalid  <= 1'b0;
        m_wdata   <= 0;
        m_wlast   <= 1'b0;

        // AXI write response channel
        m_bready  <= 1'b0;

        // Reset SRAM signals
        read_sramd_addr <= 0;

        // Reset control signals
        burst_cnt <= 0;
        split_count <= 0;
        data_buffer <= 0;
        send_done <= 1'b0;
        row_count <= 0;
      end
    else
      begin
        // Default values
        m_awvalid <= 1'b0;
        m_bready  <= 1'b0;
        send_done <= 1'b0;

        case (state)
          IDLE:
            begin
              burst_cnt <= 0;
              split_count <= 0;
              row_count <= 0;
              m_wvalid <= 1'b0; // Reset m_wvalid in IDLE
            end

          SEND_AW:
            begin
              m_awvalid <= 1'b1;
              m_awaddr <= axi_target_addr; // AXI write address
              read_sramd_addr <= 0;        // SRAM read starts at 0
              m_awlen <= axi_lens;         // 32 transfers

              if (m_awvalid && m_awready)
                m_awvalid <= 1'b0;
            end

          READ_SRAM:
            begin
              m_wvalid <= 1'b0;
            end

          WAIT_READ_SRAM:
            begin
              data_buffer <= sram_d_data_out; // Store 1024-bit SRAM data
            end

          SEND_W:
            begin
              // Prepare data and set m_wvalid
              if (row_count < max_rows && split_count < bursts_per_row)
                begin
                  m_wvalid <= 1'b1;
                  case (mtype_sel)
                    M16N16K16:
                      begin
                        case (split_count)
                          2'b00:
                            m_wdata <= data_buffer[255:0];
                          2'b01:
                            m_wdata <= data_buffer[511:256];
                          default:
                            m_wdata <= 0;
                        endcase
                      end
                    M32N8K16:
                      begin
                        m_wdata <= (split_count == 2'b00) ? data_buffer[255:0] : 0;
                      end
                    M8N32K16:
                      begin
                        case (split_count)
                          2'b00:
                            m_wdata <= data_buffer[255:0];
                          2'b01:
                            m_wdata <= data_buffer[511:256];
                          2'b10:
                            m_wdata <= data_buffer[767:512];
                          2'b11:
                            m_wdata <= data_buffer[1023:768];
                        endcase
                      end
                    default:
                      m_wdata <= 0; // Invalid matrix type
                  endcase
                end
              else
                begin
                  m_wvalid <= 1'b0;
                  m_wdata <= 0; // Beyond max rows
                end

              // Handle handshake
              if (m_wvalid && m_wready)
                begin
                  m_wvalid <= 1'b0;
                  burst_cnt <= burst_cnt + 1; // Increment per 256-bit transfer
                  split_count <= split_count + 1;
                  // Reset slice counter and advance SRAM row
                  if (split_count == bursts_per_row - 1)
                    begin
                      split_count <= 0;
                      if (row_count < max_rows)
                        begin
                          read_sramd_addr <= read_sramd_addr + 1;
                          row_count <= row_count + 1;
                        end
                    end
                  // Reset on last transfer after handshake
                  if (m_wlast && split_count == bursts_per_row - 1)
                    begin
                      m_wlast <= 1'b0;
                      burst_cnt <= 'd0;
                      read_sramd_addr <= 'd0;
                      row_count <= 'd0;
                    end
                end

              // Set last transfer flag
              if (!m_wlast && burst_cnt == axi_lens)
                m_wlast <= 1'b1;

            end

          WAIT_B:
            begin
              m_bready <= 1'b1;
              if (m_bvalid && m_bready)
                begin
                  m_bready <= 1'b0;
                  send_done <= 1'b1; // Transaction complete
                end
            end

          default:
            begin
              // Do nothing
            end
        endcase
      end
  end

endmodule
