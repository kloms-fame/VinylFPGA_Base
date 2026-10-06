"""Focused S0-S5 fixes; logs are reproducible, vendor datapaths not simulated by top_control."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim/fix_20261006"
OUT.mkdir(exist_ok=True)
libs = ["src", "src/SD", "src/io", "src/display", "src/audio", "src/boot", "src/video"]
def run(name, top_control=False):
    src = ROOT / "sim/integration" / (name + ".v") if top_control else ROOT / "sim" / (name + ".v")
    args = ["iverilog", "-g2005", "-I", "src", "-I", "src/include", "-I", "src/SD"]
    if top_control:
        args += ["-i"]  # encrypted/primitive datapaths only; clocks/data driven by bench
    args += [x for d in libs for x in ("-y",d)]
    args += ["-s",name,"-o",str(OUT/(name+".vvp")),str(src)]
    if top_control:
        args += ["src/top_tf_hdmi_audio.v"]
    c = subprocess.run(args,cwd=ROOT,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=90)
    r = subprocess.run(["vvp",str(OUT/(name+".vvp"))],cwd=ROOT,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=120) if c.returncode==0 else c
    log = c.stdout+c.stderr+r.stdout+r.stderr
    (OUT/(name+".log")).write_text(log,encoding="utf-8")
    print(name+": "+"; ".join(x for x in r.stdout.splitlines() if "PASS" in x or "FAIL" in x),flush=True)
    if c.returncode or r.returncode or "FAIL" in log or "PASS" not in log:
        raise RuntimeError(log)
if __name__ == "__main__":
    for name in ["tb_boot_window","tb_sd_card_bmp_fourbank","tb_fat32_index_loader","tb_browse_fsm","tb_io_startup_dip","tb_video_fade_transition","tb_expansion_s1","tb_s3_browse_integration"]:
        run(name)
    run("tb_top_control",True)
