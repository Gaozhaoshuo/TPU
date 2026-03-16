# TPU 逐步改进执行计划

## 1. 文档用途

这份文档作为后续推进 TPU 改造的主执行看板使用。

使用原则：

1. 每完成一个阶段或一个子任务，就在对应板块补充“实际改动”
2. 每个阶段都记录“完成情况、当前进展、出现的问题、下一步动作”
3. 不只记录计划，还记录真实执行结果

后续建议优先维护这份文档，而不是把进展分散写在多个零散笔记里。

## 2. 当前总体目标

将当前“固定形状 GEMM 加速器”逐步演进为“可编程、可分析、具备片上复用和基础融合能力的 TPU/NPU 核”。

最终希望达到：

- 架构定义清晰
- ISA 清晰
- 性能模型清晰
- 瓶颈可解释
- 数据复用策略清晰
- 具备逐步扩展 element-wise 和 layer fusion 的能力

## 3. 当前基线结论

当前工程的基线判断：

- 当前更接近固定功能 GEMM 加速器，不是通用 TPU
- shape、地址、控制、输出打包在多个模块中硬编码
- 目前缺少指令流、描述符、layout 抽象、跨层复用能力
- 当前性能分析基础已经具备，可以继续往架构演进

参考文档：

- [TPU_IMPROVEMENT_REPORT.md](/home/yian/Prj/TPU/docs/TPU_IMPROVEMENT_REPORT.md:1)
- [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:1)
- [PROJECT_ROADMAP.md](/home/yian/Prj/TPU/docs/PROJECT_ROADMAP.md:1)
- [PERF_BASELINE.md](/home/yian/Prj/TPU/docs/PERF_BASELINE.md:1)

## 4. 阶段划分总览

| 阶段 | 名称 | 目标 | 当前状态 |
|---|---|---|---|
| P0 | 基线梳理 | 把当前工程“看清楚、讲清楚” | 已完成 |
| P1 | 接口与工程清理 | 修基础集成问题，补最小工程规范 | 已完成 |
| P2 | 控制面升级 | 引入 command queue / parameterized control | 进行中 |
| P3 | 数据流与复用 | layout、bank、ping-pong、跨层驻留 | 未开始 |
| P4 | 算子扩展 | EWISE 与最小融合路径 | 未开始 |
| P5 | 验证与收敛 | 功能、性能、tradeoff 闭环 | 未开始 |

## 5. 阶段详情

## P0：基线梳理

阶段目标：

- 读清 RTL
- 明确当前架构定位
- 建立 ISA 初稿
- 建立性能模型与 baseline 报告

计划任务：

- [x] P0.1 读取并分析 `rtl/core` 关键模块
- [x] P0.2 输出工程问题分析报告
- [x] P0.3 输出 ISA v0.1 文档
- [x] P0.4 输出 perf model
- [x] P0.5 输出 small / medium / large baseline 报告

实际改动：

- 新增 [TPU_IMPROVEMENT_REPORT.md](/home/yian/Prj/TPU/docs/TPU_IMPROVEMENT_REPORT.md:1)
- 新增 [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:1)
- 新增 [perf_model.py](/home/yian/Prj/TPU/scripts/utils/perf_model.py:1)
- 新增 [perf_batch.py](/home/yian/Prj/TPU/scripts/utils/perf_batch.py:1)
- 新增 [PERF_BASELINE.md](/home/yian/Prj/TPU/docs/PERF_BASELINE.md:1)

完成情况：

- 已完成

当前进展说明：

- 当前已经具备“理论分析”和“架构问题识别”的基础
- 现阶段最大的价值不是继续堆文档，而是开始落第一批可验证的 RTL 改造

发现的问题：

- 当前工程没有统一的执行计划看板
- 路线图有阶段目标，但不够适合持续记录真实改动

下一步动作：

- 进入 P1，优先修基础工程和接口问题

## P1：接口与工程清理

阶段目标：

- 修复当前最明显的基础集成问题
- 让工程从“能跑”提升到“可信、可维护”

计划任务：

- [x] P1.1 修正 APB 接口实际接线，统一 `pclk/presetn`
- [x] P1.2 检查 top 层接口命名与行为一致性
- [x] P1.3 梳理输出路径和状态完成信号
- [x] P1.4 补最小 README/模块关系说明

预期交付物：

- 接口修复版 RTL
- 变更说明文档
- 基础仿真回归结果

验收标准：

- APB 接口语义一致
- top 级无明显“名义接口”和“实际实现”不一致问题
- 原有 testbench 至少能完成一轮回归

实际改动：

- 修正 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:133) 中 `apb_config_reg` 实例接线
- `pclk` 从原来的 `clk` 改为真实 APB 口 `pclk`
- `presetn` 从原来的 `rst_n` 改为真实 APB 口 `presetn`
- 修正 [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:17) 中端口注释，使 `m_awlen` 和 `axi_lens` 的语义与实际实现一致
- 修正 [tb.sv](/home/yian/Prj/TPU/dv/uvm/Test/tb.sv:31) 中 AXI Master 接口注释，明确 `AWSIZE=3'b101` 对应 256-bit 传输
- 在 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:171) 补充当前固定 `axi_target_addr/axi_lens` 的实现说明
- 明确 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:66) 中 `tpu_done/send_done` 为单周期脉冲信号
- 明确 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:45) 中 `tpu_done` 的触发语义
- 明确 [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:37) 中 `send_start/send_done` 的脉冲语义
- 修正 [tb.sv](/home/yian/Prj/TPU/dv/uvm/Test/tb.sv:46) 中 UVM 顶层接口注释，避免把完成信号误解为 level 信号
- 新增 [README.md](/home/yian/Prj/TPU/README.md:1)，补充工程结构、关键模块、当前执行流、当前限制和文档入口

完成情况：

- 已完成 `P1.1`
- 已完成 `P1.2`
- 已完成 `P1.3`
- 已完成 `P1.4`

当前进展说明：

- 已完成接口语义修正，当前 `tpu_top` 不再出现“暴露 APB 独立时钟/复位端口，但内部实际忽略”的问题
- 当前 simple testbench 与 UVM 中 `pclk/PCLK` 和 `clk` 频率一致，因此本次改动不会引入新的行为差异
- 这一步只修正了接口接法，没有处理真正异步 APB 场景下的跨时钟域同步问题
- 已完成一轮 top 层接口一致性检查，当前发现的主要不一致点集中在“注释/命名表述”和“固定参数未显式说明”两类
- 当前 `axi_master` 的 `axi_lens` 实际被使用，但旧注释写成了 unused；UVM 接口中 `AWSIZE` 旧注释也与真实传输宽度不一致，这两处已修正
- 已梳理输出路径完成信号语义：`tpu_done` 是计算完成脉冲，`send_done` 是写回完成脉冲，`tpu_done` 当前直接驱动 `axi_master.send_start`
- 当前输出路径仍然是严格串行的“compute done -> start write-back -> send done”，这一点已经确认并记录
- 已补齐最小工程入口文档，当前新协作者进入工程时，不需要先读完整 RTL 才能找到入口

