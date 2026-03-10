import numpy as np

def hex_to_fp32_value(hex_str):
    """将 FP32 的 32 位十六进制表示转换为其对应的十进制数值"""
    # 移除 '0x' 前缀（如果存在）
    hex_str = hex_str.lstrip('0x')
    # 将十六进制字符串转换为无符号 32 位整数
    uint32_val = int(hex_str, 16)
    # 将这个 32 位整数的字节表示解释为 float32 类型
    fp32_val = np.frombuffer(np.uint32(uint32_val).tobytes(), dtype=np.float32)[0]
    # 转换为 float64 以确保精确显示
    return float(fp32_val)

# 给定的十六进制值（FP32）
hex_val1 = "0x4b1ed800"
hex_val2 = "0x4b1ee800"

# 转换为十进制数值
value1 = hex_to_fp32_value(hex_val1)
value2 = hex_to_fp32_value(hex_val2)

# 打印结果
print(f"FP32 十六进制 {hex_val1} 对应的十进制数值是: {value1}")
print(f"FP32 十六进制 {hex_val2} 对应的十进制数值是: {value2}")

# 计算误差 (差值)
error = value2 - value1
absolute_error = abs(error)

# 打印误差
print(f"误差 ({hex_val2} - {hex_val1}) 是: {error}")
print(f"绝对误差是: {absolute_error}")