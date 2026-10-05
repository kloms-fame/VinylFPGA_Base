"""Cycle comparisons with immutable pre-optimization RTL, including timer bounds."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'prj/resource_opt_verified_20261005/baseline/src'
OUT = ROOT / 'sim/resource_opt_verified'
OUT.mkdir(parents=True, exist_ok=True)

def simulate(name, source, files):
    bench = OUT / (name + '.v')
    bench.write_text(source, encoding='utf-8')
    binary = OUT / (name + '.vvp')
    libs = [ROOT / 'src', *[p for p in (ROOT / 'src').iterdir() if p.is_dir()]]
    cp = subprocess.run(['iverilog', '-g2005', '-I', str(ROOT / 'src/include'),
                         *[a for p in libs for a in ('-y', str(p))], '-s', name,
                         '-o', str(binary), str(bench), *map(str, files)],
                        capture_output=True, text=True, timeout=60)
    if cp.returncode:
        raise RuntimeError(cp.stderr)
    run = subprocess.run(['vvp', str(binary)], capture_output=True, text=True, timeout=120)
    log = cp.stderr + run.stdout + run.stderr
    (OUT / (name + '.log')).write_text(log, encoding='utf-8')
    if run.returncode or 'FAIL' in log or 'PASS' not in log:
        raise RuntimeError(log)
    print(name + ': ' + '; '.join(s for s in log.splitlines() if 'PASS' in s), flush=True)

def reference(rel, module):
    path = OUT / (module + '_reference.v')
    src = (BASE / rel).read_text(encoding='utf-8')
    src = re.sub(r'\bmodule\s+' + module + r'\b', 'module ' + module + '_reference', src)
    if module == 'sd_card_bmp':
        src = src.replace('key_press_debounce', 'key_press_debounce_reference')
    path.write_text(src, encoding='utf-8')
    return path

def existing_miter(module, rel, outputs, bench_module=None, reset='rst_n'):
    name = 'tb_' + module + '_opt_equiv'
    bench_module = bench_module or 'tb_' + module
    src = (ROOT / 'sim' / (bench_module + '.v')).read_text(encoding='utf-8')
    src = src.replace('module ' + bench_module + ';', 'module ' + name + ';')
    inst = re.search(r'    ' + module + r'\b.*?\bdut\s*\(.*?\n    \);', src, re.S).group(0)
    ref = inst.replace(module, module + '_reference', 1).replace('dut (', 'reference_dut (')
    decl = []
    for port, width in outputs.items():
        ref = re.sub(r'(\.' + port + r'\s*\()[^)]*(\))', r'\1ref_' + port + r'\2', ref)
        decl.append('wire [%d:0] ref_%s;' % (width-1, port))
    check = 'always @(negedge clk) if (' + reset + ' && {' + ','.join('dut.' + p for p in outputs) + '} !== {' + ','.join('reference_dut.' + p for p in outputs) + '}) $fatal(1,"FAIL cycle outputs at %0t",$time);'
    src = src.replace(inst, '\n'.join(decl) + '\n' + inst + '\n' + ref + '\n' + check)
    simulate(name, src, [reference(rel, module)])

def menu():
    outputs = dict(key1_out_n=1,key2_out_n=1,cfg_brightness=8,cfg_contrast=8,
                   cfg_update_valid=1,menu_event=1,menu_kind=2,menu_level=4,menu_active=1)
    existing_miter('param_menu_controller', 'io/param_menu_controller.v', outputs)
    counters = {'key1_deb_cnt':'DEBOUNCE_CYCLES', 'key2_deb_cnt':'DEBOUNCE_CYCLES',
                'combo_cnt':'COMBO_CYCLES', 'key1_hold_cnt':'LONG_CYCLES',
                'key2_hold_cnt':'LONG_CYCLES', 'menu_idle_cnt':'TIMEOUT_CYCLES'}
    ref = reference('io/param_menu_controller.v', 'param_menu_controller')
    # Tiny powers of two exercise the saturated value itself, not only limit-1.
    # Default parameters use direct state deposits to reach real 100MHz thresholds.
    for limit in (1,2,4,8,17,0):
        name = 'tb_menu_bounds_' + str(limit)
        params = '' if limit == 0 else '#(.CLK_FREQ_HZ(1000), .DEBOUNCE_MS(%d), .COMBO_HOLD_MS(%d), .LONG_HOLD_MS(%d), .MENU_TIMEOUT_MS(%d))' % ((limit,)*4)
        checks = '\n'.join('if (dut.%s !== refdut.%s) $fatal(1,"FAIL %s at %%0t",$time);' % (p,p,p) for p in [*outputs,*counters])
        deposits = []
        for counter, bound in counters.items():
            # Replay branch combinations at limit-2, limit-1 and limit.
            setup = '''dut.key1_sync=0; refdut.key1_sync=0;
dut.key2_sync=0; refdut.key2_sync=0;
dut.key1_raw=1; refdut.key1_raw=1; dut.key2_raw=1; refdut.key2_raw=1;'''
            if 'hold' in counter or 'idle' in counter:
                setup += '''dut.menu_active=1; refdut.menu_active=1;
dut.menu_entry_lock=0; refdut.menu_entry_lock=0;
dut.key2_sync=3; refdut.key2_sync=3;
dut.key1_stable=0; refdut.key1_stable=0;
dut.key2_stable=0; refdut.key2_stable=0;'''
            if 'idle' in counter:
                setup += '''dut.key1_stable=1; refdut.key1_stable=1;
dut.key2_stable=1; refdut.key2_stable=1;'''
            deposits.append('''for (offset=2;offset>=0;offset=offset-1) begin
 if (refdut.%s >= offset) begin
  rst_n=0; repeat(2) @(negedge clk); rst_n=1;
  %s
  dut.%s=refdut.%s-offset; refdut.%s=refdut.%s-offset;
  repeat(8) @(negedge clk);
 end
end''' % (bound,setup,counter,bound,counter,bound))
        src = '''`timescale 1ns/1ps
module %s;
reg clk=0,rst_n=0,key1_n=1,key2_n=1;
integer offset,n; reg[31:0] rng=32'h159267ab;
always #5 clk=~clk;
param_menu_controller %s dut(.clk(clk),.rst_n(rst_n),.key1_n(key1_n),.key2_n(key2_n));
param_menu_controller_reference %s refdut(.clk(clk),.rst_n(rst_n),.key1_n(key1_n),.key2_n(key2_n));
always @(posedge clk) begin #1; if(rst_n) begin %s end end
initial begin
 repeat(3) @(negedge clk); rst_n=1;
 %s
 rst_n=0; repeat(3) @(negedge clk); rst_n=1;
 for(n=0;n<12000;n=n+1) begin
  @(negedge clk);
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(n%%41==0) begin key1_n=rng[0];key2_n=rng[1];end
  if(n%%877==0) rst_n=0; else rst_n=1;
 end
 $display("PASS timer boundaries, saturation, random bounce and reset");$finish;
end
endmodule
''' % (name,params,params,checks,'\n'.join(deposits))
        simulate(name, src, [ref])

def keys():
    existing_miter('sd_card_bmp', 'SD/sd_card_bmp.v',
        dict(state_code=4,display_valid=1,write_buf_idx=2,disp_buf_idx=2,select_ack=1,
             write_req=1,write_en=1,write_data=32,SD_nCS=1,SD_DCLK=1,SD_MOSI=1,
             audio_file_valid=1,audio_start_lba=32,audio_total_sectors=32,
             audio_play_enable=1,audio_sec_busy=1,audio_sec_valid=1,
             audio_sec_byte=8,audio_sec_byte_index=9,audio_sec_done=1,audio_sec_error=8),
        'tb_sd_card_bmp_fourbank', '!rst')
    ref = reference('SD/key_press_hold.v', 'key_press_hold')
    for limit in (1,2,4,8,17,0):
        name = 'tb_key_bounds_' + str(limit)
        params = '' if limit == 0 else '#(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(%d),.HOLD_MS(%d))' % (limit,limit)
        checks = '\n'.join('if(dut.%s !== refdut.%s) $fatal(1,"FAIL %s");' % (p,p,p)
                           for p in ('deb_cnt','hold_cnt','press_pulse','hold_pulse','button_stable_out'))
        src = '''`timescale 1ns/1ps
module %s;
reg clk=0,rst=1,button_in=1; integer n,offset; reg[31:0] rng=32'hb15217;
always #5 clk=~clk;
key_press_hold %s dut(.clk(clk),.rst(rst),.button_in(button_in));
key_press_hold_reference %s refdut(.clk(clk),.rst(rst),.button_in(button_in));
always @(posedge clk) begin #1; if(!rst) begin %s end end
initial begin
 repeat(3) @(negedge clk); rst=0;
 for(offset=2;offset>=0;offset=offset-1) begin
  if(refdut.HOLD_CYCLES>=offset) begin
   rst=1; repeat(2) @(negedge clk); rst=0; button_in=0;
   dut.stable=0;refdut.stable=0;dut.stable_d=0;refdut.stable_d=0;
   dut.sync0=0;refdut.sync0=0;dut.sync1=0;refdut.sync1=0;
   dut.hold_cnt=refdut.HOLD_CYCLES-offset;refdut.hold_cnt=refdut.HOLD_CYCLES-offset;
   repeat(12) @(negedge clk);
  end
  if(refdut.DEBOUNCE_CYCLES>=offset) begin
   rst=1; repeat(2) @(negedge clk); rst=0; button_in=0;
   dut.sync0=0;refdut.sync0=0;dut.sync1=0;refdut.sync1=0;
   dut.deb_cnt=refdut.DEBOUNCE_CYCLES-offset;refdut.deb_cnt=refdut.DEBOUNCE_CYCLES-offset;
   repeat(12) @(negedge clk);
  end
 end
 rst=1;repeat(2) @(negedge clk);rst=0;
 for(n=0;n<16000;n=n+1) begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(n%%37==0) button_in=rng[0];
  rst=(n%%887==0);
 end
 $display("PASS hold saturation, debounce boundary, random press/release/reset");$finish;
end
endmodule
''' % (name,params,params,checks)
        simulate(name,src,[ref])

def header():
    existing_miter('fat32_media_loader','SD/fat32_media_loader.v',
        dict(ready=1,scan_done=1,scan_found_valid=1,scan_found_index=2,scan_found_total=1,
             state_code=4,bmp_error=4,load_error=1,write_req=1,
             bmp_data_wr_en=1,bmp_data=24,sd_sec_read=1,sd_sec_read_addr=32,
             audio_file_valid=1,audio_start_lba=32,audio_total_sectors=32,
             audio_sec_busy=1,audio_sec_valid=1,audio_sec_byte=8,audio_sec_byte_index=9,
             audio_sec_done=1,audio_sec_error=8), reset='!rst')

if __name__ == '__main__':
    if sys.argv[1] == 'menu':
        menu()
    elif sys.argv[1] == 'keys':
        keys()
    elif sys.argv[1] == 'header':
        header()
