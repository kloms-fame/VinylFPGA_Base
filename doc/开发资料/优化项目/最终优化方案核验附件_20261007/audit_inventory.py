"""Read-only source/report audit; outputs only alongside this script."""
from pathlib import Path
import hashlib, json, re, csv, subprocess, shutil, xml.etree.ElementTree as ET

OUT = Path(__file__).resolve().parent
ROOT = next(p for p in OUT.parents if (p/'src/top_tf_hdmi_audio.v').exists())
BASE = ROOT/'prj/resource_opt_verified_20261005/X2_r15s5_20261007'
def read(p): return p.read_text(encoding='utf-8-sig', errors='replace')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(n,x): (OUT/n).write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
def git(*args): return subprocess.check_output(['git','-c','core.quotepath=false',*args],cwd=ROOT).decode('utf-8',errors='replace')
manifest=json.loads(read(BASE/'inputs.sha256.json'))
audit=[dict(path=k,expected=v,current=sha(ROOT/k) if (ROOT/k).exists() else None) for k,v in manifest.items()]
dump('input_hash_audit.json',dict(head=git('rev-parse','HEAD').strip(),total=len(audit),matched=sum(x['expected']==x['current'] for x in audit),files=audit))
(OUT/'git_history.txt').write_text(git('log','--all','--date=iso','--pretty=format:%h %ad %s')+'\n\n'+git('status','--short'),encoding='utf-8')
documents=list((ROOT/'doc/开发资料/拓展功能开发').glob('*.md'))+list((ROOT/'doc/开发资料/优化项目').glob('*.md'))+list((ROOT/'doc/开发资料/优化项目/优化方案').glob('*.md'))
dump('document_manifest.json',[dict(path=p.relative_to(ROOT).as_posix(),bytes=p.stat().st_size,lines=len(read(p).splitlines()),sha256=sha(p)) for p in documents if '最终优化执行方案' not in p.name])
for name in ['gate.area','final.area','final.qor','final.timing','final.constraints','native_build.tcl']:
    shutil.copy2(BASE/name,OUT/('baseline_'+name))
rp=Path('C:/Users/Renni/AppData/Local/Temp/synthpilot-td/reports/8d2380c1093c5763')
for p in rp.glob('opt_plan_audit_20261007*'): shutil.copy2(p,OUT/p.name)
rows=[]; stack=[]
for lineno,line in enumerate(read(BASE/'gate.area').splitlines(),1):
    cols=line.split('|')
    if len(cols)!=9 or not cols[3].strip().isdigit(): continue
    raw=cols[1].rstrip(); depth=(len(raw)-len(raw.lstrip()))//2
    inst=raw.strip(); stack=stack[:depth]+[inst]
    rows.append(dict(path='/'.join(stack),depth=depth,instance=inst,module=cols[2].strip(),lut=int(cols[3]),ripple=int(cols[4]),seq=int(cols[5]),bram=int(cols[6]),dsp=int(cols[7]),line=lineno))