可能问题：

- 如果未来 `pclk` 与 `clk` 变为异步时钟，`dtype_sel/mtype_sel/mixed_precision` 从 APB 域进入计算域时需要补同步或 shadow register 机制
- 当前 APB 配置寄存器仍然直接输出到计算路径，这在真实多时钟系统里不够稳健
- 当前 `tpu_top` 仍将 `axi_target_addr` 和 `axi_lens` 固定绑死为常量，接口虽然自洽，但仍不具备真正可编程性
- `tpu_done` 直接作为 `axi_master` 的 `send_start`，接口命名上可理解，但从体系结构上仍然体现出“计算完成后立即串行回传”的固定流程
- `tpu_done/send_done` 目前是 pulse，而不是 sticky status；如果后续软件或更复杂验证环境改成轮询寄存器模型，需要补状态保持机制
- README 当前是“工程入口版”，还不是完整用户手册；等控制面和运行流更稳定后还需要补充运行步骤与验证说明

下一步动作：

- P1 阶段的最小目标已完成，可以转入 P2
- 先整理 command queue 接口草案，开始 `P2.1`

## P2：控制面升级

阶段目标：

- 从固定 FSM 流程，过渡到最小可编程控制框架

计划任务：

- [x] P2.1 设计 command queue 接口
- [x] P2.2 增加 command FIFO
- [x] P2.3 抽象最小指令执行器：`DMA_LOAD/GEMM/EWISE/DMA_STORE/BARRIER`
- [ ] P2.4 把固定 shape 状态机逐步替换为参数化控制

预期交付物：

- `command_queue` 模块
- 指令译码与调度原型
- 最小运行时流程说明

验收标准：

- 同一套 RTL 不改状态机即可执行至少两组不同 command 序列

实际改动：

