import numpy as np
import os

# Conversion functions for FP16
def float16_to_hex(f16_val):
    """Convert float16 to 16-bit hex string."""
    if not isinstance(f16_val, np.float16):
        f16_val = np.float16(f16_val)
    return f"{np.frombuffer(f16_val.tobytes(), dtype=np.uint16)[0]:04x}"

def hex_str_to_float16(hex_str):
    """Convert 16-bit hex string to float16."""
    hex_str = hex_str.strip()
    try:
        uint16_val = np.uint16(int(hex_str, 16))
        return np.frombuffer(uint16_val.tobytes(), dtype=np.float16)[0]
    except ValueError:
        raise ValueError(f"Invalid hex string for FP16: {hex_str}")

# Conversion functions for FP32
def float32_to_hex(f32_val):
    """Convert float32 to 32-bit hex string."""
    if not isinstance(f32_val, np.float32):
        f32_val = np.float32(f32_val)
    return f"{np.frombuffer(f32_val.tobytes(), dtype=np.uint32)[0]:08x}"

def hex_str_to_float32(hex_str):
    """Convert 32-bit hex string to float32."""
    hex_str = hex_str.strip()
    try:
        uint32_val = np.uint32(int(hex_str, 16))
        return np.frombuffer(uint32_val.tobytes(), dtype=np.float32)[0]
    except ValueError:
        raise ValueError(f"Invalid hex string for FP32: {hex_str}")

def read_mem_file(file_path, rows, cols, dtype):
    """Read .mem file as FP16 or FP32 and return float32 matrix for computation."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File {file_path} not found.")
    
    data = []
    with open(file_path, 'r') as f:
        for line in f:
            hex_val = line.strip()
            if hex_val:
                if dtype == 'fp16':
                    f_val = hex_str_to_float16(hex_val)
                elif dtype == 'fp32':
                    f_val = hex_str_to_float32(hex_val)
                else:
                    raise ValueError(f"Unsupported dtype: {dtype}")
                data.append(np.float32(f_val))  # Convert to float32 for computation

    expected_size = rows * cols
    if len(data) != expected_size:
        raise ValueError(f"Expected {expected_size} values in {file_path}, but got {len(data)}.")
    
    return np.array(data, dtype=np.float32).reshape(rows, cols)

def read_mem_file_raw(file_path, dtype):
    """Reads a .mem file and returns a list of (hex, float) pairs for FP16 or FP32."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File {file_path} not found.")
    
    data = []
    with open(file_path, 'r') as f:
        for line in f:
            hex_val = line.strip()
            if hex_val:
                try:
                    if dtype == 'fp16':
                        float_val = hex_str_to_float16(hex_val)
                    elif dtype == 'fp32':
                        float_val = hex_str_to_float32(hex_val)
                    else:
                        raise ValueError(f"Unsupported dtype: {dtype}")
                    data.append((hex_val.lower(), float_val))
                except ValueError as e:
                    print(f"Warning: Skipping invalid hex value '{hex_val}' in {file_path}: {e}")
    return data

def save_result_with_indices(matrix, output_path, dtype):
    """Save result matrix in hex with source mapping as text."""
    rows, cols = matrix.shape
    with open(output_path, 'w') as f:
        f.write("Hex Result              : Source Explanation\n")
        f.write("-" * 60 + "\n")
        for i in range(rows):
            for j in range(cols):
                if dtype == 'fp16':
                    hex_val = float16_to_hex(np.float16(matrix[i, j]))
                else:  # dtype == 'fp32'
                    hex_val = float32_to_hex(np.float32(matrix[i, j]))
                f.write(f"{hex_val:<24} : A[{i}] x B[{j}] + C[{i},{j}]\n")

def save_mem_file(matrix, file_path, dtype):
    """Save result matrix as .mem file with hex values."""
    with open(file_path, 'w') as f:
        for val in matrix.flatten():
            if dtype == 'fp16':
                hex_val = float16_to_hex(np.float16(val))
            else:  # dtype == 'fp32'
                hex_val = float32_to_hex(np.float32(val))
            f.write(hex_val + "\n")

