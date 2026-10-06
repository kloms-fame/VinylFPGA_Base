"""Create S6 headerless RGB565LE frames from an ordered image sequence.

Example: python tools/mv_pack.py --frames frames --output TRACK1.MV
Input frames represent 10 fps. No resizing, timing resampling or silent crop.
"""
from pathlib import Path
import argparse, hashlib, json, struct
from PIL import Image

def encode_frame(path):
    with Image.open(path) as im:
        if im.size != (320,240):
            raise ValueError(f'{path}: expected 320x240, got {im.size}')
        rgb=im.convert('RGB')
        out=bytearray(153600)
        for i,(r,g,b) in enumerate(rgb.getdata()):
            struct.pack_into('<H',out,i*2,((r>>3)<<11)|((g>>2)<<5)|(b>>3))
        return out

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--frames',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    paths=sorted(x for x in a.frames.iterdir() if x.suffix.lower() in ('.png','.jpg','.jpeg','.bmp'))
    if not 1<=len(paths)<=65535: p.error('expected 1..65535 image frames, zero-padded names in time order')
    # Exclusive creation avoids overwriting an existing deliverable on errors.
    sha=hashlib.sha256()
    with a.output.open('xb') as out:
        for path in paths:
            frame=encode_frame(path);out.write(frame);sha.update(frame)
    report={'format':'RGB565LE','width':320,'height':240,'fps':10,'frames':len(paths),
            'frame_bytes':153600,'sectors_per_frame':300,'sha256':sha.hexdigest(),
            'order':'top-down row-major; lexicographic input filenames'}
    a.output.with_suffix(a.output.suffix+'.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