- 新增 [COMMAND_QUEUE_SPEC.md](/home/yian/Prj/TPU/docs/COMMAND_QUEUE_SPEC.md:1)，明确 `command_queue` 的定位、ready/valid 握手、状态信号和参数约束
- 新增 [command_queue.v](/home/yian/Prj/TPU/rtl/core/command_queue.v:1)，实现最小单队列 FIFO 骨架
- 当前 `command_queue` 采用 `128-bit` 命令宽度，与 [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:1) 保持一致
- 当前 `command_queue` 提供 `push_valid/push_ready/push_data` 与 `pop_valid/pop_ready/pop_data` 接口，并暴露 `empty/full/level`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:67)，在 top 层增加最小 command bridge，把 `tpu_start + APB 配置` 打包成内部 `GEMM` 命令送入 `command_queue`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:153)，由 `command_queue` 队首命令而不是原始 `tpu_start` 直接驱动 `systolic_controller`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:170)，增加活动命令锁存寄存器 `active_mtype_sel/active_dtype_sel/active_mixed_precision`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:207)，使 `axi_master` 也读取活动命令的 `mtype_sel`，避免计算中途 APB 配置变化导致写回路径语义漂移
- 新增 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)，抽出 `opcode/dtype/layout/M/N/K` 等命令字段解析
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:233)，用 `command_decoder` 替代 top 内联 decode 逻辑
- 新增 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，抽出最小执行发射控制、活动命令锁存和启动脉冲生成
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:227)，由 `execution_controller` 统一决定 `cmd_ready` 与 `cmd_start_pulse`
- 新增 [legacy_shape_codec.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_codec.v:1)，集中管理 legacy `mtype_sel <-> M/N/K` 映射
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:164)，命令打包不再手写三组固定 `M/N/K` 常量，而是通过 `legacy_shape_codec` 生成
- 修改 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)，解码时通过 `legacy_shape_codec` 统一识别 legacy 支持的 `M/N/K`
- 新增 [rtl_core.f](/home/yian/Prj/TPU/tb/filelist/rtl_core.f:1)，固化核心 RTL 的 `vcs` filelist
- 新增 [run_vcs_tb.sh](/home/yian/Prj/TPU/scripts/run_vcs_tb.sh:1)，支持按 testbench 名称直接执行 `vcs` compile + sim
- 修改 [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)、[tb_tpu_top_m32n8k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m32n8k16.sv:1)、[tb_tpu_top_m8n32k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m8n32k16.sv:1)，把 `.mem` 数据路径从历史 Windows 绝对路径改为仓库内相对路径
- 修改 [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1)，修正 `m_wlast` 的最后一拍判定时序，并避免最后一行后继续推进 `read_sramd_addr`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)，增加 `sram_d_readback_active`，在 AXI write-back 阶段把 SRAM D 的所有权明确切给读侧，阻断残余写使能对地址 mux 的污染
- 修改 [tb_tpu_top_m32n8k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m32n8k16.sv:1)，加入 `DEBUG_M32_TRACE` 调试钩子，用于在 `vcs` 下定位 `sram_d` 写入/读出地址冲突
- 新增 [TPU_TEACHING_GUIDE.md](/home/yian/Prj/TPU/docs/TPU_TEACHING_GUIDE.md:1)，作为后续理解升级后工程的主教学文档
- 新增 [legacy_shape_mapper.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_mapper.v:1)，集中管理 legacy 输出矩阵在 `matrix_adder/matrix_adder_loader` 路径中的“逻辑行 -> SRAM 地址/段选择”映射，以及每种 shape 的 `bursts_per_row/max_rows`
- 修改 [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:1)，写回地址与 `high_low_sel` 改为由 `legacy_shape_mapper` 统一生成
- 修改 [matrix_adder_loader.v](/home/yian/Prj/TPU/rtl/core/matrix_adder_loader.v:1)，读取 C 矩阵时的 `read_sramc_addr/high_low_sel` 改为由 `legacy_shape_mapper` 统一生成
- 修改 [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1)，仅复用 `legacy_shape_mapper` 的 `bursts_per_row/max_rows` 配置，保留 AXI write-back 对 SRAM-D 物理行的线性扫描语义
- 修改 [tb/filelist/rtl_core.f](/home/yian/Prj/TPU/tb/filelist/rtl_core.f:1)，把 `legacy_shape_mapper.v` 纳入 `vcs` filelist
- 修改 [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:1)，不再本地维护 `m16n16k16/m32n8k16/m8n32k16` 的 `M/N` 常量表，改为直接复用 [legacy_shape_codec.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_codec.v:1) 输出的 `M/N/K`
- 新增 [legacy_tile_phase_mapper.v](/home/yian/Prj/TPU/rtl/core/legacy_tile_phase_mapper.v:1)，集中管理 legacy 输入 phase 对应的 `A/B` block 选择
- 修改 [systolic_input_loader.v](/home/yian/Prj/TPU/rtl/core/systolic_input_loader.v:1)，把原来的 12 个 shape-specific load state 收敛成 4 个通用 `LOAD_PHASE0..3` 状态，并通过 `legacy_tile_phase_mapper` 生成 `SRAMA/SRAMB` block 偏移
- 修改 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)，把三个 `load_systolic_input_start_*` 总线收敛成一个通用 `load_systolic_input_start[3:0]`
- 修改 [tb/filelist/rtl_core.f](/home/yian/Prj/TPU/tb/filelist/rtl_core.f:1)，把 `legacy_tile_phase_mapper.v` 纳入 `vcs` filelist
- 修改 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)，把三套 `MAIN_M16/M32/M8 + SUB_START_*/SUB_MUL_*` 展开式 compute 子状态机收敛成通用 `MAIN_COMPUTE + SUB_START_PHASE/SUB_MUL_PHASE + phase_idx`
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，增加 `exec_inflight`，把“命令完成”的释放条件从单纯 `tpu_busy` 改成整条命令路径的 `send_done`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:257)，使 `execution_controller` 以 `send_done` 作为当前单命令 GEMM 路径的完成确认
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，显式锁存 `active_opcode` 和 `active_waits_for_writeback`，把 `compute_done` 与 `writeback_done` 两类 completion source 区分开
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:257)，把 `cmd_opcode/tpu_done/send_done` 接入 `execution_controller`，形成按 opcode 选择完成源的控制器骨架
- 修改 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)，补齐 `is_dma_load/is_dma_store/is_ewise/is_barrier` 这类 opcode 分类信号
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，新增 `gemm_issue_pulse/dma_load_issue_pulse/dma_store_issue_pulse/ewise_issue_pulse/barrier_issue_pulse`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:240)，把 decoder 的 opcode 分类结果和 controller 的 opcode-specific issue 接口接通
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，让 `BARRIER` 成为第一个真实可接受的非 GEMM opcode：可被 `cmd_ready` 接受、发出 `barrier_issue_pulse`、不启动 GEMM 数据路径、且不进入 in-flight 执行状态
- 新增 [tb_execution_controller_barrier.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_barrier.sv:1)，用独立单元 testbench 验证 `BARRIER` 的控制面语义
- 修改 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)，增加 `is_supported_dma_store`
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，让 `DMA_STORE` 成为第二个真实可接受 opcode：可被接收、发出 `dma_store_issue_pulse`、进入 in-flight，并以 `writeback_done` 作为 completion source
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:186)，让 `dma_store_issue_pulse` 直接复用现有 `axi_master` 写回启动路径，并在写回期间拉起 `sram_d_readback_active`
- 新增 [tb_execution_controller_dma_store.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dma_store.sv:1)，用独立单元 testbench 验证 `DMA_STORE` 的生命周期语义
- 修改 [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:1)，新增 `load_done`，把“shared SRAM 数据已全部装入本地 SRAM A/B/C”显式做成完成脉冲
- 修改 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)，新增 `dma_load_start/load_done/load_only_mode`，使 controller 支持“只搬运不计算”的 load-only 执行路径
- 修改 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)，增加 `is_supported_dma_load`
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，让 `DMA_LOAD` 成为第三个真实可接受 opcode：可被接收、发出 `dma_load_issue_pulse`、进入 in-flight，并以 `load_done` 作为 completion source
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)，把 `dma_load_issue_pulse` 接到 `systolic_controller.dma_load_start`，把 `dma_load_done` 接回 `execution_controller.load_done`
- 新增 [tb_execution_controller_dma_load.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dma_load.sv:1)，用独立单元 testbench 验证 `DMA_LOAD` 的生命周期语义
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)，把 `execution_controller` 的活动状态端口全部显式接线，消除 top 层实例端口缺省连接带来的 `vcs` 告警
- 新增 [ewise_unit.v](/home/yian/Prj/TPU/rtl/core/ewise_unit.v:1)，实现最小 `EWISE` 后端：直接对 `SRAM D` 物理行做片上逐元素 `FP32 RELU`
- 修改 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)，增加 `is_supported_ewise`，当前仅接受 `shape_mnk_valid + FP32 + 非 mixed_precision` 的 `EWISE`
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，让 `EWISE` 成为第四个真实可接受 opcode：可被接收、发出 `ewise_issue_pulse`、进入 in-flight，并以 `ewise_done` 作为 completion source
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)，把 `ewise_unit` 接入 `SRAM D` 读改写路径，并在 `SRAM D` 地址/段选择/写数据信号上增加 controller 与 ewise 的仲裁
- 新增 [tb_execution_controller_ewise.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_ewise.sv:1)，验证 `EWISE` 在控制面上的 issue/retire 生命周期
- 新增 [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)，验证 `ewise_unit` 确实会修改 `SRAM D` 中的片上数据
- 修改 [tb/filelist/rtl_core.f](/home/yian/Prj/TPU/tb/filelist/rtl_core.f:1)，把 `ewise_unit.v` 纳入 `vcs` filelist
- 新增 [post_op_controller.v](/home/yian/Prj/TPU/rtl/core/post_op_controller.v:1)，把“GEMM 完成后是直接写回，还是先走 fused `EWISE` 再写回”的时序策略从 top 层条件判断中抽出来
- 修改 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)，增加 `gemm_relu_fuse` 字段解码，对齐 [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:54) 里 `GEMM.arg1[1]`
- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，新增 `cmd_gemm_relu_fuse/active_gemm_relu_fuse`，把 `GEMM` 的 post-op 配置锁存进活动命令状态
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)，让 `ewise_unit` 既能接受 standalone `EWISE`，也能接受 `post_op_controller` 生成的 fused `EWISE` 启动脉冲；同时把 AXI write-back 启动改为统一由 `post_op_controller` 决定
- 新增 [tb_post_op_controller_fusion.sv](/home/yian/Prj/TPU/tb/sv/tb_post_op_controller_fusion.sv:1)，验证最小 `GEMM -> fused EWISE -> DMA_STORE` 时序策略

完成情况：

- 已完成 `P2.1`
- 已完成 `P2.2`
- 已完成 `P2.3` 的最小解耦版本；当前已经有独立 `command_decoder`，但完整多 opcode 执行器仍未完成

当前进展说明：

