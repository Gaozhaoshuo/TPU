# TPU RTL 工程问题分析与改进计划报告

## 1. 总结

从当前 RTL 的实现来看，这个工程更接近一个“固定形状的 GEMM 加速器”，而不是一个严格意义上的“可编程 TPU”。

现有设计已经具备一条完整的数据通路：

- 主机通过 AXI Slave 把矩阵数据写入 `share_sram`
- 控制器把数据从 `share_sram` 搬运到 SRAM A/B/C
- `8x8` systolic array 完成乘加计算
- `matrix_adder` 完成 `A * B + C`
- 输出结果打包到 SRAM D
- AXI Master 再把结果送出

问题不在于这条链路不能工作，而在于：

- 架构层面的抽象还不够清晰
- 控制、地址、shape、数据布局强耦合
- 扩展性差
- 难以从“理论性能”和“工程 tradeoff”两个角度把项目讲透

如果要把项目打磨成高质量项目，建议把它重新定义为：

“从固定功能 GEMM 加速器，逐步演进为面向 AI 工作负载的可编程 NPU/TPU 核”

## 2. 当前 RTL 的真实架构定位

从 top 级看，当前设计本质上是一条固定处理流水：

1. `axi_slave` 把外部数据写入 `share_sram`
2. `sram_loader` 把 A/B/C 从 `share_sram` 搬到本地 SRAM
3. `systolic_input_loader` 和 `systolic_input` 把数据送入阵列
4. `systolic` 做乘加
5. `matrix_adder_loader` 从 SRAM C 取出对应块
6. `matrix_adder` 做加法
7. `sram_segsel` 负责输出分段写回
8. `axi_master` 负责结果搬出

相关代码：

- [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:132)
- [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:53)
- [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:49)
- [systolic.v](/home/yian/Prj/TPU/rtl/core/systolic.v:1)
- [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:1)
- [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:3)

所以当前工程可以准确表述为：

“面向固定几种矩阵形状、支持多精度乘加的片上矩阵运算加速器”

而不是：

“具备通用可编程执行模型的 TPU”

## 3. 当前工程存在的主要问题

## 3.1 控制面不可编程

当前软件可见的控制只有：

- `mtype_sel`
- `dtype_sel`
- `mixed_precision`

它们通过一个 7-bit APB 写寄存器配置：

- [apb_config_reg.v](/home/yian/Prj/TPU/rtl/core/apb_config_reg.v:5)
- [apb_config_reg.v](/home/yian/Prj/TPU/rtl/core/apb_config_reg.v:27)

这意味着目前没有：

- 指令队列
- 描述符
- loop 参数
- 地址与 stride 的显式编程接口
- 算子依赖管理

结果就是：每增加一种新算子、一个新 shape、或者一种新 tile 方案，都需要修改 RTL 状态机。

这是“固定算子”而不是“可编程架构”的典型特征。

## 3.2 shape 支持被硬编码到多个模块

当前工程只支持三种矩阵类型：

- `m16n16k16`
- `m32n8k16`
- `m8n32k16`

而且这三种模式被重复硬编码在多个模块中：

- 控制器 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:48)
- SRAM 装载 [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:33)
- 输入装载 [systolic_input_loader.v](/home/yian/Prj/TPU/rtl/core/systolic_input_loader.v:16)
- C 矩阵读取 [matrix_adder_loader.v](/home/yian/Prj/TPU/rtl/core/matrix_adder_loader.v:29)
- 写回地址映射 [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:38)
- 输出搬运 [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:45)

这会导致两个问题：

1. 新 shape 很难扩展
2. shape、调度、地址映射无法解耦

## 3.3 控制逻辑和数据布局耦合过重

当前设计默认 `share_sram` 中 A/B/C 的区域固定：

- A 从地址 `0` 开始
- B 从 `OFF` 开始
- C 从 `OFF + OFF` 开始

相关代码：

- [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:46)
- [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:188)
- [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:194)
- [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:200)

这说明当前“数据排布”不是软件可选策略，而是硬件内部假设。

这会直接限制：

- 灵活 tile 调度
- 跨层数据驻留
- 不同算子复用同一片上 buffer

## 3.4 load / compute / store 基本串行，没有重叠

当前主流程大体是：

1. 先把 A/B/C 搬到本地 SRAM
2. 再计算
3. 再写回

同时 `tpu_busy` 会阻塞新的 AXI Slave 写入：

- [axi_slave.v](/home/yian/Prj/TPU/rtl/core/axi_slave.v:167)
- [axi_slave.v](/home/yian/Prj/TPU/rtl/core/axi_slave.v:190)

