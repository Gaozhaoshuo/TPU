# TPU ISA v0.1（最小可用可编程指令集）

## 1. 设计目标

- 用最少指令覆盖：数据搬运、GEMM、逐元素、同步
- 用统一地址/步长/布局字段支持不同 tile 排布
- 支持依赖 token，便于流水与融合

## 2. 指令字格式（128-bit）

采用统一 128-bit 指令头，按 opcode 复用字段。

| Bit | 字段 | 位宽 | 说明 |
|---|---:|---:|---|
| [127:120] | opcode | 8 | 指令类型 |
| [119:116] | dtype | 4 | `INT4/INT8/FP16/FP32` |
| [115] | mixedp | 1 | 混合精度使能 |
| [114:112] | layout | 3 | `ROW/COL/TILED/...` |
| [111:104] | dep_in | 8 | 依赖 token（等待） |
| [103:96] | dep_out | 8 | 完成 token（产生） |
| [95:64] | arg0 | 32 | 按 opcode 解释 |
| [63:32] | arg1 | 32 | 按 opcode 解释 |
| [31:0] | arg2 | 32 | 按 opcode 解释 |

> 备注：v0.1 先用 128-bit 固定宽度，后续若字段不足可用“扩展描述符”指针。

## 3. Opcode 定义

| opcode | 名称 | 功能 |
|---:|---|---|
| `0x01` | DMA_LOAD | DDR -> SRAM |
| `0x02` | DMA_STORE | SRAM -> DDR |
| `0x10` | GEMM | `C = A*B + C` |
| `0x11` | EWISE | 逐元素算子 |
| `0x12` | REDUCE | 归约（预留） |
| `0x20` | BARRIER | 同步屏障 |
| `0x21` | NOP | 空操作 |

## 4. 各指令字段语义

## 4.1 `DMA_LOAD` / `DMA_STORE`

- `arg0[31:0]`：外存地址低 32-bit（高位可用 base 寄存器）
- `arg1[31:24]`：SRAM bank id
- `arg1[23:8]`：SRAM 起始地址
- `arg1[7:0]`：burst_len（单位：beat）
- `arg2[31:16]`：stride（字节）
- `arg2[15:0]`：repeat 次数
- `layout`：搬运后的排布方式（row-major / col-major / tiled）

## 4.2 `GEMM`

- `arg0[31:16]`：M
- `arg0[15:0]`：N
- `arg1[31:16]`：K
- `arg1[15:12]`：tile_m
- `arg1[11:8]`：tile_n
- `arg1[7:4]`：tile_k
- `arg1[3:0]`：flags（bit0: accumulate_C, bit1: relu_fuse, 其余预留）
- `arg2[31:24]`：A bank
- `arg2[23:16]`：B bank
- `arg2[15:8]`：C bank
- `arg2[7:0]`：D bank

## 4.3 `EWISE`

- `arg0[31:24]`：op_type
  - `0x01` ADD
  - `0x02` MUL
  - `0x03` RELU
  - `0x04` CLIP
- `arg0[23]`：use_imm（1 表示 src1 用立即数）
- `arg0[22:16]`：vector_len（元素个数）
- `arg0[15:0]`：保留
- `arg1`：src0 描述（bank + addr，编码方式与 DMA 同风格）
- `arg2`：src1/dst 描述（或立即数索引）

## 4.4 `BARRIER`

- `dep_in` 指示需要等待的 token
- `dep_out` 可用于广播“阶段完成”

## 5. 数据类型编码（dtype）

| 编码 | 类型 |
|---:|---|
| `0x1` | INT4 |
| `0x2` | INT8 |
| `0x3` | FP16 |
| `0x4` | FP32 |

## 6. Layout 编码（layout）

| 编码 | 含义 |
|---:|---|
| `0` | ROW_MAJOR |
| `1` | COL_MAJOR |
| `2` | TILED_ROW_MAJOR |
| `3` | TILED_COL_MAJOR |
| `4-7` | 预留 |

## 7. 执行语义

1. 指令按 FIFO 顺序取指。
2. 每条指令先检查 `dep_in` 是否满足。
3. 执行完成后产生 `dep_out`。
4. 错误（地址越界/非法 dtype/layout）写入状态寄存器并触发中断（可选）。

## 8. v0.1 限制（明确写清）

- 仅支持单核、单 command queue
- 外存地址先用 32-bit + base 寄存器
- REDUCE 只占位，v0.1 可不实现

## 9. v0.2 预留扩展

- 扩展描述符（64-bit ptr）承载更大地址和更复杂 stride
- 多队列（load/compute/store 分离）
- 分支与循环指令（减少 host 下发负担）

