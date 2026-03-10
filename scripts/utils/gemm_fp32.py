import numpy as np
import os

def float32_to_hex(f32_val):
    if not isinstance(f32_val, np.float32):
        f32_val = np.float32(f32_val)
    return f"{np.frombuffer(f32_val.tobytes(), dtype=np.uint32)[0]:08x}"

def hex_str_to_float32(hex_str):
    hex_str = hex_str.strip()
    uint32_val = np.uint32(int(hex_str, 16))
    return np.frombuffer(uint32_val.tobytes(), dtype=np.float32)[0]

def read_mem_file(file_path, rows, cols):
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File {file_path} not found.")
    
    data = []
    with open(file_path, 'r') as f:
        for line in f:
            hex_val = line.strip()
            if hex_val:
                data.append(hex_str_to_float32(hex_val))
    
    expected_size = rows * cols
    if len(data) != expected_size:
        raise ValueError(f"Expected {expected_size} values in {file_path}, but got {len(data)}.")
    
    return np.array(data, dtype=np.float32).reshape(rows, cols)

def save_result_with_indices(matrix, output_path):
    rows, cols = matrix.shape
    with open(output_path, 'w') as f:
        f.write("Hex Result              : Source Explanation\n")
        f.write("-" * 60 + "\n")
        for i in range(rows):
            for j in range(cols):
                hex_val = float32_to_hex(matrix[i, j])
                f.write(f"{hex_val:<24} : A[{i}] x B[{j}] + C[{i},{j}]\n")

def compute_reference_result(a, b, c):
    return np.dot(a, b) + c

def main():
    # Matrix dimensions
    M, K, N = 16, 16, 16

    # Update these paths to match your environment
    matrix_a_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m8n32k16/matrix_a_fp32.mem"
    matrix_b_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m8n32k16/matrix_b_fp32.mem"
    matrix_c_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m8n32k16/matrix_c_fp32.mem"
    ref_result_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m8n32k16/ref_result_fp32_m8n32k16.mem"
    explanation_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp32/m8n32k16/ref_result_fp32_m8n32k16_explained.txt"

    try:
        matrix_a = read_mem_file(matrix_a_path, M, K)
        matrix_b = read_mem_file(matrix_b_path, K, N)
        matrix_c = read_mem_file(matrix_c_path, M, N)
    except Exception as e:
        print(f"Error loading .mem files: {e}")
        return

    ref_result = compute_reference_result(matrix_a, matrix_b, matrix_c)

    # Save ref_result in .mem (hex) format
    with open(ref_result_path, 'w') as f:
        for val in ref_result.flatten():
            f.write(float32_to_hex(val) + "\n")

    # Save human-readable explanation
    save_result_with_indices(ref_result, explanation_path)
    print(f"解释文件已保存至：{explanation_path}")

if __name__ == "__main__":
    main()
