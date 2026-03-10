# tpu_simulation.tcl

# 禁用所有交互式对话框（增强设置）
set EnableInteractive 0
set PrefMain(ExitOnFinish) 1  ;# 自动退出仿真完成提示
set PrefMain(ExitConfirm) 0   ;# 禁用退出确认
set PrefMain(AutoSaveOnExit) 0 ;# 禁用自动保存提示
set PrefMain(SaveOnExit) 0     ;# 禁用保存项目提示
set PrefMain(CloseProjectOnExit) 0 ;# 禁用关闭项目提示

# 定义基础仿真命令（强制非交互模式）
set coverage_dir "D:/1Study_work/UVM/TPU/UVM/cover_sum"
set base_cmd "vsim -batch -novopt -classdebug +UVM_TESTNAME=tpu_case%s_test -coverage -coverstore %s -testname tpu_case%s_test -l %s/tpu_case%s_test.log work.tb"

# 设置工作目录
set work_dir "D:/1Study_work/ver_test_top/p1"
if {[file exists $work_dir]} {
    cd $work_dir
    echo "当前工作目录已设置为: [pwd]"
} else {
    error "工作目录 $work_dir 不存在，请检查路径！"
}

# 创建日志目录（如果不存在）
set log_dir "$work_dir/logs"
if {![file exists $log_dir]} {
    file mkdir $log_dir
    echo "创建日志目录: $log_dir"
}

# 初始化错误统计变量
set uvm_error_count 0
set uvm_error_details [list]

# 循环运行0到17的测试用例
for {set i 0} {$i < 18} {incr i} {
    # 生成测试标识
    set test_name [format "tpu_case%d_test" $i]
    
    # 构建仿真命令（修正参数数量）
    set sim_cmd [format $base_cmd $i $coverage_dir $i $log_dir $i]
    
    # 打印当前测试用例
    echo "=================================="
    echo "运行测试用例: $test_name"
    echo "=================================="

    # 启动仿真并自动运行
    if {[catch {
        # 启动仿真
        echo "启动仿真: $sim_cmd"
        eval $sim_cmd
        
        # 配置 onbreak 和 onerror
        onbreak {
            echo "检测到断点，自动继续..."
            resume
        }
        onerror {
            echo "发生错误，自动继续..."
            resume
        }
        
        # 运行直到完成
        echo "运行仿真..."
        run -all
        
        # 仅结束当前仿真，不关闭项目
        echo "结束仿真: $test_name"
        quit -sim
        
        # 解析日志文件以查找 uvm_error
        set log_file "$log_dir/tpu_case${i}_test.log"
        if {[file exists $log_file]} {
            set fp [open $log_file r]
            set log_content [read $fp]
            close $fp
            
            # 按行分割日志内容
            set lines [split $log_content "\n"]
            foreach line $lines {
                # 检查是否包含 UVM_ERROR
                if {[string match "*UVM_ERROR*" $line]} {
                    incr uvm_error_count
                    lappend uvm_error_details "UVM_ERROR in $test_name: $line"
                }
            }
        } else {
            echo "警告: 日志文件 $log_file 不存在，跳过错误检查"
        }
        
    } error_msg]} {
        echo "ERROR in $test_name: $error_msg"
    }
}

# 打印完成信息
echo "=================================="
echo "所有测试用例仿真完成。"
echo "=================================="

# 合并覆盖率数据
echo "开始合并覆盖率数据..."
if {[file exists $coverage_dir] && [llength [glob -nocomplain $coverage_dir/*]] > 0} {
    vcover merge -out [file join $coverage_dir "merged_coverage.ucdb"] $coverage_dir
    echo "覆盖率合并完成，文件已保存至: [file join $coverage_dir "merged_coverage.ucdb"]"
} else {
    echo "警告: 覆盖率目录 $coverage_dir 为空或不存在，跳过合并"
}

# 打印 UVM_ERROR 统计和详情
echo "=================================="
echo "UVM_ERROR 统计："
echo "共检测到 $uvm_error_count 个 UVM_ERROR。"
if {$uvm_error_count > 0} {
    echo "UVM_ERROR 详情："
    foreach detail $uvm_error_details {
        echo $detail
    }
} else {
    echo "未检测到任何 UVM_ERROR。"
}
echo "=================================="

# 不退出仿真器，保持打开状态
echo "仿真器保持打开状态，您可以继续操作..."