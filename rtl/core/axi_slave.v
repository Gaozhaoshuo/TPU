module axi_slave #(
    parameter MAX_DATA_SIZE    = 32,    // SRAM 数据单元数
    parameter DATA_WIDTH       = 32,    // 每个数据单元宽度
    parameter AXI_DATA_WIDTH   = 256,   // AXI 总线数据宽度
    parameter DEPTH_SHARE_SRAM = 96,    // SRAM 深度
    parameter BURST_PER_WRITE  = (MAX_DATA_SIZE * DATA_WIDTH) / AXI_DATA_WIDTH  // 1024/256=4
)(
    //==============================================
    // 全局控制信号
    //==============================================
    input                           aclk,
    input                           aresetn,

    //==============================================
    // AXI Slave 写地址通道
    //==============================================
    input                           s_awvalid,
    output reg                      s_awready,
    input  [$clog2(DEPTH_SHARE_SRAM)-1:0] s_awaddr,
    input  [7:0]                    s_awlen,   // 突发长度 = s_awlen + 1
    input  [1:0]                    s_awburst,

    //==============================================
    // AXI Slave 写数据通道
    //==============================================
    input                           s_wvalid,
    output reg                      s_wready,
    input  [AXI_DATA_WIDTH-1:0]     s_wdata,
    input                           s_wlast,

    //==============================================
    // AXI Slave 写响应通道
    //==============================================
    output reg                      s_bvalid,
    input                           s_bready,
    output reg [1:0]                s_bresp,

    //==============================================
    // TPU 控制信号
    //==============================================
    input                           tpu_busy,  // TPU 忙信号

    //==============================================
    // SHARE_SRAM 接口
    //==============================================
    output reg                      share_sram_wen,    // SRAM 写使能
    output reg [MAX_DATA_SIZE*DATA_WIDTH-1:0] share_sram_wdata,  // 写数据(1024位)
    output reg [$clog2(DEPTH_SHARE_SRAM)-1:0] load_share_sram_addr  // SRAM地址
);

//==============================================================================
// 状态定义
//==============================================================================
localparam [2:0]
    IDLE        = 3'b000,
    ADDR_PHASE  = 3'b001,
    DATA_PHASE  = 3'b010,
    RESP_PHASE  = 3'b011,
    ERR_PHASE   = 3'b100;

//==============================================================================
// 寄存器定义
//==============================================================================
reg [2:0] state, next_state;
reg [7:0] burst_cnt;                 // 突发传输计数器
reg [$clog2(DEPTH_SHARE_SRAM)-1:0] base_addr;  // 基础地址
reg [1:0] write_cycle_count;         // 数据拼接计数器(0~3)
reg addr_error;                      // 地址错误标志

//==============================================================================
// 状态转移逻辑
//==============================================================================
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

//==============================================================================
// 下一状态组合逻辑
//==============================================================================
always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (s_awvalid) begin
                next_state = ADDR_PHASE;
            end
        end

        ADDR_PHASE: begin
            if (s_awvalid && s_awready) begin
                // 检查地址越界或突发长度是否为BURST_PER_WRITE的倍数
                if (addr_error || ((s_awlen + 1) % BURST_PER_WRITE != 0)) begin
                    next_state = ERR_PHASE;
                end else begin
                    next_state = DATA_PHASE;
                end
            end
        end

        DATA_PHASE: begin
            if (s_wvalid && s_wready) begin
                if ((burst_cnt == s_awlen) ^ s_wlast) begin
                    next_state = ERR_PHASE;
                end else if (s_wlast) begin
                    next_state = RESP_PHASE;
                end
            end
        end

        RESP_PHASE, ERR_PHASE: begin
            if (s_bvalid && s_bready) begin
                next_state = IDLE;
            end
        end

        default: begin
            next_state = IDLE;
        end
    endcase
end

