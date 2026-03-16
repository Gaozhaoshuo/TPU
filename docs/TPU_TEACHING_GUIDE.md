# TPU 升级教学文档

## 1. 文档定位

这份文档是后续理解本工程的主入口。

目标不是记录所有细节，而是保证你只看这一份文档，就能理解：

1. 这个工程原来是什么
2. 现在被改成了什么
3. 关键模块分别负责什么
4. 数据和控制是怎么流动的
5. 每一步升级到底改了哪里、为什么改
6. 当前还剩哪些架构问题没有解决

后续每完成一步 TPU 升级，都必须同步维护这份文档。

## 2. 工程当前定位

当前工程还不能称为“完整可编程 TPU”。

它的真实定位是：

“一个以固定 GEMM 主路径为基础、正在逐步演进为可编程 TPU/NPU 核的数字 IC 工程”

更具体地说：

1. 原始版本更像固定形状 GEMM 加速器
2. 当前版本已经开始引入最小命令流抽象
3. 目标版本是带 command queue、decoder、数据复用和基础算子融合能力的 TPU/NPU 核

## 3. 目录怎么读

建议优先关注下面这些目录：

- `rtl/core/`：核心 RTL
- `dv/uvm/`：UVM 验证环境
- `tb/sv/`：基础 testbench
- `scripts/utils/`：性能模型和辅助脚本
- `docs/`：架构文档、执行计划、教学文档

最关键的几个文件是：

- [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)
- [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)
- [command_queue.v](/home/yian/Prj/TPU/rtl/core/command_queue.v:1)
- [apb_config_reg.v](/home/yian/Prj/TPU/rtl/core/apb_config_reg.v:1)
- [axi_slave.v](/home/yian/Prj/TPU/rtl/core/axi_slave.v:1)
- [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1)

## 4. 原始工程的工作方式

原始工程的控制流是固定的，不是指令流。

原始执行顺序如下：

1. APB 写入 `mtype_sel / dtype_sel / mixed_precision`
2. AXI Slave 把输入数据写入 `share_sram`
3. 外部拉高 `tpu_start`
4. `systolic_controller` 按固定状态机调度 load -> compute -> write-back
5. `tpu_done` 脉冲表示计算结束
6. `axi_master` 根据固定模式把结果写出
7. `send_done` 脉冲表示写回结束

原始工程的主要问题有三类：

1. 控制面不可编程
2. shape / 地址 / layout 在多个模块硬编码
3. load / compute / store 基本串行

更完整的问题分析见：

- [TPU_IMPROVEMENT_REPORT.md](/home/yian/Prj/TPU/docs/TPU_IMPROVEMENT_REPORT.md:1)

## 5. 当前主数据通路

当前主数据路径没有被推翻，仍然是：

1. [axi_slave.v](/home/yian/Prj/TPU/rtl/core/axi_slave.v:1) 把数据写入 `share_sram`
2. [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:1) 把 A/B/C 搬到本地 SRAM
3. [systolic_input_loader.v](/home/yian/Prj/TPU/rtl/core/systolic_input_loader.v:1) 产生阵列输入地址节奏
4. [systolic_input.v](/home/yian/Prj/TPU/rtl/core/systolic_input.v:1) 把 SRAM 数据整理成阵列输入流
5. [systolic.v](/home/yian/Prj/TPU/rtl/core/systolic.v:1) 完成乘加
6. [matrix_adder_loader.v](/home/yian/Prj/TPU/rtl/core/matrix_adder_loader.v:1) 读取 C
7. [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:1) 生成 `A * B + C`
8. [sram_segsel.v](/home/yian/Prj/TPU/rtl/core/sram_segsel.v:1) 做 SRAM D 分段写入
9. [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1) 把结果搬出

所以到目前为止，升级主要发生在“控制面”，不是“数据面”。

## 6. 到目前为止已经做过的升级

## 6.1 P0：基线梳理

这一步没有改 RTL 主逻辑，主要是把工程讲清楚。

已经产出的内容：

- [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:1)
- [perf_model.py](/home/yian/Prj/TPU/scripts/utils/perf_model.py:1)
- [perf_batch.py](/home/yian/Prj/TPU/scripts/utils/perf_batch.py:1)
- [PERF_BASELINE.md](/home/yian/Prj/TPU/docs/PERF_BASELINE.md:1)
- [TPU_IMPROVEMENT_REPORT.md](/home/yian/Prj/TPU/docs/TPU_IMPROVEMENT_REPORT.md:1)

你可以把这一步理解为：

“先把这个工程是什么、瓶颈可能在哪里、下一步为什么这么改”讲清楚。

## 6.2 P1：接口与工程清理

这一步做的是“把工程从勉强能看，修到基本可信”。

已经完成的改动：

1. 修正 `tpu_top` 中 APB 接线，内部真正使用 `pclk/presetn`
2. 统一了 top / UVM / AXI 注释里的接口语义
3. 明确 `tpu_done` 和 `send_done` 都是单周期脉冲
4. 补了工程入口 [README.md](/home/yian/Prj/TPU/README.md:1)

这一阶段的价值是：

后续做控制面升级时，不会继续建立在错误接口语义之上。

## 6.3 P2.1：引入 command queue 概念

这一步第一次把“命令流”引进工程。

新增文件：

- [COMMAND_QUEUE_SPEC.md](/home/yian/Prj/TPU/docs/COMMAND_QUEUE_SPEC.md:1)
- [command_queue.v](/home/yian/Prj/TPU/rtl/core/command_queue.v:1)

当前 `command_queue` 是一个最小同步 FIFO，接口是标准 ready/valid 风格：

输入侧：

- `push_valid`
- `push_ready`
- `push_data[127:0]`

输出侧：

- `pop_valid`
- `pop_ready`
- `pop_data[127:0]`

状态侧：

- `empty`
- `full`
- `level`

这一步的意义不是“已经有完整 TPU 指令系统”，而是：

“控制面终于有了一个清晰的入口边界。”

## 6.4 P2.2：把 command queue 接入 top 层主控制路径

这是第一步真正影响运行方式的升级。

当前 `tpu_top` 里的控制流程，已经从：

`tpu_start -> systolic_controller`

变成：

`tpu_start -> 内部 GEMM 命令打包 -> command_queue -> 发射 -> systolic_controller`

这一步做了三件关键事：

1. 在 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:67) 中加入内部命令路径
2. 在命令发射时锁存 `active_mtype_sel / active_dtype_sel / active_mixed_precision`
3. 让 [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1) 使用“活动命令配置”，而不是直接读取 APB 当前配置

为什么第 3 点重要：

如果计算已经开始，而软件又修改了 APB 配置，那么“正在执行的计算”和“写回路径看到的 shape 配置”就可能不一致。

现在通过活动命令锁存，这个问题被压住了。

## 6.5 P2.3：抽出独立 `command_decoder`

在 P2.2 之后，`tpu_top` 里已经有了命令路径，但命令字段解析还是直接写在 top 里。

这样做的问题是：

1. top 层职责过重
2. 后续支持更多 opcode 时，decode 逻辑会继续堆在 top 里

所以这一步新增了：

- [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)

这个模块当前完成的事情是：

1. 从 128-bit 命令中解出 `opcode`
2. 解出 `dtype / mixed_precision / layout / dep_in / dep_out`
3. 解出 `M / N / K`
4. 判断这条命令是不是当前 legacy 路径支持的 `GEMM`
5. 如果 `M/N/K` 对应旧硬件支持的三种 shape，就转成 `legacy_mtype_sel`

这一步之后，`tpu_top` 不再自己手写命令字段切片，而是调用 `command_decoder`。

这一改动的本质是：

“控制面结构已经开始形成 `command_queue -> command_decoder -> legacy executor` 的雏形。”

## 6.6 P2.4（进行中）：抽出最小 `execution_controller`

在 P2.3 之后，decode 已经独立出来了，但“命令什么时候可以发射、发射后锁存哪些活动配置、什么时候给旧控制器打一拍启动脉冲”这些事情，仍然放在 `tpu_top` 里。

所以这一步新增了：

- [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)

当前这个模块只做三件事：

1. 根据 `cmd_valid / exec_busy / cmd_is_supported_gemm` 决定 `cmd_ready`
2. 在命令发射时锁存活动配置
3. 产生一拍 `exec_start_pulse`

这一步之后，控制面结构又清楚了一层：

`command_queue -> command_decoder -> execution_controller -> systolic_controller`

但这里要明确一件事：

当前 `execution_controller` 还不是“真正的统一执行控制器”，它只是一个最小外壳。

它还没有做到：

1. 多 opcode 分发
2. 依赖 token 管理
3. load / compute / store 的独立调度
4. 参数化替换旧 `systolic_controller`

## 6.7 P2.4（继续推进）：集中 legacy shape 映射

到这一步为止，虽然控制面已经有了 `queue / decoder / execution_controller`，但固定 shape 的知识还是散在多个地方。

最直接的两个重复点是：

1. `tpu_top` 在打包内部 `GEMM` 命令时，自己手写 `m16n16k16 / m32n8k16 / m8n32k16` 对应的 `M/N/K`
2. `command_decoder` 在解码命令时，又自己写了一遍 `M/N/K -> legacy_mtype_sel`

所以这一步新增了：

- [legacy_shape_codec.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_codec.v:1)

这个模块现在做两件事：

1. `mtype_sel -> M/N/K`
2. `M/N/K -> legacy_mtype_sel`

然后把它接到了两个地方：

1. [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:164)  
   用它生成内部 `GEMM` 命令里的 `M/N/K`
2. [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)  
   用它识别命令里的 `M/N/K` 是否属于当前 legacy 硬件支持的 shape

这一步的价值是：

虽然还没有把所有 shape 逻辑从旧模块里拔干净，但至少控制面已经不再重复维护同一套 shape 常量表。

## 6.8 仿真入口补齐：接入本地 `vcs`

前面的改动如果只靠静态阅读，很容易高估进展。

所以这一步补了一个最小但可复用的本地仿真入口：

- [rtl_core.f](/home/yian/Prj/TPU/tb/filelist/rtl_core.f:1)
- [run_vcs_tb.sh](/home/yian/Prj/TPU/scripts/run_vcs_tb.sh:1)

同时把三个直连 testbench 里的数据文件路径，从历史 Windows 绝对路径改成了仓库内相对路径：

- [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)
- [tb_tpu_top_m32n8k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m32n8k16.sv:1)
- [tb_tpu_top_m8n32k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m8n32k16.sv:1)

现在可以直接这样跑：

```bash
scripts/run_vcs_tb.sh tb_tpu_top_m16n16k16
scripts/run_vcs_tb.sh tb_tpu_top_m32n8k16
```

## 6.9 当前 `vcs` 回归结果

到目前为止，已经有三条本地可复现结果：

1. `tb_tpu_top_m16n16k16`
   - 编译通过
   - 仿真通过
   - 日志中给出 `Verification passed: All 256 elements match!`

2. `tb_tpu_top_m32n8k16`
   - 最初编译通过但仿真失败
   - 通过 `DEBUG_M32_TRACE` 抓到根因后，当前已修复并重新通过

3. `tb_tpu_top_m8n32k16`
   - 编译通过
   - 仿真通过
   - 当前三种 legacy shape 都已经有本地 `vcs` 通过记录

这件事很重要，因为它说明：

1. 我们前面做的控制面重构至少没有破坏 `m16n16k16`
2. 这个工程里确实存在过 shape 相关的功能漏洞，而且已经可以通过本地 `vcs` 被真实抓出来
3. 后续 `P2.4/P3` 不能只靠架构文档推进，必须绑定真实回归

补充一个工程约束：

4. 本地 `vcs` 使用增量编译数据库，多个 testbench 不能安全并行编译；当前标准用法应是串行运行

## 6.10 已定位并修复的真实功能 bug：`m32n8k16` 读回地址被污染

这是到目前为止最重要的一次“文档分析 -> 本地仿真 -> 根因定位 -> RTL 修复”的闭环。

现象是：

1. `m32n8k16` 在本地 `vcs` 下最开始是失败的
2. 错误集中在输出后段，第 27、28 行读回错误
3. 不是 compile 问题，而是功能问题

## 6.11 P2.4（继续推进）：集中 `matrix_adder` 路径中的 legacy shape 映射

前面 [legacy_shape_codec.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_codec.v:1) 解决的是控制面里的 shape 常量重复问题，但数据面里还有一类重复没有收掉：

1. [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:1) 里有一份 `row_counter -> write_addr/high_low_sel` 映射
2. [matrix_adder_loader.v](/home/yian/Prj/TPU/rtl/core/matrix_adder_loader.v:1) 里又有一份几乎相同的 `counter -> read_sramc_addr/high_low_sel` 映射

这两份规则描述的是同一件事：

“当前 legacy shape 下，逻辑输出行应该落到 SRAM 的哪一行、哪一段。”

所以这一步新增了：

- [legacy_shape_mapper.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_mapper.v:1)

这个模块现在统一输出四类信息：

1. `mapped_addr`
2. `seg_sel`
3. `bursts_per_row`
4. `max_rows`

其中前两项主要给 `matrix_adder / matrix_adder_loader` 用，后两项可以给 `axi_master` 这类模块复用配置。

这一轮具体改动有三处：

1. [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:1)  
   不再手写三种 shape 的写回地址 case，而是直接使用 `legacy_shape_mapper`
2. [matrix_adder_loader.v](/home/yian/Prj/TPU/rtl/core/matrix_adder_loader.v:1)  
   不再手写三种 shape 的 C 矩阵读取地址 case，而是直接使用 `legacy_shape_mapper`
3. [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1)  
   只复用了 `bursts_per_row/max_rows`，没有复用地址映射

这里要特别理解第 3 点。

`matrix_adder` 路径里的地址语义是：

“逻辑输出行如何映射到 SRAM-D 的物理地址和段选择。”

