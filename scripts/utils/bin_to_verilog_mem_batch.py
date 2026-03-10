import numpy as np
import struct
import os

def int8_to_mem(data, r, c, mem_file):
    if data.size != r * c:
        raise ValueError(f"int8: Expected {r*c} elements, got {data.size}")
    matrix = data.reshape(r, c)
    with open(mem_file, 'w') as f:
        for val in matrix.flatten():
            f.write(f"{val & 0xFF:02X}\n")

def int4_to_mem(data, r, c, mem_file):
    total_elements = r * c
    expected_bytes = (total_elements + 1) // 2
    if data.size != expected_bytes:
        raise ValueError(f"int4: Expected {expected_bytes} bytes, got {data.size}")
    int4_vals = []
    for byte in data:
        high = (byte >> 4) & 0x0F
        low = byte & 0x0F
        high_signed = high - 16 if high > 7 else high
        low_signed = low - 16 if low > 7 else low
        int4_vals.extend([high_signed, low_signed])
    int4_vals = int4_vals[:total_elements]
    matrix = np.array(int4_vals, dtype=np.int8).reshape(r, c)
    with open(mem_file, 'w') as f:
        for val in matrix.flatten():
            f.write(f"{val & 0x0F:X}\n")  # 1位十六进制

def int32_to_mem(data, r, c, mem_file):
    if data.size != r * c:
        raise ValueError(f"int32: Expected {r*c} elements, got {data.size}")
    matrix = data.reshape(r, c)
    with open(mem_file, 'w') as f:
        for val in matrix.flatten():
            f.write(f"{val & 0xFFFFFFFF:08X}\n")  # 32-bit unsigned representation

def fp16_to_mem(data, r, c, mem_file):
    if data.size != r * c:
        raise ValueError(f"fp16: Expected {r*c} elements, got {data.size}")
    matrix = data.reshape(r, c)
    with open(mem_file, 'w') as f:
        for val in matrix.flatten():
            bits = np.frombuffer(np.float16(val).tobytes(), dtype=np.uint16)[0]
            f.write(f"{bits:04X}\n")

def fp32_to_mem(data, r, c, mem_file):
    if data.size != r * c:
        raise ValueError(f"fp32: Expected {r*c} elements, got {data.size}")
    matrix = data.reshape(r, c)
    with open(mem_file, 'w') as f:
        for val in matrix.flatten():
            bits = struct.unpack('>I', struct.pack('>f', val))[0]
            f.write(f"{bits:08X}\n")

def bin_to_verilog_mem(bin_file, mem_file, r, c, dtype='int8'):
    with open(bin_file, 'rb') as f:
        raw = f.read()

    if dtype == 'int8':
        data = np.frombuffer(raw, dtype=np.int8)
        int8_to_mem(data, r, c, mem_file)

    elif dtype == 'int4':
        data = np.frombuffer(raw, dtype=np.uint8)
        int4_to_mem(data, r, c, mem_file)

    elif dtype == 'int32':
        data = np.frombuffer(raw, dtype=np.int32)
        int32_to_mem(data, r, c, mem_file)

    elif dtype == 'fp16':
        data = np.frombuffer(raw, dtype=np.float16)
        fp16_to_mem(data, r, c, mem_file)

    elif dtype == 'fp32':
        data = np.frombuffer(raw, dtype=np.float32)
        fp32_to_mem(data, r, c, mem_file)

    else:
        raise ValueError(f"Unsupported dtype: {dtype}")

if __name__ == "__main__":
    # 基础路径
    base_path = "D:/FPGA/Prj/TPU/TPU/Dataset"

    # 定义数据类型和矩阵尺寸
    dtypes = ['fp16', 'fp32', 'int4', 'int4_int32', 'int8', 'int8_int32']
    matrix_sizes = ['m8n32k16', 'm16n16k16', 'm32n8k16']
    matrices = ['a', 'b', 'c']

    # 矩阵尺寸对应的行和列
    size_configs = {
        'm8n32k16': {'a': (8, 16), 'b': (16, 32), 'c': (8, 32)},
        'm16n16k16': {'a': (16, 16), 'b': (16, 16), 'c': (16, 16)},
        'm32n8k16': {'a': (32, 16), 'b': (16, 8), 'c': (32, 8)}
    }

    # 数据类型映射
    dtype_map = {
        'fp16': {'a': 'fp16', 'b': 'fp16', 'c': 'fp16'},
        'fp32': {'a': 'fp32', 'b': 'fp32', 'c': 'fp32'},
        'int4': {'a': 'int4', 'b': 'int4', 'c': 'int4'},
        'int4_int32': {'a': 'int4', 'b': 'int4', 'c': 'int32'},
        'int8': {'a': 'int8', 'b': 'int8', 'c': 'int8'},
        'int8_int32': {'a': 'int8', 'b': 'int8', 'c': 'int32'}
    }

    # 批量处理
    for dtype in dtypes:
        for size in matrix_sizes:
            for matrix in matrices:
                # 获取行列数
                rows, cols = size_configs[size][matrix]
                
                # 确定数据类型
                matrix_dtype = dtype_map[dtype][matrix]
                
                # 构建输入和输出文件路径
                bin_file = f"{base_path}/{dtype}/{size}/{matrix}_{matrix_dtype}_{size}.bin"
                mem_file = f"{base_path}/{dtype}/{size}/matrix_{matrix}_{matrix_dtype}.mem"
                
                # 检查输入文件是否存在
                if not os.path.exists(bin_file):
                    print(f"Warning: {bin_file} does not exist, skipping...")
                    continue
                
                # 确保输出目录存在
                os.makedirs(os.path.dirname(mem_file), exist_ok=True)
                
                try:
                    # 转换文件
                    bin_to_verilog_mem(bin_file, mem_file, rows, cols, matrix_dtype)
                    print(f"{matrix_dtype} matrix {matrix} for {size} ({dtype}) converted successfully to {mem_file}")
                except Exception as e:
                    print(f"Error converting {bin_file} to {mem_file}: {str(e)}")

    print("All conversions completed.")