- 控制面已经有了第一个明确入口，后续可以在不直接推翻现有 `systolic_controller` 的前提下，逐步引入 `command_decoder` 和 `execution_controller`
- 这一版 `command_queue` 的目标是固定接口边界，不是立即接管完整执行流
- 当前实现是最小同步 FIFO，足够支撑后续命令流联调和测试平台接入
- 当前 `tpu_top` 已经从“外部 `tpu_start` 直接敲控制器”演进为“外部 `tpu_start` 先入内部命令路径，再由命令启动控制器”
- 为避免运行中的配置漂移，当前控制路径已经会在命令发射时锁存 `mtype/dtype/mixed_precision`
- 当前命令字段解析已经从 `tpu_top` 中剥离出来，控制面的边界比上一版更清晰
- 后续如果引入 `DMA_LOAD / EWISE / BARRIER`，可以优先扩展 `command_decoder` 和其后的执行分发逻辑，而不是继续在 top 里堆条件判断
- 教学文档已建立，后续每一步改动都要同步维护，不再依赖零散对话记录回溯工程演进
- 当前执行发射控制也已经从 `tpu_top` 中剥离出来，控制面结构从 `queue -> decoder -> top内联发射` 变成了 `queue -> decoder -> execution_controller -> legacy executor`
- `execution_controller` 当前还只是最小外壳，只负责“是否可发射、锁存活动配置、打一拍启动脉冲”，尚未承担多 opcode 调度
- 当前固定 shape 的前向映射和反向识别，已经开始从分散硬编码转向集中管理
- `legacy_shape_codec` 现在同时服务命令打包和命令解码，减少了控制面里重复维护 shape 常量表的地方
- 本地 `vcs` 仿真入口已建立，当前工程不再只能依赖静态代码核对
- 已用 `vcs` 跑通 [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)，结果 `Verification passed: All 256 elements match!`
- 已用 `vcs` 跑 [tb_tpu_top_m32n8k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m32n8k16.sv:1)，最初失败，后经定位与修复后已通过
- 通过 `DEBUG_M32_TRACE` 证明了失败根因：`m32n8k16` 在读回第 27、28 行时，`sram_d_wen` 的残余脉冲抢占了 `sram_d_addr` mux，导致 AXI 读到错误行（1、5 而不是 27、28）
- 当前修复后，`m16n16k16`、`m32n8k16`、`m8n32k16` 三个直连 `vcs` 用例都已通过
- `legacy_shape_mapper` 已把 `matrix_adder` 和 `matrix_adder_loader` 里重复的 shape 地址规则收敛到一个模块中，控制面和数据面的 shape 规则开始有了可复用边界
- 这次收敛过程中也验证了一个重要边界：`axi_master` 的读回地址语义是“线性扫描物理 SRAM-D 行”，不能直接复用 `matrix_adder` 路径里的“逻辑输出行映射”
- 本地 `vcs` 使用增量编译数据库，多个 testbench 并行编译会争用 `hsim.sdb/rmapats.so`；当前回归流程应改为串行运行
- `sram_loader` 现在也复用了 `legacy_shape_codec` 作为尺寸 truth source，`m/n/k` 不再同时在 `tpu_top/command_decoder/sram_loader` 三处各写一套常量
- 这一步没有改 `systolic_controller` 的三套 legacy compute 子状态机，只是进一步统一了尺寸 profile 的来源；当前三种 shape 经本地 `vcs` 串行回归后仍全部通过
- `systolic_input_loader` 已经不再按 `m16/m32/m8` 展开 12 个独立 load state，而是收敛成“4 个通用 phase + 1 个 block mapper”的结构
- `legacy_tile_phase_mapper` 现在把 “第几个 phase 该读 A 的哪一块、B 的哪一块” 这个知识从 `systolic_input_loader` 里抽出来，成为输入数据路径的共享 profile
- `systolic_controller` 到 `systolic_input_loader` 的接口也更干净了：现在只传“当前 shape + 当前 phase one-hot”，不再传三套 shape-specific start bus
- 这一轮改动后，`m16n16k16`、`m32n8k16`、`m8n32k16` 三个直连 `vcs` 用例再次串行通过
- `systolic_controller` 主 compute 控制现在也已经从三套 shape-specific 状态跳转，收敛为统一的 “phase0 -> phase1 -> phase2 -> phase3” 骨架
- 这一步的关键不是减少状态名字，而是把“什么时候发 phase、什么时候等 mul_done、什么时候等 compute_done”这些控制语义统一到同一套时序结构里
- `execution_controller` 现在不再只看 `tpu_busy`，而是显式管理“命令在飞”状态，直到 `send_done` 才允许接受下一条命令
- 这一步修正的是控制面的执行边界：对于当前 legacy GEMM 路径，命令真正完成的定义应是“写回完成”，而不是“计算核心不 busy”
- `execution_controller` 现在已经显式区分 `compute_done` 和 `writeback_done` 两类完成事件，虽然当前只支持 GEMM，但后续接 `DMA/EWISE/BARRIER` 时不需要再推翻控制器骨架
- 当前 GEMM 命令会锁存 `active_opcode=0x10` 且 `active_waits_for_writeback=1`，因此其 completion source 仍然是 `send_done`
- `decoder -> execution_controller -> top` 之间现在已经有了 opcode-specific issue 边界，控制面可以明确区分 `gemm_issue`、`dma_load_issue`、`dma_store_issue`、`ewise_issue`、`barrier_issue`
- 当前这些 issue 信号里，只有 `gemm_issue_pulse` 真正连接到 legacy 执行后端；其它 issue 目前仍是占位接口，用于后续接多执行单元
- `BARRIER` 现在已经不是纯占位信号，而是第一个真正可被控制面接受并完成的非 GEMM opcode
- 当前 `BARRIER` 语义是“仅在控制面完成”：它会产生 `barrier_issue_pulse`，但不会驱动 `exec_start_pulse`，也不会进入 `exec_inflight`
- 这一步之后，工程第一次具备了“除了 GEMM 之外，还有一个真实 opcode 能被执行”的闭环能力
- `DMA_STORE` 现在已经成为第二个真实 opcode，并且是第一个复用现有数据路径后端的非 GEMM 指令
- 当前 `DMA_STORE` 语义是“直接触发现有 SRAM-D -> AXI write-back 路径”：它不会启动 GEMM 计算，但会进入 in-flight，并等待 `send_done`
- 这一步证明当前控制面已经不只是“识别 opcode”，而是真正能把不同 opcode 路由到不同完成路径
- `DMA_LOAD` 现在已经成为第三个真实 opcode，并且是第一个复用现有 load 数据路径后端的非 GEMM 指令
- 当前 `DMA_LOAD` 语义是“把 share_sram 中当前 legacy shape 对应的 A/B/C 数据搬运到本地 SRAM A/B/C，然后以 `load_done` 退休”，它不会启动 GEMM 计算，也不会触发 AXI write-back
- 这里的 `DMA_LOAD` 仍然是片内加载语义，不是外部 DDR/AXI read DMA；它复用的是现有 `sram_loader` 和 legacy dataflow，而不是新增 AXI master read 通道
- 已用 `vcs` 跑通 [tb_execution_controller_dma_load.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dma_load.sv:1)，结果 `Verification passed: DMA_LOAD command waits for load_done and then retires.`
- 本轮 `DMA_LOAD` 改动后，再次串行回归 [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)、[tb_tpu_top_m32n8k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m32n8k16.sv:1)、[tb_tpu_top_m8n32k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m8n32k16.sv:1)，三组仍全部通过
- 这一步也再次确认：当前 `vcs` 回归必须串行执行，不能并行共享默认增量编译数据库
- `EWISE` 现在已经成为第四个真实 opcode，并且是第一个真正修改片上输出数据的“新算子后端”
- 当前 `EWISE` 语义被刻意收窄为“对 `SRAM D` 物理行做 `FP32 RELU`”：它不启动 GEMM，不触发 AXI write-back，而是在片上把已有输出矩阵做后处理，并以 `ewise_done` 退休
- 这一步用 [tb_execution_controller_ewise.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_ewise.sv:1) 验证了控制面生命周期；用 [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1) 验证了数据确实被改写
- `EWISE` 接入后，再次串行回归 [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)、[tb_tpu_top_m32n8k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m32n8k16.sv:1)、[tb_tpu_top_m8n32k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m8n32k16.sv:1)，三组仍全部通过
- 在 `ewise_unit` 调试过程中修正了一个真实的同步 SRAM 读时序问题：跨行时必须提前一拍准备下一行地址，否则会把上一行数据重复抓入 `row_buffer`
- 融合路径的最小时序控制已经建立：当前 `post_op_controller` 能区分 “普通 GEMM 直接写回” 和 “带 `relu_fuse` 的 GEMM 先触发 fused `EWISE` 再写回”
- 已用 [tb_post_op_controller_fusion.sv](/home/yian/Prj/TPU/tb/sv/tb_post_op_controller_fusion.sv:1) 验证该时序策略，同时再次串行回归三组 legacy GEMM 用例，结果都仍然通过
- 当前内部 `tpu_start -> GEMM bridge` 已增加一个过渡编码：当 APB 配置为 `FP32 + mixed_precision=1` 时，bridge 会把它解释为 `relu_fuse=1`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)，增加 `bridge_gemm_relu_fuse/bridge_mixed_precision`，并修正 `cmd_push_data` 的字段拼接宽度，使 `relu_fuse` 与 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:44) 的 `cmd_data[33]` 对齐
- 新增 [tb_tpu_top_fp32_relu_fuse_bridge.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_fp32_relu_fuse_bridge.sv:1)，验证 APB 写入 `FP32 + mixed_precision=1` 后，内部 bridge 生成的 `GEMM` 命令会带 `relu_fuse=1`，同时把 bridge 生成命令中的 `mixed_precision` 清零
- 已用 [tb_tpu_top_fp32_relu_fuse_bridge.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_fp32_relu_fuse_bridge.sv:1) 验证入口桥接编码，并再次回归 [tb_post_op_controller_fusion.sv](/home/yian/Prj/TPU/tb/sv/tb_post_op_controller_fusion.sv:1) 与 [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)