但 `axi_master` 的地址语义是：

“把已经写好的 SRAM-D 物理行，按 0..15 / 0..31 / 0..7 的顺序线性扫出来。”

这两个语义不一样。

我一开始把 `axi_master` 也直接接到了 `legacy_shape_mapper` 的地址输出上，结果马上在本地 `vcs` 中把 `m16n16k16` 跑坏了。根因是：

1. 对 `m16n16k16`，`matrix_adder` 的逻辑行 8 并不对应物理 SRAM 行 8，而是回到物理行 0 的高半段
2. 但 `axi_master` 此时应该去读的是物理 SRAM 行 8 的低半段

所以后面做了修正：

1. `axi_master` 保留线性扫描 `read_sramd_addr <= read_sramd_addr + 1`
2. 只复用 `legacy_shape_mapper` 里的 `bursts_per_row/max_rows`

这一步的价值不是“又多了一个模块”，而是把一个之前混在多个模块中的核心知识边界讲清楚了：

1. `legacy_shape_codec` 解决“控制面 shape 编码”
2. `legacy_shape_mapper` 解决“输出矩阵在 SRAM 中如何排布”
3. `axi_master` 解决“如何把 SRAM 中已经排布好的结果按 AXI burst 写回”

## 6.12 这一步之后的回归状态

在引入 [legacy_shape_mapper.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_mapper.v:1) 并修正 `axi_master` 地址语义之后，三组直连 testbench 已重新用本地 `vcs` 串行回归：

1. `tb_tpu_top_m16n16k16`
   - 通过
2. `tb_tpu_top_m32n8k16`
   - 通过
3. `tb_tpu_top_m8n32k16`
   - 通过

这里强调“串行”是因为：

1. `vcs` 当前使用增量编译数据库
2. 并行跑多个 testbench 会争用 `hsim.sdb/rmapats.so`
3. 这会产生工具级错误，不代表 RTL 有功能问题

所以当前工程的标准回归习惯应该是：

```bash
scripts/run_vcs_tb.sh tb_tpu_top_m16n16k16
scripts/run_vcs_tb.sh tb_tpu_top_m32n8k16
scripts/run_vcs_tb.sh tb_tpu_top_m8n32k16
```

## 6.13 P2.4（继续推进）：统一 `sram_loader` 的尺寸 profile 来源

前面已经把控制面里的 shape 编码收到了 [legacy_shape_codec.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_codec.v:1)，也把输出矩阵地址映射收到了 [legacy_shape_mapper.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_mapper.v:1)。

但 `sram_loader` 里还留着第三份重复知识：

1. `m16n16k16 -> M=16, N=16`
2. `m32n8k16 -> M=32, N=8`
3. `m8n32k16 -> M=8, N=32`

这些信息其实已经在 `legacy_shape_codec` 里存在，不应该再在 [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:1) 里单独维护一遍。

所以这一步做的事情是：

1. 删掉 `sram_loader` 里本地的 shape 尺寸常量表
2. 在 `sram_loader` 中直接实例化 [legacy_shape_codec.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_codec.v:1)
3. 用 `shape_m/shape_n` 驱动 `m_max/n_max`

这一步之后，`sram_loader` 的作用边界更干净了：

1. 它只负责“按已经给定的 `m/n` 去搬数据”
2. 它不再负责“重新定义 shape 是多少”

这里要明确，这一步只是“尺寸 profile 收敛”，不是“控制器参数化完成”。

当前还没有动的部分是：

1. [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1) 里三套 legacy compute 子状态机
2. [systolic_input_loader.v](/home/yian/Prj/TPU/rtl/core/systolic_input_loader.v:1) 里按 block 偏移展开的地址规则

也就是说，当前进度是：

1. `legacy_shape_codec`：统一 shape 编码和 `M/N/K`
2. `legacy_shape_mapper`：统一输出矩阵在 SRAM 中的排布
3. `sram_loader`：统一尺寸来源
4. `systolic_controller/systolic_input_loader`：仍然是下一步要继续清理的 legacy 核心

## 6.14 这一步的验证结果

在 [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:1) 切到 `legacy_shape_codec` 之后，我重新用本地 `vcs` 串行跑了三组回归：

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

这说明：

1. 这一步只是收敛尺寸配置来源，没有改变功能行为
2. `legacy_shape_codec` 现在已经不只是控制面模块，而是开始变成整个 legacy shape profile 的共享信息源

## 6.15 P2.4（继续推进）：统一输入 phase 的 block 选择规则

接下来收敛的是输入路径里的另一类重复知识：

“当前是第几个 phase，就该从 SRAMA/SRAMB 的哪一个 8-row block 读数据。”

原始实现里，这件事被写成了两层重复：

1. [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1) 输出三套不同的 `load_systolic_input_start_*`
2. [systolic_input_loader.v](/home/yian/Prj/TPU/rtl/core/systolic_input_loader.v:1) 用 12 个 shape-specific load state 分别展开地址偏移

这其实表达的是同一个概念：

1. 当前 shape 是哪一种
2. 当前 phase 是 0/1/2/3 中的哪一个
3. 这个 phase 对应 A 的哪个 block、B 的哪个 block

所以这一步新增了：

- [legacy_tile_phase_mapper.v](/home/yian/Prj/TPU/rtl/core/legacy_tile_phase_mapper.v:1)

这个模块专门回答一个问题：

“给定 `mtype_sel + phase_idx`，A/B 应该选哪两个 block。”

三种 shape 的规则分别是：

1. `m16n16k16`
   - phase0: `A0/B0`
   - phase1: `A0/B1`
   - phase2: `A1/B0`
   - phase3: `A1/B1`
2. `m32n8k16`
   - phase0: `A0/B0`
   - phase1: `A1/B0`
   - phase2: `A2/B0`
   - phase3: `A3/B0`
3. `m8n32k16`
   - phase0: `A0/B0`
   - phase1: `A0/B1`
   - phase2: `A0/B2`
   - phase3: `A0/B3`

### 6.15.1 这一步改了什么

1. [systolic_input_loader.v](/home/yian/Prj/TPU/rtl/core/systolic_input_loader.v:1)
   - 接口从三套 `load_systolic_input_start_*` 收敛成一套 `load_systolic_input_start[3:0]`
   - 状态机从 12 个 shape-specific load state 收敛成 4 个通用 `LOAD_PHASE0..3`
   - `read_srama_addr/read_sramb_addr` 改为通过 `legacy_tile_phase_mapper` 生成 block 偏移

2. [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)
   - 不再维护三套 start bus
   - 改成输出一套通用 `load_systolic_input_start[3:0]`

### 6.15.2 为什么这一步是对的

因为对于 `systolic_input_loader` 来说，真正需要的不是 “当前是 `m16_LOAD_A1_B0` 还是 `m32_LOAD_A2_B` 这种名字”，而只是：

1. 当前 phase 是第几个
2. A/B 的 block 偏移是多少

把状态名字从“shape-specific 名字”收敛成“通用 phase 名字”，不会改变功能语义，但会让后续参数化更容易。

### 6.15.3 这一步之后的验证结果

这一步完成后，我重新用本地 `vcs` 串行跑了三组回归：

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

所以当前可以明确说：

1. 输入路径里的 phase block 规则已经被抽成共享模块
2. 但 `systolic_controller` 主 compute 状态机本身还没有参数化
3. 下一步如果继续推进，就该处理主状态机里三套 shape-specific 的状态跳转

## 6.16 P2.4（继续推进）：统一主 compute FSM 的 phase 推进骨架

在 6.15 之后，输入路径已经能用统一 `phase_idx` 来表达，但 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1) 自己还保留着三整套展开式状态：

1. `MAIN_M16N16K16_COMPUTE`
2. `MAIN_M32N8K16_COMPUTE`
3. `MAIN_M8N32K16_COMPUTE`

每一套下面又各自带一串：

1. `SUB_START_*`
2. `SUB_MUL_*`
3. `SUB_START_*`
4. `SUB_MUL_*`
5. ...

这些状态名字不同，但控制语义其实完全一样：

1. 发起当前 phase
2. 等待这一个 phase 的乘法完成
3. 如果不是最后一个 phase，就进入下一个 phase
4. 如果是最后一个 phase，就等待 `compute_done`

所以这一步把主 compute FSM 收成了统一骨架：

1. 主状态：
   - `MAIN_IDLE`
   - `MAIN_START_LOAD_SRAM`
   - `MAIN_LOAD_SRAM`
   - `MAIN_COMPUTE`
   - `MAIN_DONE`
2. 子状态：
   - `SUB_IDLE`
   - `SUB_START_PHASE`
   - `SUB_MUL_PHASE`
3. 新增寄存器：
   - `phase_idx`

现在 `systolic_controller` 的核心思路变成：

1. `load_ab_done` 之后进入 `MAIN_COMPUTE`
2. 从 `phase_idx = 0` 开始
3. `SUB_START_PHASE` 发起当前 phase 的 one-hot start
4. `SUB_MUL_PHASE` 等待 `mul_done`
5. 如果 `phase_idx < 3`，则 `phase_idx++` 继续下一 phase
6. 如果 `phase_idx == 3`，则等待 `compute_done`，再进入 `MAIN_DONE`

### 6.16.1 这一步为什么重要

因为现在真正 controlling compute progression 的不再是：

1. “我是不是 `SUB_START_M16N16K16_LOAD_A1_B0`”
2. “我是不是 `SUB_M32N8K16_MUL_A2_B`”

而是：

1. 我当前是否在 `START_PHASE`
2. 我当前 `phase_idx` 是多少
3. 当前 phase 完成后该不该进入下一 phase

这就是从“按名字堆状态”向“按控制语义建状态机”转过去的关键一步。

### 6.16.2 这一步没有做到什么

这一步虽然把 compute phase 推进统一了，但还没有做到：

1. 多 opcode 调度
2. load / compute / store overlap
3. 真正把 `execution_controller` 变成统一调度器
4. 把固定串行主流程拆成可重叠的多引擎控制

所以它仍然属于：

“把 legacy GEMM 控制器整理成更清晰的通用骨架”

而不是：

“已经完成 NPU 级 runtime/controller 升级”

### 6.16.3 这一步的验证结果

这一步完成后，我重新用本地 `vcs` 串行回归了三组 testbench：

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

所以当前可以明确说：

1. 输入路径的 phase 规则已经统一
2. 主 compute phase 推进也已经统一
3. 现在剩下的 legacy 问题，更多是系统级的串行调度方式，而不是 shape-specific phase 状态爆炸

## 6.17 P2.4（继续推进）：把命令完成边界从 `tpu_busy` 收口到 `send_done`

到 6.16 为止，compute 骨架已经统一了，但控制面还有一个容易被忽略的问题：

旧版 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1) 的 `cmd_ready` 只参考 `tpu_busy`。

这会带来一个边界错误：

1. 计算核心结束后，`tpu_busy` 会拉低
2. 但 AXI write-back 可能还没有完成
3. 如果这时接受下一条命令，就会让“新计算”和“旧结果回写”在系统层面重叠到同一条 legacy 路径上

对于当前工程，这是不对的。  
因为当前这条命令路径的真实生命周期是：

1. command issue
2. load / compute
3. `tpu_done`
4. AXI write-back
5. `send_done`

所以这一步做了两件事：

1. [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)
   - 新增 `exec_inflight`
   - 命令发射时置位
   - 在 `send_done` 时清零
   - `cmd_ready` 改成以 `exec_inflight` 为准

2. [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:257)
   - 把 `send_done` 接给 `execution_controller`
   - 让当前单命令 GEMM 路径的 completion source 明确等于 write-back 完成

### 6.17.1 这一步的意义

这一步不是简单“多了一个 busy 位”，而是把执行边界讲清楚了：

1. `tpu_busy`：表示计算核心正在工作
2. `tpu_done`：表示 compute 阶段结束
3. `send_done`：表示整条 legacy GEMM 命令真正完成

所以对当前工程来说：

“命令完成” 应该看 `send_done`，不是看 `tpu_busy`

### 6.17.2 这一步之后的验证结果

这一步完成后，我重新用本地 `vcs` 串行回归了三组 testbench：

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

### 6.17.3 这一步仍然没做到什么

这一步仍然只适用于当前“单条 in-flight GEMM + 固定 write-back”路径。

如果后面引入：

1. 纯 DMA 指令
2. 不需要 AXI write-back 的片上融合指令
3. 多执行单元并行

那么 `execution_controller` 还要继续升级成：

“按 opcode 决定 completion source 的执行控制器”

## 6.18 P2.4（继续推进）：把 completion source 选择显式做进控制器

6.17 已经把当前 GEMM 路径的完成条件改成了 `send_done`，但那时控制器还只是“行为上这样做了”，结构上还没有把这件事讲清楚。

所以这一步继续往前推了一格：

1. 在 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1) 中新增
   - `active_opcode`
   - `active_waits_for_writeback`
2. 把输入完成事件拆成两类
   - `compute_done`
   - `writeback_done`
3. 在控制器里显式生成
   - `exec_complete_event`

当前的规则很简单：

1. 如果是 GEMM（`opcode = 0x10`）
   - `active_waits_for_writeback = 1`
   - 完成源看 `writeback_done`

以后如果接入新的 opcode，就可以继续扩成：

1. `DMA_LOAD`
   - 完成源看 DMA 完成
2. `EWISE`
   - 完成源看 vector/ALU 完成
3. `BARRIER`
   - 完成源可能是立即完成或 token 满足

### 6.18.1 这一步为什么重要

因为现在 `execution_controller` 不再只是“能发一条 GEMM”的小外壳，而是开始具备 runtime/controller 应有的基本结构：

1. 锁存当前 active command 的身份
2. 锁存当前 active command 的 completion policy
3. 根据 completion policy 选择真正的完成事件

这一步之后，控制器语义更接近：

