"""Exhaustive decimal formatting and linear CRC equivalence against M0 RTL."""
from pathlib import Path
import argparse
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--label',default='current');a=p.parse_args()
out=ROOT/'sim/resource_opt_verified'/('arithmetic_'+a.label);out.mkdir(parents=True,exist_ok=True)
base=ROOT/'prj/resource_opt_verified_20261005/S703_M0_20261006/src'
parts=['`timescale 1ns/1ps','module tb_arithmetic;','reg [15:0] capture;','reg[15:0] expected;',
       'integer i,j; reg[31:0] c; reg[7:0] d; reg[31:0] noise=32\'h39bda781;',
       'task put_byte; input[7:0] b;begin capture={capture[7:0],b};end endtask']
for root,suffix in [(base,'_ref'),(ROOT/'src','')]:
    source=(root/'io/exp_echo_reporter.v').read_text(encoding='utf-8')
    for name in ('put_dec2','put_dec1'):
        fragment=re.search(r'\btask '+name+r';.*?endtask',source,re.S)[0]
        parts.append(fragment.replace('task '+name+';', 'task '+name+suffix+';'))
    source=(root/'SD/song_index_db.v').read_text(encoding='utf-8')
    fragment=re.search(r'function \[31:0\] crc32_byte;.*?endfunction',source,re.S)[0]
    parts.append(fragment.replace('crc32_byte','crc32_byte'+suffix))
    source=(root/'SD/fat32_media_loader.v').read_text(encoding='utf-8')
    expr=next(expr for expr in re.findall(r'required_pixel_bytes_q\s*<=\s*([^;]+);',source)
              if 'bmp_width' in expr)
    parts.append('function [31:0] pixel_bytes'+suffix+'; input[15:0] bmp_width,bmp_height; begin pixel_bytes'+suffix+' = '+expr+'; end endfunction')
parts+=['task check_crc; begin if(crc32_byte(c,d)!==crc32_byte_ref(c,d)) $fatal(1,"FAIL CRC c=%h d=%h",c,d); end endtask',
        'initial begin',
        'for(i=0;i<256;i=i+1) begin',
        'capture=0;put_dec2_ref(i[7:0]);expected=capture;capture=0;put_dec2(i[7:0]);',
        'if(capture!==expected)$fatal(1,"FAIL decimal2 %0d",i);',
        'capture=0;put_dec1_ref(i[7:0]);expected=capture;capture=0;put_dec1(i[7:0]);',
        'if(capture!==expected)$fatal(1,"FAIL decimal1 %0d",i);',
        'end',
        # Each fixed byte across zero, all-one, each CRC basis bit and PRNG states.
        'for(i=0;i<256;i=i+1) begin d=i; c=0;check_crc;c=32\'hffffffff;check_crc;',
        'for(j=0;j<32;j=j+1)begin c=32\'b1<<j;check_crc;end end',
        'for(i=0;i<100000;i=i+1)begin noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};c=noise;d=noise[15:8];check_crc;end',
        'for(i=0;i<100000;i=i+1)begin noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};',
        'if(pixel_bytes(noise[31:16],noise[15:0])!==pixel_bytes_ref(noise[31:16],noise[15:0])) $fatal(1,"FAIL pixel arithmetic");end',
        'if(pixel_bytes(65535,65535)!==pixel_bytes_ref(65535,65535))$fatal(1,"FAIL 32-bit overflow");',
        '$display("PASS decimal1/2 all 256 bytes; CRC 8704 basis/byte pairs + 100000 random pairs; pixel arithmetic 100001 pairs");$finish;',
        'end','endmodule']
bench=out/'tb_arithmetic.v';bench.write_text('\n'.join(parts),encoding='utf-8');binary=out/'tb_arithmetic.vvp'
c=subprocess.run(['iverilog','-g2005','-s','tb_arithmetic','-o',str(binary),str(bench)],cwd=ROOT,capture_output=True,text=True,timeout=30)
assert c.returncode==0,c.stderr
r=subprocess.run(['vvp',str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=60)
log=c.stdout+c.stderr+r.stdout+r.stderr;(out/'result.log').write_text(log,encoding='utf-8');print(log)
raise SystemExit(0 if r.returncode==0 and 'PASS' in log and 'FAIL' not in log else 1)
