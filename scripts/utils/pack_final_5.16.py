import os  # 导入 os 模块，用于文件路径操作，如检查文件是否存在
import re  # 导入正则表达式模块，用于解析文件中的十六进制数据
from functools import partial  # 导入 partial 函数（未使用，可能是为扩展准备）

class HexProcessor:
    """多精度十六进制处理器：处理不同位宽（4/8/16/32位）的字节流"""
    # 配置字典：定义不同位宽的处理规则
    BIT_CONFIG = {
        4: {'bytes_per_element': 0.5, 'hex_digits': 1, 'le_format': False},  # 4位：半字节，1位十六进制，无需小端格式
        8: {'bytes_per_element': 1, 'hex_digits': 2, 'le_format': False},    # 8位：1字节，2位十六进制，无需小端格式
        16: {'bytes_per_element': 2, 'hex_digits': 4, 'le_format': True},    # 16位：2字节，4位十六进制，需小端格式
        32: {'bytes_per_element': 4, 'hex_digits': 8, 'le_format': True}     # 32位：4字节，8位十六进制，需小端格式
    }

    @classmethod
    def process(cls, bit_width, byte_stream):
        """处理字节流为指定位宽的十六进制字符串
        参数：
            bit_width: 位宽（4/8/16/32）
            byte_stream: 输入的字节流（如 b'\x12\x34'）
        返回：按位宽分割的十六进制字符串列表
        """
        # 获取指定位宽的配置
        cfg = cls.BIT_CONFIG.get(bit_width)
        if not cfg:
            # 如果位宽不在配置中，抛出错误
            raise ValueError(f"不支持的位宽：{bit_width}，可选[4,8,16,32]")
        
        # 4位特殊处理，调用专用方法,半个字节
        if bit_width == 4:
            return cls._process_4bit(byte_stream)
        
        # 计算每个元素占多少字节（如 16位是 2 字节）
        element_size = int(cfg['bytes_per_element'])
        # 检查字节流长度是否能被元素大小整除
        if len(byte_stream) % element_size != 0:
            raise ValueError(f"数据长度{len(byte_stream)}字节不兼容{bit_width}位格式")
        
        elements = []  # 存储处理后的十六进制字符串
        # 按元素大小切分字节流
        for i in range(0, len(byte_stream), element_size):
            chunk = byte_stream[i:i+element_size]  # 取出当前块
            if cfg['le_format']:  # 如果需要小端格式（低字节在前）
                chunk = chunk[::-1]  # 反转字节顺序 [start:end:step] 中 step = -1 表示从后向前取（反转）。
            # 转为大写十六进制字符串，补齐指定位数（如 4 位补到 0000）
            elements.append(chunk.hex().upper().zfill(cfg['hex_digits']))
        
        return elements  # 返回处理结果
                            #如果输入字节流是 b'\x12\x34'，位宽是 16：
                            #切成 b'\x12\x34'。
                            #小端格式反转为 b'\x34\x12'。
                            #转为十六进制 3412，返回 [3412]。
    @staticmethod
    def _process_4bit(byte_stream):
        """处理4位（半字节）格式的字节流
        参数：
            byte_stream: 输入字节流
        返回：每个字节拆成高低4位的十六进制字符串列表
        """
        elements = []
        for b in byte_stream:  # 遍历每个字节
            high = (b >> 4) & 0x0F  # 提取高4位（如 0xAB -> 0xA）
            low = b & 0x0F          # 提取低4位（如 0xAB -> 0xB）
            # 将高低4位转为十六进制字符串，加入列表
            elements.extend([f"{high:X}", f"{low:X}"])
        return elements

    @staticmethod
    def extend_to_32bit(element, bit_width):
        """将十六进制元素扩展到32位（8位十六进制）
        参数：
            element: 输入的十六进制字符串
            bit_width: 原位宽
        返回：补齐到8位的十六进制字符串
        """
        # 定义各位宽对应的十六进制位数
        hex_digits = {4: 1, 8: 2, 16: 4, 32: 8}
        required_digits = hex_digits[bit_width]
        # 检查输入元素是否超过位宽允许的长度
        if len(element) > required_digits:
            raise ValueError(f"元素 '{element}' 超过{bit_width}位格式")
        # 左侧补0到8位（如 "12" -> "00000012"）
        return element.zfill(8)