“我知道当前在执行什么，也知道它应该由谁来宣告完成”

而不只是：

“我等某个固定 done 信号”

### 6.18.2 这一步还没做到什么

仍然要明确：

1. 当前 `cmd_ready` 还是只接受 `cmd_is_supported_gemm`
2. 当前没有 DMA/EWISE/BARRIER 的真实执行后端
3. 所以这一步只是把骨架搭好，不是已经实现多 opcode

### 6.18.3 这一步的验证结果

这一步之后，我再次用本地 `vcs` 串行跑了三组回归：

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

所以当前可以明确说：

1. legacy GEMM 数据路径仍然稳定
2. `execution_controller` 的内部抽象已经比最初清晰得多
3. 后面如果继续升级控制面，重点就该转到“多 opcode 发射与后端分发”，而不是继续在 GEMM completion 语义上打补丁

## 6.19 P2.4（继续推进）：建立 opcode-specific issue 接口

到 6.18 为止，控制器已经知道“当前 active command 是什么、它该由谁宣告完成”，但还差一个明显的 runtime 边界：

“发射时，controller 应该往哪个执行后端送 issue 信号？”

所以这一步先把接口立起来，不急着实现所有后端。

### 6.19.1 这一步改了什么

1. [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)
   - 新增 opcode 分类信号：
   - `is_dma_load`
   - `is_dma_store`
   - `is_ewise`
   - `is_barrier`

2. [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)
   - 新增 opcode-specific issue 输出：
   - `gemm_issue_pulse`
   - `dma_load_issue_pulse`
   - `dma_store_issue_pulse`
   - `ewise_issue_pulse`
   - `barrier_issue_pulse`

3. [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:240)
   - 把 decoder 的 opcode 分类结果接到 controller
   - 把 controller 的 issue 输出接到 top 层内部信号

### 6.19.2 这一步之后，控制面边界怎么理解

现在控制面已经逐步形成下面这层结构：

1. `command_queue`
   - 存指令
2. `command_decoder`
   - 判断这条命令是什么类型
3. `execution_controller`
   - 判断能不能发
   - 锁存 active command
   - 根据 opcode 产生对应的 issue pulse
   - 根据 opcode 选择 completion source

这意味着：

后面如果你要接新的后端，优先要看的已经不是 top 里某段 if/case，而是：

1. `command_decoder` 有没有正确识别这条命令
2. `execution_controller` 有没有给出对应 issue pulse
3. 这个 opcode 的完成源是什么

### 6.19.3 这一步要特别注意

这一步虽然已经建立了：

1. `gemm_issue`
2. `dma_load_issue`
3. `dma_store_issue`
4. `ewise_issue`
5. `barrier_issue`

但当前真正有执行后端的还是只有：

1. `gemm_issue`

其余几个信号现在只是占位接口。  
也就是说，这一步是：

“把 runtime/controller 的接口边界立起来”

不是：

“已经支持多 opcode 执行”

### 6.19.4 这一步的验证结果

这一步之后，我再次用本地 `vcs` 串行跑了三组回归：

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

### 6.19.5 当前最合理的下一步

如果继续推进控制面，而又不想一下子大改 RTL，最合理的是先选一个“侵入最小”的 opcode 做第一个真实非 GEMM 后端：

1. `BARRIER`
   - 最简单，可以做成无数据通路、只改控制器/token 逻辑
2. `DMA_STORE`
   - 也比较实际，可以复用现有 AXI 写回结构

相比之下：

1. `EWISE`
   - 会牵涉新的 vector/ALU 后端
2. `DMA_LOAD`
   - 会更深地碰输入数据组织

## 6.20 P2.4（继续推进）：把 `BARRIER` 做成第一个真实非 GEMM opcode

6.19 只是把 opcode-specific issue 接口立起来了，但那时除了 `GEMM` 以外，其他 opcode 还都只是“能被识别，不能真正执行”。

所以这一步我先选了最轻量的一个：

1. `BARRIER`

原因很直接：

1. 它几乎不碰数据通路
2. 它可以先验证“非 GEMM opcode 能被 controller 接受并完成”
3. 它能最小代价地把控制面从“只有 GEMM 真执行”往前推一步

### 6.20.1 这一步改了什么

1. [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)
   - `cmd_ready` 不再只接受 `GEMM`
   - 现在也接受 `BARRIER`
   - `BARRIER` 发射时：
     - 会产生 `barrier_issue_pulse`
     - 不会产生 `exec_start_pulse`
     - 不会进入 `exec_inflight`

2. 新增单元 testbench：
   - [tb_execution_controller_barrier.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_barrier.sv:1)

这个 testbench 验证的不是数据结果，而是控制语义：

1. `BARRIER` 能被 controller 接受
2. `barrier_issue_pulse` 会被拉高
3. 不会错误启动 GEMM 路径
4. 不会错误进入 in-flight 执行态

### 6.20.2 这一步意味着什么

这一步之后，工程里已经不再是：

1. 只有 `GEMM` 是真实 opcode

而是：

1. `GEMM`：真实数据路径 opcode
2. `BARRIER`：真实控制路径 opcode

这很重要，因为它说明：

控制面已经不再只是“给 GEMM 打包参数”，而开始具备真正 runtime/controller 的轮廓。

### 6.20.3 这一步的验证结果

这一步我做了两层验证。

第一层：`BARRIER` 单元测试

1. [tb_execution_controller_barrier.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_barrier.sv:1)
   - `Verification passed: BARRIER command is accepted and completes in control path.`

第二层：原有 GEMM 回归

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

所以当前可以明确说：

1. `BARRIER` 已经成为第一个真实非 GEMM opcode
2. 它没有破坏现有 GEMM 主路径

### 6.20.4 这一步之后，下一步最合理做什么

现在再往前推，最合理的是：

1. `DMA_STORE`

因为：

1. 现有工程已经有 AXI write-back 路径
2. 可以最大程度复用现有 `axi_master`
3. 比 `DMA_LOAD/EWISE` 对现有 RTL 的侵入更小

## 6.21 P2.4（继续推进）：把 `DMA_STORE` 做成第二个真实 opcode

在 6.20 里，`BARRIER` 已经证明了“非 GEMM opcode 可以在控制面被真实执行”。  
接下来最合理的就是把第一个可复用现有数据路径后端的 opcode 接起来，也就是：

1. `DMA_STORE`

因为当前工程已经有一条成熟的写回路径：

1. `SRAM-D`
2. [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1)
3. AXI write-back

### 6.21.1 这一步改了什么

1. [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)
   - 新增 `is_supported_dma_store`
   - 当前规则是：`DMA_STORE + 合法 legacy shape`

2. [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)
   - `DMA_STORE` 现在可被 `cmd_ready` 接受
   - 发射时会产生 `dma_store_issue_pulse`
   - 不会产生 `exec_start_pulse`
   - 会进入 `exec_inflight`
   - 会等待 `writeback_done`

3. [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:186)
   - 把 `dma_store_issue_pulse` 接到现有 `axi_master.send_start`
   - 写回期间也会拉起 `sram_d_readback_active`

这意味着 `DMA_STORE` 现在已经不只是 controller 里的抽象信号，而是确实复用了现有的写回后端。

### 6.21.2 这一步之后，三类真实 opcode 是什么

到现在为止，工程里已经有三类“真实可接受”的 opcode：

1. `GEMM`
   - 真正驱动 compute + writeback
2. `BARRIER`
   - 只在控制面完成
3. `DMA_STORE`
   - 真正驱动 writeback，但不启动 compute

这三类 opcode 分别覆盖了：

1. 计算路径
2. 控制路径
3. 搬运路径（写回方向）

### 6.21.3 这一步的验证结果

这一步我做了两层验证。

第一层：`DMA_STORE` 单元测试

1. [tb_execution_controller_dma_store.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dma_store.sv:1)
   - `Verification passed: DMA_STORE command waits for writeback_done and then retires.`

这个 testbench 验证的是：

1. `DMA_STORE` 可以被接受
2. `dma_store_issue_pulse` 会拉高
3. 它不会错误启动 GEMM
4. 它会进入 in-flight
5. 它会在 `writeback_done` 后退休

第二层：原有 GEMM 主路径回归

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

所以当前可以明确说：

1. `DMA_STORE` 已经成为第二个真实数据路径 opcode
2. 它复用了现有 `axi_master` 写回后端
3. 它没有破坏原有 GEMM 主路径

## 6.22 P2.4（继续推进）：把 `DMA_LOAD` 做成第三个真实 opcode

在 6.21 里，`DMA_STORE` 已经把“写回”这条非 GEMM 数据路径打通了。  
下一步最合理的是把“加载”也命令化，但这里要把语义讲清楚：

当前工程里的 `DMA_LOAD` 不是“从外部 DDR 读回来的 AXI DMA”。  
它的真实含义是：

1. 从 `share_sram` 中读取已由 AXI slave 预先写入的数据
2. 按当前 legacy shape 的规则，把 A/B/C 搬运进本地 `SRAM A/B/C`
3. 搬完以后，以一个独立的 `load_done` 事件退休

也就是说，这一步做的是：

“把原先 GEMM 固定流程里的 load 阶段，抽成一个可单独发射、可单独完成的命令。”

### 6.22.1 为什么先做这个，而不是直接做 AXI read DMA

原因很直接：

1. 当前工程已经有完整可工作的 `share_sram -> sram_loader -> SRAM A/B/C` 数据路径
2. 这条路径和现有 legacy GEMM 强绑定，最适合先拿来做第一个 load-only opcode
3. 如果现在直接加 AXI read master，会同时引入：
   - 新的外部带宽通道
   - 新的 backpressure
   - 新的地址描述符
   - 新的验证维度

这会把问题规模一下子放大，不适合当前阶段。

所以这一步的工程策略是：

1. 先把“load 阶段可独立命令化”打通
2. 再在后续 `P3/P4` 里考虑更通用的 read DMA / layout descriptor

### 6.22.2 这一步具体改了什么

#### 1. `sram_loader` 增加 `load_done`

文件：[sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:1)

原先 `sram_loader` 只对 GEMM 路径暴露 `load_ab_done`。  
这不够，因为：

1. `load_ab_done` 表示的是“可以开始算”
2. 但 `DMA_LOAD` 需要的是“整个 load-only 命令已经完成”

所以现在增加了：

1. `load_done`
2. 它在 `LOAD_C_DONE` 时产生脉冲

这就把“本地 SRAM A/B/C 都装载完毕”显式做成了一个 completion event。

#### 2. `systolic_controller` 增加 load-only 模式

文件：[systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)

新增了：

1. `dma_load_start`
2. `load_done`
3. `load_only_mode`

现在 `systolic_controller` 的主流程变成：

1. 如果是普通 GEMM：
   - `MAIN_START_LOAD_SRAM`
   - `MAIN_LOAD_SRAM`
   - `MAIN_COMPUTE`
   - `MAIN_DONE`
2. 如果是 `DMA_LOAD`：
   - `MAIN_START_LOAD_SRAM`
   - `MAIN_LOAD_SRAM`
   - 等 `sram_load_done`
   - 直接 `MAIN_DONE`

也就是说：

`DMA_LOAD` 现在会复用原来的 load path，但不会进入 compute。

#### 3. `execution_controller` 增加 “等待 load 完成” 语义

文件：[execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)

新增了：

1. `cmd_is_supported_dma_load`
2. `load_done`
3. `active_waits_for_load`

现在 controller 的 completion source 选择逻辑变成：

1. 如果当前命令等待写回：看 `writeback_done`
2. 否则如果当前命令等待 load：看 `load_done`
3. 否则：看 `compute_done`

这说明 controller 现在已经不止能区分：

1. 计算完成
2. 写回完成

还开始能区分：

3. 加载完成

#### 4. `tpu_top` 把 `DMA_LOAD` 控制链接通

文件：[tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)

接通了两条关键线：

1. `dma_load_issue_pulse -> systolic_controller.dma_load_start`
2. `systolic_controller.load_done -> execution_controller.load_done`

这就把 `DMA_LOAD` 的 issue 和 retire 连成了闭环。

#### 5. 新增 `DMA_LOAD` 单测

文件：[tb_execution_controller_dma_load.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dma_load.sv:1)

这个 testbench 验证的是控制器语义，不是矩阵结果：

1. `DMA_LOAD` 能被接收
2. 会发出 `dma_load_issue_pulse`
3. 不会错误发出 `exec_start_pulse`
4. 会进入 `exec_inflight`
5. 会等待 `load_done`
6. 收到 `load_done` 后退休

### 6.22.3 我们实际验证了什么

第一层：`DMA_LOAD` 单元测试

结果是：

1. `Verification passed: DMA_LOAD command waits for load_done and then retires.`

第二层：原有 GEMM 主路径回归

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

所以当前可以明确说：

1. `DMA_LOAD` 已经成为第三个真实 opcode
2. 它复用了现有 `share_sram -> sram_loader -> SRAM A/B/C` 路径
3. 它没有破坏原有 GEMM 主路径

### 6.22.4 这一步要特别注意的边界

最容易误解的一点是：

不要把当前 `DMA_LOAD` 当成“完整的 AXI read DMA”。

它现在还不是：

1. 通用外存读取引擎
2. 带地址/stride/layout descriptor 的 DMA read engine
3. 可独立控制目标 bank/目标 tile 的通用装载器

它现在是：

1. 现有 legacy load path 的命令化封装
2. 一个真实可退休的 load-only opcode
3. 把固定串行主流程里的“load”阶段，从 GEMM 主路径中分离出来

这个差别必须讲清楚，否则后面做架构报告时会把工程现状说大。

### 6.22.5 这一步之后，下一步最合理做什么

现在控制面里已经有四类真实可接受 opcode：

1. `GEMM`
2. `BARRIER`
3. `DMA_STORE`
4. `DMA_LOAD`

