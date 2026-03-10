# TPU 项目打磨路线图（用于进度对照）

> 目标：将当前“固定形状 GEMM 算子核”演进为“可编程 NPU 核”，并形成可复现的性能与瓶颈理论分析。

## 0. 当前状态（Baseline）

- 控制面：配置寄存器 + 固定状态机（非指令流）
- 能力面：以 GEMM 为中心，shape 与流程较固定
- 性能面：尚无统一 roofline/cycle 理论模型
- 数据面：已有 SRAM 分层，但缺少统一 layout/stride 规范

## 1. 阶段目标与里程碑

## Phase A：建模与定义（先把“理论”讲清楚）

- [ ] A1. 建立统一术语与符号（M/N/K、tile、bytes、ops、OI）
- [x] A2. 固化 ISA v0.1（最小可用指令集）
- [x] A3. 完成性能模型脚本（roofline 点 + 瓶颈判定）
- [x] A4. 输出 3 组基准 case（小/中/大）做模型演示

**验收标准**
- 任意给定 M/N/K + 带宽 + 频率，能自动判断 compute-bound / bandwidth-bound
- 指令字段、语义、依赖关系可被 host 程序生成

## Phase B：控制面升级（从“硬编码流程”到“可编程”）

- [ ] B1. 增加 command queue（指令 FIFO）
- [ ] B2. 微码/控制器支持 `DMA_LOAD/GEMM/EWISE/DMA_STORE/BARRIER`
- [ ] B3. 完成最小 runtime（下发指令、轮询完成、中断可选）

**验收标准**
- 同一硬件可运行至少 2 种不同 layer 序列（无需改 RTL 状态机）

## Phase C：数据流与复用优化

- [ ] C1. 定义统一数据布局：row/col/tiled + stride + transpose flag
- [ ] C2. 设计 A/B/C 在 SRAM 的 tile 映射与 bank 策略
- [ ] C3. 引入 ping-pong buffering，重叠搬运与计算
- [ ] C4. 明确跨层驻留策略（layer fusion 前提）

**验收标准**
- 数据搬运占比下降，DMA 与 compute 重叠率可测量

## Phase D：算子扩展与融合

- [ ] D1. 增加 EWISE 单元（relu/add/mul/clip，支持 broadcast）
- [ ] D2. 支持 `GEMM + EWISE` 融合执行
- [ ] D3. 视资源加入 REDUCE（为 layernorm/softmax 铺路）

**验收标准**
- 至少 1 条融合路径不落 DDR（仅 SRAM 内链路）

## Phase E：验证与质量收敛

- [ ] E1. 建立分层验证：unit / integration / end2end
- [ ] E2. 建立性能回归（固定 case 自动生成 perf 报告）
- [ ] E3. 文档化 tradeoff：面积/时序/带宽/编程复杂度

**验收标准**
- 每次改动可回归功能 + 性能，不靠人工判断

## 2. 关键理论分析模板（后续报告可直接复用）

## 2.1 Roofline 核心

- 峰值算力：`P_compute = 2 * PE_count * f_clk`
- 峰值带宽：`P_bw = BW_bytes_per_s`
- 算术强度：`OI = Ops / Bytes`
- 屋顶性能：`Perf <= min(P_compute, OI * P_bw)`

## 2.2 GEMM（C=A*B+C）

- `Ops = 2*M*N*K`
- `Bytes = bpe*(M*K + K*N + M*N) + C_rw_bytes`
- 若读写 C：`C_rw_bytes = bpe*(M*N + M*N)`
- `OI = Ops / Bytes`

## 2.3 瓶颈判定

- `OI < P_compute/P_bw` => 带宽瓶颈
- `OI >= P_compute/P_bw` => 计算瓶颈

## 3. 设计 tradeoff 对照表（后续逐项填数据）

| 设计策略 | 收益 | 成本 | 风险 |
|---|---|---|---|
| 增大阵列规模 | 峰值算力上升 | 面积/功耗/时序压力 | 更易被带宽卡住 |
| 增大片上 SRAM | 提升复用、降 DDR 流量 | 面积上升 | 布局布线复杂 |
| 引入指令流 | 可编程性和扩展性提升 | 控制复杂、验证成本升高 | 调度错误风险 |
| 融合算子 | 降低外存读写 | 控制与依赖更复杂 | 死锁/一致性问题 |
| 支持多精度 | 适配更多模型 | 数据通路复杂 | 精度与验证成本 |

## 4. 推荐执行顺序（强约束）

1. 先完成 `ISA v0.1 + perf_model.py`（本次已交付）
2. 再做 command queue + 最小 5 指令执行器
3. 再做 data layout 统一与 ping-pong
4. 最后做融合和高级算子
