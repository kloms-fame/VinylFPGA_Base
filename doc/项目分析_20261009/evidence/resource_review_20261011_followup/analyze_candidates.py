from pathlib import Path
import json

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[3]
pic=b'PIC1    BMP'
aud=b'AUDIO   PCM'
idx=b'INDEX   BIN'
positions=[]
for pos in range(11):
    predicates=[]
    for tag,word in [('PIC',pic),('AUDIO',aud),('INDEX',idx)]:
        pred='range_1_4' if tag=='PIC' and pos==3 else f'eq_{word[pos]:02X}'
        if pred not in predicates: predicates.append(pred)
    positions.append({'position':pos,'predicates':predicates})
# This establishes encoding size, not implemented RTL equivalence or area savings.
result={'directory_predicate_positions':positions,'unique_predicate_bits':sum(len(p['predicates']) for p in positions),'pic_digit_bits':2,'original_name_bits':88,'nominal_encoded_bits':sum(len(p['predicates']) for p in positions)+2,'scope':'predicate encoding mathematics only; no candidate RTL or candidate synthesis'}
ctx=json.loads((OUT/'isolated_context.json').read_text(encoding='utf-8'))
historical=Path('C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b')
before=json.loads((historical/'sim_before_full/results.json').read_text(encoding='utf-8'))
after=json.loads((historical/'sim_after_full/results.json').read_text(encoding='utf-8'))
result['historical_regression']={'count':len(before),'before_pass':sum(before.values()),'after_pass':sum(after.values()),'differences':[k for k in before if before[k]!=after.get(k)],'failed':[k for k,v in after.items() if not v]}
failures=[]
for name in result['historical_regression']['failed']:
    log=historical/'sim_after_full'/f'{name}.log'
    if log.exists():
        lines=log.read_text(encoding='utf-8',errors='replace').splitlines()
        failures.append({'test':name,'lines':[line for line in lines if any(p in line.lower() for p in ('fail','error','not found','unable','port'))][-8:]})
result['historical_failure_details']=failures
result['test_source_inventory']=[p.name for p in (ROOT/'sim').glob('*.v') if any(s in p.name for s in ('playback','scroll','five','window','progress','brightness','ec2','timebase','font'))]
(OUT/'candidate_analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k not in ('directory_predicate_positions','historical_failure_details')},ensure_ascii=True,indent=2))