接下来最合理的是做 `EWISE`。

原因是：

1. 控制面骨架已经足够支撑新的 opcode
2. `DMA_LOAD/DMA_STORE` 两边都已经打通
3. 再往前推进，最能体现“从 GEMM 加速器走向 NPU”的，就是 element-wise 和融合路径

所以后续重点不该再停留在“再造更多控制壳子”，而应该开始碰第一个真正的新算子后端。

### 6.22.6 回归方法上的一个工程结论

这一步还再次确认了一个环境约束：

1. 当前 `vcs` 回归必须串行跑
2. 不能直接并行共享默认 `csrc/hsim.sdb` 和 `rmapats.so`

并行执行时出现的问题是：

1. 数据库争用
2. 增量编译产物互相覆盖
3. `rmapats.so` 生成失败

所以后续如果做批量回归脚本，要么：

1. 明确串行化

要么：

2. 给每个 testbench 独立的构建目录和数据库

### 6.22.7 一个小的工程清理

在本轮 `DMA_LOAD` 验证后，我还把 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1) 里 `execution_controller` 的活动状态端口都改成了显式接线。  
这一步不改行为，但能避免 `vcs` 在 top 层实例上持续报“too few instance port connections”。

## 6.23 P2.4（继续推进）：把 `EWISE` 做成第一个真实新算子后端

到 6.22 为止，控制面里已经有：

1. `GEMM`
2. `DMA_LOAD`
3. `DMA_STORE`
4. `BARRIER`

但它们里只有 `GEMM` 是真正的计算算子。  
如果项目要从“固定 GEMM 加速器”往 “NPU/TPU 核”走，下一步就不能继续只做控制壳子，而必须把一个新算子后端接进来。

这一步我选的是：

1. `EWISE`
2. 具体实现成最小 `FP32 RELU`
3. 作用对象是 `SRAM D`

也就是：

先做“对 GEMM 输出做片上逐元素后处理”，而不是一上来做完整向量流水线。

### 6.23.1 为什么这样收窄，而不是直接做通用 vector engine

原因很直接：

1. 当前工程里最稳定、最容易复用的数据对象就是 `SRAM D`
2. `SRAM D` 本来就承接 GEMM 输出，最适合拿来做后处理
3. 如果现在直接做通用 `src0/src1/dst/bank/layout` 向量引擎，范围会立刻膨胀

所以这一步的目标不是“把 EWISE 做完整”，而是先证明三件事：

1. `EWISE` 能作为真实 opcode 被接收
2. 它有独立完成事件
3. 它确实会修改片上输出数据

### 6.23.2 这一步具体改了什么

#### 1. `command_decoder` 增加 `is_supported_ewise`

文件：[command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)

当前规则是：

1. opcode 必须是 `0x11`
2. shape 必须是当前 legacy 支持的合法 `M/N/K`
3. dtype 必须是 `FP32`
4. `mixed_precision` 必须关闭

这意味着当前 `EWISE` 是一个刻意收窄的实现，不会假装自己已经支持所有 dtype/op。

#### 2. `execution_controller` 增加 `EWISE` 的生命周期语义

文件：[execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)

新增了：

1. `cmd_is_supported_ewise`
2. `ewise_done`
3. `active_waits_for_ewise`

现在 controller 的完成源选择变成：

1. 写回型命令看 `writeback_done`
2. load 型命令看 `load_done`
3. ewise 型命令看 `ewise_done`
4. 其它计算型命令看 `compute_done`

这一步之后，`execution_controller` 已经不只是区分 load/store/compute，而是开始区分更细的算子完成源。

#### 3. 新增真正的数据路径模块 `ewise_unit`

文件：[ewise_unit.v](/home/yian/Prj/TPU/rtl/core/ewise_unit.v:1)

这个模块做的事是：

1. 顺序扫描 `SRAM D` 的物理行
2. 按当前 `mtype_sel` 获取 `bursts_per_row/max_rows`
3. 逐段读出 `SRAM D` 的 256-bit segment
4. 对每个 32-bit 元素应用最小 `FP32 RELU`
5. 原地写回 `SRAM D`
6. 全部完成后拉 `done`

当前实现有两个重要边界：

1. 它按 `legacy_shape_mapper` 暴露的物理行布局工作
2. 它只实现了 `FP32 RELU`

#### 4. `tpu_top` 接入 `EWISE` 的 `SRAM D` 仲裁

文件：[tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)

接入方式是：

1. `ewise_issue_pulse -> ewise_unit.start`
2. `ewise_unit.done -> execution_controller.ewise_done`
3. `sram_d_addr / seg_sel / data_in / write_enable` 在 `systolic_controller` 和 `ewise_unit` 之间做仲裁

这意味着 `EWISE` 现在不是只停在 controller 里，而是已经真正占用了片上数据通路。

### 6.23.3 这一步踩到并修掉的真实问题

在调试 `ewise_unit` 时，出现了一个真实的同步 SRAM 读时序问题：

1. `SRAM D` 是同步读
2. 跨行时如果不提前一拍准备下一行地址
3. `row_buffer` 会重复抓到上一行数据

最后的修复是：

1. 在 `ewise_unit` 中提前一拍装载下一行 `sram_d_addr`
2. 把跨行地址准备和 `CAPTURE` 时序分开

这不是测试问题，而是一个真实 RTL bug。  
这一步把它在一个最小新后端里暴露并修掉了。

### 6.23.4 这一步我们实际验证了什么

第一层：控制面单测

文件：[tb_execution_controller_ewise.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_ewise.sv:1)

结果：

1. `Verification passed: EWISE command waits for ewise_done and then retires.`

这个 testbench 验证的是：

1. `EWISE` 能被 controller 接受
2. 会发出 `ewise_issue_pulse`
3. 不会误触发 `exec_start_pulse`
4. 会进入 in-flight
5. 会等待 `ewise_done`
6. 收到 `ewise_done` 后退休

第二层：数据路径单测

文件：[tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)

结果：

1. `Verification passed: EWISE unit applies FP32 RELU over SRAM-D physical rows.`

这个 testbench 验证的是：

1. `ewise_unit` 确实读取了 `SRAM D`
2. 负的 `FP32` 元素被改成了 `0`
3. 正值和 `0` 保持不变
4. 多 segment、多 physical row 都被正确处理

第三层：原有 GEMM 主路径回归

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

这说明 `EWISE` 接入 `SRAM D` 仲裁后，没有把原有三种 legacy GEMM 路径打坏。

### 6.23.5 当前 `EWISE` 到底算“做到了什么”

现在可以明确说：

1. `EWISE` 已经成为第四个真实 opcode
2. 它是第一个真实新算子后端
3. 它不只是控制面占位，而是真的会改写片上输出数据

这一步的意义比 `BARRIER/DMA_LOAD/DMA_STORE` 更大，因为它第一次把“不是 GEMM 的计算”接进了工程。

### 6.23.6 当前 `EWISE` 还没有做到什么

必须同时写清楚限制：

1. 只支持 `FP32`
2. 只支持 `RELU`
3. 只支持 `SRAM D` 原地后处理
4. 还不支持 `ADD/MUL/CLIP`
5. 还不支持通用 `src0/src1/dst` 描述
6. 还不支持 `INT8/FP16`
7. 还不支持真正的 `GEMM -> EWISE` 自动融合调度

所以它现在更准确的名称应该是：

“最小片上 post-op 后端”

而不是：

“完整 vector engine”

### 6.23.7 这一步之后，下一步最合理做什么

现在控制面里已经有：

1. `GEMM`
2. `DMA_LOAD`
3. `DMA_STORE`
4. `BARRIER`
5. `EWISE`

下一步最合理的不是继续新增孤立 opcode，而是开始把它们串起来。

最有价值的方向是：

1. 做最小 `GEMM -> EWISE -> DMA_STORE` 融合路径
2. 让 `EWISE` 支持至少一个二元算子（如 `ADD`）
3. 或者把命令写入入口扩成真正可下发多 opcode 的 host/APB 接口

## 6.24 P2.4（继续推进）：建立最小 `GEMM -> EWISE -> DMA_STORE` 融合调度骨架

到 6.23 为止，`EWISE` 已经是一个真实 opcode，`DMA_STORE` 也已经能独立写回。  
但这些东西还是“并排存在”，还没有形成真正的融合链。

这一步我做的不是直接上完整 fused testcase，而是先把融合的时序策略从 top 层条件判断里抽成一个独立小模块，让工程里第一次出现明确的：

1. `GEMM done -> direct writeback`
2. `GEMM done -> fused EWISE -> writeback`

这两条路径。

### 6.24.1 为什么先做“调度骨架”，而不是先做端到端融合测试

原因很直接：

1. 当前外部命令入口还是内部 `tpu_start -> GEMM bridge`
2. 当时这条 bridge 还不能从 host 侧显式下发 `relu_fuse=1`
3. 如果那时强行写端到端 fused testcase，就得先补一套临时命令入口

这会把问题混在一起。

所以这一步先把：

1. ISA 字段解码
2. 活动命令锁存
3. 后处理时序控制

三件事连起来。

### 6.24.2 这一步具体改了什么

#### 1. `command_decoder` 开始解 `GEMM` 的 `relu_fuse`

文件：[command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)

对齐的是 [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:54) 中的定义：

1. `GEMM.arg1[1] = relu_fuse`

现在 decoder 已经能把这个位解出来，输出为：

1. `gemm_relu_fuse`

#### 2. `execution_controller` 锁存融合配置

文件：[execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)

新增了：

1. `cmd_gemm_relu_fuse`
2. `active_gemm_relu_fuse`

这意味着 fused post-op 不再是 top 层临时判断，而是成为活动命令状态的一部分。

#### 3. 新增 `post_op_controller`

文件：[post_op_controller.v](/home/yian/Prj/TPU/rtl/core/post_op_controller.v:1)

这个模块专门做一件事：

决定在 `GEMM` 计算完成后，到底是：

1. 直接启动 AXI write-back
2. 还是先启动 fused `EWISE`，等 `ewise_done` 后再写回

当前它只看几个核心信号：

1. `active_opcode`
2. `active_gemm_relu_fuse`
3. `compute_done`
4. `ewise_done`
5. `dma_store_issue_pulse`

这样做的价值是：

融合时序第一次被明确抽象成一个独立控制边界，而不是散落在 `tpu_top` 里。

#### 4. `tpu_top` 接入 fused post-op 路径

文件：[tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)

现在：

1. standalone `EWISE` 仍然可以直接启动 `ewise_unit`
2. fused `GEMM` 也可以由 `post_op_controller` 触发 `ewise_unit`
3. AXI write-back 的启动，也改为统一由 `post_op_controller` 决定

所以现在 top 层已经具备这两种语义：

1. 非 fused GEMM：`compute_done -> writeback`
2. fused GEMM：`compute_done -> ewise_done -> writeback`

### 6.24.3 这一步怎么验证

我没有假装已经有完整 host 可下发 fused GEMM。  
当前验证分两层。

第一层：融合调度单测

文件：[tb_post_op_controller_fusion.sv](/home/yian/Prj/TPU/tb/sv/tb_post_op_controller_fusion.sv:1)

结果：

1. `Verification passed: post_op_controller sequences GEMM, fused EWISE, and DMA_STORE correctly.`

它验证的是：

1. 普通 GEMM 完成后会直接 writeback
2. 带 `relu_fuse` 的 GEMM 完成后会先启动 fused `EWISE`
3. fused `EWISE` 完成后才会启动 writeback
4. `DMA_STORE` 仍然直接触发 writeback

第二层：回归不回退

1. `tb_tpu_top_m16n16k16`
   - `Verification passed: All 256 elements match!`
2. `tb_tpu_top_m32n8k16`
   - `Verification passed: All 256 elements match!`
3. `tb_tpu_top_m8n32k16`
   - `Verification passed: All 256 elements match!`

这说明新的 post-op 调度骨架没有把旧主路径打坏。

### 6.24.4 当前这一步做到哪里，没做到哪里

做到的：

1. ISA 里的 `relu_fuse` 已经能被解码
2. 活动命令已经能锁存 fused post-op 配置
3. RTL 里已经存在真实的 fused 调度路径

没做到的：

1. 当时内部 `tpu_start -> GEMM bridge` 还不会自动把 `relu_fuse` 置成 1
2. 当时还没有一个端到端 fused top-level testcase，从外部命令入口一路跑到 writeback

所以这一步要准确描述成：

“融合后端和调度骨架已接好”

而不是：

“外部已经能直接下发并验证 fused GEMM”

### 6.24.5 这一步之后，最合理的下一步

现在最合理的两个方向是：

1. 补一个真正能下发 `relu_fuse=1` 的命令入口
2. 基于这个入口补一条端到端 fused top-level testcase

如果继续留在 P2，我会优先做第 1 个。  
如果开始向 P4 过渡，也可以考虑让 `EWISE` 再支持一个二元算子，如 `ADD`。

## 6.25 P2.4（继续推进）：补上 fused GEMM 的临时 APB 命令入口

6.24 结束时，融合后端和调度骨架已经具备了。  
真正缺的是：外部怎么把 `relu_fuse=1` 送进来。

这一步我没有直接重做 APB 寄存器接口。原因很直接：

1. 当前 [apb_config_reg.v](/home/yian/Prj/TPU/rtl/core/apb_config_reg.v:1) 只有 7 bit 写数据
2. 这 7 bit 已经被 `mtype_sel[2:0] + dtype_sel[2:0] + mixed_precision` 占满
3. 如果现在直接改 APB 寄存器定义，会把接口、testbench、后续软件约定一起打散

所以这一步采用了一个明确写清楚的过渡方案：

1. 只在 `FP32` 场景下生效
2. 如果 APB 配置写成 `FP32 + mixed_precision=1`
3. 内部 bridge 不再把它当成真正的 mixed precision
4. 而是把它翻译成：`relu_fuse=1`

