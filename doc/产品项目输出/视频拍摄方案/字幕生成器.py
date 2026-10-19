"""Generate rehearsal subtitles from a measured startup time. Standard library only.
This script writes text assets, never accesses FPGA, EDA tools or source RTL.
"""
from pathlib import Path
import argparse
import csv
import json
import math
import textwrap

BASE = Path(__file__).resolve().parent

def timecode(seconds):
    millis = round(seconds * 1000)
    hours, millis = divmod(millis, 3600000)
    minutes, millis = divmod(millis, 60000)
    secs, millis = divmod(millis, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"

def chunks(text, maximum=36):
    remaining = text.strip()
    result = []
    while len(remaining) > maximum:
        positions = [i + 1 for i, ch in enumerate(remaining[:maximum])
                     if ch in "，。；、" and i >= 15]
        cut = positions[-1] if positions else maximum
        result.append(remaining[:cut].strip())
        remaining = remaining[cut:].strip()
    if remaining:
        result.append(remaining)
    return result

def voice_cues(source, startup, mode="soft"):
    cues = []
    for item in source:
        a, b, text = item["start"], item["end"], item["text"]
        if a < 134.5:
            cues.append((a, b, text))
        elif a == 134.5:
            line = ("现在软重启，核对保存的设置。" if mode == "soft"
                    else "接着真实断电、重新上电，核对保存的设置。")
            if startup < 6:
                line = "现在软重启。" if mode == "soft" else "现在断电重启。"
            cues.append((134.5, 136.5 + min(startup, 6), line))
        elif a == 141.5:
            if startup >= 15:
                cues.append((136.5 + startup * 0.4, 136.5 + startup * 0.9,
                             "整个启动过程保留原速。"))
        else:
            shift = startup - 20
            cues.append((a + shift, b + shift, text))
    return cues

def srt_for_voice(cues):
    rows = []
    for a, b, text in cues:
        pieces = chunks(text)
        total = sum(len(p) for p in pieces)
        cursor = a
        for p in pieces:
            end = cursor + (b - a) * len(p) / total
            wrapped = "\n".join(textwrap.wrap(p, width=22,
                                             break_long_words=True,
                                             break_on_hyphens=False))
            rows.append((cursor, end, wrapped))
            cursor = end
    return serialize_srt(rows)

def serialize_srt(rows):
    previous_end = -1
    output = []
    for i, (a, b, text) in enumerate(rows, 1):
        if a < 0 or b <= a or a < previous_end - 0.0001:
            raise ValueError(f"Invalid subtitle timing at cue {i}")
        previous_end = b
        output.append(f"{i}\n{timecode(a)} --> {timecode(b)}\n{text}\n")
    return "\n".join(output)

def feature_cues(source, startup, mode="soft"):
    output = []
    for a, b, title, detail in source:
        if a == 134.5:
            title = "红外E9软重启" if mode == "soft" else "镜头内真实断电 / 重新供电"
            detail = "180秒锚点触发；不是断电" if mode == "soft" else "LED真实熄灭；180秒锚点复电"
        elif a == 136.5:
            b = 136.5 + startup
            title = "软重启过程：原速保留" if mode == "soft" else "冷启动过程：原速保留"
            detail = f"按输入T标注：{startup:g}秒；以实际录像核准"
        elif a >= 156.5:
            a += startup - 20
            b += startup - 20
        output.append((a, b, title + "\n" + detail))
    return output

def shot_rows(source, startup, mode="soft"):
    output = []
    for a, b, action, evidence in source:
        output.append((a, b, a, b, "1x", action, evidence))
    output.extend([
        (112, 170, 112, 126.5, "4x", "真实无人操作前58秒",
         "必须保留原片；成片公开标注4倍速"),
        (170, 172, 126.5, 128.5, "1x", "自动消隐前恢复原速",
         "保留触发前两秒；若实际边沿变化须重定锚点"),
        (172, 174, 128.5, 130.5, "1x", "自动消隐后保留原声",
         "屏幕黑，音频继续"),
        (174, 178, 130.5, 134.5, "1x", "普通按键第一次只唤醒",
         "画面恢复，播放不因此暂停"),
        (178, 180, 134.5, 136.5, "1x",
         "对准遥控，180秒发E9软重启" if mode == "soft" else "断电灯灭，180秒重新供电",
         "立即复位，无二次确认" if mode == "soft" else "LED真实熄灭再启动"),
        (180, 180 + startup, 136.5, 136.5 + startup, "1x",
         "软重启真实等待" if mode == "soft" else "冷启动真实等待", "到浏览页稳定可操作"),
        (180 + startup, 192 + startup, 136.5 + startup, 148.5 + startup,
         "1x", "核对五项保存值并重新播放", "参数相同，不称断电续播"),
        (192 + startup, 200 + startup, 148.5 + startup, 156.5 + startup,
         "1x", "全景收尾", "完整设备运行"),
    ])
    return output

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--startup-seconds", type=float, required=True,
                        help="Measured accepted soft-reset (or power-on) to usable browser time")
    parser.add_argument("--restart-mode", choices=("soft", "power"), default="soft",
                        help="soft: IR E9 reset; power: actual power cycle (already bootable)")
    parser.add_argument("--output", type=Path,
                        help="Text output folder; default is a new folder beside this script")
    args = parser.parse_args()
    startup = args.startup_seconds
    if not math.isfinite(startup) or not 0.1 <= startup <= 300:
        parser.error("startup-seconds must be finite and in [0.1, 300]")
    data = json.loads((BASE / "字幕素材.json").read_text(encoding="utf-8-sig"))
    tag = f"T{startup:g}"
    mode = args.restart_mode
    folder = args.output if args.output else BASE / f"字幕输出_{mode}_{tag}秒"
    folder.mkdir(parents=True, exist_ok=True)
    voices = voice_cues(data["vo"], startup, mode)
    files = {
        f"旁白字幕_{tag}排练版.srt": srt_for_voice(voices),
        f"功能标签_{tag}排练版.srt": serialize_srt(feature_cues(data["labels"], startup, mode)),
        f"配音稿_{tag}排练版.txt": (
            f"Rehearsal only. Mode={mode}. Input T={startup:g}s. Edited duration={156.5+startup:g}s.\n\n"
            + "\n\n".join(f"{timecode(a)} - {timecode(b)}\n{text}"
                          for a, b, text in voices)
        ),
    }
    for name, content in files.items():
        (folder / name).write_text(content, encoding="utf-8")
    with (folder / f"分镜表_{tag}排练版.csv").open(
            "w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.writer(stream)
        writer.writerow(["raw_start_s", "raw_end_s", "edit_start_s", "edit_end_s",
                         "speed", "action", "visible_evidence"])
        writer.writerows(shot_rows(data["shots"], startup, mode))
    print(f"Mode={mode}; Input T={startup:g}s; raw={200+startup:g}s; edited={156.5+startup:g}s")
    if startup > 21.5:
        print("Over the planned 178-second ceiling: revise the shooting plan.")
    print("Generated text assets only. Match subtitles to the actual recorded events.")

if __name__ == "__main__":
    main()

