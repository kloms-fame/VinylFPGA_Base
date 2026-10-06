"""Real FAT32 pack/readback, MV negatives and PC-to-RTL shared fixtures."""
from pathlib import Path
import json,struct,tempfile
from PIL import Image
import vinyl_packer as vp
from mv_pack import encode_frame
from test_vinyl_packer import Fat32Builder,make_bmp
R=Path(__file__).resolve().parents[1]; O=R/'sim/s6_20261006';O.mkdir(exist_ok=True)
def expect_error(fn):
 try:fn()
 except vp.PackError:return
 raise AssertionError('invalid resource accepted')
def fixture(fragmented=False,bad_size=False):
 b=Fat32Builder(1100)
 cover=make_bmp(64,4,1);b.put_file(b'COVER   BMP',cover,b.alloc(2))
 audio=b'\0'*2048;b.put_file(b'AUDIO   PCM',audio,b.alloc(4))
 mv=b'\x00\xf8'*76800+b'\xe0\x07'*76800
 if bad_size:mv=mv[:-1]
 if fragmented:
  first=b.alloc(300);b.alloc(1);cl=first+b.alloc(300)
 else:cl=b.alloc(600)
 b.put_file(b'TRACK1  MV ',mv,cl)
 path=O/('bad_size.img' if bad_size else 'fragmented.img' if fragmented else 'mv_card.img')
 b.flush(path)
 return path
manifest=O/'manifest.json';manifest.write_text(json.dumps({'songs':[{'cover':'COVER.BMP','audio':'AUDIO.PCM','mv':'TRACK1.MV'}]}),encoding='utf-8')
path=fixture()
assert vp.main(['pack','--image',str(path),'--manifest',str(manifest),'--width','64','--height','4'])==0
assert vp.main(['verify','--image',str(path),'--width','64','--height','4'])==0
with vp.Fat32Image(path) as card:
 e=card.find_root_file('INDEX.BIN');blob=card.read_file(e.first_cluster,e.size)
 info=vp.parse_index(blob);assert info['version']==2 and info['songs'][0]['mv_frames']==2
 meta=struct.unpack_from('<Q',blob,120)[0]
 (O/'mv_expected.vh').write_text(f"localparam [63:0] EXPECTED_MV=64'h{meta:016x};\n",encoding='utf-8')
 (O/'index_v2.hex').write_text(''.join(f'{x:02x}\n' for x in blob),encoding='ascii')
 old=bytearray(blob);old[8:10]=b'\x01\x00'
 (O/'index_v1.hex').write_text(''.join(f'{x:02x}\n' for x in old),encoding='ascii')
for bad in [fixture(fragmented=True),fixture(bad_size=True)]:
 assert vp.main(['pack','--image',str(bad),'--manifest',str(manifest),'--width','64','--height','4'])==2
for s in [vp.IndexSong(flags=9,mv_frames=0,mv_lba=100),vp.IndexSong(flags=9,mv_frames=1,mv_lba=100,mv_fps=12),vp.IndexSong(flags=9,mv_frames=65535,mv_lba=0xfffffff0)]:expect_error(lambda:vp.build_index([s]))
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'red.png';Image.new('RGB',(320,240),(255,0,0)).save(p)
 assert encode_frame(p)==b'\x00\xf8'*76800
print('TEST_PASS s6_assets FAT32 contiguous MV v1/v2 RGB565 negative metadata/fragmentation/truncation')
