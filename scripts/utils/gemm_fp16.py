import numpy as np
import os

def float16_to_hex(f16_val):
    """Convert float16 to 16-bit hex string."""
    if not isinstance(f16_val, np.float16):
        f16_val = np.float16(f16_val)
    return f"{np.frombuffer(f16_val.tobytes(), dtype=np.uint16)[0]:04x}"

def hex_str_to_float16(hex_str):
    """Convert 16-bit hex string to float16."""
    hex_str = hex_str.strip()
    uint16_val = np.uint16(int(hex_str, 16))
    return np.frombuffer(uint16_val.tobytes(), dtype=np.float16)[0]

def read_mem_file_fp16(file_path, rows, cols):
    """Read .mem file as float16 and return float32 matrix for computation."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File {file_path} not found.")
    
    data = []
    with open(file_path, 'r') as f:
        for line in f:
            hex_val = line.strip()
            if hex_val:
                f16 = hex_str_to_float16(hex_val)
                data.append(np.float32(f16))  # Convert to float32 for computation

    expected_size = rows * cols
    if len(data) != expected_size:
        raise ValueError(f"Expected {expected_size} values in {file_path}, but got {len(data)}.")
    
    return np.array(data, dtype=np.float32).reshape(rows, cols)

def save_result_with_indices_fp16(matrix_fp32, output_path):
    """Save result matrix in hex with source mapping as text, converting to float16."""
    rows, cols = matrix_fp32.shape
    with open(output_path, 'w') as f:
        f.write("Hex Result : Source Explanation\n")
        f.write("-" * 40 + "\n")
        for i in range(rows):
            for j in range(cols):
                f16_val = np.float16(matrix_fp32[i, j])
                hex_val = float16_to_hex(f16_val)
                f.write(f"{hex_val:<10} : A[{i}] x B[{j}] + C[{i},{j}]\n")

def save_mem_file_fp16(matrix_fp32, file_path):
    """Save result matrix as .mem file with float16 hex values."""
    with open(file_path, 'w') as f:
        for val in matrix_fp32.flatten():
            hex_val = float16_to_hex(np.float16(val))
            f.write(hex_val + "\n")

def compute_reference_result(a, b, c):
    """Compute A * B + C in float32."""
    return np.dot(a, b) + c

def main():
    # Matrix dimensions
    M, K, N = 32, 16, 8

    # Update these paths to match your environment
    matrix_a_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/matrix_a_fp16.mem"
    matrix_b_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/matrix_b_fp16.mem"
    matrix_c_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/matrix_c_fp16.mem"
    ref_result_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/ref_result_fp16.mem"
    explanation_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/ref_result_fp16_explained.txt"

    try:
        matrix_a = read_mem_file_fp16(matrix_a_path, M, K)
        matrix_b = read_mem_file_fp16(matrix_b_path, K, N)
        matrix_c = read_mem_file_fp16(matrix_c_path, M, N)
    except Exception as e:
        print(f"Error loading .mem files: {e}")
        return

    ref_result = compute_reference_result(matrix_a, matrix_b, matrix_c)

    # Save reference result as .mem file (FP16 hex)
    save_mem_file_fp16(ref_result, ref_result_path)

    # Save human-readable explanation
    save_result_with_indices_fp16(ref_result, explanation_path)
    print(f"FP16 结果已保存至：{ref_result_path}")
    print(f"解释文件已保存至：{explanation_path}")

if __name__ == "__main__":
    main()
