"""Compare observable FAT32 transactions after intentional internal pipelining."""
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'sim/resource_opt'
OUT.mkdir(exist_ok=True)
def invoke(name,source,extra):
    p=OUT/(name+'.v');p.write_text(source,encoding='utf-8')
    binary=OUT/(name+'.vvp')
    c=subprocess.run(['iverilog','-g2005','-s',name,'-o',str(binary),str(p),str(extra)],cwd=ROOT,capture_output=True,text=True)
    if c.returncode:raise RuntimeError(c.stderr)
    r=subprocess.run(['vvp',str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=120)
    (OUT/(name+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
    if r.returncode or 'FAIL' in r.stdout or 'PASS' not in r.stdout:raise RuntimeError(r.stdout+r.stderr)
    return [x for x in r.stdout.splitlines() if x.startswith('TRACE')]

def main():
    ref=OUT/'fat32_file_streamer_reference.v'
    ref.write_text((ROOT/'prj/resource_opt_20261005/baseline/fat32_file_streamer.v').read_text(encoding='utf-8').replace('module fat32_file_streamer #(','module fat32_file_streamer_reference #('),encoding='utf-8')
    source=(ROOT/'sim/tb_fat32_file_streamer.v').read_text(encoding='utf-8')
    trace='''
    always @(negedge clk) if(rst_n) begin
        if(sector_req) $display("TRACE_REQ %h",sector_lba);
        if(file_valid) $display("TRACE_BYTE %h %h",file_byte_offset,file_byte);
        if(file_done) $display("TRACE_END %h",fs_error);
    end
'''
    # Request timing differs, so each implementation has its own sector server.
    # Compare ordered LBA, byte+offset and terminal status, not idle cycles.
    source=source.replace('    always #5 clk = ~clk;',trace+'\n    always #5 clk = ~clk;')
    a=invoke('tb_streamer_transactions',source.replace('module tb_fat32_file_streamer;','module tb_streamer_transactions;'),ROOT/'src/SD/fat32_file_streamer.v')
    b=invoke('tb_streamer_reference_transactions',source.replace('module tb_fat32_file_streamer;','module tb_streamer_reference_transactions;').replace('fat32_file_streamer dut','fat32_file_streamer_reference dut'),ref)
    assert a==b and len(a)>1536, 'FAT32 byte/LBA/error transaction mismatch'
    print(f'PASS: FAT32 baseline transaction equivalence ({len(a)} ordered events)')
    source='''`timescale 1ns/1ps
module tb_cluster_offset_pipeline;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,start=0;reg [31:0] first_cluster=0;reg [7:0] spc=0;
wire req,done;wire [31:0]lba;wire[7:0]err;
integer s,n;reg[31:0]expected;
fat32_file_streamer dut(.clk(clk),.rst_n(rst_n),.file_start(start),
 .first_cluster(first_cluster),.file_size(32'd512),.sectors_per_cluster(spc),
 .fat_start_lba(32'd10),.data_start_lba(32'd30),.max_cluster(32'hffffffff),
 .sector_busy(1'b0),.sector_valid(1'b0),.sector_byte(8'd0),.sector_byte_index(9'd0),
 .sector_done(1'b0),.sector_error(8'd0),.sector_req(req),.sector_lba(lba),.file_done(done),.fs_error(err));
initial begin
 for(s=0;s<256;s=s+1) for(n=0;n<1024;n=n+1) begin
  @(negedge clk);rst_n=0;start=0;spc=s;first_cluster=n<4 ? n : $random;
  repeat(2) @(negedge clk);rst_n=1;start=1;
  @(negedge clk);start=0;wait(req || done);#1;
  if(first_cluster<2 || spc==0) begin
   if(!done || err!=8'h24) $fatal(1,"FAIL invalid first cluster/SPC");
  end else begin
   expected=30+((first_cluster-32'd2)<<dut.cluster_shift(spc));
   if(!req || lba!==expected) $fatal(1,"FAIL pipelined cluster address");
  end
 end
 $display("PASS: 262144 pipelined cluster LBA cases, all BPB selector bytes");$finish;
end
endmodule
'''
    invoke('tb_cluster_offset_pipeline',source,ROOT/'src/SD/fat32_file_streamer.v')
    print('PASS: 262144 pipelined cluster LBA cases, all BPB selector bytes')
if __name__=='__main__':main()
