from pathlib import Path
import json
import re
import shutil

OUT = Path(__file__).resolve().parent
context = json.loads((OUT/'isolated_context.json').read_text(encoding='utf-8'))
source = Path(context['isolated'])
native = source.with_name(source.name+'_native2')
native.mkdir()
for folder in ('src','constraints'):
    shutil.copytree(source/folder, native/folder)
(native/'prj').mkdir()
project = (source/'prj/VinylFPGA.al').read_text(encoding='utf-8').replace((source/'prj').as_posix(), (native/'prj').as_posix())
(native/'prj/VinylFPGA.al').write_text(project,encoding='utf-8')
old = Path('C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_native_confirm_v4')
script = (old/'prj/native_build_v4.tcl').read_text(encoding='utf-8').replace(old.as_posix(),native.as_posix())
gate_extra = '\n'.join([
    f'write_verilog {{{native.as_posix()}/prj/native_gate.v}}',
])
script = script.replace('set_param place seed 5',gate_extra+'\nset_param place seed 5')
final_extra = '\n'.join([
    f'write_verilog {{{native.as_posix()}/prj/native_final.v}}',
    'help report_hfn',
    'help report_analysis',
])
script = script.replace('puts NATIVE_ROUND_COMPLETE', final_extra+'\nputs NATIVE_ROUND_COMPLETE')
(native/'prj/native_baseline.tcl').write_text(script,encoding='utf-8')
shutil.copy2(native/'prj/native_baseline.tcl',OUT/'native_baseline.tcl')
context['native_isolated'] = str(native)
(OUT/'isolated_context.json').write_text(json.dumps(context,indent=2,ensure_ascii=False),encoding='utf-8')
print(native.as_posix())
