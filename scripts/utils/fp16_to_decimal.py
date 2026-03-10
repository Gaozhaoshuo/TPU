import os
import numpy as np

def hex_str_to_float16(hex_str):
    """Convert 4-character hex string to float16."""
    hex_str = hex_str.strip()
    try:
        # Convert hex string to 16-bit integer
        uint16_val = np.uint16(int(hex_str, 16))
        # Interpret as float16
        return np.frombuffer(uint16_val.tobytes(), dtype=np.float16)[0]
    except ValueError:
        raise ValueError(f"Invalid hex string for FP16: {hex_str}")

def read_mem_file_raw(file_path):
    """Reads a .mem file and returns a list of (hex, float) pairs for FP16."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File {file_path} not found.")
    
    data = []
    with open(file_path, 'r') as f:
        for line in f:
            hex_val = line.strip()
            if hex_val:
                try:
                    float_val = hex_str_to_float16(hex_val)
                    data.append((hex_val.lower(), float_val))
                except ValueError as e:
                    print(f"Warning: Skipping invalid hex value '{hex_val}' in {file_path}: {e}")
    return data

def save_one_per_line_with_header(data_pairs, output_path):
    """Save each hex-float pair on a single line with header and alignment."""
    with open(output_path, 'w') as f:
        # Write header
        f.write(f"{'Hex':>8s} : {'Float16 Value':>24s}\n")
        f.write(f"{'-'*8} : {'-'*24}\n")
        # Write each data pair
        for hex_val, float_val in data_pairs:
            line = f"{hex_val:>8s} : {float_val:>24.10f}\n"
            f.write(line)

# File paths
ref_result_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/ref_result_fp16.mem"
output_txt_path = "D:/FPGA/Prj/TPU/TPU/Dataset/fp16/m32n8k16/ref_result_fp16_hex_decimal.txt"

# Main process
if __name__ == "__main__":
    try:
        print(f"Reading FP16 .mem file: {ref_result_path}")
        data_pairs = read_mem_file_raw(ref_result_path)
        print(f"Saving hex-decimal output to: {output_txt_path}")
        save_one_per_line_with_header(data_pairs, output_txt_path)
        print(f"Single-column hex + decimal output saved to {output_txt_path}")
    except Exception as e:
        print(f"Error: {e}")