def parse_hex_file(file_path):
    """解析十六进制文件，提取有效数据
    参数：
        file_path: 文件路径
    返回：字节流（如 b'\x12\x34'）
    """
    byte_stream = bytearray()  # 用于存储解析后的字节
    # 正则表达式：匹配形如 "00000000: 12 34" 的行，前八个数为地址，后面为数据
    line_pattern = re.compile(r'^[0-9a-fA-F]{8}:[\t ]+(.+)$')

    # 打开文件，按行读取
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()  # 去除首尾空白
            if not line:  # 跳过空行
                continue
            
            match = line_pattern.match(line)  # 尝试匹配行格式
            if not match:  # 不匹配则跳过
                continue
            
            # 提取冒号后的数据，替换制表符为空格后分割
            hex_data = match.group(1).replace('\t', ' ').split()
            for hd in hex_data:  # 遍历每个十六进制单元
                # 只处理长度为2或4的单元（如 "12" 或 "1234"）
                if len(hd) not in (2,4):
                    print(f"警告：非常规数据单元 '{hd}'，已跳过")
                    continue
                try:
                    # 将十六进制字符串转为字节，加入字节流
                    byte_stream.extend(bytes.fromhex(hd))
                except ValueError:
                    # 如果转换失败（非法十六进制），打印错误
                    print(f"错误：非法十六进制数据 '{hd}'")
    
    return bytes(byte_stream)  # 返回字节流
                                ##00000000: 12 34 AB CD
                                #提取 12 34 AB CD，转为字节流 b'\x12\x34\xAB\xCD'

def main():
    """主函数：与用户交互，处理文件并生成矩阵"""
    try:
        # 获取用户输入：文件路径
        file_path = input("请输入转储文件路径：").strip()
        # 检查文件是否存在
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"文件不存在：{file_path}")
        
        # 获取用户输入：位宽（4/8/16/32）
        bit_width = int(input("请选择元素位宽（4/8/16/32）："))
        # 检查位宽是否合法
        if bit_width not in (4,8,16,32):
            raise ValueError("无效位宽选择")
        
        # 解析文件，获取字节流
        raw_bytes = parse_hex_file(file_path)
        # 处理字节流为指定位宽的十六进制字符串
        elements = HexProcessor.process(bit_width, raw_bytes)
        # 将所有元素扩展到32位
        elements_32bit = [HexProcessor.extend_to_32bit(elem, bit_width) for elem in elements]
        
        # 统计元素总数
        total = len(elements_32bit)
        print(f"共解析到 {total} 个{bit_width}位元素（已扩展到32位）")
        
        # 获取用户输入：矩阵行数和列数
        rows = int(input("请输入矩阵行数："))
        cols = int(input("请输入矩阵列数："))
        
        # 检查矩阵维度是否匹配元素总数
        if rows * cols != total:
            raise ValueError(f"维度不匹配：{rows}x{cols} ({rows*cols}) ≠ {total}")
        
        # 将元素列表分割成矩阵（每行 cols 个元素）
        matrix = [elements_32bit[i*cols : (i+1)*cols] for i in range(rows)]
        
        # 询问是否转置矩阵（行列互换）
        transpose = input("是否对矩阵进行转置（y/n）：").lower() == 'y'
        if transpose:
            # 转置：行列互换
            matrix = list(map(list, zip(*matrix)))
            rows, cols = cols, rows  # 更新行列数
        
        # 对每行元素倒序排列（如 [A, B] -> [B, A]）
        for i in range(len(matrix)):
            matrix[i] = matrix[i][::-1]
        
        # 补齐每行到1024位（32个32位元素）
        elements_per_row = 32  # 每行固定32个元素
        # 检查列数是否超过最大值
        if cols > elements_per_row:
            raise ValueError(f"列数{cols}超过每行最大元素数{elements_per_row}")
        
        # 为每行补齐0（左侧补 "00000000"）
        for i in range(len(matrix)):
            row_elements = matrix[i]
            # 计算需要补齐的元素数
            padding_elements = ['00000000'] * (elements_per_row - len(row_elements))
            matrix[i] = padding_elements + row_elements  # 补齐后拼接
        
        # 预览前两行结果
        print("\n前2行示例：")
        for i, row in enumerate(matrix[:2]):  # 只显示前两行
            hex_str = ''.join(row)  # 拼接每行元素
            preview = f"1024'h{hex_str[:16]}..."  # 显示前16位，省略其余
            print(f"Row {i:02}: {preview}")
        
        # 询问是否保存结果
        if input("\n是否保存完整结果？(y/n): ").lower() == 'y':
            save_path = input("保存路径：").strip()  # 获取保存路径
            # 打开文件写入结果
            with open(save_path, 'w') as f:
                # 写入文件头部注释
                f.write(f"// 位宽：{bit_width}-bit 元素数：{total} 矩阵维度：{rows} x {cols}\n")
                # 写入每行数据，格式为 Verilog 的 1024'h 常量
                for i, row in enumerate(matrix):
                    hex_str = ''.join(row)  # 拼接每行元素
                    if i < len(matrix) - 1:
                        f.write(f"1024'h{hex_str},\n")  # 非最后一行加逗号
                    else:
                        f.write(f"1024'h{hex_str}\n")  # 最后一行不加逗号
            # 打印保存路径（绝对路径）
            print(f"已保存至：{os.path.abspath(save_path)}")

    except Exception as e:
        # 捕获所有异常，打印错误信息
        print(f"\n错误：{str(e)}")
    finally:
        # 无论是否出错，都等待用户按回车退出
        input("按回车退出...")

if __name__ == '__main__':
    main()  # 运行主函数