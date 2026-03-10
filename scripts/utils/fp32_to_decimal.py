import os
import struct

def hex_str_to_float32(hex_str):
    """Convert 8-character hex string to float32."""
    return struct.unpack('!f', bytes.fromhex(hex_str))[0]

def read_mem_file_raw(file_path):
    """Reads a .mem file and returns a list of (hex, float) pairs."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File {file_path} not found.")
    
    data = []
    with open(file_path, 'r') as f:
        for line in f:
            hex_val = line.strip()
            if hex_val:
                float_val = hex_str_to_float32(hex_val)
                data.append((hex_val.lower(), float_val))
    return data

def save_one_per_line_with_header(data_pairs, output_path):
    """Save each hex-float pair on a single line with header and alignment."""
    with open(output_path, 'w') as f:
        # 写入表头
        f.write(f"{'Hex':>13s} : {'Float32 Value':>24s}\n")
        f.write(f"{'-'*13} : {'-'*24}\n")
        # 写入每个数据
        for hex_val, float_val in data_pairs:
            line = f"{hex_val:>13s} : {float_val:>24.10f}\n"
            f.write(line)

# 示例文件路径
ref_result_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m32n8k16/ref_result_fp32.mem"
output_txt_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m32n8k16/ref_result_fp32_hex_decimal.txt"

# 主流程
if __name__ == "__main__":
    data_pairs = read_mem_file_raw(ref_result_path)
    save_one_per_line_with_header(data_pairs, output_txt_path)
    print(f"Single-column hex + decimal output saved to {output_txt_path}")
