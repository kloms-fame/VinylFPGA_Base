"""Verify and bind a freshly generated audio candidate to its source and DB."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('snapshot',type=Path)
p.add_argument('--evidence-dir',type=Path,required=True,
               help='Directory containing baseline_hashes.json and protected_runs.json')
p.add_argument('--regression',type=Path,required=True,
               help='Fresh regression results.json whose input hashes match the live source tree')
a=p.parse_args();dest=a.snapshot.resolve(strict=True)
root=Path(__file__).resolve().parents[1]
evidence=a.evidence_dir.resolve(strict=True)
regression_path=a.regression.resolve(strict=True)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def git(*args): return subprocess.check_output(['git',*args],cwd=root).decode().strip()
assert git('branch','--show-current')=='main'
backup='backup/audio-stall-r5-src-prj-20261016'
assert git('rev-parse',backup)=='b35b7561c2434fdf4f7a354dbc5da209ce913397'
inputs=json.loads((dest/'inputs.sha256.json').read_text())
source_hashes={}
for n,h in inputs.items():
    assert sha(dest/n)==h,n
    if n.startswith(('src/','constraints/')):
        assert sha(root/n)==h,n
        source_hashes[n]=h
signoff=json.loads((dest/'sta_release.result.json').read_text())
assert signoff['internal_sta_pass'] and sha(dest/'routed.db')==signoff['database_sha256']
assert signoff['clock_and_constraint_checks_pass'] is True
assert all(v>=0 if k.endswith('WNS') else v==0 for k,v in signoff['metrics_ps'].items())
route=json.loads((dest/'route.result.json').read_text())
assert route['phase_completed'] and route['artifacts']['routed.db']==sha(dest/'routed.db')
bit_phase='bitgen_release' if (dest/'bitgen_release.result.json').exists() else 'bitgen'
for phase in ['gate','place','route',bit_phase]:
    result=json.loads((dest/(phase+'.result.json')).read_text())
    assert result['phase_completed'],phase
    for n,h in result['artifacts'].items():assert sha(dest/n)==h,n
regression=json.loads(regression_path.read_text())
assert len(regression)>=24
for case in regression:
    assert case['pass'],case['test']
    for n,h in case['inputs_sha256'].items(): assert sha(root/n)==h,n
seed=json.loads((dest/'place.process.json').read_text())['seed']
bit=dest/('VFPGA_AUDIO_PREFETCH_CLOSED_S'+str(seed)+('_RELEASE' if bit_phase=='bitgen_release' else '')+'.bit')
data=bit.read_bytes();header,payload=data.split(b'\n\n',1)
for value in [b'# Anlogic ASCII Bitstream',b'# Design name: top',b'# Architecture: eagle_s20',b'# Package: EG4S20BG256']:
    assert value in header,value
for field in [b'Bitstream CRC',b'Transfer CRC']:
    assert re.search(field+rb': [01]{32}',header),field
assert 500000<len(data)<1000000 and b'\xcc\x55\xaa\x33' in payload and len(set(payload))>128
log=(dest/(bit_phase+'.log')).read_text(encoding='gbk')
completion='AUDIO_'+bit_phase.upper()+'_COMPLETE'
for marker in ['BIT-1004','RUN-1003 : finish command "bitgen',completion]:
    assert marker in log,marker
assert (dest/('.'+bit_phase+'.end.f')).read_text().strip()==completion
assert (dest/(bit.name+'gen_param.f')).stat().st_size>0
protected=json.loads((evidence/'protected_runs.json').read_text())
for n,v in protected.items():
    f=root/n
    assert f.is_file() and f.stat().st_size==v['bytes'] and sha(f)==v['sha256'],n
assert len([f for f in (root/'prj/VinylFPGA_Runs').rglob('*') if f.is_file()])==len(protected)
prior_snapshot_path=evidence/'root_runs_previous_manifest_comparison.json'
prior_snapshot=json.loads(prior_snapshot_path.read_text()) if prior_snapshot_path.exists() else None
baseline={n.replace('\\','/'):h for n,h in json.loads((evidence/'baseline_hashes.json').read_text()).items()}
assert sha(root/'prj/VinylFPGA.al')==baseline['prj/VinylFPGA.al']
for n in ['constraints/pin.adc','constraints/timing.sdc']: assert sha(root/n)==baseline[n]
aggregate=hashlib.sha256(json.dumps(source_hashes,sort_keys=True,separators=(',',':')).encode()).hexdigest()
artifacts={f.name:{'bytes':f.stat().st_size,'sha256':sha(f)} for f in dest.iterdir()
           if f.is_file() and f.suffix in ['.db','.tcl','.log','.json','.bit','.f','.timing','.qor','.area','.status','.constraints']}
manifest={'branch':'main','head':git('rev-parse','HEAD'),
          'snapshot_head':json.loads((dest/'provenance.json').read_text())['head'],
          'backup_ref':backup,'backup_oid':git('rev-parse',backup),
          'tool':'TD 6.2.168116 / SynthPilot 1.4.0','device':'EG4S20BG256',
          'seed':json.loads((dest/'place.process.json').read_text())['seed'],
          'internal_sta_pass':True,'external_io_signoff_complete':False,'hardware_acceptance':'pending user manual programming',
          'clock_diagnostics':{'clock_definition_after_timing_refresh':0,
                               'feedback_physical_evidence':'audit_pll_retry.log: both feedback nets Route Type global, driven by EG_PHY_GCLK',
                               'inherited_warnings_retained':['USR-6135 PLL feedback diagnostic disagrees with physical global routing',
                                                              'PHY-5079 CTS summary marks ext_mem_clk_sft to the hard SDRAM clock pin as one local route branch'],
                               'report_clock_summary_requires_final_timing_refresh':True},
          'constraint_gaps':{'inputs_without_delay':33,'outputs_without_delay':38},
          'metrics_ps':signoff['metrics_ps'],'functional_cases':len(regression),
          'bit':str(bit),'bit_bytes':len(data),'bit_sha256':sha(bit),
          'routed_db':str(dest/'routed.db'),'routed_db_sha256':sha(dest/'routed.db'),
          'source_tree_sha256':aggregate,'source_hashes':source_hashes,
          'protected_runs_unchanged_since_current_capture':True,
          'protected_runs_previous_snapshot_comparison':prior_snapshot,
          'protected_runs_files':len(protected),'artifacts':artifacts}
output=dest/'release_manifest.json'
assert not output.exists(), 'Refusing to replace a release manifest'
output.write_text(json.dumps(manifest,indent=2))
print(json.dumps({k:manifest[k] for k in ['internal_sta_pass','external_io_signoff_complete','functional_cases','bit','bit_bytes','bit_sha256','routed_db_sha256','source_tree_sha256']},indent=2))
