`timescale 1ns/1ps
`include "sim/optimization/song_index_db_reference.v"
// Default: actual encoded candidate wires are checked. Only unchanged baseline
// and the deliberate pre-implementation mutant use -DN2_BASELINE_TB.
module tb_resource_n2_version_equiv;
reg clk=0,rst_n=0,start=0,in_valid=0,in_done=0;
reg [7:0] in_byte=0,in_error=0;
reg [31:0] max_cluster=100;
reg [7:0] blob[0:511];
reg [15:0] oracle_raw=0;
reg [8:0] oracle_idx=0;
reg [31:0] rng=32'h62e2b731;
integer cycles=0,wire_checks=0,exhaustive=0,transactions=0,done_pulses=0;
integer low_updates=0,high_updates=0,gaps=0,busy_starts=0,wraps=0;
integer n,j,v,c,errcase,old_done=0,finish_before;
reg [15:0] model_raw;
reg model_l1,model_l2,model_h0;
integer model_checks=0,fourstate_cases=0;
wire  d_busy, r_busy;
wire  d_done, r_done;
wire  d_valid, r_valid;
wire [7:0] d_err, r_err;
wire [2:0] d_song_count, r_song_count;
wire [15:0] d_song_flags, r_song_flags;
wire [63:0] d_song_cover0, r_song_cover0;
wire [63:0] d_song_cover1, r_song_cover1;
wire [63:0] d_song_cover2, r_song_cover2;
wire [63:0] d_song_cover3, r_song_cover3;
wire [63:0] d_song_audio0, r_song_audio0;
wire [63:0] d_song_audio1, r_song_audio1;
wire [63:0] d_song_audio2, r_song_audio2;
wire [63:0] d_song_audio3, r_song_audio3;
wire [63:0] d_song_mv0, r_song_mv0;
wire [63:0] d_song_mv1, r_song_mv1;
wire [63:0] d_song_mv2, r_song_mv2;
wire [63:0] d_song_mv3, r_song_mv3;
song_index_db dut(.clk(clk),.rst_n(rst_n),.start(start),.in_valid(in_valid),.in_byte(in_byte),.in_done(in_done),.in_error(in_error),.max_cluster(max_cluster),.busy(d_busy),.done(d_done),.valid(d_valid),.err(d_err),.song_count(d_song_count),.song_flags(d_song_flags),.song_cover0(d_song_cover0),.song_cover1(d_song_cover1),.song_cover2(d_song_cover2),.song_cover3(d_song_cover3),.song_audio0(d_song_audio0),.song_audio1(d_song_audio1),.song_audio2(d_song_audio2),.song_audio3(d_song_audio3),.song_mv0(d_song_mv0),.song_mv1(d_song_mv1),.song_mv2(d_song_mv2),.song_mv3(d_song_mv3));
song_index_db_reference reference_dut(.clk(clk),.rst_n(rst_n),.start(start),.in_valid(in_valid),.in_byte(in_byte),.in_done(in_done),.in_error(in_error),.max_cluster(max_cluster),.busy(r_busy),.done(r_done),.valid(r_valid),.err(r_err),.song_count(r_song_count),.song_flags(r_song_flags),.song_cover0(r_song_cover0),.song_cover1(r_song_cover1),.song_cover2(r_song_cover2),.song_cover3(r_song_cover3),.song_audio0(r_song_audio0),.song_audio1(r_song_audio1),.song_audio2(r_song_audio2),.song_audio3(r_song_audio3),.song_mv0(r_song_mv0),.song_mv1(r_song_mv1),.song_mv2(r_song_mv2),.song_mv3(r_song_mv3));
always #5 clk=~clk;
// Input-driven independent 16-bit oracle; never changes product byte_idx.
always @(posedge clk) begin
  cycles=cycles+1;
  if(!rst_n) begin oracle_raw=0; oracle_idx=0; end
  else if(start && reference_dut.phase==0) begin oracle_raw=0; oracle_idx=0; end
  else if(reference_dut.phase==1 && in_valid) begin
    if(oracle_idx==8) begin oracle_raw[7:0]=in_byte; low_updates=low_updates+1; end
    if(oracle_idx==9) begin oracle_raw[15:8]=in_byte; high_updates=high_updates+1; end
    if(oracle_idx==511) wraps=wraps+1;
    oracle_idx=oracle_idx+9'd1;
  end
  #1;
  if(d_busy !== r_busy) $fatal(1,"FAIL output busy cycle=%0d version=%h",cycles,oracle_raw);