这意味着当前很难做：

- ping-pong buffer
- prefetch
- load/compute/store overlap

这会使外部带宽延迟无法被计算隐藏。

## 3.5 APB 接口存在集成层面的问题

`tpu_top` 明明暴露了 `pclk` 和 `presetn`，但实例化 APB 寄存器时用的是 `clk` 和 `rst_n`：

- [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:19)
- [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:133)

这会带来两个隐患：

1. 接口语义不清晰
2. 多时钟域设计意图不明确

即使当前系统是单时钟，也不应该把接口定义和实现写成这种“名义分离、实际复用”的形式。

## 3.6 PE/ALU 的实现强绑定 K=16

在 `alu` 中，乘法结果不是传统 systolic PE 那种“每拍一乘一加立即累加”的模式，而是先缓存 16 个乘积，再统一送入累加器：

- [alu.v](/home/yian/Prj/TPU/rtl/core/ALU/alu.v:173)
- [alu.v](/home/yian/Prj/TPU/rtl/core/ALU/alu.v:195)

这实际上把 `K=16` 深度隐含到了 PE 实现里。

这会带来几个问题：

1. 难以支持任意 `K tile`
2. 阵列行为更像“块式乘加器”，不够像标准流式 systolic PE
3. 做性能分析时，阵列利用率和传统 systolic array 不完全一致

## 3.7 完成信号与计数逻辑较脆弱

输出完成判定依赖固定的 `ROW_COUNT_MAX = 32`：

- [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:43)
- [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:147)
- [matrix_adder_loader.v](/home/yian/Prj/TPU/rtl/core/matrix_adder_loader.v:34)

这在当前 3 种固定模式下可以工作，但它不是一个通用完成协议。

如果未来要支持：

- 更大矩阵
- 不同 tile 数
- 融合算子

现有完成逻辑会很快失效。

## 3.8 输出打包方式是局部实现，不是通用布局抽象

当前结果写回采用：

- `high_low_sel` 控制写入 1024-bit 行中的哪个 256-bit 段
- `sram_segsel` 负责段写
- `axi_master` 再根据模式做切片输出

相关代码：

- [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:154)
- [sram_segsel.v](/home/yian/Prj/TPU/rtl/core/sram_segsel.v:1)
- [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:116)

这种方法本身没有错，但它还停留在“为了当前三种模式能跑起来”的层面，还没有升级成“可复用的数据布局机制”。

## 4. 项目里应该明确写进去的架构思考

如果想把项目提升到高质量，应当明确提出一个架构分层模型。

建议把整个加速器分成四层来写：

1. 指令与控制层
2. 数据搬运层
3. 计算核心层
4. 数据布局与复用层

这样做的价值是：

- 可以把项目从“若干 RTL 模块”提升为“完整的加速器体系结构”
- 后续每个改动都能归类到一个架构层面
- 更容易讲清楚 bottleneck 和 tradeoff

## 5. 指令系统应该如何设计

当前工程的核心问题之一，就是没有真正的指令系统。

建议从一个最小可用 ISA 开始，不要一步做得太大。
最小集合可以是：

1. `DMA_LOAD`
2. `DMA_STORE`
3. `GEMM`
4. `EWISE`
5. `BARRIER`

建议语义如下：

- `DMA_LOAD`：从外存把 tile 按指定 layout 搬到片上 SRAM
- `DMA_STORE`：把片上 tile 写回外存
- `GEMM`：执行 `D = A * B + C`
- `EWISE`：执行逐元素操作，如 `ADD`、`MUL`、`RELU`
- `BARRIER`：控制 load/compute/store 之间的依赖

重点不是“指令数量多”，而是“把 shape、地址、stride、layout 从 RTL 硬编码变成软件参数”。

你之前的 ISA 文档已经是个很好的起点：

- [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:9)

这一块完全可以写进架构设计章节，作为“从固定算子走向可编程加速器”的关键演进方向。

## 6. 代入简单 AI 模型分析 bottleneck

为了让项目更像 AI 加速器，而不是单纯矩阵乘 demo，建议代入一个简单模型来分析。

最合适的是一个两层 MLP：

- `Y = GELU(XW1 + b1)W2 + b2`

它可以分解为：

1. `GEMM1`：`X * W1`
2. `EWISE1`：加 bias
3. `EWISE2`：激活函数，如 GELU/ReLU
4. `GEMM2`：中间结果乘 `W2`
5. `EWISE3`：再加 bias

为什么这个例子好：

- 有 GEMM
- 有 element-wise
- 有跨层中间结果
- 可以自然讨论数据驻留、片上复用、融合执行