这不是最终 ISA/CSR 方案。  
它只是为了把“fused GEMM 从外部入口一路走到内部命令编码”先打通。

### 6.25.1 这一步具体改了什么

#### 1. 在 `tpu_top` 中增加 bridge 级别的过渡编码

文件：[tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:192)

新增了两个 bridge 层信号：

1. `bridge_gemm_relu_fuse`
2. `bridge_mixed_precision`

它们的语义是：

1. 当 `dtype_sel == FP32` 且 APB `mixed_precision == 1` 时
2. `bridge_gemm_relu_fuse = 1`
3. `bridge_mixed_precision = 0`

也就是：

对当前这条 bridge 来说，`FP32 + mixed_precision=1` 会被重新解释成  
“生成一条带 `relu_fuse=1` 的 FP32 GEMM 命令”。

#### 2. 修正 `cmd_push_data` 的字段宽度 bug

文件：[tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:210)

这个过程中暴露了一个真实 bug：

原来的 `cmd_push_data` 拼接只有 `127 bit`。  
Verilog 在赋值到 `128 bit` 总线时，会在最高位自动补 `0`。

结果就是：

1. `command_decoder` 期待的 `cmd_data[33]`
2. 实际上没有落到我们以为的 `relu_fuse`

这是一个典型的“命令字段定义和实际打包不一致”的错误。

修复方法是：

1. 把 `arg1` 段补齐到完整 `32 bit`
2. 让 `relu_fuse` 真正落在 `cmd_data[33]`
3. 同时保留 `mixed_precision` 在 `cmd_data[115]`

这一步很关键，因为它证明：

不是“概念上觉得字段在这里”就够了，必须用 testbench 把位段对齐打实。

### 6.25.2 这一步怎么验证

新增文件：[tb_tpu_top_fp32_relu_fuse_bridge.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_fp32_relu_fuse_bridge.sv:1)

这个 testbench 不跑完整矩阵路径。  
它只做最小、最有针对性的验证：

1. 通过 APB 写入 `mtype=16x16, dtype=FP32, mixed_precision=1`
2. 拉起 `tpu_start`
3. 检查 bridge 信号：
   - `bridge_gemm_relu_fuse == 1`
   - `bridge_mixed_precision == 0`
4. 检查内部命令编码：
   - `cmd_push_data[33] == 1`
   - `cmd_push_data[115] == 0`
5. 检查命令经 queue/decode/controller 后：
   - `cmd_gemm_relu_fuse == 1`
   - `active_gemm_relu_fuse == 1`

实际结果：

1. `Verification passed: APB FP32 mixed_precision bridge generates fused GEMM command encoding.`

同时我还补跑了：

1. [tb_post_op_controller_fusion.sv](/home/yian/Prj/TPU/tb/sv/tb_post_op_controller_fusion.sv:1)
   - `Verification passed: post_op_controller sequences GEMM, fused EWISE, and DMA_STORE correctly.`
2. [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)
   - `Verification passed: All 256 elements match!`

这说明两件事：

1. 临时 bridge 入口已经能把 fused 配置送进内部命令流
2. 现有非 fused 主路径没有被这次改动打坏

### 6.25.3 这一步做到什么，没做到什么

做到的：

1. `relu_fuse` 已经可以从外部 APB 配置一路进入内部 GEMM 命令
2. bridge 级别的命令打包和 decoder 位段已经被 testbench 对齐验证
3. fused GEMM 不再只是“内部骨架存在”，而是已经有一个可触发的过渡入口

没做到的：

1. 这不是正式的 CSR/ISA 入口
2. 它只覆盖 `FP32`
3. 它复用了 `mixed_precision` 这个旧字段，语义是临时借位，不可长期保留
4. 还没有补一条真正端到端的 fused top-level 功能用例

所以你要把它准确理解为：

“为了先打通融合路径，增加的一个临时 bridge 编码”

而不是：

“正式的命令接口设计已经完成”

### 6.25.4 这一步之后，最合理的下一步

现在最合理的下一步很明确：

1. 补一条端到端 fused top-level testcase
2. 证明 `FP32 + mixed_precision=1` 这个临时 bridge 入口，真的会走到：
   - `GEMM`
   - `fused EWISE`
   - `DMA_STORE`
3. 然后再回头把这个临时入口替换成正式可扩展的 host-visible 指令/CSR 写入接口

## 6.26 P2.4（继续推进）：补端到端 fused top-level testcase，并暴露出真实系统集成 bug

6.25 之后，入口桥接已经通了。  
下一步自然就是把它真正跑穿：

1. baseline GEMM
2. fused `GEMM -> EWISE(RELU) -> DMA_STORE`
3. 比较最终写回结果

### 6.26.1 为什么这一步不能再继续依赖旧 golden

原有 [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1) 的 `FP32` 校验能过，但它本质上容忍了现有主路径输出和 `.mem` 参考值之间的轻微 LSB 级差异。

这意味着：

如果直接拿 `.mem` 里的 reference 去做 fused `RELU`，你会混进两类问题：

1. 真正的 fused 路径问题
2. 原始 GEMM 主路径本来就存在的细小数值偏差

所以这一步我把 testbench 改成了“两阶段自校验”：

1. 先跑一次 baseline GEMM，记录硬件实际 `FP32` 输出
2. 再跑一次 fused 路径
3. 把第二次输出和“第一次输出逐元素做 `RELU`”比较

这样才能把问题聚焦到：

“融合链条本身有没有把 baseline 结果做对”

### 6.26.2 这一步具体改了什么

文件：[tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1)

这条 testbench 现在做的是：

1. 加载与 baseline GEMM 相同的 `FP32` 数据集
2. 第一轮用 `mixed_precision=0` 跑 baseline GEMM
3. 记录 baseline 的实际 `SRAM D -> AXI` 写回结果
4. 复位 DUT
5. 第二轮用 `FP32 + mixed_precision=1` 触发 bridge 编码后的 fused GEMM
6. 检查第二轮输出是否等于：
   - baseline 输出为负的元素 -> `0`
   - baseline 输出为非负的元素 -> 保持原值

为了让这条校验不再依赖 `real` 的奇怪转换路径，我还把这条 testbench 的 `FP32` 校验切成了：

1. 直接按 `32-bit` 位模式采集
2. 直接按 `32-bit` 位模式比较

这比旧 testbench 里 `real/$bitstoreal/$realtobits` 那套路径更接近硬件真实语义。

### 6.26.3 这一步验证得到了什么结果

结果分成两部分。

第一部分：现有子路径验证仍然成立

1. [tb_tpu_top_fp32_relu_fuse_bridge.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_fp32_relu_fuse_bridge.sv:1)
   - 通过
   - 说明 APB bridge 入口能把 `relu_fuse` 正确送进命令流
2. [tb_post_op_controller_fusion.sv](/home/yian/Prj/TPU/tb/sv/tb_post_op_controller_fusion.sv:1)
   - 通过
   - 说明融合调度骨架本身成立
3. [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)
   - 通过
   - 说明 `ewise_unit` 在独立环境里能对 `SRAM D` 物理行做 `FP32 RELU`
4. [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)
   - 通过
   - 说明非 fused 主路径没被打坏

第二部分：端到端 fused top-level 用例目前**不通过**

文件：[tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1)

当前结果是：

1. baseline 第一轮可正常跑完
2. fused 第二轮也可正常跑完
3. 但最终写回结果和“baseline-output RELU”不一致

而且不一致不是随机误差，而是**系统性的排布/覆盖错误**。

### 6.26.4 这一步暴露出的真实问题是什么

到这里可以明确说：

问题已经不是：

1. APB bridge 字段没送进去
2. `post_op_controller` 时序没接好
3. `ewise_unit` 单体不会做 `RELU`
4. 旧 golden 和当前硬件有 1 LSB 差异

这些都已经分别被排除了。

真正暴露出来的是：

1. `EWISE`
2. `SRAM D`
3. top 层仲裁/排布
4. write-back 读出路径

这四者组合起来的系统集成，还有一处真实 bug。

当前从波形外部表现看，它更像是：

1. 一部分 segment 被正确做了 `RELU`
2. 另一部分 segment 仍保留了原始 GEMM 输出
3. 或者部分物理行/segment 的覆盖顺序和预期不一致

也就是说：

这已经不是“文档还没写完”，而是一次被新回归用例实打实抓出来的系统级缺陷。

### 6.26.5 这一步之后怎么理解工程状态

现在工程状态要准确表述成：

1. 最小 ISA 控制骨架已建立
2. `GEMM / DMA_LOAD / DMA_STORE / BARRIER / EWISE` 都已经有真实路径
3. bridge 入口可以触发 fused GEMM
4. 但 fused top-level 还没有闭环

这很重要。

因为这意味着：

项目已经从“只有想法和骨架”进展到了“能用真实 regression 抓系统集成 bug”的阶段。

### 6.26.6 下一步最合理做什么

接下来最合理的不是继续加新功能，而是先把这条 fused e2e 用例转绿。

排查重点应该放在：

1. `EWISE` 对 `SRAM D` 的物理行/segment 访问规则
2. `SRAM D` 的 top 层仲裁
3. `sram_d_readback_active` 与 `writeback_start_pulse` 的交互
4. `matrix_adder` 真实写回排布和 `EWISE` 假设之间是否完全一致

### 6.26.7 继续诊断后，哪些假设已经被排除了

在继续 debug 这条 e2e 用例时，我又补了两类诊断：

1. 在 fused 运行中直接打印 `ewise_unit` 的实际配置
2. 在 testbench 里直接检查 `dut.sram_d.memory`

得到的结论非常关键：

1. `ewise_unit` 的配置是对的
   - `bursts_per_row = 2`
   - `max_rows = 16`
   - `active_mtype_sel = 3'b001`
2. 所以问题**不是**：
   - shape decode 错了
   - `mtype_sel` 锁错了
   - `EWISE` 被错误地当成 `m32` 或 `m8x32`
3. 同时，`dut.sram_d.memory` 在 fused 运行结束后就已经不满足“baseline-output RELU”
4. 所以问题也**不是**单纯 `axi_master` 把对的数据读错了

这把问题范围进一步缩小到了：

1. `EWISE` 自己如何从 `SRAM D` 读一整行
2. `EWISE` 什么时候把某个 segment 写回 `SRAM D`
3. top 层 `sram_d_addr / sram_d_wen / seg_sel / data_in` 的仲裁在 fused 场景下有没有产生实际的时序副作用

### 6.26.8 当时最值得继续查什么

到 6.26 结束时，下一轮 debug 的重点已经很明确：

1. `EWISE` 在跨物理行时拿到的 `row_buffer` 是否总是当前行
2. `sram_segsel` 的同步读写行为，是否会让 `EWISE` 在某些拍里读到旧行
3. `EWISE` 的最后一拍写和 top 层其它控制信号是否还存在覆盖窗口

也就是说：

当时最合理的下一步不是继续扩功能，而是把 `EWISE` 对 `SRAM D` 的真实时序彻底钉死。

## 6.27 P2.4（继续推进）：用最小 e2e 回归和新单测闭环修复 fused `EWISE` 写时序 bug

6.26 暴露出 fused top-level 结果错位后，我没有继续在原来的大 testbench 上盲调。  
我先做了两件更有效的事：

1. 新建最小 e2e 用例，把问题从历史验证代码里剥出来
2. 新建 `m16n16` 的 `ewise_unit` 单测，把 bug 钉在单体还是 top

### 6.27.1 为什么要再建一个“最小 e2e”用例

原来的 [tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1) 已经变成一个很重的调试平台：

1. 它混了很多历史通用验证代码
2. 它本身还存在对单周期脉冲的观测问题
3. 继续在它上面追 bug，很难第一时间分清楚是 DUT 问题还是 testbench 自己的问题

所以我新建了：

[tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1)

它只做这条最小主链路：

1. 跑一轮 baseline `FP32 GEMM`
2. 记录 baseline 实际写回 bit pattern
3. 复位
4. 跑一轮 fused `FP32 GEMM -> RELU -> DMA_STORE`
5. 逐元素比较 fused 输出是否等于 baseline 输出逐元素做 `RELU`
6. 再直接检查 `dut.sram_d.memory`

这个用例里不再依赖历史那套 `real/$bitstoreal/$realtobits` 通路，也不再依赖旧 golden。

### 6.27.2 最小 e2e 回归抓到了什么模式

这个最小用例第一次把错误模式打印得很清楚：

1. `EWISE` trace 在 `m16n16` 下表现为：
   - 原来错误版本里，显示出来是 `addr0/seg0 -> addr1/seg1 -> addr1/seg0 ...`
2. 最终 bitwise mismatch 不是随机噪声，而是高度结构化：
   - `col[8:15]` 会按行向下串移
3. `SRAM D` 物理行也不满足“baseline-output RELU”

这说明问题不是：

1. `RELU` 算错
2. `axi_master` 读回错行
3. `bridge` 字段错误

而是更基础的：

`EWISE` 自己写 `SRAM D` 的时序就已经错了。

### 6.27.3 为什么还要补一个 `m16n16` 的 `ewise_unit` 单测

原来已有 [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)，但它测的是：

1. `m8n32`
2. `4 segments/row`

它并不能覆盖这次 fused 路径里真正出错的 `m16n16`：

1. `2 segments/row`
2. 更容易暴露“segment 写入慢一拍”的问题

所以我新增了：

[tb_ewise_unit_relu_fp32_m16n16.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32_m16n16.sv:1)

这个单测只测最关键的两行、两段，结果一跑就失败：

1. `row0 segment1 relu result mismatch`

到这一步，问题边界就彻底清楚了：

1. 不是 top 层仲裁主因
2. 是 [ewise_unit.v](/home/yian/Prj/TPU/rtl/core/ewise_unit.v:1) 自己在 `m16n16` 下的写时序有问题

