"""Check the ASCII font's Icarus table against its 32K primitive INIT words."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
text = (ROOT / 'src/display/ascii_font_rom.v').read_text(encoding='utf-8')
words = [0] * 1024
for addr, value in re.findall(r"row_mem\[(\d+)\]\s*=\s*8'h([0-9a-fA-F]{2})", text):
    words[int(addr)] = int(value, 16)
params = {int(index, 16): int(value, 16) for index, value in
          re.findall(r"\.INIT_([0-9A-F]{2})\(256'h([0-9a-fA-F]{64})\)", text)}
for address, expected in enumerate(words):
    value = (params.get(address // 16, 0) >> ((address % 16) * 16)) & 0xffff
    if value != expected:
        raise SystemExit(f'font INIT mismatch at {address}: {value:04x} != {expected:02x}')
print('PASS: 1024 font values match 32K primitive initialization')
