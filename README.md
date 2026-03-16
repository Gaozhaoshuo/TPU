# TPU Project

## 项目定位

当前工程实现的是一个面向固定矩阵模式的片上 GEMM 加速器，并以此为基础逐步演进为可编程 TPU/NPU 核。

当前 RTL 已具备完整的主路径：

1. AXI Slave 写入 `share_sram`
2. 控制器把 A/B/C 搬运到本地 SRAM
3. `8x8` systolic array 完成乘加
4. `matrix_adder` 完成 `A * B + C`
5. 结果写入 SRAM D
6. AXI Master 输出结果

## 目录结构

- `rtl/core/`：核心 RTL
- `tb/sv/`：基础 testbench
- `dv/uvm/`：UVM 验证环境
- `scripts/utils/`：数据处理、性能模型、批量脚本
- `data/dataset/`：测试数据集
- `docs/`：架构分析、路线图、执行计划、性能报告

## 关键模块

- [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)：top 级集成
- [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)：主控制器
- [sram_loader.v](/home/yian/Prj/TPU/rtl/core/sram_loader.v:1)：A/B/C 装载
- [systolic_input_loader.v](/home/yian/Prj/TPU/rtl/core/systolic_input_loader.v:1)：阵列输入地址调度
- [systolic.v](/home/yian/Prj/TPU/rtl/core/systolic.v:1)：`8x8` systolic 阵列
- [matrix_adder_loader.v](/home/yian/Prj/TPU/rtl/core/matrix_adder_loader.v:1)：C 矩阵读取与对齐
- [matrix_adder.v](/home/yian/Prj/TPU/rtl/core/matrix_adder.v:1)：输出加法与写回地址生成
- [axi_slave.v](/home/yian/Prj/TPU/rtl/core/axi_slave.v:1)：输入写通路
- [axi_master.v](/home/yian/Prj/TPU/rtl/core/axi_master.v:1)：输出写回通路

## 当前执行流

当前控制流是固定的，不是指令流：

1. 通过 APB 配置 `mtype_sel / dtype_sel / mixed_precision`
2. 通过 AXI Slave 把输入矩阵写入 `share_sram`
3. 拉高 `tpu_start`
4. 控制器按固定 FSM 完成 load -> compute -> write-back
5. `tpu_done` 表示计算结束脉冲
6. `send_done` 表示 AXI 写回结束脉冲

## 当前工程假设

- 当前 simple testbench 与 UVM 顶层默认 `clk` 与 `pclk` 同频
- 当前 `tpu_done` 与 `send_done` 都是单周期脉冲，不是寄存器状态位
- 当前 `axi_target_addr` 与 `axi_lens` 在 top 层仍是常量
- 当前只支持三种固定矩阵模式：
  - `m16n16k16`
  - `m32n8k16`
  - `m8n32k16`

## 当前限制

- 还没有 command queue / ISA 执行框架
- shape、地址、layout 在多个模块中硬编码
- load / compute / store 基本串行
- 还没有 element-wise 单元和融合执行路径
- 如果未来 `pclk` 与 `clk` 变成异步，需要补 CDC 处理

## 关键文档

- [TPU_TEACHING_GUIDE.md](/home/yian/Prj/TPU/docs/TPU_TEACHING_GUIDE.md:1)：升级后工程的主教学文档
- [TPU_EXECUTION_PLAN.md](/home/yian/Prj/TPU/docs/TPU_EXECUTION_PLAN.md:1)：逐步推进执行计划
- [TPU_IMPROVEMENT_REPORT.md](/home/yian/Prj/TPU/docs/TPU_IMPROVEMENT_REPORT.md:1)：架构问题分析与改进计划报告
- [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:1)：ISA 初稿
- [PERF_BASELINE.md](/home/yian/Prj/TPU/docs/PERF_BASELINE.md:1)：性能 baseline
- [PROJECT_ROADMAP.md](/home/yian/Prj/TPU/docs/PROJECT_ROADMAP.md:1)：阶段路线图

## 当前建议阅读顺序

1. 先读 [TPU_TEACHING_GUIDE.md](/home/yian/Prj/TPU/docs/TPU_TEACHING_GUIDE.md:1)
2. 再读 [TPU_EXECUTION_PLAN.md](/home/yian/Prj/TPU/docs/TPU_EXECUTION_PLAN.md:1)
3. 再读 [TPU_IMPROVEMENT_REPORT.md](/home/yian/Prj/TPU/docs/TPU_IMPROVEMENT_REPORT.md:1)
4. 然后看 [tpu_top.v](/home/yian/Prj/TPU/rtl/core/tpu_top.v:1)
5. 再看 [systolic_controller.v](/home/yian/Prj/TPU/rtl/core/systolic_controller.v:1)
6. 最后看 `load / compute / write-back` 相关子模块
