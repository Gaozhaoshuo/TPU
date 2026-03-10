import numpy as np

def hex_to_fp16_value(hex_str):
    """将 FP16 的 16 位十六进制表示转换为其对应的十进制数值"""
    # 移除 '0x' 前缀（如果存在）
    hex_str = hex_str.lstrip('0x')
    # 将十六进制字符串转换为无符号 16 位整数
    uint16_val = int(hex_str, 16)
    # 将这个 16 位整数的字节表示解释为 float16 类型
    fp16_val = np.frombuffer(np.uint16(uint16_val).tobytes(), dtype=np.float16)[0]
    # 为了更精确地显示十进制，转换为 float64
    return float(fp16_val)

# 给定的十六进制值
hex_val1 = "0x58ee"
hex_val2 = "0x58ed"

# 转换为十进制数值
value1 = hex_to_fp16_value(hex_val1)
value2 = hex_to_fp16_value(hex_val2)

print(f"FP16 十六进制 {hex_val1} 对应的十进制数值是: {value1}")
print(f"FP16 十六进制 {hex_val2} 对应的十进制数值是: {value2}")

# 计算误差 (差值)
error = value2 - value1
absolute_error = abs(error)

print(f"误差 ({hex_val2} - {hex_val1}) 是: {error}")
print(f"绝对误差是: {absolute_error}")