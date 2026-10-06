"""Exhaust every ROM address and random jumps against the frozen S7-03 image."""
from pathlib import Path
import argparse
import subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--label',default='current');a=p.parse_args()
out=ROOT/'sim/resource_opt_verified'/('logo_'+a.label);out.mkdir(parents=True,exist_ok=True)
base=ROOT/'prj/resource_opt_verified_20261005/S703_M0_20261006/src/boot/boot_logo_rom.v'
reference=base.read_text(encoding='utf-8').replace('BOOT_LOGO_ROM_V','S703_LOGO_REFERENCE_V').replace('module boot_logo_rom #','module boot_logo_rom_reference #')
(out/'boot_logo_rom_reference.v').write_text(reference,encoding='utf-8')
bench=out/'tb_logo_equivalence.v'
bench.write_text('''`timescale 1ns/1ps
module tb_logo_equivalence;
reg clk=0;always #5 clk=~clk;
reg[14:0] addr=0;wire[23:0] rgb,ref_rgb;
reg[31:0] noise=32'h163ae409;integer i,checks=0,lit=0;
boot_logo_rom dut(.clk(clk),.pix_index(addr),.rgb(rgb));
boot_logo_rom_reference reference_dut(.clk(clk),.pix_index(addr),.rgb(ref_rgb));
task check;
begin
 @(posedge clk);#1;
 if(rgb!==ref_rgb)$fatal(1,"FAIL ROM addr=%d rgb=%h ref=%h",addr,rgb,ref_rgb);
 checks=checks+1;if(rgb!=0)lit=lit+1;
end endtask
initial begin
 for(i=0;i<32768;i=i+1)begin @(negedge clk);addr=i;check;end
 for(i=0;i<10000;i=i+1)begin
  @(negedge clk);noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};addr=noise[14:0];check;
 end
 if(lit==0)$fatal(1,"FAIL empty image");
 $display("PASS all 32768 addresses + 10000 random jumps, same one-cycle latency; checks=%0d nonblack=%0d",checks,lit);$finish;
end
endmodule
''',encoding='utf-8')
binary=out/'logo.vvp'
c=subprocess.run(['iverilog','-g2005','-s','tb_logo_equivalence','-o',str(binary),str(bench),str(ROOT/'src/boot/boot_logo_rom.v'),str(out/'boot_logo_rom_reference.v')],cwd=ROOT,capture_output=True,text=True,timeout=60)
assert c.returncode==0,c.stderr
r=subprocess.run(['vvp',str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=60)
log=c.stdout+c.stderr+r.stdout+r.stderr;(out/'result.log').write_text(log,encoding='utf-8');print(log)
raise SystemExit(0 if r.returncode==0 and 'PASS' in log and 'FAIL' not in log else 1)
