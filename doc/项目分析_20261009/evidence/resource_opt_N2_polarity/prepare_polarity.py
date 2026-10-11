from pathlib import Path
import json, shutil

OUT=Path(__file__).resolve().parent
n2=json.loads((OUT.parent/'resource_opt_N2/context.json').read_text(encoding='utf-8'))
source=Path(n2['after']); after=Path(n2['base'])/'N2_polarity_after'
after.mkdir()
for folder in ('src','constraints','sim','tools','doc'):
    shutil.copytree(source/folder,after/folder,ignore=shutil.ignore_patterns('resource_*','*.vvp','*.vcd','*.fst','__pycache__'))
(after/'prj').mkdir()
for name in ('VinylFPGA.al','native_candidate.tcl'):
    text=(source/'prj'/name).read_text(encoding='utf-8').replace(source.as_posix(),after.as_posix())
    (after/'prj'/name).write_text(text,encoding='utf-8')
context={**n2,'after':str(after),'variant':'N2 high-byte predicate stored with zero reset; logical classification unchanged',
         'mcp_prefixes':{'before':'n2_before_1720','after':'n2_polarity_1730'}}
(OUT/'context.json').write_text(json.dumps(context,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(context,ensure_ascii=True,indent=2))