可能问题：

- 当前很多 shape 逻辑仍然散落在多个模块中，后续做 `command_decoder` 时必须明确哪些字段先只做“透传配置”，哪些字段真正驱动执行路径
- 当前 `command_queue` 还没有和 APB 或软件可见寄存器桥接，因此软件侧仍不能真正按 ISA 写入任意 128-bit 指令
- 当前 top 层只会合成一种内部 `GEMM` 命令，相当于“命令化的旧路径”，还不是真正的多 opcode 执行流
- `tpu_start` 仍是单周期脉冲；如果 `command_queue` 满而软件没有检查 `push_ready`，命令会被丢弃
- 当前环境里没有现成 Verilog 编译器可做快速语法回归，这一步是静态代码核对，不是完整仿真验证
- 当前 FIFO 骨架默认 `DEPTH=8`，功能上足够，但还没有做与后续 backpressure/flush/error handling 相关的扩展
- 当前 `command_decoder` 只完成了“解码”和“legacy GEMM 识别”，还没有对不同 opcode 产生真正独立的执行请求
- 当前 `execution_controller` 还没有把 `DMA_LOAD / DMA_STORE / EWISE / BARRIER` 分发到不同执行后端，仍然只是 legacy GEMM 路径的发射器
- `P2.4` 目前只完成了执行外壳抽象，固定 shape 状态机本体仍在 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1) 中
- `legacy_shape_codec + legacy_shape_mapper + legacy_tile_phase_mapper` 目前已经收敛了控制面、`sram_loader` 尺寸配置、输入 phase block 选择、输出地址映射以及主 compute FSM 的 phase 推进骨架，但 `axi_slave` 和旧 load/store 串行组织方式仍然保留较多 legacy 结构
- 当前 `systolic_controller` 虽然已经是通用 4-phase 骨架，但本质上仍然是 legacy GEMM 控制器，还没有升级为真正的多 opcode/multi-engine 调度器
- 当前 `execution_controller` 仍然只支持单条 in-flight GEMM，并且完成条件绑定在 `send_done`；后续如果引入纯 compute 或纯 DMA 指令，需要按 opcode 重新定义 completion source
- 当前 `execution_controller` 虽然已经具备“按 opcode 区分完成源”的骨架，但 `cmd_ready` 仍然只接受 `cmd_is_supported_gemm`，也就是执行后端实际上还是只有 GEMM
- 当前 opcode-specific issue 接口已经建立，但未支持的 opcode 依然不会被 `cmd_ready` 接受；这一步是“搭边界”，不是“开放多 opcode 执行”
- 当前 `GEMM`、`BARRIER`、`DMA_STORE`、`DMA_LOAD` 都已经进入“真实可接受”的阶段，但 `EWISE` 仍然只有接口，没有执行后端
- 当前 `vcs` 编译还存在 ALU 相关 `TFIPC` warning，需要后续单独清理，但这不阻塞当前功能回归
- `vcs` 当前不能安全并行跑多个 testbench；如果要批量回归，需要在脚本层明确串行化，或给每个 job 隔离独立编译目录和数据库
- 当前 `DMA_LOAD` 只是 legacy load path 的命令化封装，仍然依赖固定 shape 的 A/B/C 数据组织方式；它还不是通用 layout-aware DMA
- 当前 `DMA_LOAD` 没有 host-visible descriptor，也没有独立 AXI read engine，因此不能把它误认为完整的外存读取 DMA
- 当前 `EWISE` 只支持 `FP32 + RELU + SRAM D 原地后处理`，还不支持 `ADD/MUL/CLIP`、不支持通用 bank/src-dst 描述，也不支持 `INT8/FP16`
- 当前 `EWISE` 仍然按 `legacy_shape_mapper` 暴露的物理行布局工作，它还不是基于 layout descriptor 的通用向量引擎
- 当前 fused `GEMM -> EWISE -> DMA_STORE` 路径已经在 RTL 中接好，并且已有一个过渡性的 APB 入口：`FP32 + mixed_precision=1 -> relu_fuse=1`
- 这个入口只是临时 bridge 语义，不是最终可扩展的 CSR/ISA 设计；它只适用于当前 `FP32` 场景
- 新增 [tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1)，采用“两阶段自校验”方式：先跑 baseline GEMM 记录实际 `FP32` 输出，再跑 fused 路径，检查第二次结果是否等于第一次结果逐元素做 `RELU`
- 随后补了最小端到端回归 [tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1)，去掉历史 testbench 中的大量通用验证逻辑，只保留 `baseline -> fused -> bitwise compare` 主链路
- 这个最小回归明确抓到：`m16n16` fused 场景下，`col[8:15]` 会按行向下串移，`SRAM D` 物理行也整体不匹配“baseline-output RELU”
- 新增 [tb_ewise_unit_relu_fp32_m16n16.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32_m16n16.sv:1) 后确认：问题不在 top 仲裁，而在 [ewise_unit.v](/home/yian/Prj/TPU/rtl/core/ewise_unit.v:1) 自身对 `m16n16` 两段布局的写时序
- 根因是 `ewise_unit` 原先把 `sram_d_addr / sram_d_seg_sel / sram_d_data_in` 做成时序寄存输出，导致单口同步 `SRAM D` 实际写入时总是比当前 `seg_idx` 慢一拍；`m16n16` 的 `2 segments/row` 最容易暴露这个 bug
- 已修复 [ewise_unit.v](/home/yian/Prj/TPU/rtl/core/ewise_unit.v:1)：把 `SRAM D` 写接口改成基于当前 `state/row_idx/seg_idx` 的组合输出，同时保留 `prefetch_addr` 负责下一行同步读预取
- 修复后，本地 `vcs` 已通过：
  - [tb_ewise_unit_relu_fp32_m16n16.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32_m16n16.sv:1)
  - [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)
  - [tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1)
  - [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)