def save_hex_decimal_file(data_pairs, output_path, dtype):
    """Save each hex-float pair on a single line with header and alignment."""
    with open(output_path, 'w') as f:
        # Write header
        if dtype == 'fp16':
            f.write(f"{'Hex':>8s} : {'Float16 Value':>24s}\n")
            f.write(f"{'-'*8} : {'-'*24}\n")
            for hex_val, float_val in data_pairs:
                f.write(f"{hex_val:>8s} : {float_val:>24.10f}\n")
        else:  # dtype == 'fp32'
            f.write(f"{'Hex':>13s} : {'Float32 Value':>24s}\n")
            f.write(f"{'-'*13} : {'-'*24}\n")
            for hex_val, float_val in data_pairs:
                f.write(f"{hex_val:>13s} : {float_val:>24.10f}\n")

def compute_reference_result(a, b, c):
    """Compute A * B + C in float32."""
    return np.dot(a, b) + c

def main():
    # Base path
    base_path = "D:/FPGA/Prj/TPU/TPU/Dataset"

    # Define data types and matrix sizes
    dtypes = ['fp16', 'fp32']
    matrix_sizes = ['m8n32k16', 'm16n16k16', 'm32n8k16']
    matrices = ['a', 'b', 'c']

    # Matrix size configurations
    size_configs = {
        'm8n32k16': {'a': (8, 16), 'b': (16, 32), 'c': (8, 32)},
        'm16n16k16': {'a': (16, 16), 'b': (16, 16), 'c': (16, 16)},
        'm32n8k16': {'a': (32, 16), 'b': (16, 8), 'c': (32, 8)}
    }

    # Data type mapping
    dtype_map = {
        'fp16': {'a': 'fp16', 'b': 'fp16', 'c': 'fp16'},
        'fp32': {'a': 'fp32', 'b': 'fp32', 'c': 'fp32'}
    }

    # Process each data type and matrix size
    for dtype in dtypes:
        for size in matrix_sizes:
            print(f"\nProcessing dtype={dtype}, size={size}")
            
            # Load matrices
            try:
                matrix_a = read_mem_file(
                    f"{base_path}/{dtype}/{size}/matrix_a_{dtype}.mem",
                    size_configs[size]['a'][0], size_configs[size]['a'][1], dtype
                )
                matrix_b = read_mem_file(
                    f"{base_path}/{dtype}/{size}/matrix_b_{dtype}.mem",
                    size_configs[size]['b'][0], size_configs[size]['b'][1], dtype
                )
                matrix_c = read_mem_file(
                    f"{base_path}/{dtype}/{size}/matrix_c_{dtype}.mem",
                    size_configs[size]['c'][0], size_configs[size]['c'][1], dtype
                )
            except Exception as e:
                print(f"Error loading .mem files for {dtype}/{size}: {e}")
                continue

            # Compute reference result
            ref_result = compute_reference_result(matrix_a, matrix_b, matrix_c)

            # Save reference result as .mem file
            ref_result_path = f"{base_path}/{dtype}/{size}/ref_result_{dtype}_{size}.mem"
            save_mem_file(ref_result, ref_result_path, dtype)
            print(f"Reference result saved to: {ref_result_path}")

            # Save human-readable explanation
            explanation_path = f"{base_path}/{dtype}/{size}/ref_result_{dtype}_{size}_explained.txt"
            save_result_with_indices(ref_result, explanation_path, dtype)
            print(f"Explanation saved to: {explanation_path}")

            # Save hex-decimal output
            try:
                hex_decimal_path = f"{base_path}/{dtype}/{size}/ref_result_{dtype}_{size}_hex_decimal.txt"
                data_pairs = read_mem_file_raw(ref_result_path, dtype)
                save_hex_decimal_file(data_pairs, hex_decimal_path, dtype)
                print(f"Hex-decimal output saved to: {hex_decimal_path}")
            except Exception as e:
                print(f"Error generating hex-decimal file for {dtype}/{size}: {e}")

if __name__ == "__main__":
    main()