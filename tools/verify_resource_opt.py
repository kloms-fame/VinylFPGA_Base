"""Run lecture regressions and compare WAV outputs against the saved baseline.

Run from any directory with Python and Icarus Verilog on PATH.
Generated benches/logs stay in sim/resource_opt; any FAIL or timeout fails the run.
"""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'sim/resource_opt'
OUT.mkdir(parents=True, exist_ok=True)
BASE = ROOT / 'prj/resource_opt_20261005/baseline/wav_stream_player.v'
reference = OUT / 'wav_stream_player_reference.v'
reference.write_text(BASE.read_text(encoding='utf-8').replace(
    'module wav_stream_player #(', 'module wav_stream_player_reference #('), encoding='utf-8')


def run(name, sources, top=None):
    binary = OUT / (name + '.vvp')
    libraries = [str(p) for p in (ROOT / 'src').iterdir() if p.is_dir()]
    compile_result = subprocess.run(['iverilog', '-g2005', '-I', str(ROOT / 'src/include'),
        '-y', str(ROOT / 'src'), *[arg for path in libraries for arg in ('-y', path)],
        '-s', top or name, '-o', str(binary), *map(str, sources)],
        cwd=ROOT, capture_output=True, text=True, timeout=60,
        encoding='utf-8', errors='replace')
    if compile_result.returncode:
        raise RuntimeError(compile_result.stderr)
    result = subprocess.run(['vvp', str(binary)], cwd=OUT, capture_output=True,
                            text=True, timeout=120, encoding='utf-8', errors='replace')
    log = compile_result.stdout + compile_result.stderr + result.stdout + result.stderr
    (OUT / (name + '.log')).write_text(log, encoding='utf-8')
    if result.returncode or 'FAIL' in log or 'PASS' not in log:
        raise RuntimeError(name + '\n' + log)
    print(name + ': ' + '; '.join(x for x in log.splitlines() if 'PASS' in x))


def equivalence_bench(name, source, stress=False, control=False):
    source = source.replace('module tb_wav_stream_player_flow;', 'module ' + name + ';')
    source = source.replace('SECTORS = 12', 'SECTORS = 40')
    source = source.replace('wire        sample_ready = 1\'b1;',
                            "reg         sample_ready = 1'b1;")
    outputs = {'sd_req': 1, 'sd_lba': 32, 'sample_out': 16, 'sample_valid': 1,
               'sample_counter': 32, 'stream_active': 1, 'stream_end': 1, 'buffer_low': 1}
    instance = re.search(r'    wav_stream_player #\(.*?\n    \);', source, re.S).group(0)
    ref_instance = instance.replace('wav_stream_player #(', 'wav_stream_player_reference #(').replace(') dut (', ') reference_dut (')
    declarations = '\n'.join('    wire [%d:0] ref_%s;' % (width - 1, port)
                             for port, width in outputs.items())
    for port in outputs:
        ref_instance = re.sub(r'(\.' + port + r'\s*\()' + port + r'(\))',
                              r'\1ref_' + port + r'\2', ref_instance)
    checks = '''
    integer compared = 0;
    always @(negedge wr_clk or negedge rd_clk) begin
        if (wr_rst_n && rd_rst_n) begin
            compared = compared + 1;
            if ({sd_req,sd_lba,sample_out,sample_valid,sample_counter,
                 stream_active,stream_end,buffer_low} !==
                {ref_sd_req,ref_sd_lba,ref_sample_out,ref_sample_valid,ref_sample_counter,
                 ref_stream_active,ref_stream_end,ref_buffer_low})
                $fatal(1, "FAIL cycle equivalence at %0t sample=%h ref=%h count=%0d", $time,
                       sample_out, ref_sample_out, sample_counter);
        end
    end
'''
    if stress:
        source = source.replace('end else if (feeding) begin',
                                'end else if (feeding && noise_wr[2:0] != 0) begin')
        checks += '''
    reg [31:0] noise_wr = 32'h7129a34b;
    reg [31:0] noise_rd = 32'h164cab97;
    always @(negedge wr_clk)
        noise_wr <= {noise_wr[30:0],noise_wr[31]^noise_wr[21]^noise_wr[1]^noise_wr[0]};
    always @(negedge rd_clk) begin
        noise_rd <= {noise_rd[30:0],noise_rd[31]^noise_rd[21]^noise_rd[1]^noise_rd[0]};
        sample_ready <= noise_rd[1:0] != 0;
    end
'''
    source = source.replace(instance, declarations + '\n' + instance + '\n' + ref_instance + checks)
    if control:
        # Interrupted playback need not satisfy the uninterrupted-stream scoreboard.
        # It must still match every baseline output on both clocks.
        begin = source.index('    always @(negedge rd_clk) begin\n        if (stream_active)')
        end = source.index('    initial begin', begin)
        source = source[:begin] + source[end:]
        begin = source.index('    initial begin\n        repeat (8)')
        end = source.index('    initial begin\n        #200_000_000;', begin)
        source = source[:begin] + '''
    initial begin
        repeat (8) @(negedge wr_clk);
        wr_rst_n = 1;
        repeat (8) @(negedge rd_clk);
        rd_rst_n = 1;
        play_enable = 1;
        repeat (2500) @(negedge rd_clk);
        play_enable = 0;
        repeat (20) @(negedge rd_clk);
        play_enable = 1;
        repeat (2500) @(negedge rd_clk);
        wr_rst_n = 0; rd_rst_n = 0;
        repeat (10) @(negedge rd_clk);
        wr_rst_n = 1; rd_rst_n = 1;
        total_sectors = 1;
        // A card error asserted during transfer must drain identically.
        wait (tx_index == 97);
        @(negedge wr_clk); sd_error = 8'h41;
        repeat (3000) @(negedge rd_clk);
        if (!stream_end || stream_active)
            $fatal(1, "FAIL error stream did not drain");
        play_enable = 0;
        repeat (16) @(negedge rd_clk);
        wr_rst_n = 0; rd_rst_n = 0;
        repeat (10) @(negedge rd_clk);
        sd_error = 0; total_sectors = 1;
        wr_rst_n = 1; rd_rst_n = 1; play_enable = 1;
        repeat (3500) @(negedge rd_clk);
        if (!stream_end || sample_counter != 256)
            $fatal(1, "FAIL restart did not finish");
        $display("PASS: stop/restart, reset, SD error, silence equivalence");
        $finish;
    end
''' + source[end:]
    source = source.replace('$finish;', '$display("Compared %0d clock edges", compared); $finish;')
    file = OUT / (name + '.v')
    file.write_text(source, encoding='utf-8')
    run(name, [file, ROOT / 'src/audio/wav_stream_player.v', reference])


