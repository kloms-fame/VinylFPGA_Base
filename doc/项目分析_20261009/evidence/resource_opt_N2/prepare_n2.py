from pathlib import Path
import hashlib, json, re, shutil

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
n1=json.loads((OUT.parent/'resource_opt_N1/context.json').read_text(encoding='utf-8'))
base=Path(n1['base']); source=Path(n1['before'])
before=base/'N2_before';after=base/'N2_after'
before.mkdir()
for folder in ('src','constraints','sim','tools','doc'):
    shutil.copytree(source/folder,before/folder,ignore=shutil.ignore_patterns('resource_*','*.vvp','*.vcd','*.fst','__pycache__'))
(before/'prj').mkdir()
project=(source/'prj/VinylFPGA.al').read_text(encoding='utf-8').replace(source.as_posix(),before.as_posix())
(before/'prj/VinylFPGA.al').write_text(project,encoding='utf-8')
for name in ('sim/tb_resource_n1_directory_equiv.v','sim/optimization/fat32_volume_scanner_reference.v'):
    dest=before/name;dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(Path(n1['after'])/name,dest)
shutil.copytree(before,after)
p=after/'prj/VinylFPGA.al';p.write_text(p.read_text(encoding='utf-8').replace(before.as_posix(),after.as_posix()),encoding='utf-8')
template=(source/'prj/native_candidate.tcl').read_text(encoding='utf-8')
for folder in (before,after):
    (folder/'prj/native_candidate.tcl').write_text(template.replace(source.as_posix(),folder.as_posix()),encoding='utf-8')
old=json.loads((OUT.parent/'resource_review_20261011_followup/isolated_context.json').read_text(encoding='utf-8'))
context={'workspace':str(ROOT),'base':str(base),'before':str(before),'after':str(after),'round':'N2',
         'native_before':old['native_isolated'],'n1_decision':'Rejected: final Slice+3, PLB+1, setup116ps->0ps, hold30ps->27ps; no main-tree RTL applied.',
         'mcp_prefixes':{'before':'n2_before_1720','after':'n2_after_1720'}}
(OUT/'context.json').write_text(json.dumps(context,ensure_ascii=False,indent=2),encoding='utf-8')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
manifest=[{'path':p.relative_to(before).as_posix(),'sha256':sha(p)} for d in ('src','constraints') for p in (before/d).rglob('*') if p.is_file()]
(OUT/'before_input_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(context,ensure_ascii=True,indent=2))