if(d_done !== r_done) $fatal(1,"FAIL output done cycle=%0d version=%h",cycles,oracle_raw);
if(d_valid !== r_valid) $fatal(1,"FAIL output valid cycle=%0d version=%h",cycles,oracle_raw);
if(d_err !== r_err) $fatal(1,"FAIL output err cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_count !== r_song_count) $fatal(1,"FAIL output song_count cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_flags !== r_song_flags) $fatal(1,"FAIL output song_flags cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_cover0 !== r_song_cover0) $fatal(1,"FAIL output song_cover0 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_cover1 !== r_song_cover1) $fatal(1,"FAIL output song_cover1 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_cover2 !== r_song_cover2) $fatal(1,"FAIL output song_cover2 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_cover3 !== r_song_cover3) $fatal(1,"FAIL output song_cover3 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_audio0 !== r_song_audio0) $fatal(1,"FAIL output song_audio0 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_audio1 !== r_song_audio1) $fatal(1,"FAIL output song_audio1 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_audio2 !== r_song_audio2) $fatal(1,"FAIL output song_audio2 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_audio3 !== r_song_audio3) $fatal(1,"FAIL output song_audio3 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_mv0 !== r_song_mv0) $fatal(1,"FAIL output song_mv0 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_mv1 !== r_song_mv1) $fatal(1,"FAIL output song_mv1 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_mv2 !== r_song_mv2) $fatal(1,"FAIL output song_mv2 cycle=%0d version=%h",cycles,oracle_raw);
if(d_song_mv3 !== r_song_mv3) $fatal(1,"FAIL output song_mv3 cycle=%0d version=%h",cycles,oracle_raw);
`ifdef N2_BASELINE_TB
  if(dut.hdr_version !== oracle_raw) $fatal(1,"FAIL baseline raw oracle");
  if((dut.hdr_version==16'd1) !== (oracle_raw==16'd1) ||
     (dut.hdr_version==16'd2) !== (oracle_raw==16'd2)) $fatal(1,"FAIL baseline classification");
`else
  if(dut.version_is_v1 !== (oracle_raw==16'd1) ||
     dut.version_is_v2 !== (oracle_raw==16'd2))
    $fatal(1,"FAIL actual encoded wires cycle=%0d raw=%h v1=%b v2=%b",cycles,oracle_raw,dut.version_is_v1,dut.version_is_v2);
`endif
  wire_checks=wire_checks+2;
  if(d_done) begin
    done_pulses=done_pulses+1;
    if(old_done) $fatal(1,"FAIL consecutive done pulse");
  end
  old_done=d_done;
  if((reference_dut.phase==1 || reference_dut.phase==2 || reference_dut.phase==3) && d_valid)
    $fatal(1,"FAIL outputs released before P_FIN edge");
end
task tick;
 input s,iv,id; input [7:0] b,e;
 begin
  @(negedge clk);start=s;in_valid=iv;in_done=id;in_byte=b;in_error=e;
  @(posedge clk);#2;
 end
endtask
task reset_all;
 begin
  @(negedge clk);rst_n=0;start=0;in_valid=0;in_done=0;in_error=0;
  @(posedge clk);#2;
  @(negedge clk);rst_n=1;
  @(posedge clk);#2;
 end
endtask
task begin_load;
 begin tick(1,0,0,0,0);transactions=transactions+1;end
endtask
// Independent bit-serial CRC: consume each incoming bit and feedback bit,
// unlike the production byte-xor implementation. Check canonical known vector.
function [31:0] crc_bitserial;
 input [31:0] ci; input [7:0] data;
 reg [31:0] q;reg mix;integer bitn;
 begin q=ci;for(bitn=0;bitn<8;bitn=bitn+1) begin
   mix=q[0]^data[bitn];q=q>>1;if(mix)q=q^32'hedb88320;
 end crc_bitserial=q;end
endfunction
task put32;
 input integer off;input [31:0] value;integer z;
 begin for(z=0;z<4;z=z+1)blob[off+z]=(value>>(8*z));end
endtask
task re_crc;
 reg [31:0] q;integer z;
 begin q=32'hffffffff;for(z=64;z<320;z=z+1)q=crc_bitserial(q,blob[z]);put32(16,q^32'hffffffff);end
endtask
task make_blob;
 input [15:0] ver;input mv_enabled;integer z,base;
 begin
  for(z=0;z<512;z=z+1)blob[z]=0;
  blob[0]="V";blob[1]="I";blob[2]="N";blob[3]="Y";
  blob[4]="L";blob[5]="I";blob[6]="D";blob[7]="X";
  blob[8]=ver[7:0];blob[9]=ver[15:8];blob[10]=64;blob[12]=4;
  for(z=0;z<4;z=z+1)begin
   base=64+z*64;blob[base]=mv_enabled?8'h0b:8'h03;
   put32(base+4,3+z);put32(base+8,822+z);
   put32(base+16,12+z);put32(base+20,2048+z);
   put32(base+56,32'h12340000+z);
   blob[base+60]=5+z;blob[base+61]=0;blob[base+62]=10;blob[base+63]=1;
  end
  re_crc;
 end
endtask
task complete_load;
 input integer len;input gap_mode;input simultaneous;input [7:0] stream_err;
 integer z,waitn,pulses_before;reg inject;
 begin
  pulses_before=done_pulses;begin_load;
  for(z=0;z<len;z=z+1)begin
   if(gap_mode && (z%7==0))begin
    tick(0,0,0,8'hff,0);tick(0,0,0,8'h02,0);gaps=gaps+2;
   end
   inject=gap_mode && (z%53==8);
   if(inject)busy_starts=busy_starts+1;
   tick(inject,1,simultaneous && z==len-1,blob[z%512],stream_err);
  end
  if(!simultaneous)tick(0,0,1,0,stream_err);
  tick(0,0,0,0,0);
  waitn=0;
  while(!d_done && waitn<16)begin tick(0,0,0,0,0);waitn=waitn+1;end
  if(!d_done)$fatal(1,"FAIL missing done");
  if(done_pulses!=pulses_before+1)$fatal(1,"FAIL done pulse count");
  tick(0,0,0,0,0);
 end
endtask
task expected_error;
 input [7:0] e;
 begin if(d_valid !== (e==0) || d_err !== e)$fatal(1,"FAIL independent error expected=%h got=%h valid=%b",e,d_err,d_valid);end
endtask
task positives;
 input [15:0] ver;input mv_enabled;
 begin
  make_blob(ver,mv_enabled);complete_load(512,1,0,0);expected_error(0);
  if(d_song_count!==3'd4)$fatal(1,"FAIL literal count");
  if(d_song_flags!==((ver==2 && mv_enabled)?16'hbbbb:16'h3333))$fatal(1,"FAIL literal flags");
  if(d_song_cover0!==64'h0000033600000003 || d_song_cover1!==64'h0000033700000004 ||
     d_song_cover2!==64'h0000033800000005 || d_song_cover3!==64'h0000033900000006 ||
     d_song_audio0!==64'h000008000000000c || d_song_audio1!==64'h000008010000000d ||
     d_song_audio2!==64'h000008020000000e || d_song_audio3!==64'h000008030000000f)
    $fatal(1,"FAIL literal cover/audio descriptors");
  if(ver==2 && mv_enabled) begin
   if(d_song_mv0!==64'h010a000512340000 || d_song_mv1!==64'h010a000612340001 ||
      d_song_mv2!==64'h010a000712340002 || d_song_mv3!==64'h010a000812340003)
    $fatal(1,"FAIL literal MV descriptors");
  end else if({d_song_mv0,d_song_mv1,d_song_mv2,d_song_mv3}!==256'd0)$fatal(1,"FAIL MV suppression");
 end
endtask
// Algebraic model supplements actual-stream checks: both byte orders, repeated
// writes and partial versions with stale opposite-byte information.
task model_check;
 begin
  if((model_l1&&model_h0)!==(model_raw==16'd1) || (model_l2&&model_h0)!==(model_raw==16'd2))
   $fatal(1,"FAIL independent model");model_checks=model_checks+1;
 end
endtask
reg [31:0] crc_known;
// Explicit four-state streamed bytes supplement the 65536 binary versions.
// Existing NBA checks compare actual candidate wires and all public outputs;
// expected classifications also check known mismatch dominates X/Z semantics.
task fourstate_header;
 input [7:0] lo,hi;input integer len;input expected_v1,expected_v2;
 begin
  reset_all;make_blob(2,1);blob[8]=lo;blob[9]=hi;
  complete_load(len,1,0,0);
  if((oracle_raw==16'd1)!==expected_v1 || (oracle_raw==16'd2)!==expected_v2)
   $fatal(1,"FAIL four-state expected classification raw=%h",oracle_raw);
  fourstate_cases=fourstate_cases+1;
 end
endtask
initial begin
 if(dut.SIDX_VERSION!==16'd1 || dut.SIDX_VERSION[15:8]!==8'd0)$fatal(1,"FAIL constant premise");
 crc_known=32'hffffffff;
 for(n=0;n<9;n=n+1)crc_known=crc_bitserial(crc_known,8'h31+n);
 if((crc_known^32'hffffffff)!==32'hcbf43926)$fatal(1,"FAIL CRC known vector");
 reset_all;
 // Valid positives and rejection paths precede the long exhaustive sweep so a
 // semantic mutant fails quickly, before production implementation.
 positives(1,0);positives(1,1);positives(2,0);positives(2,1);
 for(v=0;v<7;v=v+1)begin
  case(v)0:make_blob(0,1);1:make_blob(3,1);2:make_blob(16'h0101,1);
   3:make_blob(16'h0102,1);4:make_blob(16'hff02,1);5:make_blob(16'hffff,1);6:make_blob(16'h0006,1);endcase
  complete_load(512,1,0,0);expected_error(8'h31);
 end
 // Error priorities with multiple simultaneous invalid fields.
 make_blob(3,1);blob[0]=0;blob[10]=0;blob[12]=5;blob[16]=~blob[16];
 complete_load(512,0,0,8'h55);expected_error(8'h36);
 complete_load(512,0,0,0);expected_error(8'h30);
 blob[0]="V";complete_load(512,0,0,0);expected_error(8'h31);
 blob[8]=2;complete_load(512,0,0,0);expected_error(8'h32);
 blob[10]=64;complete_load(512,0,0,0);expected_error(8'h33);
 blob[12]=4;complete_load(512,0,0,0);expected_error(8'h34);
 re_crc;max_cluster=2;complete_load(512,0,0,0);expected_error(8'h35);max_cluster=100;
 make_blob(2,1);blob[64]=8'h0a;re_crc;complete_load(512,0,0,0);expected_error(8'h35);
 make_blob(2,1);put32(68,1);re_crc;complete_load(512,0,0,0);expected_error(8'h35);
 make_blob(2,1);put32(72,0);re_crc;complete_load(512,0,0,0);expected_error(8'h35);
 for(v=0;v<3;v=v+1)begin
  make_blob(2,1);case(v)0:blob[12]=0;1:blob[12]=5;2:blob[13]=1;endcase
  complete_load(512,0,0,0);expected_error(8'h33);
 end
 // Truncated header/payload, exact payload, extra length/wrap, and in_valid+done.
 for(n=0;n<=20;n=n+1)begin make_blob(2,1);complete_load(n,1,0,0);end
 make_blob(2,1);complete_load(319,1,0,0);expected_error(8'h34);
 make_blob(2,1);complete_load(320,1,0,0);expected_error(0);
 make_blob(2,1);complete_load(320,1,1,0); // old CRC priority on coincident final byte
 make_blob(2,1);complete_load(511,1,1,0);expected_error(0);
 make_blob(2,1);complete_load(576,1,0,0);expected_error(0);
 make_blob(2,1);complete_load(1024,0,0,0);expected_error(8'h34);
 // Reset during header and payload, accepted start with valid+done ignored,
 // reload after success, start while checking/finishing ignored.
 begin_load;for(n=0;n<9;n=n+1)tick(0,1,0,n,0);reset_all;
 make_blob(2,1);begin_load;for(n=0;n<100;n=n+1)tick(0,1,0,blob[n],0);reset_all;
 tick(1,1,1,8'h02,8'hff);tick(0,0,0,0,0);reset_all;
 make_blob(2,1);begin_load;for(n=0;n<320;n=n+1)tick(0,1,0,blob[n],0);
 tick(1,0,1,0,0);while(!d_done)tick(1,1,0,8'hff,0);tick(0,0,0,0,0);
 positives(1,1);positives(2,1);
 // Deterministic malformed inputs and random gap/reload sequences.
 for(v=0;v<100;v=v+1)begin
  make_blob((v%2)+1,v%3!=0);
  rng=(rng<<1)^{32{rng[31]}}&32'h04c11db7;
  if(v%4!=0)blob[rng%320]=blob[rng%320]^8'h81;
  complete_load(320+(v%3)*192,1,v%5==0,0);
 end
 // Full streams exercise uncertain MV flags/descriptors as well as wires.
 fourstate_header(8'hxx,8'h00,512,1'bx,1'bx);
 fourstate_header(8'hzz,8'h00,512,1'bx,1'bx);
 fourstate_header(8'b000000x1,8'h00,512,1'bx,1'b0);
 fourstate_header(8'b000000z0,8'h00,512,1'b0,1'bx);
 fourstate_header(8'h01,8'b0000000x,512,1'bx,1'b0);
 fourstate_header(8'h02,8'b0000000z,512,1'b0,1'bx);
 fourstate_header(8'h03,8'hxx,10,1'b0,1'b0);
 fourstate_header(8'h00,8'hzz,10,1'b0,1'b0);
 fourstate_header(8'hxx,8'h01,10,1'b0,1'b0);
 fourstate_header(8'hzz,8'bxxxxxxx1,10,1'b0,1'b0);
 fourstate_header(8'h01,8'bxxxxxxx1,10,1'b0,1'b0);
 fourstate_header(8'h02,8'bzzzzzzz1,10,1'b0,1'b0);
 // Partial headers retain reset-zero bytes; the unread supplied high byte
 // cannot affect classification, including when that supplied value is X/Z.
 fourstate_header(8'hxx,8'h01,9,1'bx,1'bx);
 fourstate_header(8'h02,8'hxx,9,1'b0,1'b1);
 fourstate_header(8'hxx,8'hzz,8,1'b0,1'b0);
 fourstate_header(8'h01,8'hzz,9,1'b1,1'b0);
 // Every 16-bit version enters the actual DUT using reset/start and bytes 0..9.
 // Every partial low-byte and high-byte result is checked after NBA above.
 for(v=0;v<65536;v=v+1)begin
  reset_all;begin_load;
  for(j=0;j<10;j=j+1)begin
   case(j)0:in_byte="V";1:in_byte="I";2:in_byte="N";3:in_byte="Y";
    4:in_byte="L";5:in_byte="I";6:in_byte="D";7:in_byte="X";8:in_byte=v[7:0];9:in_byte=v[15:8];endcase
   tick(0,1,0,in_byte,0);
  end
  exhaustive=exhaustive+1;
  model_raw=16'hff02;model_l1=0;model_l2=1;model_h0=0;model_check;
  model_raw[7:0]=v[7:0];model_l1=(v[7:0]==1);model_l2=(v[7:0]==2);model_check;
  model_raw[15:8]=v[15:8];model_h0=(v[15:8]==0);model_check;
  model_raw[15:8]=v[15:8];model_h0=(v[15:8]==0);model_check;
  model_raw=16'h0101;model_l1=1;model_l2=0;model_h0=0;model_check;
  model_raw[15:8]=v[15:8];model_h0=(v[15:8]==0);model_check;
  model_raw[7:0]=v[7:0];model_l1=(v[7:0]==1);model_l2=(v[7:0]==2);model_check;
 end
 reset_all;
 $display("TEST_PASS resource_n2_version_equiv exhaustive_actual_versions=%0d fourstate_cases=%0d wire_checks=%0d model_checks=%0d cycles=%0d transactions=%0d low_updates=%0d high_updates=%0d gaps=%0d busy_starts=%0d wraps=%0d seed=62e2b731",exhaustive,fourstate_cases,wire_checks,model_checks,cycles,transactions,low_updates,high_updates,gaps,busy_starts,wraps);
 $finish;
end
initial begin #50000000;$fatal(1,"FAIL timeout");end
endmodule