rtl = ROOT / 'src'
run('tb_wav_stream_player', [ROOT / 'sim/tb_wav_stream_player.v', rtl / 'audio/wav_stream_player.v'])
flow = (ROOT / 'sim/tb_wav_stream_player_flow.v').read_text(encoding='utf-8')
equivalence_bench('tb_wav_equiv_long', flow)
equivalence_bench('tb_wav_equiv_stalls', flow, stress=True)
equivalence_bench('tb_wav_equiv_control', flow, control=True)
run('tb_promax_audio_waveform', [ROOT / 'sim/tb_promax_audio_waveform.v', rtl / 'display/promax_audio_waveform.v'])

# Re-run the existing subsystem benches against the current sources.
for bench in sorted((ROOT / 'sim').glob('tb_*.v')):
    if bench.stem.startswith('tb_wav_') or bench.stem == 'tb_promax_audio_waveform':
        continue
    run(bench.stem, [bench])

# Compare the complete fragmented-chain test and all 256 possible BPB byte values.
stream_ref = OUT / 'fat32_file_streamer_reference.v'
stream_ref.write_text((BASE.parent / 'fat32_file_streamer.v').read_text(encoding='utf-8').replace(
    'module fat32_file_streamer #(', 'module fat32_file_streamer_reference #('), encoding='utf-8')
source = (ROOT / 'sim/tb_fat32_file_streamer.v').read_text(encoding='utf-8')
name = 'tb_fat32_streamer_equiv'
source = source.replace('module tb_fat32_file_streamer;', 'module ' + name + ';')
instance = re.search(r'    fat32_file_streamer dut \(.*?\n    \);', source, re.S).group(0)
outputs = {'file_busy':1,'file_done':1,'file_valid':1,'file_byte':8,
           'file_byte_offset':32,'fs_error':8,'sector_req':1,'sector_lba':32}
ref_inst = instance.replace('fat32_file_streamer dut', 'fat32_file_streamer_reference reference_dut')
for port in outputs:
    ref_inst = ref_inst.replace('(' + port + ')', '(ref_' + port + ')')
decl = '\n'.join('    wire [%d:0] ref_%s;' % (width-1, port) for port,width in outputs.items())
bus = ','.join(outputs)
ref_bus = ','.join('ref_' + x for x in outputs)
check = '\n    always @(negedge clk) if (rst_n && {' + bus + '} !== {' + ref_bus + '}) $fatal(1,"FAIL streamer cycle equivalence");\n'
source = source.replace(instance, decl + '\n' + instance + '\n' + ref_inst + check)
file = OUT / (name + '.v')
file.write_text(source, encoding='utf-8')
run(name, [file, stream_ref])

# Prove the only changed combinational expression for every selector and random
# 32-bit cluster values, including wraparound, invalid BPB values and sign bits.
source = '''`timescale 1ns/1ps
module tb_cluster_offset_equiv;
reg [31:0] first_cluster;
reg [7:0] sectors_per_cluster;
integer s, n;
fat32_file_streamer dut (.first_cluster(first_cluster), .sectors_per_cluster(sectors_per_cluster));
initial begin
  for (s=0;s<256;s=s+1) begin
    sectors_per_cluster=s;
    for (n=0;n<1024;n=n+1) begin
      first_cluster = n<4 ? n : $random;
      #1;
      if (dut.first_cluster_offset !== ((first_cluster - 32'd2) << dut.cluster_shift(sectors_per_cluster)))
        $fatal(1,"FAIL cluster offset spc=%0d cluster=%h",s,first_cluster);
    end
  end
  $display("PASS: 262144 cluster offset cases, all BPB byte values");
  $finish;
end
endmodule
'''
file = OUT / 'tb_cluster_offset_equiv.v'
file.write_text(source, encoding='utf-8')
run('tb_cluster_offset_equiv', [file])
print('PASS: all resource optimization regressions')