- 原来的大而重的 [tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1) 仍然保留，但它还混有大量历史验证逻辑和单周期脉冲观察问题；后续建议继续以最小 e2e 用例作为 fused 主回归
- 已新增最小串行回归脚本 [run_vcs_regression_min.sh](/home/yian/Prj/TPU/scripts/run_vcs_regression_min.sh:1)，当前固定覆盖：
  - [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)
  - [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)
  - [tb_ewise_unit_relu_fp32_m16n16.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32_m16n16.sv:1)
  - [tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1)
- 已更新 [run_vcs_tb.sh](/home/yian/Prj/TPU/scripts/run_vcs_tb.sh:1)，为每个 testbench 分配独立 `-Mdir=${BUILD_DIR}/csrc`，避免不同 testbench 共享 `vcs` 增量编译数据库
- 已给旧的 [tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1) 增加显式 timeout；它现在更适合作为 debug 平台，而不是主回归入口
- 已继续推进命令入口升级：在 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1) 新增正式直接命令口 `cmd_valid_i / cmd_ready_o / cmd_data_i[127:0]`
- 当前 direct command 入口优先级高于旧的 `tpu_start + APB` bridge；旧入口仍保留，用于兼容现有回归
- 已同步更新所有现有 `tpu_top` testbench 端口连接，默认把 direct command 入口绑为 `0`
- 新增 [tb_tpu_top_direct_cmd_gemm_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_gemm_relu_fuse.sv:1)，验证一条 `GEMM + relu_fuse` 指令可以直接送入命令队列并被 `execution_controller` 正确锁存，而不依赖 APB `FP32 + mixed_precision=1` 临时桥接语义
- 本轮本地 `vcs` 通过：
  - `scripts/run_vcs_regression_min.sh`
  - [tb_tpu_top_fp32_relu_fuse_bridge.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_fp32_relu_fuse_bridge.sv:1)
  - [tb_tpu_top_direct_cmd_gemm_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_gemm_relu_fuse.sv:1)

下一步动作：

- 继续推进 `P2.4`，把 `execution_controller` 从“发射外壳”扩成真正的执行控制边界
- 继续推进 `P2.4`，把 `execution_controller` 从“单一 GEMM in-flight 管理器”扩成按 opcode 区分完成源的执行控制边界
- 继续推进 `P2.4`，把 `execution_controller` 从“按 opcode 区分完成源的控制骨架”扩成真正能发射多类指令的执行控制边界
- `EWISE` 已完成最小后端，下一步优先考虑把它和 `GEMM` 连成最小 `GEMM -> EWISE -> DMA_STORE` 融合路径
- 融合调度骨架和临时 APB bridge 已完成，下一步优先考虑补一条端到端 fused top-level testcase
- 端到端 fused top-level testcase 已补，并且最小 e2e 用例已经转绿；下一步把这套最小回归纳入正式基线
- 最小回归基线已经固化到 `scripts/run_vcs_regression_min.sh`
- 后续继续清理旧的 heavyweight fused testbench；当前已先补 timeout，后面再逐步删除历史通用验证分支，避免再次出现“testbench 漏采 send_done”这类伪问题
- 当前已经有正式 direct command 入口，下一步可以开始让新的多 opcode 测试和 host 侧工具优先走这个入口
- 然后再把当前“`FP32 + mixed_precision=1` 复用成 `relu_fuse`”的临时入口逐步降级为兼容路径，而不是主入口
- 如果继续留在 P2，可先把“命令来源”从内部 `tpu_start -> GEMM bridge` 扩成真正可写入多 opcode 的 host/APB 入口
- 继续清理 `P2.4` 剩余的 legacy 串行控制痕迹，优先考虑 `MAIN_START_LOAD_SRAM -> MAIN_LOAD_SRAM -> MAIN_COMPUTE -> MAIN_DONE` 这条固定流水的可调度化
- 把 `run_vcs_tb.sh` 或批量回归脚本改成明确串行执行，避免 `vcs` 增量编译数据库冲突
- 明确命令写入入口是“APB 寄存器桥”还是“单独 host port”，避免后续重复返工

## P3：数据流与复用

阶段目标：

- 把数据搬运和布局从硬编码升级为架构能力

计划任务：

- [ ] P3.1 定义 layout descriptor
- [ ] P3.2 设计 SRAM bank 组织方式
- [ ] P3.3 引入 ping-pong buffer
- [ ] P3.4 支持 load / compute / store overlap
- [ ] P3.5 设计跨层驻留策略

预期交付物：

- layout 规范文档
- bank / tile 映射图
- overlap 时序图

验收标准：