当前 RTL 只能支持其中 GEMM 核心的一小部分，而不能很好表达：

- GEMM 后直接做逐元素
- 中间结果留在片上给下一层用

所以这个例子很适合用来说明“当前版本与目标 TPU 架构之间的差距”。

## 7. Performance 与 bottleneck 的理论分析

## 7.1 Roofline 分析

对于 GEMM：

- `Ops = 2 * M * N * K`
- `Bytes = bpe * (M*K + K*N + M*N_read + M*N_write)`
- `OI = Ops / Bytes`

其中：

- `bpe` 是每个元素字节数
- `OI` 是算术强度，单位是 `ops/byte`

计算峰值性能：

- `P_compute = 2 * PE_count * f_clk`

在当前设计中：

- 阵列规模是 `8 x 8`
- `PE_count = 64`

如果每个 PE 每拍能做 1 次 MAC，那么：

- `P_compute = 2 * 64 * f_clk`

例如频率取 `200 MHz`：

- `P_compute = 25.6 GOPS`

带宽屋顶：

- `P_bw = OI * BW`

瓶颈判断标准：

- 若 `OI < P_compute / BW`，则是带宽瓶颈
- 若 `OI >= P_compute / BW`，则是计算瓶颈

如果外部带宽取 `6.4 GB/s`，则拐点是：

- `OI* = 25.6 / 6.4 = 4 ops/byte`

也就是说：

- `OI < 4` 时偏带宽瓶颈
- `OI >= 4` 时偏计算瓶颈

这一点已经能和已有脚本、已有报告对应起来：

- [perf_model.py](/home/yian/Prj/TPU/scripts/utils/perf_model.py:1)
- [PERF_BASELINE.md](/home/yian/Prj/TPU/docs/PERF_BASELINE.md:1)

## 7.2 对当前工程意味着什么

对于 FP32 GEMM 且考虑 C 读写：

- 小矩阵如 `16x16x16`，通常 OI 较低，更容易带宽瓶颈
- 中大矩阵如 `64x64x64`、`256x256x256`，OI 较高，更容易计算瓶颈

这说明一个真正的 TPU/NPU 架构必须同时解决两类问题：

1. 计算阵列的利用率
2. 数据搬运和片上复用

如果只堆算力，不改善数据驻留和带宽隐藏，很多工作负载仍然会卡在带宽上。

## 7.3 RTL 内部还存在微观瓶颈

即便 roofline 判断某 workload 是 compute-bound，当前 RTL 也未必能达到理想算力，因为内部还有额外损耗：

1. load/compute/store 串行执行
2. PE 行为绑定 `K=16`
3. 行完成检测依赖整行 ALU 完成状态
4. 输出 packing/unpacking 逻辑增加额外控制开销

所以瓶颈分析应该分两层：

1. 宏观瓶颈：算力瓶颈还是带宽瓶颈
2. 微观瓶颈：RTL 内部调度与利用率损失

这部分完全值得写进设计分析章节。

## 8. MNK 数据如何复用

## 8.1 GEMM 中的基础复用规律

对一个 tile `Mt x Nt x Kt`：

- A 中每个元素会被复用到 `Nt` 个输出
- B 中每个元素会被复用到 `Mt` 个输出
- 输出部分和会沿 K 维持续累加

这正是 systolic array 最核心的价值来源。

## 8.2 当前设计实现了什么复用

当前 RTL 已经具备块内复用：

- A、B 被搬到本地 SRAM A/B
- systolic array 在固定 `K=16` 深度下使用这些 tile
- C 在对应输出块时被读出并相加

所以它实现的是：

- 单次块内复用

但还没有很好实现：

- 跨 tile 复用
- 跨 layer 复用
- 软件可控的驻留策略

## 8.3 层与层之间如何复用

真正的 TPU/NPU 项目中，最值得强调的是“跨层驻留”。

例如：

- `GEMM -> bias add -> activation`
- `GEMM -> residual add`
- `projection -> projection`

理想做法是：

1. 前一层输出保留在片上 SRAM
2. 直接作为下一条指令的输入
3. 不经过 DDR 回写再读回

你完全可以把这部分写成“后续架构演进目标”：

- 通过 bank 化片上 SRAM 实现中间结果驻留
- 通过指令依赖控制执行顺序
- 通过融合减少外存流量

## 9. element-wise 算子应该如何实现

不建议把逐元素算子塞进 systolic array 内部。
更合理的方式是在输出路径旁边增加一个轻量 vector/EWISE 单元。

最小支持集合建议是：

- `ADD`
- `MUL`
- `RELU`
- `CLIP`
- `BIAS_ADD`