### 6.27.4 根因到底是什么

根因不是“数学变换错了”，而是 `SRAM D` 写接口的时序建模错了。

原先 `ewise_unit` 里：

1. `sram_d_wen`
2. `sram_d_addr`
3. `sram_d_seg_sel`
4. `sram_d_data_in`

都是在时钟过程里按 `state/row_idx/seg_idx` 赋值的寄存输出。

这对单口同步 `SRAM` 是有问题的，因为真正写内存时，`SRAM` 在这个时钟边沿采到的是：

1. 上一拍的 `addr`
2. 上一拍的 `seg_sel`
3. 上一拍的 `data_in`

所以实际效果变成：

1. `seg_idx` 已经推进到当前段
2. 但真正落到 `SRAM D` 的还是上一拍那组接口值

在 `m16n16` 的 `2 segments/row` 下，这会直接表现成：

1. `segment1` 写入错位
2. 高半段数据向下一行串移

### 6.27.5 修复方法是什么

修复不是继续在时钟过程里补丁式地“提前一拍改地址”，而是把接口语义改对。

我对 [ewise_unit.v](/home/yian/Prj/TPU/rtl/core/ewise_unit.v:1) 做了两件事：

1. 引入 `prefetch_addr`
   - 只负责“下一行同步读预取”
2. 把 `sram_d_wen / sram_d_addr / sram_d_seg_sel / sram_d_data_in`
   - 改成由当前 `state/row_idx/seg_idx` 驱动的组合输出

这样当前拍真正写 `SRAM D` 时，外部看到的是：

1. 当前 row
2. 当前 segment
3. 当前 transformed data

而不是上一拍残留值。

同时，`prefetch_addr` 继续负责在行切换时给同步读路径准备下一行地址，不破坏原来独立单测已经覆盖过的同步读行为。

### 6.27.6 修复后验证结果

修复后，我用本地 `vcs` 跑了四条回归：

1. [tb_ewise_unit_relu_fp32_m16n16.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32_m16n16.sv:1)
   - 通过
   - 说明 `m16n16` 的两段布局已经写对
2. [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)
   - 通过
   - 说明原来的 `m8n32` 覆盖没有被打坏
3. [tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1)
   - 通过
   - `SRAM D physical rows match baseline-output RELU expectation.`
   - `Verification passed: fused FP32 RELU output matches baseline-output RELU over all 256 elements.`
4. [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)
   - 通过
   - 说明非 fused baseline 主路径没被这次改动打坏

而且修复后的 `EWISE` trace 也从原来可疑的：

1. `addr0/seg0 -> addr1/seg1 -> addr1/seg0 ...`

变成了符合预期的：

1. `addr0/seg0 -> addr0/seg1 -> addr1/seg0 -> addr1/seg1 ...`

### 6.27.7 现在应如何理解 fused 路径状态

到这一步，状态要更新成：

1. fused `GEMM -> EWISE -> DMA_STORE` 路径已经在最小 e2e 用例上闭环通过
2. `EWISE` 的真实设计 bug 已被 regression 抓出并修掉
3. 原先那条 heavyweight fused testbench 仍然保留，但它已经不再是主判断依据

更准确地说：

当前推荐把 [tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1) 当作 fused 路径主回归基线。

### 6.27.8 这一步之后最合理的下一步

现在不该再把时间花在“证明 fused 路径能不能通”上了，因为它已经通了。

下一步最合理的是：

1. 把最小 fused e2e 用例正式纳入基线回归
2. 清理旧的 heavyweight fused testbench，把单周期脉冲观察改成 sticky/事件化观察
3. 继续向正式 host-visible 指令入口推进，替换现在的临时 APB bridge

## 6.28 P2.4（继续推进）：把最小 fused e2e 固化为正式回归基线，并隔离 `vcs` 编译数据库

6.27 把设计 bug 修完之后，下一步不该只是“知道它通了”，而是要把它固定成之后每次改 RTL 都会跑的一条正式基线。

### 6.28.1 为什么这一步有必要

前面已经踩过两个很具体的工程坑：

1. 并行跑多个 `vcs` 用例会冲突 `hsim.sdb/rmapats.so`
2. 旧的 heavyweight fused testbench 会因为历史验证逻辑过重而难以判断问题到底在 DUT 还是在 testbench

如果不把回归基线和回归入口工程化，后面每次改控制面、数据路、EWISE，都还会反复掉回这些非设计问题。

### 6.28.2 这一步具体改了什么

#### 1. 给 `run_vcs_tb.sh` 加独立 `-Mdir`

文件：[run_vcs_tb.sh](/home/yian/Prj/TPU/scripts/run_vcs_tb.sh:1)

这一步把每个 testbench 的增量编译目录固定到：

1. `${BUILD_DIR}/csrc`

作用是：

1. 不同 testbench 不再共享同一份 `vcs` 编译数据库
2. 以后即使需要并发调度，也不会像之前那样直接打架在全局 `csrc`

注意：

这不代表“现在可以放心并行跑一切用例”。  
它只是把最明显的数据库冲突隔离掉了。当前项目里，回归策略仍推荐串行。

#### 2. 新增最小串行回归脚本

文件：[run_vcs_regression_min.sh](/home/yian/Prj/TPU/scripts/run_vcs_regression_min.sh:1)

它当前固定串行跑 4 条最关键基线：

1. [tb_tpu_top_m16n16k16.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16.sv:1)
2. [tb_ewise_unit_relu_fp32.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32.sv:1)
3. [tb_ewise_unit_relu_fp32_m16n16.sv](/home/yian/Prj/TPU/tb/sv/tb_ewise_unit_relu_fp32_m16n16.sv:1)
4. [tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1)

这 4 条的覆盖含义分别是：

1. baseline GEMM 不回退
2. 原来的 `EWISE m8n32` 不回退
3. 新补的 `EWISE m16n16` 不回退
4. fused `GEMM -> EWISE -> DMA_STORE` 最小 e2e 不回退

#### 3. 给旧 heavyweight fused testbench 加 timeout

文件：[tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1)

这一步没有把它重写，而是先补了两件最低限度的工程保护：

1. `test_done`
2. 明确 timeout block

这样即使它后面再因为历史分支逻辑卡住，也不会继续长期占住 CPU 跑挂死的 `simv`。

### 6.28.3 本地验证结果

我本地直接跑了：

```bash
scripts/run_vcs_regression_min.sh
```

结果是：

1. `All minimal VCS regressions passed.`

这说明最小基线现在已经真正可以一键重放。

### 6.28.4 现在应该怎么看“两个 fused testbench”的角色

当前这两个 fused testbench 的角色已经分开了：

#### 主回归入口

[tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse_min.sv:1)

它的特点是：

1. 路径短
2. 只测核心语义
3. 适合作为每次 RTL 修改后的首选 fused 回归

#### 调试平台

[tb_tpu_top_m16n16k16_fp32_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_m16n16k16_fp32_relu_fuse.sv:1)

它的特点是：

1. 还保留大量历史验证逻辑
2. 输出更丰富
3. 更适合做 debug
4. 不适合再当作主判断依据

### 6.28.5 这一步之后最合理的下一步

现在最合理的下一步是继续把“临时入口”升级成正式接口，而不是继续在 fused 回归上打转。

也就是说，下一步优先级应该是：

1. 设计正式的 host-visible 指令/CSR 写入入口
2. 让 `command_queue` 不再只吃内部 `tpu_start -> GEMM bridge`
3. 把当前临时 `FP32 + mixed_precision=1 -> relu_fuse=1` 语义逐步退场

## 6.29 P2.4（继续推进）：给 `tpu_top` 增加正式直接命令入口，旧 bridge 退化为兼容路径

6.28 之后，最小 fused e2e 已经稳定了。  
接下来最自然的一步，就是把“命令入口”从：

1. 只能靠 `tpu_start + APB 配置`

推进到：

1. 有一个真正显式存在的指令输入口

### 6.29.1 为什么这一步先不做 APB 多字指令写入

原因很直接：你当前这个 APB 接口本身就不够做真正的多字指令 CSR。

[apb_config_reg.v](/home/yian/Prj/TPU/rtl/core/apb_config_reg.v:1) 现在只有：

1. `pwdata[6:0]`
2. 没有 `paddr`
3. 也没有寄存器索引空间

这意味着：

如果现在强行说“我要用 APB 下发 128-bit 指令”，那其实是在用一个并不具备地址能力的接口假装自己是寄存器文件。

这条路不对。

所以这一步我先做的是：

1. 给 `tpu_top` 增加正式直接命令口
2. 让它和现有 `command_queue` 对接
3. 保留旧 `tpu_start + APB` 入口作为兼容路径

也就是说：

这一步是先把“命令进入点”做对，而不是先把“命令从哪个总线写进来”做死。

### 6.29.2 这一步具体改了什么

#### 1. `tpu_top` 新增 direct command 入口

文件：[tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)

新增了 3 个端口：

1. `cmd_valid_i`
2. `cmd_ready_o`
3. `cmd_data_i[127:0]`

现在 `tpu_top` 的命令入口分成两条：

1. 旧入口：
   - `tpu_start + APB 配置`
   - 在 top 内部打包成 legacy bridge GEMM 命令
2. 新入口：
   - 外部直接给出 `128-bit` 指令
   - 直接送入 `command_queue`

#### 2. direct command 优先级高于 legacy bridge

这一步我明确规定了：

1. 如果 `cmd_valid_i=1`
2. 那就优先使用 `cmd_data_i`
3. 旧的 `tpu_start` bridge 本拍不再推命令

原因是：

1. 这样语义最清楚
2. 不需要在当前阶段做两个来源同时 push 的复杂仲裁
3. 也不会破坏旧 testbench，因为它们默认把 direct 入口绑成 `0`

#### 3. `cmd_ready_o` 的语义

当前：

1. `cmd_ready_o = command_queue.push_ready`
2. 只对 direct command 来源有效

也就是说，新的外部命令源现在第一次拥有了明确的 ready/valid 背压接口，而旧的 `tpu_start` 仍然是 legacy 脉冲语义。

这一步非常重要，因为它意味着：

后面新的 host/testbench/tooling 应该优先围绕 direct command 口构建，而不是继续围绕 `tpu_start`。

### 6.29.3 兼容性怎么处理

这一步我没有把老入口删掉。

相反，我做的是：

1. 所有已有 `tpu_top` testbench 都补了新端口连接
2. 默认把它们绑成：
   - `cmd_valid_i = 0`
   - `cmd_data_i = 0`

这样原有回归不需要改测试意图，就能继续沿 legacy 路径跑。

这一步的工程价值在于：

1. 新入口进来了
2. 旧回归不碎
3. 后续可以逐步把测试迁到新入口

### 6.29.4 这一步怎么验证

我做了两类验证。

#### 第一类：旧入口不回退

直接重跑了：

1. `scripts/run_vcs_regression_min.sh`

结果：

1. `All minimal VCS regressions passed.`

这说明新增 direct command 入口没有把：

1. baseline GEMM
2. `EWISE`
3. fused 最小 e2e

这些已有主路径打坏。

#### 第二类：新入口真的能绕开 APB bridge

新增测试：

[tb_tpu_top_direct_cmd_gemm_relu_fuse.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_gemm_relu_fuse.sv:1)

它直接送一条：

1. `opcode = GEMM`
2. `dtype = FP32`
3. `M/N/K = 16/16/16`
4. `relu_fuse = 1`

然后检查：

1. `cmd_ready_o` 会拉高
2. `command_decoder` 能正确解出 `gemm_relu_fuse`
3. `execution_controller` 能正确锁存 `active_gemm_relu_fuse`
4. 整个过程不依赖 APB `FP32 + mixed_precision=1` 这个旧桥接语义

本地 `vcs` 结果：

1. `Verification passed: direct command interface injects fused GEMM without APB bridge.`

另外，旧桥接测试：

[tb_tpu_top_fp32_relu_fuse_bridge.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_fp32_relu_fuse_bridge.sv:1)

也仍然通过，说明兼容路径还在。

### 6.29.5 到这一步，应该怎么重新理解工程状态

现在工程状态比 6.28 更进一步：

1. `command_queue` 不再只吃 top 内部临时 bridge 生成的命令
2. `tpu_top` 已经有了正式显式的 `128-bit` 命令输入口
3. 旧 `tpu_start + APB` 路径已经降级成兼容入口

这意味着：

项目第一次真正具备了“外部直接送指令”的结构基础。

虽然它现在还不是一个完整的 CSR/driver/runtime 体系，但至少控制边界已经是对的了。

### 6.29.6 这一步之后最合理的下一步

到这里，最合理的下一步已经很明确：

1. 基于 direct command 入口补一个真正的多 opcode top-level 测试序列
2. 让新的测试不再依赖 `tpu_start + APB` 旧桥接
3. 再往后，才是决定“正式 host-visible 入口最终落在 APB 扩展、独立 command port、还是别的总线”

也就是说：

下一步不该再围绕“bridge 怎么 hack 一下”打转，而该围绕：

“新的 direct command 入口，怎样承载真正的最小指令流”

## 7. 当前版本的控制流应该怎么理解

虽然我们已经引入了 `command_queue`，但当前版本仍然不是完整的通用指令执行器。

当前控制流可以理解为：

1. APB 先写配置寄存器
2. 外部给出 `tpu_start`
3. top 把当前配置打包成一条内部 `GEMM` 命令
4. 命令进入 `command_queue`
5. `command_decoder` 解析出 `opcode / M / N / K / dtype`
6. `execution_controller` 判断是否允许发射
7. 发射时锁存活动配置，并产生一次 `cmd_start_pulse`
8. `systolic_controller` 仍按旧的固定 FSM 执行一次 GEMM
9. 计算完成后，`axi_master` 按活动命令配置写回

