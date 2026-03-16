# Command Queue 接口草案

## 1. 目的

`command_queue` 作为控制面的第一步抽象，负责把软件下发的命令缓存起来，并以稳定的 ready/valid 接口送给后续指令译码与执行模块。

这一阶段的目标不是立即替换原有 `systolic_controller`，而是先把“命令入口”标准化。

## 2. 设计原则

1. 先支持单队列、顺序执行
2. 与 [ISA_v0.1.md](/home/yian/Prj/TPU/docs/ISA_v0.1.md:1) 对齐，命令宽度固定为 `128-bit`
3. 使用标准 `push` / `pop` ready-valid 风格接口
4. 增加最小状态可观测性：`empty/full/level`

## 3. 模块定位

建议放在控制面结构中：

`host / runtime -> command_queue -> command_decoder -> execution_controller`

当前阶段只实现：

`host / runtime -> command_queue`

## 4. 接口定义

### 4.1 输入侧（软件或寄存器桥）

- `push_valid`：命令写入请求有效
- `push_ready`：队列可以接收新命令
- `push_data[127:0]`：命令字

握手规则：

- `push_valid && push_ready` 时写入 1 条命令

### 4.2 输出侧（译码器或执行器）

- `pop_valid`：当前队首命令有效
- `pop_ready`：下游愿意接收命令
- `pop_data[127:0]`：当前队首命令

握手规则：

- `pop_valid && pop_ready` 时弹出 1 条命令

### 4.3 状态信号

- `empty`
- `full`
- `level`

建议 `level` 宽度为 `$clog2(DEPTH + 1)`

## 5. 参数

- `CMD_WIDTH = 128`
- `DEPTH = 8` 或 `16`

第一版建议默认 `DEPTH = 8`，足够做最小命令串测试。

## 6. 当前阶段约束

当前 `command_queue` 只解决“缓存与交付”，不解决：

- opcode 解析
- token 依赖判断
- 多发射
- load/compute/store 多队列拆分

这些内容放到后续 `command_decoder` 和 `execution_controller` 里做。

## 7. 与现有 RTL 的关系

当前工程里还没有真正的指令流，因此 `command_queue` 暂时不会接入 `tpu_top` 主路径。

当前阶段的作用是：

1. 固定控制面接口边界
2. 降低后续 P2.2/P2.3 推翻重来的概率
3. 为后续替换固定 FSM 做准备

## 8. 后续演进方向

后续可以按下面顺序扩展：

1. `command_queue`
2. `command_decoder`
3. `execution_controller`
4. 逐步接管 `DMA_LOAD / GEMM / EWISE / DMA_STORE / BARRIER`

## 9. 当前结论

这一阶段完成的标志不是“已经可运行完整 TPU 指令流”，而是：

- 队列接口已经稳定
- 命令格式已经和 ISA 对齐
- 后续控制面升级有了明确入口
