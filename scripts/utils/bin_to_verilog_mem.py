import numpy as np
import struct

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
    # 修改此处参数
    bin_file = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m8n32k16/b_fp32_m8n32k16.bin"
    mem_file = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m8n32k16/matrix_b_fp32.mem"
    r = 16   # 行数
    c = 32  # 列数
    dtype = "fp32"   # 可选: int8 / int4 / int32 / fp16 / fp32

    bin_to_verilog_mem(bin_file, mem_file, r, c, dtype)
    print(f"{dtype} matrix converted successfully to {mem_file}")