这说明当前处于一个过渡阶段：

“旧控制器还在，但它前面已经加了一层命令化入口。”

## 8. 当前版本还没有做到什么

当前还没有做到的事情必须明确写清，否则会误以为工程已经完成了控制面升级。

目前还缺：

1. 真正的软件可见 128-bit 指令写入接口
2. 真正完整的 `execution_controller`
3. 把更多 legacy shape 逻辑从旧模块内部抽到共享映射层
4. 正式的软件可见多 opcode 命令写入接口
5. 端到端 fused top-level 功能用例
6. load / compute / store overlap
7. 更通用的 element-wise 单元
8. layout descriptor 和跨层驻留机制
9. 固定 shape 规则在 `axi_master / matrix_adder / matrix_adder_loader` 中的进一步集中化

## 9. 当前最重要的几个概念

如果你是初学者，先把下面几个概念建立起来。

### 9.1 `share_sram`

这是输入数据的共享缓冲区，外部通过 AXI Slave 写入这里。

### 9.2 SRAM A / B / C / D

- SRAM A：存放 A tile
- SRAM B：存放 B tile
- SRAM C：存放 C tile
- SRAM D：存放结果 tile

### 9.3 `mtype_sel`

这是当前旧架构里用来选择固定矩阵模式的信号。

当前只支持：

- `m16n16k16`
- `m32n8k16`
- `m8n32k16`

以后理想状态下，不应该再靠它直接决定所有硬件流程，而应该由命令里的 `M/N/K/tile` 字段驱动。

### 9.4 `command_queue`

它本质上就是“命令 FIFO”。

作用是把“外界要做什么”先缓存下来，再交给后面的译码器和执行器。

### 9.5 `command_decoder`

它负责把 128-bit 指令字拆成硬件内部可用的字段。

你可以把它理解成：

“把命令从二进制切片，翻译成控制面能消费的信息”

当前它还比较简单，但已经把 decode 这层从 top 层里剥出来了。

### 9.6 `execution_controller`

它负责处理“命令能不能发、发了之后把哪些配置锁住”。

当前你可以把它理解成：

“decode 后面的一层轻量执行发射器”

它存在的价值是把 `tpu_top` 从控制细节里继续解放出来。

### 9.7 `legacy_shape_codec`

它负责把“旧硬件支持的固定矩阵模式”和“命令里的 `M/N/K`”对应起来。

你可以把它理解成：

“旧世界 shape 编码 和 新世界命令字段 之间的翻译表”

它现在很重要，因为工程正处在“从固定 `mtype_sel` 过渡到显式 `M/N/K`”的阶段。

### 9.8 `vcs` 回归入口

它是当前工程最直接的“真实验收”方式。

你可以把它理解成：

“每做一步 RTL 改动后，快速检查工程是不是还真的能跑”

当前入口脚本是：

- [run_vcs_tb.sh](/home/yian/Prj/TPU/scripts/run_vcs_tb.sh:1)

### 9.9 `sram_d_readback_active`

它是这次 `m32n8k16` bug 修复里新引入的一个关键控制位。

作用是：

一旦进入 AXI write-back 阶段，就把 SRAM D 的所有权切给读侧，避免旧计算路径的残余写脉冲继续污染 `sram_d_addr`。

### 9.10 活动命令锁存

当前 top 里增加了：

- `active_mtype_sel`
- `active_dtype_sel`
- `active_mixed_precision`

它们的作用是：

当一条命令开始执行后，把这条命令对应的配置锁住，避免执行过程中外部重新写 APB 导致语义漂移。

## 10. 当前推荐阅读顺序

如果你现在要顺着代码学，按这个顺序看效率最高：

1. 先读本教学文档
2. 再读 [TPU_EXECUTION_PLAN.md](/home/yian/Prj/TPU/docs/TPU_EXECUTION_PLAN.md:1)
3. 再看 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)
4. 然后看 [command_queue.v](/home/yian/Prj/TPU/rtl/core/command_queue.v:1)
5. 再看 [command_decoder.v](/home/yian/Prj/TPU/rtl/core/command_decoder.v:1)
6. 再看 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)
7. 再看 [legacy_shape_codec.v](/home/yian/Prj/TPU/rtl/core/legacy_shape_codec.v:1)
8. 再看 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)
9. 最后再往 `sram_loader / systolic / matrix_adder / axi_master` 这些子模块钻

## 11. 后续维护规则

从现在开始，每完成一步升级，都必须同步更新这份文档，至少补充下面四类内容：

1. 这一步改了什么
2. 为什么要这么改
3. 改动涉及哪些模块
4. 改完之后，整个控制流或数据流发生了什么变化

如果未来你只想看一份文档来理解工程，就看这份：

- [TPU_TEACHING_GUIDE.md](/home/yian/Prj/TPU/docs/TPU_TEACHING_GUIDE.md:1)

## 6.30 P2.4（继续推进）：direct command 顶层多指令序列打通

这一阶段之前，我们已经有了两类 direct command 验证：

1. 一个 smoke test，证明 128-bit 命令能从 `tpu_top` 新入口进入 `command_queue / command_decoder / execution_controller`
2. 一条最小 fused e2e，用来证明 `GEMM -> fused EWISE -> writeback` 这条路径本身是通的

但这两者还不等价于“runtime 已经能在顶层顺序执行多条不同 opcode 命令”。

所以这一步的目标很明确：

- 不再依赖旧的 `tpu_start + APB` bridge
- 直接从 `cmd_valid_i/cmd_data_i` 入口送多条命令
- 在顶层验证它们的发射顺序和最终输出行为

### 1. 新增的顶层用例是什么

新增文件：

- [tb_tpu_top_direct_cmd_sequence.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_sequence.sv:1)

它做的事情是：

1. 先像旧 top-level testbench 一样，把 `A/B/C` 数据经 AXI Slave 写入 `share_sram`
2. 然后完全绕过 APB bridge，直接从 `cmd_data_i` 顺序下发四条命令：
   - `DMA_LOAD`
   - `GEMM(relu_fuse=1)`
   - `BARRIER`
   - `DMA_STORE`
3. 最后在 AXI Master 写回口上捕获两次写回事务：
   - 第 1 次：fused GEMM 自带的隐式写回
   - 第 2 次：显式 `DMA_STORE` 写回
4. 比较两次写回的 256 个元素是否完全一致

这个检查的含义是：

- 前一条 `GEMM(relu_fuse)` 生成的片上 `SRAM D` 结果
- 能被后面的 `BARRIER`
- 再被后面的显式 `DMA_STORE`
- 按顺序、无污染地重新写回出去

这已经是一个真正的“多 opcode 顶层序列”验证了。

### 2. 这一步为什么没有直接做 `DMA_LOAD -> GEMM -> EWISE -> DMA_STORE`

因为当前 `GEMM` 这条 legacy 路径本身还自带 writeback 语义。

如果立刻做显式 `EWISE` 链条，验证关注点会被两件事混在一起：

1. legacy GEMM 固有的自动 writeback
2. 显式 `EWISE/DMA_STORE` 的再处理路径

所以这一轮先选了一个更稳妥的序列：

- `DMA_LOAD -> GEMM(relu_fuse) -> BARRIER -> DMA_STORE`

这样可以先回答两个更基础的问题：

1. 顶层 direct command 顺序调度是不是通的
2. 同一份 fused 结果，隐式写回和后续显式 `DMA_STORE` 写回是不是一致

把这一步打通后，下一步再补“显式 `EWISE` opcode 链”会更干净。

### 3. 这一步踩到的坑：不是 RTL bug，而是 testbench 握手 bug

这一步第一次跑挂的时候，现象很像：

- `DMA_LOAD` 被重复 issue
- `cmd_queue_level` 也出现异常增长

一开始很容易误判成 `command_queue` 或 `execution_controller` 有 bug。

但最后定位下来，真正的原因是：

- testbench 里的 `send_direct_cmd` task 把 `cmd_valid_i` 多保持了一个周期
- 结果每条 direct command 都被重复入队

这个坑的教学价值很高，因为它说明：

- 你看到“命令重复执行”时，不能立刻假设 RTL 有 bug
- testbench 自己的握手时序也可能制造完全一样的假象

修复后，这条用例已经稳定通过。

### 4. 这一步完成后，direct command 入口达到了什么程度

现在 direct command 入口已经有三层验证：

1. smoke：能不能进来
2. single fused e2e：一条 fused GEMM 能不能跑通
3. multi-op top-level sequence：多条 opcode 能不能在顶层按顺序执行

所以现在你可以把 `cmd_valid_i/cmd_data_i` 理解成：

“一个已经能承载最小 runtime 流程的正式命令入口”

它还不是最终的软件接口形态，但已经不再只是 demo 级占位接口。

### 5. 本地 `vcs` 结果

这一步完成后，已通过：

- `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_sequence`
- `scripts/run_vcs_regression_min.sh`

其中新的关键通过信息是：

- `Verification passed: direct command sequence DMA_LOAD -> GEMM(relu_fuse) -> BARRIER -> DMA_STORE issued in order and both writebacks match.`

### 6. 当前还没解决的问题

这一步完成，不代表 direct command runtime 已经完全成熟。

当前还没做的事情包括：

1. 还没有一条显式 `DMA_LOAD -> GEMM -> EWISE -> DMA_STORE` 顶层链路
2. 还没有基于 `dep_in/dep_out` 的真正 token 依赖调度
3. `run_vcs_regression_min.sh` 还没有升级成严格日志失败检测脚本

所以当前 direct command 入口的状态应该被准确描述为：

- 已经能跑最小多 opcode 顶层序列
- 但还不是完整 runtime

## 6.31 P2.4（继续推进）：显式 `EWISE opcode` 顶层链路与 fused 路径正式分开验证

在上一阶段，我们已经有了一条 direct-command 多指令序列：

- `DMA_LOAD -> GEMM(relu_fuse) -> BARRIER -> DMA_STORE`

它证明的是：

- fused GEMM 的结果可以在顶层命令流里继续被后续显式 `DMA_STORE` 消费

但它仍然没有回答一个更重要的问题：

- standalone `EWISE opcode` 自己能不能在顶层 runtime 序列里独立工作？

所以这一阶段专门做了“显式 `EWISE`”的顶层链路。

### 1. 新增的顶层用例是什么

新增文件：

- [tb_tpu_top_direct_cmd_explicit_ewise.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_explicit_ewise.sv:1)

它做的事情是：

1. 先把 `A/B/C` 数据写进 `share_sram`
2. 然后直接从 `cmd_valid_i/cmd_data_i` 入口顺序下发：
   - `DMA_LOAD`
   - `GEMM`
   - `BARRIER`
   - `EWISE`
   - `BARRIER`
   - `DMA_STORE`
3. 抓取两次 AXI Master 写回：
   - 第 1 次是 baseline `GEMM` 输出
   - 第 2 次是显式 `EWISE + DMA_STORE` 输出
4. 检查：
   - 第 2 次写回是否等于“第 1 次写回逐元素做 `RELU`”

这个检查非常关键，因为它把两条 post-op 路径正式分开了：

1. fused 路径：`GEMM(relu_fuse)` 内部自动触发 `EWISE`
2. explicit 路径：先 baseline `GEMM`，再由独立 `EWISE opcode` 做片上后处理

### 2. 为什么这里要加两个 `BARRIER`

因为当前 runtime 还没有真正的 `dep_in/dep_out token` 依赖机制。

所以在 direct-command 顶层序列里，如果想让验证语义清楚，就需要用 `BARRIER` 做最小顺序约束：

1. 第一个 `BARRIER`：把 baseline `GEMM` 和后续 `EWISE` 分开
2. 第二个 `BARRIER`：把 `EWISE` 和后续 `DMA_STORE` 分开

这不是最终 ISA/runtime 的理想调度方式，但非常适合作为当前阶段的顶层验证脚手架。

### 3. 这一阶段踩到的坑

这一步第一次跑的时候，失败信息是：

- 第二个 `BARRIER` 顺序不符合 testbench 预设

最后确认，这不是 RTL bug，而是 testbench 把第二个 `BARRIER` 的允许状态写得过死了。

实际情况是：

- `EWISE` 已经正常发射
- 第二个 `BARRIER` 正是在 `EWISE` 后面出现
- 这是完全符合这条命令流语义的

所以这一步再次提醒一个很重要的工程判断原则：

- testbench 里的“顺序模型”也可能写错
- 不能因为顺序断言失败，就直接判 RTL 有 bug

### 4. 这一步完成后，工程状态发生了什么变化

完成这一步之后，你可以把当前工程里的 post-op 能力准确理解成：

1. 既支持 fused post-op
2. 也支持 explicit post-op opcode
3. 两条路径都已经有顶层 `vcs` 回归

也就是说，现在 `EWISE` 已经不只是：

- unit test 能跑
- 控制器单测能发

而是真正进入了：

- top-level command runtime sequence

### 5. 本地 `vcs` 结果

这一步完成后，已通过：

- `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_explicit_ewise`
- `scripts/run_vcs_regression_min.sh`

新用例的关键信息是：

- `Verification passed: direct command sequence DMA_LOAD -> GEMM -> BARRIER -> EWISE -> BARRIER -> DMA_STORE matches baseline-output RELU.`

### 6. 当前最重要的阶段结论

到这里为止，`P2.4` 已经不只是“控制骨架重构”了，而是已经拿到了一套很实在的最小 runtime 证据：

1. 命令能排队
2. 命令能解码
3. 不同 opcode 能按顺序在顶层发射
4. fused 路径可用
5. explicit `EWISE` 路径也可用

这意味着，下一步如果继续留在 `P2`，最自然的方向就是：

- 把 `dep_in/dep_out` 从占位字段推进成真正依赖机制

如果转入 `P3`，最自然的方向就是：

- 把已经存在的 fused/explicit 两条路径，纳入带宽复用和 performance 分析

