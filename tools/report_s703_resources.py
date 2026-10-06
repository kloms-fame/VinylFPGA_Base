"""Extract measured TD resources, hierarchy rankings and per-clock Fmax."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def measure(folder):
    area = (folder / 'final.area').read_text(encoding='gbk')
    qor = (folder / 'final.qor').read_text(encoding='gbk')
    timing = (folder / 'final.timing').read_text(encoding='gbk')
    metrics = {key: int(re.search(r'^#' + key + r'\s+(\d+)', area, re.M)[1])
               for key in ('lut', 'reg', 'bram', 'bram32k', 'dsp')}
    for key in ('#slices', 'Setup WNS', 'Setup TNS', 'Hold WNS', 'Hold TNS',
                'Num of violated S-EP', 'Num of violated H-EP'):
        metrics[key] = int(re.search(re.escape(key) + r'\s*\|\s*(-?\d+)', qor)[1])
    rows = []
    stack = []
    for line in area.splitlines():
        columns = line.split('|')
        if len(columns) != 10 or not columns[3].strip().isdigit():
            continue
        raw = columns[1]
        depth = (len(raw) - len(raw.lstrip())) // 2
        stack = stack[:depth] + [raw.strip()]
        le, lut, ripple, ff, bram, dsp = map(int, columns[3:9])
        rows.append(dict(path='/'.join(stack), depth=depth, module=columns[2].strip(),
                         lut=lut+ripple, ff=ff, bram=bram, dsp=dsp, le=le))
    clocks = {}
    for match in re.finditer(r'Path Group\s*:\s*(\w+) -> \1.*?Min Period\s*:\s*([\d.]+)ns\s*Fmax\s*:\s*([\d.]+)MHz', timing, re.S):
        clocks[match[1]] = dict(period_ns=float(match[2]), fmax_mhz=float(match[3]))
    hashes = json.loads((folder / 'inputs.sha256.json').read_text())
    mismatch = [name for name, value in hashes.items()
                if hashlib.sha256((folder/name).read_bytes()).hexdigest() != value]
    assert not mismatch, mismatch
    return dict(round=folder.name, metrics=metrics, clocks=clocks, hierarchy=rows,
                input_count=len(hashes), snapshot_inputs_verified=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('rounds', nargs='+')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--accepted', help='Explicit retained round; later failed experiments are not releases')
    a = p.parse_args()
    data = [measure(ROOT/'prj/resource_opt_verified_20261005'/name) for name in a.rounds]
    if a.accepted:
        accepted = next(r for r in data if r['round'] == a.accepted)
        m = accepted['metrics']
        assert m['Setup WNS'] >= 0 and m['Hold WNS'] >= 0
        assert all(m[k] == 0 for k in ('Setup TNS', 'Hold TNS', 'Num of violated S-EP', 'Num of violated H-EP'))
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.with_suffix('.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
    lines = ['# S7-03 TD 实测资源与时序', '',
             '层次 LUT=lut+ripple，FF=seq；父模块包含子模块，不可重复相加。全局 FF 以 #reg 为准。', '',
             '| 轮次 | LUT | FF | BRAM9K | BRAM32K | DSP | Slices | Setup WNS ps | Hold WNS ps | Setup/Hold TNS ps | S/H 违例端点 |',
             '|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|']
    for record in data:
        m = record['metrics']
        lines.append('| '+record['round']+' | '+' | '.join(str(m[k]) for k in ('lut','reg','bram','bram32k','dsp','#slices','Setup WNS','Hold WNS'))+
                     f" | {m['Setup TNS']}/{m['Hold TNS']} | {m['Num of violated S-EP']}/{m['Num of violated H-EP']} |")
    if a.accepted:
        lines += ['', '**当前保留版本：'+a.accepted+'。** 后续失败实验不代表交付版本。',
                  'M3 与 M6 seed7 未完成 final 报告，其 gate/失败诊断见执行记录，未混入本表。']
    for record in data:
        lines += ['', '## '+record['round'], '', '### 各时钟 Fmax（TD 原生报告值）', '', '| 时钟 | Fmax MHz | 最小周期 ns |', '|---|---:|---:|']
        for name, v in record['clocks'].items():
            lines.append(f"| {name} | {v['fmax_mhz']} | {v['period_ns']} |")
        for key in ('lut','ff','bram','dsp'):
            lines += ['', f'### {key.upper()} 排名（顶层互不重叠子树）', '', '| 实例 | LUT | FF | BRAM | DSP |', '|---|---:|---:|---:|---:|']
            for row in sorted((r for r in record['hierarchy'] if r['depth']==1), key=lambda r:r[key], reverse=True)[:12]:
                if not row[key]:
                    continue
                lines.append('| '+row['path']+' | '+' | '.join(str(row[k]) for k in ('lut','ff','bram','dsp'))+' |')
        lines += ['', '### 子模块热点（与父树重叠，仅用于定位）', '', '| 实例 | LUT | FF | BRAM | DSP |', '|---|---:|---:|---:|---:|']
        for row in record['hierarchy']:
            if row['module'] in ('song_index_db','fat32_volume_scanner','exp_echo_reporter','fat32_file_streamer','lrc_font_rom'):
                lines.append('| '+row['path']+' | '+' | '.join(str(row[k]) for k in ('lut','ff','bram','dsp'))+' |')
    a.output.write_text('\n'.join(lines)+'\n', encoding='utf-8')
    print(json.dumps([{k:v for k,v in r.items() if k!='hierarchy'} for r in data], indent=2))


if __name__ == '__main__':
    main()