//==============================================================================
// 主控制逻辑
//==============================================================================
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        // AXI控制信号复位
        s_awready <= 1'b0;
        s_wready  <= 1'b0;
        s_bvalid  <= 1'b0;
        s_bresp   <= 2'b00;
        
        // SRAM接口复位
        share_sram_wen   <= 1'b0;
        share_sram_wdata <= {MAX_DATA_SIZE*DATA_WIDTH{1'b0}};
        load_share_sram_addr <= {$clog2(DEPTH_SHARE_SRAM){1'b0}};
        
        // 计数器复位
        burst_cnt <= 8'd0;
        write_cycle_count <= 2'b00;
        base_addr <= {$clog2(DEPTH_SHARE_SRAM){1'b0}};
        addr_error <= 1'b0;
    end else begin
        // 默认值避免锁存器
        s_awready <= 1'b0;
        s_wready  <= 1'b0;
        share_sram_wen <= 1'b0;

        case (state)
            //==========================================
            // IDLE状态
            //==========================================
            IDLE: begin
                burst_cnt <= 8'd0;
                write_cycle_count <= 2'b00;
                addr_error <= 1'b0;
                share_sram_wdata <= {MAX_DATA_SIZE*DATA_WIDTH{1'b0}};
            end

            //==========================================
            // ADDR_PHASE状态
            //==========================================
            ADDR_PHASE: begin
                if (tpu_busy) begin
                    // TPU忙，禁止接收地址
                    s_awready <= 1'b0;
                end else begin
                    // TPU空闲，准备接收地址
                    s_awready <= 1'b1;
                end

                if (s_awvalid && s_awready) begin
                    base_addr <= s_awaddr;
                    // 检查地址是否越界
                    if (s_awaddr >= DEPTH_SHARE_SRAM || 
                        (s_awburst == 2'b01 &&   
                         s_awaddr + ((s_awlen + 1) / BURST_PER_WRITE) > DEPTH_SHARE_SRAM)) begin
                        addr_error <= 1'b1;
                    end
                end
            end

            //==========================================
            // DATA_PHASE状态
            //==========================================
            DATA_PHASE: begin
                if (tpu_busy) begin
                    // TPU忙，禁止接收数据
                    s_wready <= 1'b0;
                end else begin
                    // TPU空闲，准备接收数据
                    s_wready <= 1'b1;
                end

                if (s_wvalid && s_wready) begin
                    // 数据拼接：将256位AXI数据累积到share_sram_wdata
                    case (write_cycle_count)
                        2'b00: share_sram_wdata[255:0]   <= s_wdata;   // 第1次传输
                        2'b01: share_sram_wdata[511:256] <= s_wdata;   // 第2次传输
                        2'b10: share_sram_wdata[767:512] <= s_wdata;   // 第3次传输
                        2'b11: begin
                            share_sram_wdata[1023:768] <= s_wdata;     // 第4次传输
                            share_sram_wen <= 1'b1;
                            load_share_sram_addr <= base_addr;
                            
                            if (s_awburst == 2'b01) begin
                                // INCR突发：每1024位(4次AXI传输)递增SRAM地址
                                base_addr <= base_addr + 1;
                            end
                        end
                    endcase
                    write_cycle_count <= write_cycle_count + 2'b01;

                    // 重置计数器
                    if (write_cycle_count == 2'b11) begin
                        write_cycle_count <= 2'b00;
                    end

                    // 更新突发计数器
                    burst_cnt <= burst_cnt + 8'd1;
                    if (s_wlast) begin
                        burst_cnt <= 8'd0;
                    end
                end
            end

            //==========================================
            // RESP_PHASE状态
            //==========================================
            RESP_PHASE: begin
                s_bvalid <= 1'b1;
                s_bresp  <= 2'b00; // OKAY响应
            end

            //==========================================
            // ERR_PHASE状态
            //==========================================
            ERR_PHASE: begin
                s_bvalid <= 1'b1;
                s_bresp  <= 2'b10; // SLVERR响应
            end

            default: begin
                s_bvalid <= 1'b0;
                s_bresp  <= 2'b00;
            end
        endcase
    end
end

endmodule