后续可扩展：

- `GELU` 近似
- `SIGMOID/TANH` 近似
- `LayerNorm` 所需的 reduce + scale/shift

为什么应该独立成单元：

1. 不污染 GEMM 核心
2. element-wise 本身通常更偏带宽瓶颈，适合单独建模
3. 便于实现 `GEMM + EWISE` 融合

## 10. 数据如何排布

当前设计其实已经隐含了一种排布规则：

- `share_sram` 一行是 `1024-bit`
- A/B/C 在 `share_sram` 中按固定区域放置
- D 在 1024-bit 行内按 `256-bit` 段存放

但这些规则目前都藏在 RTL 实现细节里，没有抽象成“数据布局协议”。

建议把 layout 明确定义成软件和硬件共同遵守的契约。

推荐描述字段：

- base address
- row stride
- column stride
- tile shape
- transpose flag
- bank id
- packing rule

最少支持的 layout 类型：

1. `ROW_MAJOR`
2. `COL_MAJOR`
3. `TILED_ROW_MAJOR`
4. `TILED_COL_MAJOR`

只有把 layout 抽象出来，地址生成和算子调度才能从“硬编码逻辑”升级为“可复用框架”。

## 11. 各种设计策略之间如何做 tradeoff

这是高质量项目最重要的一部分之一。

## 11.1 增大 systolic array

收益：

- 峰值算力提高

代价：

- 面积增加
- 功耗增加
- 时序和布线压力更大

风险：

- 如果带宽和数据复用没有同步提升，阵列利用率会下降

## 11.2 增大片上 SRAM

收益：

- tile 驻留能力更强
- 外存访问减少
- 更容易实现跨层复用

代价：

- 面积上升
- bank 设计与冲突管理更复杂

## 11.3 引入更灵活的 ISA

收益：

- 可编程性增强
- 算子覆盖面更广

代价：

- 控制逻辑更复杂
- 验证难度明显上升

## 11.4 算子融合

收益：

- 减少外存流量
- 降低总体延迟

代价：

- 调度器更复杂
- 正确性和依赖关系更难验证

## 11.5 增加多精度和混合精度

收益：

- 更贴近真实 AI 模型
- 有机会提高性能/功耗比

代价：

- ALU 后端更复杂
- corner case 验证成本很高

## 12. 推荐的改进计划

## 第一阶段：先把架构讲清楚

这一阶段先不急着大改 RTL，而是先把“项目应该怎么解释”建立起来。

建议输出：

1. 当前架构图
2. roofline 分析
3. reuse 分析
4. bottleneck 分类
5. MLP 示例 workload 分析

目标是让项目先从“能跑”变成“讲得清楚”。

## 第二阶段：控制面解耦

建议做：

1. 增加 command queue
2. 用参数化 command 执行代替固定 shape FSM
3. 把地址、stride、layout 从 RTL 中抽出来

目标是让硬件从“固定几种 shape”过渡到“执行一组稳定 primitive”。

## 第三阶段：增强数据流能力

建议做：

1. bank 化片上 SRAM
2. 加 ping-pong buffer
3. 支持 load/compute/store overlap

目标是让带宽不再被完全暴露在串行流程中。

## 第四阶段：加入 element-wise 融合

建议做：

1. 加 vector/EWISE 单元
2. 支持 `GEMM + BIAS + RELU` 这样的最小融合路径
3. 尽量让中间结果不回 DDR

这一阶段会极大增强“像 AI 加速器”的感觉。

## 第五阶段：统一 layout 和调度

建议做：

1. 明确 layout descriptor
2. 支持 row/col/tiled 等多种布局
3. 让 host/runtime 来决定 tile 遍历方式

这一阶段会让架构真正具备长期扩展性。

## 13. 推荐的项目定位表述

最适合写进项目介绍里的说法是：

“本项目第一版实现了一个面向固定矩阵模式的 GEMM 加速器；在此基础上，进一步朝可编程 TPU/NPU 架构演进，重点围绕指令控制、数据布局抽象、片上复用、roofline 性能分析与算子融合展开优化。”

这个表述技术上诚实，同时也保留了架构升级空间。

## 14. 立即应该做的三件事

如果要继续推进，最优先的是：

1. 修正接口层面的基本问题，尤其是 APB 时钟/复位接法
2. 围绕现有 datapath 增加最小 command queue
3. 实现一个 `GEMM + BIAS + RELU` 的最小融合路径

这三件事的收益最高，因为它们能同时提升：

- 架构完整性
- 项目说服力
- 理论分析质量
- 后续可扩展性