dump('hierarchy_area.json',rows)
with (OUT/'hierarchy_area.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
tree=['# 当前基线的完整综合实例树','', '来源：`X2_r15s5_20261007/gate.area`。数字为累计 LUT/ripple/seq/BRAM/DSP；父子不能相加；被内联的模块不一定保留独立行。','', '```text']
tree += ['  '*x['depth']+x['instance']+' : '+x['module']+'  '+ '/'.join(str(x[k]) for k in ['lut','ripple','seq','bram','dsp']) for x in rows]
tree+=['```','']
(OUT/'完整综合实例树.md').write_text('\n'.join(tree),encoding='utf-8')
project=ET.ElementTree(ET.fromstring(read(ROOT/'prj/VinylFPGA.al').replace('UsedInP&R','UsedInP&amp;R')))
registered={}
for f in project.findall('.//Verilog/File'):
    rel=(ROOT/'prj'/f.attrib['Path']).resolve().relative_to(ROOT).as_posix()
    registered[rel]=any(a.attrib.get('Name')=='AutoExcluded' and a.attrib.get('Val')=='true' for a in f.findall('.//Attr'))
def strip_comments(s):
    return re.sub(r'/\*.*?\*/|//[^\n]*',lambda m:'\n'*m[0].count('\n'),s,flags=re.S)
sources={p.relative_to(ROOT).as_posix():read(p) for p in (ROOT/'src').rglob('*') if p.suffix.lower() in ['.v','.sv','.vh','.vhd']}
units=[]
for path,s in sources.items():
    clean=strip_comments(s)
    for m in re.finditer(r'\bmodule\s+(\w+)\b(.*?)\bendmodule\b',clean,re.S):
        units.append(dict(file=path,module=m[1],line=clean[:m.start()].count('\n')+1,body=m[2]))
names={u['module'] for u in units}; edges=[]
for u in units:
    b=u['body']
    for m in re.finditer(r'\b('+'|'.join(re.escape(n) for n in sorted(names,key=len,reverse=True))+r')\s*(#\s*\(|[A-Za-z_]\w*\s*\()',b):
        tail=b[m.start():]; typ=m[1]; rest=tail[len(typ):].lstrip()
        if rest.startswith('#'):
            pos=rest.find('('); level=1; j=pos+1
            while j<len(rest) and level:
                level+=(rest[j]=='(')-(rest[j]==')');j+=1
            rest=rest[j:].lstrip()
        im=re.match(r'(\w+)\s*\(',rest)
        if im: edges.append(dict(parent=u['module'],child=typ,instance=im[1],file=u['file'],line=u['line']+b[:m.start()].count('\n')))
dump('source_instance_edges.json',edges)
reachable={'top'}
while True:
    nxt=reachable|{e['child'] for e in edges if e['parent'] in reachable}
    if nxt==reachable: break
    reachable=nxt
purposes={
'top':'系统集成与 CDC/复位/图层/存储仲裁', 'audio_arc_calculate':'HDMI ACR N/CTS 生成', 'hdmi_phy_wrapper':'HDMI PHY 包装', 'lane_lvds_10_1':'TMDS LVDS 串化', 'reset_sync':'异步复位同步释放', 'sync_2ff':'单比特跨域同步', 'startup_pulse':'启动 EDID 触发', 'video_rgb_to_axis_640x480':'RGB/DE 到 AXIS，综合可能归入上游组合逻辑',
'hdmi_audio_tone_i2s_64fs':'旧 I2S 测试音', 'I2S_receiver':'旧 I2S 接收', 'video_source_test':'旧测试图', 'audio_source_mux':'音源选择及 ready 路由', 'hdmi_pcm_source_bridge':'PCM 到 HDMI 契约桥', 'hdmi_pcm_audio_bridge':'旧 PCM 测试桥', 'm06_pcm_contract_adapter':'PCM valid/ready 契约转换', 'pcm_media_tone':'非 WAV 场景琶音源', 'pcm_tap':'PCM 只读幅值抽头', 'pcm_volume_fade':'音量和淡变乘法', 'play_ctrl':'播放/暂停/选曲/EOF 策略', 'seek_controller':'Seek 钳位与目标运算流水', 'stream_session':'切曲/Seek 代次与在途事务排空', 'sync_fade_gain':'视频包络到 PCM 增益', 'timebase_48k':'样本驱动媒体时基', 'wav_stream_player':'WAV 缓冲/读取/EOF/Seek',
'boot_layer':'启动 Logo/保护窗/跳过', 'boot_logo_rom':'压缩调色板 Logo BRAM', 'brightness_contrast_adjust':'画质流水/对比度', 'lrc_font_rom':'60 个 16×16 字形组合 ROM', 'lrc_lines_rom':'单曲时间戳与字形索引', 'lrc_osd':'单行歌词扫描与像素叠加', 'osd_overlay_24':'旧调试字符 OSD 包装', 'status_osd_overlay':'1E00 / E0F0 / BxxCyy 三行显示', 'promax_audio_waveform':'时域幅度柱（非 FFT）', 'seg_business_mux':'错误/临时参数/业务数码管页面', 'thumbnail_layout':'四宫格坐标/bank映射', 'thumbnail_view_reader':'缩略图 SDRAM 读与 FIFO', 'video_fade_transition':'F0/F1/F2 转场状态控制', 'video_transition_apply':'转场/亮度像素运算', 'vinyl_renderer':'黑胶几何像素层', 'frame_blend':'旧双帧 alpha 混合', 'bilinear_8q8':'可选双线性插值',
'browse_fsm':'J2/母板事件到全屏/缩略图/播放', 'buzzer_feedback':'母板/J2 操作反馈音', 'cover_navigation':'忙时累计封面目标', 'debounce_filter':'独立同步+20位消抖计数', 'encoder_monitor':'编码器旋转及按压事件', 'exp_baud_tick':'UART 波特率时基', 'exp_echo_reporter':'UART 格式化/队列/报文', 'exp_uart_tx':'UART 8N1 发送', 'expansion_integration':'输入/命令/诊断/LED/WS/蜂鸣集成', 'expansion_io_hub':'J2 键/DIP/EC/IR 驱动', 'health_monitor':'诊断计数与当前错误锁存', 'ir_nec_decoder':'NEC 帧/重复帧解码', 'key_dip_monitor':'按键/DIP 消抖与启动抑制', 'led_business_driver':'IR/操作/心跳/故障 LED', 'param_menu_controller':'母板组合长按亮度/对比度菜单', 'quadrature_decoder':'A/B 稳定和正交方向计数', 'sync_bit':'输入两级同步', 'thumbnail_controller':'缩略图焦点/选择/模式', 'ui_command_router':'IR/DIP/消隐唤醒/重启/命令', 'ui_event_bridge':'业务事件到各域 toggle', 'ui_event_bus':'逐源 pending 事件仲裁', 'ws2812_driver':'WS2812 GRB 串行发送', 'ws2812_effects':'WS 音频包络/进度效果',
'color_bar':'显示扫描时序，RGB彩条口不使用', 'fat32_file_streamer':'FAT簇链字节流', 'fat32_media_loader':'卷/索引/BMP/媒体装载仲裁', 'fat32_volume_scanner':'MBR/BPB/根目录资源发现', 'frame_fifo_read':'帧读突发节奏/刷新间隔', 'frame_fifo_write':'帧写突发/翻转地址', 'frame_read_write':'双异步FIFO与SDRAM请求', 'key_press_hold':'母板短按/长按识别', 'media_probe':'空闲低优先级卡在场探测', 'media_supervisor':'挂载/超时/重试/复位代次', 'sd_card_bmp':'封面预加载/显示提交/旧轮播', 'key_press_debounce':'sd_card_bmp 文件内母板消抖', 'sd_card_cmd':'SD命令/响应', 'sd_card_sec_read_write':'SD初始化/扇区事务', 'sd_card_top':'SD SPI封装', 'sd_sector_adapter':'扇区请求适配/超时', 'sdram_rd_arbiter':'正常/缩略图单读口交接', 'sdram':'SDRAM硬核包装（SD版有效，IP版排除）', 'seg_decoder':'数码管字形译码', 'seg_scan':'六位数码管扫描', 'song_index_db':'INDEX校验/条目/CRC', 'spi_master':'SPI字节传输', 'video_delay':'视频数据与同步对齐', 'video_timing_data':'帧请求/扫描接口', 'ax_debounce':'旧消抖模块', 'bmp_read':'旧裸扇区BMP扫描',
'mv_frame_scheduler':'按媒体时间预取/提交MV帧', 'mv_sector_mux':'PCM优先的MV/WAV扇区互斥', 'mv_stream_player':'MV RGB565字节流与SDRAM写完成', 's6_video_layer':'MV/黑胶选择与帧边界提交', 'sys_pll':'100/125/125相移时钟', 'video_pll':'25/125MHz时钟', 'PLL_HDMI_AUDIO':'已排除的旧音频PLL', 'wfifo_32_32_512':'32×512写异步FIFO', 'rfifo_32_32_512':'32×512读异步FIFO'}
purposes.update({'sdram_phy':'旧SDRAM物理包装，当前AutoExcluded','sdr_as_ram':'加密SDRAM用户接口与控制核','sdr_init_ref':'加密SDRAM初始化与刷新','fifo_cross_domain_addr_process_al_wfifo_32_32_512':'写FIFO指针跨域','fifo_cross_domain_addr_process_al_rfifo_32_32_512':'读FIFO指针跨域','ram_infer_wfifo_32_32_512':'写FIFO双口RAM存储','ram_infer_rfifo_32_32_512':'读FIFO双口RAM存储'})
delete={'exp_baud_tick','exp_echo_reporter','exp_uart_tx','param_menu_controller','key_press_hold','osd_overlay_24','status_osd_overlay'}
opt={'debounce_filter','key_dip_monitor','lrc_font_rom','lrc_osd','health_monitor','sd_card_bmp','key_press_debounce','expansion_integration','browse_fsm','top'}
inventory=[]
for path,s in sorted(sources.items()):
    us=[u for u in units if u['file']==path]
    mods=[u['module'] for u in us]
    status='AutoExcluded（清理前核回归依赖）' if registered.get(path) else ('顶层可达' if any(m in reachable for m in mods) else '头文件/加密IP/内联候选，不能据无层次行判死代码')
    decision='按用户要求移除生产实例；关联测试迁移' if set(mods)&delete else ('定向重构，保留业务' if set(mods)&opt else '保留；暂无可证明安全的资源删除项')
    if registered.get(path): decision='生产清单可移除；物理删除须完成依赖审计；面积收益0'
    purpose='；'.join(dict.fromkeys(purposes.get(m,'生成/加密子模块，以实例树和接口为准') for m in mods)) or ('参数/宏定义' if '.enc.' not in path else '加密逻辑，保留IP边界')
    refs=[]
    for m in mods:
        refs.extend(e['parent']+'.'+e['instance'] for e in edges if e['child']==m)
    inventory.append(dict(file=path,modules=mods,definitions=[f"{u['module']}:{u['line']}" for u in us],purpose=purpose,status=status,decision=decision,parents=sorted(set(refs)),lines=len(s.splitlines()),sha256=sha(ROOT/path)))
dump('source_inventory.json',inventory)
md=['# 全量 RTL/头文件逐项清单','', '文件来自当前 src，例化引用为去注释后的静态扫描；generate 展开和实际资源以完整综合实例树为准。静态扫描不解析加密IP内部，AutoExcluded 不等于仿真不用。','', '| 文件与定义行 | 功能 | 生产状态 | 本轮决策 |','|---|---|---|---|']
for x in inventory:
    md.append('| `'+x['file']+'`<br>'+', '.join(x['definitions'])+' | '+x['purpose']+' | '+x['status']+' | '+x['decision']+' |')
md+=['','## 源码例化边（包含内联前和参数化候选）','','| 父模块 | 子实例 | 类型 | 源文件:行 |','|---|---|---|---|']
for e in edges: md.append(f"| {e['parent']} | {e['instance']} | {e['child']} | {e['file']}:{e['line']} |")
(OUT/'全量RTL逐项清单.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
excluded=[k for k,v in registered.items() if v]
refs={}
scan=[p for folder in ['sim','tools','src'] for p in (ROOT/folder).rglob('*') if p.suffix in ['.v','.sv','.py','.ps1','.tcl','.do']]
for path in excluded:
    ms=next(x['modules'] for x in inventory if x['file']==path)
    hits=[]
    for p in scan:
        if p.relative_to(ROOT).as_posix()==path: continue
        for n,line in enumerate(read(p).splitlines(),1):
            if any(re.search(r'\b'+re.escape(m)+r'\b',line) for m in ms): hits.append(f'{p.relative_to(ROOT).as_posix()}:{n}: {line.strip()[:180]}')
    refs[path]=hits
dump('excluded_dependencies.json',refs)
dump('audit_summary.json',dict(files=len(inventory),verilog=sum(k.endswith('.v') for k in sources),headers=sum(k.endswith('.vh') for k in sources),module_definitions=len(units),static_edges=len(edges),hierarchy_rows=len(rows),top_instances=sum(x['depth']==1 for x in rows),excluded=len(excluded),input_matches=sum(x['expected']==x['current'] for x in audit),input_total=len(audit)))
print((OUT/'audit_summary.json').read_text(encoding='utf-8'))
print('TOP LUT:')
for r in sorted((x for x in rows if x['depth']==1),key=lambda x:x['lut'],reverse=True)[:18]: print(r)