- 至少一个用例中 DMA 与计算可重叠
- 中间结果可不经 DDR 驻留片上

实际改动：

- 暂无

完成情况：

- 未开始

当前进展说明：

- 这一阶段决定项目是否能真正讲清“reuse”和“带宽优化”

可能问题：

- 现有 SRAM 深度和数据打包方式未必适合直接 bank 化

下一步动作：

- 等控制面有雏形后再进入本阶段

## P4：算子扩展

阶段目标：

- 增加 element-wise 能力，建立最小融合执行路径

计划任务：

- [ ] P4.1 设计 vector / EWISE 单元接口
- [ ] P4.2 支持 `ADD/MUL/RELU/BIAS_ADD`
- [ ] P4.3 打通 `GEMM + BIAS + RELU`
- [ ] P4.4 评估是否加入 reduce 类原语

预期交付物：

- `ewise_unit` RTL
- 融合执行时序与数据流图
- 对应性能对比结果

验收标准：

- 至少一条融合路径不落 DDR

实际改动：

- 暂无

完成情况：

- 未开始

当前进展说明：

- 这一阶段会显著提升“像 AI 加速器”的程度

可能问题：

- 融合后完成信号与 buffer 生命周期管理会更复杂

下一步动作：

- 先等 P2/P3 基础控制和数据路径准备好

## P5：验证与收敛

阶段目标：

- 形成“功能正确 + 性能可解释 + tradeoff 可量化”的闭环

计划任务：

- [ ] P5.1 建立 unit 级验证
- [ ] P5.2 建立 integration 级验证
- [ ] P5.3 建立性能回归脚本
- [ ] P5.4 补充 tradeoff 表和实验结果
- [ ] P5.5 输出最终版本项目总结

预期交付物：

- 回归脚本
- 性能趋势表
- 最终实验总结

验收标准：

- 每次改动后能自动知道功能是否退化、性能是否变差

实际改动：

- 暂无

完成情况：

- 未开始

当前进展说明：

- 这是最后收口阶段，不应过早开始

可能问题：

- 如果前面阶段没有明确记录，就会导致最后无法做可对照的总结

下一步动作：

- 保持本计划文档持续更新

## 6. 统一进展记录格式

后续每完成一个任务，建议按以下格式在对应阶段下追加：

- 实际改动：改了哪些文件、加了哪些模块、删了哪些旧逻辑
- 完成情况：完成 / 部分完成 / 暂停
- 当前进展：做到什么程度
- 出现的问题：遇到的技术问题、验证问题、接口问题
- 下一步动作：下一次具体做什么

## 7. 当前建议的推进顺序

严格建议按下面顺序推进：

1. 先完成 P1，不要直接跳去做复杂 ISA
2. 再进入 P2，把控制面抽象出来
3. 然后做 P3，把 reuse 和带宽问题真正落地
4. 再做 P4，让它更像 AI 加速器
5. 最后做 P5，把项目收敛成高质量成果

## 8. 当前状态结论

当前已经完成的是“看清楚问题、建立理论分析和目标架构”。

真正的 RTL 改进还没有开始。

下一次建议直接进入：

- P1.1 修正 APB 接口与 top 级基础集成问题

这是最合适的第一个实际 RTL 改造点。

## P2.4 继续推进：direct command 顶层多指令序列回归落地

实际改动：

- 新增顶层 direct-command 多指令序列 testbench：[tb_tpu_top_direct_cmd_sequence.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_sequence.sv:1)
- 用 direct `128-bit` command 入口顺序下发 `DMA_LOAD -> GEMM(relu_fuse) -> BARRIER -> DMA_STORE`
- 在该 testbench 中加入 AXI writeback 事务捕获，对比 fused GEMM 隐式写回与显式 `DMA_STORE` 写回是否逐元素一致
- 更新最小回归脚本：[run_vcs_regression_min.sh](/home/yian/Prj/TPU/scripts/run_vcs_regression_min.sh:1)，把新用例纳入基线

完成情况：

- 已完成

当前进展：

- direct command 入口已不只是 smoke test，而是具备顶层多 opcode 序列验证
- 当前已验证的 direct command 顶层序列为：`DMA_LOAD -> GEMM(relu_fuse) -> BARRIER -> DMA_STORE`
- 本地 `vcs` 已通过：
  - `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_sequence`
  - `scripts/run_vcs_regression_min.sh`

出现的问题：

- 首轮失败不是 RTL bug，而是新 testbench 的 `send_direct_cmd` task 握手机制写错，导致 `cmd_valid_i` 多保持一个周期，从而把每条 direct command 重复入队
- 这个问题已经在 [tb_tpu_top_direct_cmd_sequence.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_sequence.sv:1) 中修复，最终回归通过
- 当前 `run_vcs_regression_min.sh` 仍依赖各 testbench 自身打印 `Verification passed` 作为人工判据；脚本本身尚未升级成严格检查日志失败关键字的形式

下一步动作：

- 继续留在 P2.4，推进 direct command 入口下的更多 top-level 场景
- 优先考虑补一条显式 `DMA_LOAD -> GEMM -> EWISE -> DMA_STORE` 非 fused 序列，用来把“隐式 fused post-op”与“显式 opcode 链”区分开

## P2.4 继续推进：显式 EWISE opcode 顶层链路打通

实际改动：

- 新增 direct-command 顶层显式 `EWISE` 序列用例：[tb_tpu_top_direct_cmd_explicit_ewise.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_explicit_ewise.sv:1)
- 用 direct `128-bit` command 入口顺序下发：`DMA_LOAD -> GEMM -> BARRIER -> EWISE -> BARRIER -> DMA_STORE`
- 在该用例中捕获两次 AXI writeback：
  - 第 1 次：非 fused `GEMM` 的 baseline 写回
  - 第 2 次：显式 `EWISE + DMA_STORE` 写回
- 更新最小回归脚本：[run_vcs_regression_min.sh](/home/yian/Prj/TPU/scripts/run_vcs_regression_min.sh:1)，把该用例纳入基线

完成情况：

- 已完成

当前进展：

- 当前工程里已经同时存在两条可验证的 post-op 路径：
  - fused：`GEMM(relu_fuse) -> implicit EWISE -> writeback`
  - explicit：`GEMM -> EWISE opcode -> DMA_STORE`
- 本地 `vcs` 已通过：
  - `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_explicit_ewise`
  - `scripts/run_vcs_regression_min.sh`

出现的问题：

- 首轮失败不是 RTL bug，而是 testbench 中对第二个 `BARRIER` 的顺序状态建模过死；实际运行中该 `BARRIER` 出现在 `EWISE` 之后，这符合设计语义
- 该问题已在 [tb_tpu_top_direct_cmd_explicit_ewise.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_explicit_ewise.sv:1) 中修正，最终回归通过