## 6.32 P2.4（继续推进）：`dep_in/dep_out` 从占位字段变成可工作的最小依赖机制

前面几步里，ISA 和 `command_decoder` 其实已经有了：

- `dep_in`
- `dep_out`

但在那之前，它们只是：

- 文档里有定义
- 命令字里有字段
- `decoder` 能切出来

并没有真正进入运行时控制。

所以这一阶段做的事情，本质上就是把这两个字段从“名义存在”推进成“真正生效”。

### 1. 这一步到底做了什么

核心改动在 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)。

新增了三类状态：

1. `cmd_dep_in/cmd_dep_out`
2. `active_dep_out`
3. `completed_token / completed_token_valid`

新的最小语义是：

1. 如果一条命令 `dep_in == 0`，它没有依赖
2. 如果 `dep_in != 0`，那么只有当：
   - `completed_token_valid == 1`
   - 且 `completed_token == dep_in`
   才允许它 issue
3. 一条命令完成时，如果 `dep_out != 0`，就把这个 token 发布为新的 `completed_token`
4. `BARRIER` 因为是立即完成 opcode，所以它也可以立即发布 token

这是一种非常简化的 token 依赖机制，但已经足够让命令之间产生真正的“前后约束”。

### 2. 为什么我先做“单 token”，而不是直接做完整 scoreboard

因为当前工程仍然是：

- 单 inflight command
- FIFO 顺序 issue

在这种前提下，先做完整多 token scoreboard，收益不高，复杂度却会上升很多。

所以这一阶段选的是最务实的版本：

- 先做一个单 token 的最小依赖机制
- 让 `dep_in/dep_out` 真正进入运行时控制
- 把从 ISA 到 runtime 的链路先打通

等后面确实需要：

- 更复杂的 DAG 依赖
- 多 inflight
- 更细粒度调度

再升级成真正 scoreboard 会更合理。

### 3. 这一步做了两层验证

#### 3.1 unit 级验证

新增：

- [tb_execution_controller_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dep_tokens.sv:1)

这条用例验证的是最关键的控制语义：

1. 一个 `DMA_STORE`，如果 `dep_in=0x33` 而 token 还没出现，就不能 issue
2. 一个 `BARRIER(dep_out=0x33)` 可以立即发布 token
3. token 出现后，前面的 `DMA_STORE(dep_in=0x33)` 才会变得可 issue
4. `DMA_STORE` 完成后还能继续发布自己的 `dep_out`

也就是说，它证明了：

- 依赖 gating 不是摆设，而是真正会卡住 issue

#### 3.2 top-level 级验证

新增：

- [tb_tpu_top_direct_cmd_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_dep_tokens.sv:1)

这条用例直接从 `cmd_valid_i/cmd_data_i` 入口下发：

- `DMA_LOAD(dep_out=0x11)`
- `GEMM(dep_in=0x11, dep_out=0x22)`
- `EWISE(dep_in=0x22, dep_out=0x33)`
- `DMA_STORE(dep_in=0x33, dep_out=0x44)`

注意，这条链路里：

- 没有再插 `BARRIER`

也就是说，它证明了：

- 当前 top-level direct command runtime 已经可以靠 `dep_in/dep_out` 自己串起一条最小命令链

### 4. 这一步为什么很重要

在这一步之前，你的 runtime 更像：

- 一个严格按 FIFO 顺序做事的轻量控制器

在这一步之后，它已经开始具备：

- 明确的命令间依赖语义

虽然现在还是最小版本，但它有一个非常重要的意义：

- 从 ISA 到 runtime 的“依赖字段”已经闭环

这让你后面在架构报告里谈：

- `BARRIER`
- command dependency
- layer fusion 的前后约束
- 为什么有些命令必须等前面结果 ready

就不再只是概念设计，而是已经有 RTL 和回归支撑。

### 5. 本地 `vcs` 结果

这一步完成后，已通过：

- `scripts/run_vcs_tb.sh tb_execution_controller_dep_tokens`
- `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_dep_tokens`
- `scripts/run_vcs_regression_min.sh`

其中新的关键通过信息有两条：

1. `Verification passed: execution_controller enforces dep_in/dep_out tokens.`
2. `Verification passed: dep-token direct command sequence DMA_LOAD -> GEMM -> EWISE -> DMA_STORE matches baseline-output RELU without BARRIER.`

### 6. 当前边界

要准确理解，这一步并不等于“完整 runtime 依赖系统已经完成”。

当前仍然只是：

1. 单 inflight command
2. FIFO 顺序 issue
3. 单 completed token 记录

所以它还不支持：

- 多 token 并存
- 任意 DAG 依赖
- 更复杂的 scoreboard

但作为当前阶段，这已经足够回答一个很重要的问题：

- 你的 `dep_in/dep_out` 不是空话，已经进入 RTL 的实际执行路径

## 6.33 P2.4（继续推进）：从“最近 token”升级到最小多 token scoreboard

上一阶段里，`dep_in/dep_out` 已经进入了真实执行路径，但当时还是一个非常简化的版本：

- 只有 `completed_token`
- 也就是“只记住最近一次发布的 token”

这个版本能工作，但有一个明显问题：

- 如果先发布 `0x11`
- 再发布 `0x55`
- 那么依赖 `0x11` 的后续命令就会被错误挡住

因为控制器只记得“最后一个 token 是 0x55”，却忘了 `0x11` 曾经也已经完成过。

所以这一阶段的核心改动，就是把它升级成一个最小 scoreboard。

### 1. 这一步到底改了什么

核心改动仍然在 [execution_controller.v](/home/yian/Prj/TPU/rtl/core/execution_controller.v:1)。

新增状态：

- `completed_token_bitmap[255:0]`

新的依赖判定不再是：

- `completed_token == cmd_dep_in`

而是：

- `completed_token_bitmap[cmd_dep_in] == 1`

也就是说：

1. 一条命令完成，只要它发布了非零 `dep_out`
2. 对应 token 的 bit 就会被置位
3. 后续命令只要 `dep_in` 对应的 bit 已经置位，就允许 issue

这样一来，就不怕“旧 token 被新 token 覆盖”。

### 2. 为什么还保留 `completed_token/completed_token_valid`

虽然现在真正的依赖判定已经改用 bitmap，但我没有把：

- `completed_token`
- `completed_token_valid`

删掉。

原因很简单：

- 它们仍然是非常好用的调试出口

你在 testbench 或 debug 时，仍然经常想知道：

- “最近一次发布的 token 是什么”

所以这两个信号保留下来，作为：

- 最近一次 token 发布事件的观测接口

而真正的依赖 gating，则交给 bitmap。

### 3. 这一步怎么验证的

#### 3.1 unit 级验证

更新：

- [tb_execution_controller_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_execution_controller_dep_tokens.sv:1)

这条用例现在覆盖了一个比之前更强的场景：

1. 先发布 token `0x33`
2. 再发布 token `0x55`
3. 然后验证：依赖 `0x33` 的 `DMA_STORE` 仍然可以 issue

这个场景非常关键，因为它证明：

- 依赖判定已经不再是“只看最近 token”

#### 3.2 top-level 级验证

更新：

- [tb_tpu_top_direct_cmd_dep_tokens.sv](/home/yian/Prj/TPU/tb/sv/tb_tpu_top_direct_cmd_dep_tokens.sv:1)

新的顶层链路变成：

- `DMA_LOAD(dep_out=0x11)`
- `EWISE(dep_in=0x11, dep_out=0x55)`
- `GEMM(dep_in=0x11, dep_out=0x22)`
- `EWISE(dep_in=0x22, dep_out=0x33)`
- `DMA_STORE(dep_in=0x33, dep_out=0x44)`

这里最关键的一步是：

- `GEMM` 依赖的是 `0x11`
- 但在它 issue 之前，最近一次发布的 token 已经被第一条 `EWISE` 改成了 `0x55`

如果控制器还是旧逻辑，`GEMM` 会被挡住。 
现在它仍然能正常 issue，这就说明：

- `0x11` 还保留在 scoreboard 里

这正是这一步最重要的证据。

### 4. 这一步完成后，runtime 的性质发生了什么变化

这一步之后，当前 runtime 不再只是：

- “带一个最近 token 寄存器的串行控制器”

而是已经具备了：

- “最小依赖 scoreboard”

虽然它还很简单，但这是一个明显的架构分水岭。

因为从这里开始，你在设计说明里谈：

- 命令依赖
- 跨命令同步
- 为什么某条命令能在新的 token 发布后仍然满足旧依赖

就已经不再是概念，而是有 RTL 和回归证明的。

### 5. 当前边界

这一步仍然不是“完整 dependency runtime”。

当前 scoreboard 还有几个明确限制：

1. token 一旦置位，会一直保留到复位
2. 不支持 token 回收
3. 不支持更复杂的生命周期管理
4. 仍然只有单 inflight command

所以当前更准确的定位是：

- 最小多 token scoreboard

不是：

- 完整命令调度器

### 6. 本地 `vcs` 结果

这一步完成后，已通过：

- `scripts/run_vcs_tb.sh tb_execution_controller_dep_tokens`
- `scripts/run_vcs_tb.sh tb_tpu_top_direct_cmd_dep_tokens`
- `scripts/run_vcs_regression_min.sh`

新的关键验证点是：

- 即使最近 token 已经变成别的值，旧 token 对应的依赖仍然能命中

## 6.34 从 P2 切到 P3：先建立统一流量模型，再谈 layout 和复用

从这一刻开始，主线已经从“控制面和最小 runtime 能不能跑起来”，切到“这些命令流到底搬了多少数据、为什么会卡带宽”。

这里要注意一个常见误区：

- 不能一进入 P3 就直接画 bank 图、讲 ping-pong、讲跨层驻留
- 如果你连当前几条真实执行流到底各搬多少字节都没量化，后面的 tradeoff 很容易变成空话

所以 P3 的第一步，我没有马上改 RTL，而是先做了一个统一流量模型。

### 1. 新增了什么

新增脚本：

- [runtime_flow_model.py](/home/yian/Prj/TPU/scripts/utils/runtime_flow_model.py:1)

新增报告：

- [P3_RUNTIME_FLOW_ANALYSIS.md](/home/yian/Prj/TPU/docs/P3_RUNTIME_FLOW_ANALYSIS.md:1)

它们不是在分析“理想 TPU 应该怎么做”，而是在分析：

- 你当前这个工程里已经真实存在的四条执行流

### 2. 当前纳入比较的四条执行流

#### 2.1 `baseline_gemm`

- `DMA_LOAD -> GEMM(writeback)`

含义：

- 把 `A/B/C` 装进片上
- 算完
- 把结果写回一次

#### 2.2 `fused_gemm_relu`

- `DMA_LOAD -> GEMM(relu_fuse) -> implicit EWISE -> writeback`

含义：

- `RELU` 在片上做完后再写回
- 不需要为 post-op 再多做一次 off-chip 输出回写

#### 2.3 `explicit_ewise`

- `DMA_LOAD -> GEMM(writeback) -> EWISE -> DMA_STORE`

含义：

- baseline `GEMM` 先写回一次
- 再在片上做 `EWISE`
- 然后显式 `DMA_STORE` 再写回一次

#### 2.4 `dep_token_explicit_ewise`

- 控制上和 `explicit_ewise` 类似
- 只是顺序约束从 `BARRIER` 换成 `dep_in/dep_out`

关键点：

- 它改善的是控制语义
- 不是外存流量

### 3. 第一版模型得出的结论是什么

当前 `m16n16k16 fp32` 的结果是：

- `baseline_gemm`: `4096 B`
- `fused_gemm_relu`: `4096 B`
- `explicit_ewise`: `5120 B`
- `dep_token_explicit_ewise`: `5120 B`

这几个数字很重要，因为它们直接把前面很多“架构直觉”落成了定量结论：

1. `fused_gemm_relu` 和 baseline 的 off-chip 流量一样
2. 但 fused 路径做了更多有用工作
3. `explicit_ewise` 比 fused 多一次输出写回
4. 所以 explicit 路径更通用，但也更吃带宽
5. `dep_token` 改进的是 runtime 语义，不直接省字节

这就是 P3 应该讲的第一层 tradeoff：

- fusion 的价值，不只是“更高级”
- 而是“在当前实现下，它明确减少了外存 traffic”

### 4. 为什么这一步对后面的 layout/bank 很重要

后面你要讨论：

- 数据排布
- SRAM bank 组织
- ping-pong
- 片上驻留
- load/compute/store overlap

这些都必须围绕一个核心问题：

- 你到底想减少哪一类 traffic？

如果前面没有把 baseline / fused / explicit 三条路径的流量差异定量写清楚，那么后面谈“某个 bank 设计更好”就没有参照物。

所以这一步虽然没有改 RTL，但它实际上是在给后续 P3 RTL 改造立评价标准。

### 5. 当前这份 P3 模型的边界

这一步也要准确理解它没做什么。

当前模型还没有覆盖：

1. bank conflict
2. SRAM 端口争用
3. 片上带宽上界
4. overlap 调度开销
5. token/buffer 管理开销

它目前只覆盖：

- 外存 traffic
- roofline 上界
- 不同执行流的相对优劣

所以它是：

- P3 的第一层模型

不是：

- 完整系统性能模型

### 6. 这一步后，最自然的下一步是什么

有了这份流量基线之后，最自然的下一步就是：

- 进入 `P3.1`，定义 layout descriptor

因为只有先把 layout 说清楚，你才能继续回答：

1. `A/B/C/D` 在片上到底怎么排
2. 为什么某些 tile 能 reuse
3. 为什么 fused 路径能少一次输出流量
4. 哪些中间结果应该驻留在片上

也就是说，P3 的顺序现在已经清楚了：

1. 先统一流量模型
2. 再做 layout descriptor
3. 再谈 bank / ping-pong / overlap / residency