下一步动作：

- 继续留在 P2.4，考虑是否要把 direct command 的 `dep_in/dep_out` 从“占位字段”推进到真正的依赖 token 机制
- 或者开始进入 P3，把当前已具备的 fused/explicit post-op 路径纳入性能与带宽复用分析

## P2.4 继续推进：`dep_in/dep_out` 最小依赖 token 机制落地

实际改动：

- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，把 `cmd_dep_in/cmd_dep_out` 正式接入控制语义
- 在 `execution_controller` 中新增最小 token 状态：
  - `completed_token`
  - `completed_token_valid`
  - `active_dep_out`
- 修改 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)，把 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1) 解析出的 `dep_in/dep_out` 连接到 `execution_controller`
- 新增 unit test：[tb_execution_controller_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dep_tokens.sv:1)
- 新增 top-level direct-command 依赖链路用例：[tb_tpu_top_direct_cmd_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_dep_tokens.sv:1)
- 更新最小回归脚本：[run_vcs_regression_min.sh](/home/yian/Prj/TPU/scripts/run_vcs_regression_min.sh:1)，把上述两条用例纳入基线

完成情况：

- 已完成

当前进展：

- `dep_in/dep_out` 已经不再只是 ISA 文档和 decoder 里的占位字段，而是进入了实际控制流
- 当前 token 语义为：
  - `dep_in == 0`：无依赖，可直接 issue
  - `dep_in != 0`：只有当 `completed_token_valid == 1` 且 `completed_token == dep_in` 时才允许 issue
  - 一条命令完成后，如果 `dep_out != 0`，则发布该 token
  - `BARRIER` 属于立即完成 opcode，也可以立即发布 `dep_out`
- 本地 `vcs` 已通过：
  - `scripts/run_vcs_tb.sh tb_execution_controller_dep_tokens`
  - `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_dep_tokens`
  - `scripts/run_vcs_regression_min.sh`

出现的问题：

- 这一步没有暴露新的 RTL 功能 bug，主要工作量在于把原本未使用的 `dep_in/dep_out` 真正纳入控制边界
- 当前 token 机制仍然是“单 token 完成记录”，不是完整的多 token scoreboard，因此还不支持更复杂的依赖图

下一步动作：

- 如果继续留在 P2.4，下一步可以考虑把 token 机制从“单 completed token”扩成“多 token scoreboard”
- 如果准备转入 P3，则可以开始把 fused/explicit/dep-token 三类命令流纳入 performance 和 data reuse 分析

## P2.4 继续推进：从单 completed token 升级到最小多 token scoreboard

实际改动：

- 修改 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)，新增 `completed_token_bitmap[255:0]`，把依赖判定从“最近一次 token”等价判断升级成“token 集合成员判断”
- 保留 `completed_token/completed_token_valid` 作为最近一次发布 token 的调试/观测出口
- 更新 [tb_execution_controller_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dep_tokens.sv:1)，加入“先发布 `0x33`、再发布 `0x55`，依赖 `0x33` 的命令仍能 issue”场景
- 更新 [tb_tpu_top_direct_cmd_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_dep_tokens.sv:1)，加入“`0x11` 已发布后又被 `0x55` 覆盖为最近 token，但依赖 `0x11` 的 `GEMM` 仍能正常发射”场景

完成情况：

- 已完成

当前进展：

- 依赖判定已经不再依赖“最后一个完成 token”，而是依赖“该 token 是否已经在 scoreboard 中出现过”
- 当前 scoreboard 语义为：
  - token `0x00` 仍表示“无依赖”
  - 非零 token 一旦被某条命令发布，就在 bitmap 中置位并保持到复位
  - 后续命令只要 `dep_in` 对应 bit 已置位，就允许 issue
- 本地 `vcs` 已通过：
  - `scripts/run_vcs_tb.sh tb_execution_controller_dep_tokens`
  - `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_dep_tokens`
  - `scripts/run_vcs_regression_min.sh`

出现的问题：

- 这一步没有暴露新的 RTL bug，主要问题在于 top-level 依赖链路 testbench 的顺序断言需要从“最近 token 等于依赖 token”调整为“虽然最近 token 已变化，但旧 token 仍应保留在 scoreboard 中”
- 当前 scoreboard 仍然只支持“token 出现后永久有效直到复位”，还不支持 token 回收或更细粒度生命周期管理

下一步动作：

- 如果继续留在 P2.4，下一步可以考虑补 token 生命周期管理，或让 command queue/front-end 支持更复杂的依赖拓扑
- 如果准备切入 P3，则当前已经具备足够稳定的 runtime 骨架，可以开始把 fused/explicit/dep-token 三类执行流纳入性能与带宽分析

## P3 启动：建立当前执行流的统一流量模型

实际改动：

- 新增运行时流量分析脚本：[runtime_flow_model.py](/home/yian/Prj/TPU/scripts/utils/runtime_flow_model.py:1)
- 新增第一版 P3 分析报告：[P3_RUNTIME_FLOW_ANALYSIS.md](/home/yian/Prj/TPU/docs/P3_RUNTIME_FLOW_ANALYSIS.md:1)
- 把当前已经在 RTL 中存在的四条执行流统一到一个可比较模型中：
  - `baseline_gemm`
  - `fused_gemm_relu`
  - `explicit_ewise`
  - `dep_token_explicit_ewise`

完成情况：

- P3 已开始
- 当前完成的是 P3 的“流量基线建模”，还不是 layout/bank RTL 改造

当前进展：

- 已经能用统一口径比较四条执行流的：
  - off-chip bytes
  - arithmetic intensity
  - roofline 下的可达性能
  - 当前带宽/计算瓶颈判断
- 对 `m16n16k16 fp32` 当前模型结果为：
  - `baseline_gemm`: `4096 B`
  - `fused_gemm_relu`: `4096 B`
  - `explicit_ewise`: `5120 B`
  - `dep_token_explicit_ewise`: `5120 B`
- 结论已经很清楚：
  - fused 路径和 baseline 的 off-chip 流量相同，但做了更多有用工作
  - explicit post-op 路径多一次输出写回，带宽成本更高
  - dep-token 改进的是控制语义，不直接改 off-chip bytes

出现的问题：

- 你这台机器上的 `python3` 没有 `dataclasses`，因此 [runtime_flow_model.py](/home/yian/Prj/TPU/scripts/utils/runtime_flow_model.py:1) 已改成更兼容的普通类写法
- 当前这个模型还只覆盖外存流量与 roofline 上界，不覆盖 bank conflict、片上端口争用、SRAM 深度约束

下一步动作：

- 正式进入 `P3.1`，先定义 layout descriptor
- 然后把“为什么 fused 更省带宽”进一步落实到 tile/layout/residency 语义上，而不只是报告层对比
