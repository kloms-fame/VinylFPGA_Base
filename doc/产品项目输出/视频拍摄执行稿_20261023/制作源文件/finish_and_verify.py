from pathlib import Path
from html.parser import HTMLParser
import csv
import hashlib
import html
import json
import re
import zipfile

OUT=Path(__file__).resolve().parent.parent
ROOT=OUT.parents[2]
plan=json.loads((OUT/'制作源文件/scene_plan.json').read_text(encoding='utf-8'))
scenes=plan['scenes']

# feature, source, shots, appendix, observable evidence, evidence boundary
FEATURES=[
('实际板卡/器件与独立播放','prj/VinylFPGA.al; src/top_tf_hdmi_audio.v','S02 S03','B01','型号和接线可辨，无运行时额外处理器参与','型号实物、当前固件与冷启动待现场登记'),
('TF卡BMP读取与SDRAM帧缓存','src/SD/fat32_media_loader.v; src/SD/frame_read_write.v','S03 S04','','卡内封面经HDMI显示，手动换图有结果','代码来源明确；不是任意文件浏览器'),
('640×480真实HDMI有效画面','src/SD/color_bar.v; src/top_tf_hdmi_audio.v','S03 S04 S06','','手机实拍完整输出，保持4:3','1080p是成片规格，不是板卡输出升级'),
('配置Flash固化后上电自启','README.md; 选题解析课件第21页','S03 S26','B01','完全断电再供电，无JTAG下载进入可操作页','bit存在不证明已固化；现场必须核验'),
('启动Logo与启动旁路','src/boot/boot_layer.v; src/io/expansion_integration.v','S03','B01','SW2关/开各自启动路径，Logo与可操作结果','运行时拨SW2不重新触发启动'),
('母板KEY1硬复位与遥控软重启','src/top_tf_hdmi_audio.v; src/io/ui_command_router.v','S34','B01','复位/重启后重新初始化，标签区分冷启动','不能用这两条代替断电自启'),
('EC1双向浏览及曲目回绕','src/io/ui_event_bridge.v; src/io/cover_navigation.v','S04','B02','顺/逆转封面变化，第4曲和第1曲回绕','可见结果优先于输入反馈音'),
('KEY1至KEY5浏览与确认','src/io/ui_event_bridge.v; src/io/browse_fsm.v','S04 S06','B02','方向选择、KEY2启动播放','相同业务的等价入口，非五个独立亮点'),
('自动轮播开启与关闭','src/io/slideshow_controller.v','S05','B02','无操作两次自动换图，关闭后停止','DIP2与ROT条件均需满足'),
('直切/水平擦入/淡出淡入','src/display/video_fade_transition.v; src/display/video_transition_apply.v','S07','B03','浏览切图时完整看见三种效果','播放页保护不能拍成新转场'),
('四曲真实音乐与标题艺人','src/SD/song_index_db.v; src/display/song_text_rom.v','S08','','四曲曲号、文字、音频、封面匹配','最多四曲；文字来自ROM，不是任意LRC热更新'),
('48kHz PCM经HDMI输出','src/audio/wav_stream_player.v; src/top_tf_hdmi_audio.v','S06','B13','真实作品声音，工程设置与实际输出分开表述','单声道原始PCM，非通用MP3/WAV解码'),
('独立已知测试音（若要求）','选题解析课件第5页; src/audio/audio_source_mux.v','','B13','同一最终固件/媒体镜像输出已知测试PCM','当前正常浏览静音，未安排可凭空发声的测试键'),
('暂停/恢复及媒体时间冻结','src/audio/play_ctrl.v; src/audio/timebase_48k.v','S09 S33','B02','音乐、进度、歌词/MV与电机停/走','静音与暂停区分'),
('EC1每格±2秒Seek','src/audio/seek_controller.v; src/io/ui_event_bridge.v','S11','B09','方向、时间跳变和重新起播','卡等待保留；不承诺瞬时定位'),
('遥控±5秒、长按连发','src/io/ui_command_router.v; src/audio/seek_controller.v','S12','B09','BB后退/BF前进及连续定位','仅进度键有repeat，实体方向需核对'),
('本曲重播','src/io/ui_command_router.v; src/audio/seek_controller.v','S12','B09','B9后同曲回起点并重新出声','不把回零动画当真正重播'),
('播放态左右切曲、上下音量','src/io/ui_event_bridge.v; src/audio/play_ctrl.v','S11 S17','B02','KEY1/3曲号变化，KEY4/5音量变化','旧手册快进/歌词翻行映射作废'),
('退出播放回浏览','src/io/browse_fsm.v; src/audio/play_ctrl.v','S34','B02 B08','KEY7或A1回中央封面，当前播放结束','区分单纯黑屏'),
('五行歌词逐句高亮滚动','src/display/lrc_window_controller.v; src/display/lrc_five_osd.v','S08 S15','B12','换句、暂停与Seek定位前后对应','不是逐字卡拉OK'),
('KEY6当前句专注切换','doc/产品项目输出/29_KEY6歌词专注模式开发与验证_20261022.md','S15','B03 B12','五行→当前句→五行，滚动连续，复位回默认','B版源码/仿真/构建来源明确；新增实板待核验'),
('封面/MV视窗切换','src/video/s6_video_layer.v; src/video/mv_frame_scheduler.v','S13','B03','KEY8后静态/动态各自真实出现','MV320×240 RGB565LE10fps，不贴原视频替代'),
('灰/虚化/艺术图1/艺术图2背景','src/display/playback_background.v; src/video/background_cache_loader.v','S14','B03','四种完整且不同背景实际出现','灰底回退不证明艺术资源已加载'),
('PCM波形/电平可视化','src/display/promax_audio_waveform.v; src/audio/pcm_tap.v','S06 S08 S17','','波形随真实输出，音量/静音有响应','不称FFT频谱'),
('EC2 SELECT/ADJUST与超时隐藏','src/io/ec2_param_controller.v','S16','','按压选择/调节、旋转选项/改值、停后隐藏','不是按压直接轮换参数'),
('VOL音量0至255','src/io/ui_param_csr.v','S17','B02','数值变化与声音相符，步长16','不要后期归一抹平变化'),
('BRI全局亮度五档','src/top_tf_hdmi_audio.v; src/display/brightness_contrast_steps.v','S18','','参数、歌词、MV与OSD同画面变化','相机固定曝光，不凭自动补偿判断'),
('CON对比度五档','src/display/brightness_contrast_steps.v','S18','','同画面明暗层次变化和参数读数','与BRI分条取证'),
('ROT轮播周期实际应用','src/io/ui_param_csr.v; src/io/slideshow_controller.v','S19','','2秒档/5秒档真实无操作切图','只改参数数字不算完整演示'),
('WSL双灯亮度0/25/50/75/100%','src/io/vinyl_playback_effects.v; src/io/ws2812_effects.v','S20','B07','两路同变，0档双灯黑而转盘继续','百分比相对各自安全调色板'),
('静音/恢复与时间继续','src/io/expansion_integration.v; src/top_tf_hdmi_audio.v','S22','B08','KEY4/F3音频静音，进度仍走，恢复原音量','母板KEY4与扩展KEY4不同'),
('手动黑屏与音乐继续','src/io/ui_command_router.v; src/top_tf_hdmi_audio.v','S22','B08','F6黑画面，真实声音继续','HDMI黑画面不是HDMI断链'),
('60秒无操作自动黑屏','src/io/ui_command_router.v','S31 S32','B16','连续真实60秒后自然黑屏、声音继续','S31—S33同条原片；不手动触发替代'),
('首个普通操作只唤醒','src/io/ui_command_router.v','S22 S33','','首按亮屏不暂停，第二次才执行','维护事件有独立处理，不泛称所有事件均被吞'),
('EOF播完暂停','src/audio/play_ctrl.v','S27','B10','自然到尾后当前曲停住','不是只切策略图标'),
('EOF单曲循环','src/audio/play_ctrl.v','S27','B10','自然到尾同曲从起点重新播放','保留重播起音'),
('EOF列表下一首及末曲回首','src/audio/play_ctrl.v','S27','B10','到尾下一曲起播，末曲回首曲另补','恢复默认策略为列表下一首'),
('手动保存五参数','src/io/ui_param_persistence.v; src/io/w25q64_param_store.v','S25','B11','先改脏、保存、忙灭/已保存亮','母板KEY3/E6均可，非无变化重复保存'),
('停变5秒自动保存','src/io/ui_param_persistence.v','S24','B11','SW3开，改参，5秒后触发并完成','5秒为触发条件，不是总事务时长'),
('五参数恢复默认并持久化','src/io/ui_param_csr.v; src/io/ui_param_persistence.v','S23','B08','非默认→200/3/2/2/4；等待默认记录完成','不把默认提交误计为下一笔自动保存'),
('正常保存后断电恢复五参','src/io/ui_param_persistence.v','S25 S26','B11','同组快照与复电值一致，恢复灯佐证','不含位置/曲目/背景/KEY6模式续存'),
('保存完成三音与操作声区分','src/io/system_sound_scheduler.v; src/io/buzzer_feedback.v','S24 S25','B11','提交完成后的连续三音，灯态相符','不能用按键响证明成功'),
('母板四灯NVM状态','src/io/ui_param_persistence.v; src/top_tf_hdmi_audio.v','S23 S24 S25 S26','','恢复/已保存/忙/故障分别识别','母板LED与扩展LED含义不同'),
('抬针/落针机械联动','src/io/vinyl_playback_effects.v','S10','B07','抬针电机和唱片灯停，音乐时间继续','不称抬针暂停音频，不称模拟黑胶读取'),
('转盘暂停/退出时停止','src/io/vinyl_playback_effects.v','S09 S34','B07','不同播放状态的电机响应','逻辑使能驱动外部功率级，不是FPGA脚直接供电'),
('唱片灯彩色相位效果','src/io/vinyl_playback_effects.v','S01 S10 S20','B07','落针/播放/使能条件下彩灯运行','无转速随音乐幅度变化的承诺'),
('J2 VU灯与KEY10模式','src/io/ws2812_effects.v; src/io/ui_event_bridge.v','S21','B03 B07','音乐包络变化，KEY10只关J2','不同于唱片灯'),
('DIP6双灯使能','src/io/ui_command_router.v; src/io/vinyl_playback_effects.v','S21','B07','双灯灭/开，转盘不因此停止','关后需实际黑帧结果'),
('扩展ACTION/MV/IR/心跳故障灯','src/io/led_business_driver.v','S21','B05 B08','动作短亮、MV状态、IR短亮、心跳/故障','不沿用旧播放/暂停灯表'),
('数码管时间和曲号、SW1使能','src/display/seg_business_mux.v','S11 S21','B05','时间/曲号对应；关数码不停止播放','浏览是总时长，播放是已播'),
('DIP1业务门控与恢复','src/io/expansion_integration.v','','B04','同一普通输入关无效、开恢复','不称整机电源总开关'),
('DIP3扩展LED开关','src/io/ui_command_router.v; src/io/led_business_driver.v','','B05','关扩展四灯，业务继续','母板LED不由此控制'),
('DIP5红外业务门控','src/io/ui_command_router.v','','B06','相同合法帧开有效、关无业务','不是接收头电源断开'),
('DIP4关自动消隐/开60秒','src/io/ui_command_router.v','S31 S32','B16','关闭清自动计时，开启后重新验证','手动黑屏独立存在'),
('21个遥控映射入口','src/io/ui_command_router.v','S12 S22 S25 S34','B08','逐个合法按钮动作可与主条引用对应','不编造遥控KEY8/KEY10/KEY12独立映射'),
('无卡当前故障与SW4告警门控','src/io/system_sound_scheduler.v; src/io/expansion_integration.v','S28','B16','真实错误、重复告警、SW4关/开对照','先实机排练再用确定旁白；旧未接线说明过期'),
('蜂鸣硬件开关与操作反馈','src/io/buzzer_feedback.v; doc/开发方案/产品交互.md','S21 S24 S28','B05','操作声/完成音/告警分清，物理开关只影响响声','蜂鸣不一定在HDMI轨，收现场原声'),
('Media Studio项目导入/保存/曲序','VinylFPGA_MediaStudio/使用说明.md','S29','B14','演示项目副本的素材、曲序、保存','离线工作，不改拍摄用主内容'),
('歌词编辑/偏移/拆行字库约束','VinylFPGA_MediaStudio/使用说明.md','S29','B14','编辑应用为素材，检查实际拆行与占用','草稿保存不等于镜像更新'),
('FAT32镜像构建与完整回读校验','VinylFPGA_MediaStudio/验收报告.md','S29','B14','真实成功版本及校验结果，构建等待标注节选','已有测试记录；本次没有重跑或生成媒体镜像'),
('从最终镜像预览与PCM试听','VinylFPGA_MediaStudio/使用说明.md','S29','','640×480预览、点阵、10fps原始MV、电脑试听','标离线预览，不替代实机屏幕/原声'),
('冻结ROM兼容与自定义ROM交接','VinylFPGA_MediaStudio/使用说明.md','S29','B14','冻结差异提示；自定义requires_build提示','只写卡不能更新固件中文字，KEY6新模式不在旧预览配置'),
('文件模拟写入与回读','VinylFPGA_MediaStudio/验收报告.md','S29','B14','明确模拟文件、回读成功结果','模拟不等于物理SD写入'),
('实体卡写入入口及全量回读','VinylFPGA_MediaStudio/使用说明.md','S29','B14','备用卡目标身份、实际写入与完整回读成功','现有工具报告未完成物理写卡；主稿仅入口，不宣称已实测'),
('像素比对/RTL历史证据与实板PNG入口','VinylFPGA_MediaStudio/evidence/rtl_final/results.json','S29','B15','12组固定RTL状态历史0差异；本次实板仅凭实际导入结果','旧配置不覆盖KEY6新状态；手机照片不能作零差异证据'),
('共同时间轴/多级缓存/MV三缓冲','src/audio/timebase_48k.v; src/video/mv_frame_scheduler.v','S30','','设计示意与生产源码匹配','这是设计解释，不是全部边界或长期零卡顿证明'),
('版本绑定资源与时序报告','prj/VinylFPGA_Runs/lyric_focus_20261022/final.area; doc/产品项目输出/27_最终冻结与收尾验收_20261022.md','S35','','选实际A/B版对应报告数值','本次读取历史构建报告，非重新跑实现')
]

with (OUT/'07_全功能覆盖与补录.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.writer(f)
    w.writerow(['编号','功能/控制分支','依据（相对项目根）','主片镜头','补录附件','成功判据','事实/证据边界','现场结果（待填写）','原片文件（待填写）','成片位置（待填写）'])
    for n,row in enumerate(FEATURES,1):
        w.writerow([f'F{n:02}',*row,'','',''])

# Spoken expansions avoid an engine misreading compressed acronyms.
ttsdir=OUT/'TTS逐条文本'
ttsdir.mkdir(exist_ok=True)
def spoken(s):
    substitutions=[('VinylFPGA','唱片音乐画屏'),('Media Studio','媒体工作室'),
       ('EG4S20 FPGA','F P G A'),('FPGA','F P G A'),('HDMI','H D M I'),
       ('TF卡','T F 卡'),('PCM','P C M'),('MV','音乐视频'),('SW4','主板告警开关'),
       ('J2','扩展板'),('KEY6','歌词切换键')]
    for a,b in substitutions: s=s.replace(a,b)
    return s
for s in scenes:
    if not s['narration']: continue
    suffix={'S03':'_需冷启动实机证据','S15':'_B版且实板核验后','S28':'_故障实机核验后'}.get(s['id'],'')
    (ttsdir/(s['id']+suffix+'.txt')).write_text(spoken(s['narration'])+'\n',encoding='utf-8')
alternatives={
 'S15_A版替换.txt':'歌词随播放进度逐句高亮，并保留前后文。暂停时歌词时间停住，重新定位后跟随新的播放位置。',
 'S03_尚未固化时仅作待补说明.txt':'启动后，系统读取媒体卡并进入封面浏览。当前冷启动证据仍需补充。',
 'S28_未完成故障实拍时替换.txt':'当前代码也接入了故障提醒与主板开关控制。这部分实机取证列在补录清单。'
}
for name,txt in alternatives.items():
    (ttsdir/name).write_text(txt+'\n',encoding='utf-8')
(ttsdir/'使用前必读.md').write_text('''# TTS文本使用说明

主稿34条有旁白，S32没有旁白。条件条S03、S15、S28按实际素材选一种，不要把替换稿也追加到同一个镜头。每个txt只包含可读正文，可逐条复制到你使用的TTS工具。

统一中文声线，先试S01、S09、S24。品牌名默认口播“唱片音乐画屏”，画面仍写VinylFPGA；媒体工具口播“媒体工作室”。F P G A、H D M I等按字母读，若引擎停顿不自然，用引擎的发音词典或你习惯的读法替换。展开不保证每个引擎发音相同，必须试听。

音频文件按S01.wav命名。实测时长、字词停顿和最后一字是否完整都检查后再排时间线。旁白的计划字幕仍用常见技术写法，最终须跟实际合成语音重对齐。没有在本次执行TTS生成或替你调用付费合成服务。
''',encoding='utf-8')

# Small Markdown subset used by this booklet. No remote assets or scripts.
def inline(s):
    code=[]
    def keep(m):
        code.append('<code>'+html.escape(m.group(1))+'</code>')
        return f'CODETOKEN{len(code)-1}END'
    s=re.sub(r'`([^`]+)`',keep,s)
    s=html.escape(s)
    s=re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',s)
    s=re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)',r'<a href="\2">\1</a>',s)
    for i,v in enumerate(code): s=s.replace(f'CODETOKEN{i}END',v)
    return s

def markdown(txt):
    lines=txt.splitlines(); out=[]; i=0
    while i<len(lines):
        line=lines[i]
        if not line.strip(): i+=1; continue
        if line.startswith('```'):
            i+=1; buf=[]
            while i<len(lines) and not lines[i].startswith('```'): buf.append(lines[i]); i+=1
            out.append('<pre>'+html.escape('\n'.join(buf))+'</pre>'); i+=1; continue
        m=re.match(r'^(#{1,6}) (.+)',line)
        if m:
            n=len(m[1]); title=m[2]
            sid=(re.match(r'(S\d{2})｜',title) or [None,None])[1]
            anchor=f' id="{sid}"' if sid else ''
            out.append(f'<h{n}{anchor}>{inline(title)}</h{n}>'); i+=1; continue
        if line.startswith('|'):
            rows=[]
            while i<len(lines) and lines[i].startswith('|'):
                cells=[x.strip() for x in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-+:?',x.replace(' ','')) for x in cells): rows.append(cells)
                i+=1
            out.append('<div class="tablewrap"><table>')
            for n,row in enumerate(rows):
                tag='th' if n==0 else 'td'
                out.append('<tr>'+''.join(f'<{tag}>{inline(x)}</{tag}>' for x in row)+'</tr>')
            out.append('</table></div>'); continue
        if re.match(r'^[-*] ',line) or re.match(r'^\d+\. ',line):
            ordered=bool(re.match(r'^\d+\. ',line)); tag='ol' if ordered else 'ul'
            out.append(f'<{tag}>')
            pat=r'^\d+\. ' if ordered else r'^[-*] '
            while i<len(lines) and re.match(pat,lines[i]):
                s=re.sub(pat,'',lines[i]); s=s.replace('[ ]','□').replace('[x]','☑')
                out.append('<li>'+inline(s)+'</li>'); i+=1
            out.append(f'</{tag}>'); continue
        if line.startswith('> '):
            out.append('<blockquote>'+inline(line[2:])+'</blockquote>'); i+=1; continue
        buf=[line]; i+=1
        while i<len(lines) and lines[i].strip() and not re.match(r'^(#|\||```|[-*] |\d+\. |>)',lines[i]):
            buf.append(lines[i]); i+=1
        out.append('<p>'+inline(' '.join(buf))+'</p>')
    return '\n'.join(out)

chapters=[('start','00_从这里开始.md'),('script','02_十三分钟完整版_逐镜头脚本.md'),
 ('shoot','03_拍摄日执行与后期手册.md'),('card','09_开拍前核验与补拍卡.md'),
 ('voice','05_旁白提词稿.md'),('short','04_三分钟精简版.md'),('audit','01_项目代码与资料复核.md')]
nav=''.join(f'<a href="#{anchor}">{html.escape(fn.split("_",1)[1][:-3])}</a>' for anchor,fn in chapters)
body=''.join('<section id="'+anchor+'">'+markdown((OUT/fn).read_text(encoding='utf-8'))+'</section>' for anchor,fn in chapters)
matrix='<section id="coverage"><h1>全功能覆盖与补录总表</h1><p>本表是拍摄计划，不是已拍完/已通过的验收报告。现场结果在CSV填写。</p><table><tr><th>编号/功能</th><th>主片/补录</th><th>观察判据与边界</th></tr>'
for n,(feat,source,shots,extra,proof,boundary) in enumerate(FEATURES,1):
    matrix+=f'<tr><td>F{n:02} {html.escape(feat)}</td><td>{html.escape(shots)}<br>{html.escape(extra)}</td><td>{html.escape(proof)}<br><small>{html.escape(boundary)}</small></td></tr>'
matrix+='</table></section>'
css='''
:root{color-scheme:light;--ink:#243329;--green:#345b42;--line:#d4ddd3;--pale:#f3f6ef}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;color:var(--ink);background:#e9eee6;font:16px/1.85 "Microsoft YaHei","Segoe UI",sans-serif}
header{padding:44px max(30px,calc((100% - 1100px)/2));background:#203d2d;color:#fff}header p{color:#d8e4cf;max-width:850px}header h1{margin:0;font-size:34px}
nav{display:flex;flex-wrap:wrap;gap:8px;margin-top:20px}nav a{padding:5px 12px;background:#35543e;color:white;text-decoration:none;border-radius:5px}
main{max-width:1160px;padding:28px 35px;margin:auto;background:#fff}section{padding:8px 0 32px;border-bottom:2px solid var(--line);scroll-margin-top:15px}
h1{font-size:28px;color:#24422f;line-height:1.5;margin-top:30px}h2{font-size:22px;margin-top:34px;color:#345b42}h3{font-size:19px;margin:34px 0 15px;padding:13px 16px;background:var(--pale);border-left:5px solid #78945d;scroll-margin-top:15px}
p{margin:12px 0}a{color:#2d6641}table{width:100%;border-collapse:collapse;font-size:14px;line-height:1.65;margin:14px 0}th,td{border:1px solid var(--line);padding:9px 10px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#eef3e9}tr:nth-child(even){background:#fafbf8}.tablewrap{overflow-x:auto}
code{font-family:Consolas,"Microsoft YaHei",monospace;background:#f2f3ee;padding:1px 4px;font-size:.88em;overflow-wrap:anywhere}blockquote{margin:18px 0;padding:12px 22px;border-left:4px solid #71925e;background:#f3f6ef}li{margin:6px 0}small{color:#607064}footer{max-width:1160px;margin:auto;padding:22px 35px;color:#52604e;font-size:13px}
@media(max-width:650px){main{padding:14px 18px}header{padding:28px 18px}header h1{font-size:27px}table{font-size:12px}}
@page{size:A4;margin:16mm 14mm} @media print{body{background:white;font-size:10.5pt;line-height:1.65}main{padding:0;max-width:none}header{padding:10mm;color:#172f1d;background:#eef3e9}header p{color:#34513a}nav{display:none}h1{font-size:20pt}h2{font-size:15pt}h3{font-size:12pt;break-after:avoid}table{font-size:8.5pt}tr,blockquote{break-inside:avoid}section{break-before:page;border:0}section:first-child{break-before:auto}a{color:inherit;text-decoration:none}footer{padding:5mm 0}.tablewrap{overflow:visible}}
'''
document='<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>VinylFPGA 拍摄执行手册</title><style>'+css+'</style></head><body><header><h1>VinylFPGA · 拍摄执行手册</h1><p>13分钟完整版 · 35个镜头 · 多手机固定机位 · 真实作品原声 · 分段TTS · 2026-10-23</p><p>先看拍摄脚本，再按拍摄日手册执行。KEY6和故障镜头按实板核验选择，不混淆版本。所有拍摄条目均为计划，现场结果需登记。</p><nav>'+nav+'<a href="#coverage">功能覆盖表</a></nav></header><main>'+body+matrix+'</main><footer>本地独立阅读文件，无外部脚本或网络资源依赖。浏览器打印可导出PDF。修改源文件后重新运行制作脚本生成。</footer></body></html>'
(OUT/'VinylFPGA_拍摄执行手册.html').write_text(document,encoding='utf-8')

# Evidence-based checks: content structure and existing artifact identity only.
checks={}
checks['timeline_780_seconds']=scenes[0]['start']==0 and scenes[-1]['end']==780 and all(a['end']==b['start'] for a,b in zip(scenes,scenes[1:]))
checks['35_complete_scene_cards']=len(scenes)==35 and all(all(s.get(k) for k in ['id','state','action','overlay','sound','criterion','raw','exit']) for s in scenes)
checks['60_seconds_real_idle_budget']=next(s for s in scenes if s['id']=='S32')['duration']==62
checks['no_idle_narration']=next(s for s in scenes if s['id']=='S32')['narration']==''
ids={s['id'] for s in scenes}
checks['coverage_scene_references_exist']=all(all(x in ids for x in row[2].split()) for row in FEATURES)
checks['coverage_all_have_shot_or_supplement']=all(row[2] or row[3] for row in FEATURES)
checks['all_35_scenes_represented_in_coverage']=ids <= {s for r in FEATURES for s in r[2].split()} | {'S01','S02'}
short=(OUT/'04_三分钟精简版.md').read_text(encoding='utf-8')
times=re.findall(r'\| T\d+ \| (\d\d):(\d\d)—(\d\d):(\d\d) \|',short)
pairs=[(int(a)*60+int(b),int(c)*60+int(d)) for a,b,c,d in times]
checks['short_180_seconds']=len(pairs)==14 and pairs[0][0]==0 and pairs[-1][1]==180 and all(a[1]==b[0] for a,b in zip(pairs,pairs[1:]))
checks['34_default_tts_plus_3_alternates']=len(list(ttsdir.glob('*.txt')))==37
checks['html_all_35_scene_anchors']=all(f'id="{s}"' in document for s in ids)
checks['known_user_equipment_in_booklet']=all(x in document for x in ['没有HDMI采集卡','助手','TTS'])

manifest=json.loads((ROOT/'prj/VinylFPGA_Runs/lyric_focus_20261022/release_manifest.json').read_text(encoding='utf-8'))
input_diffs=[]
for name,digest in manifest['hardware_inputs_sha256'].items():
    p=Path(name)
    if not p.is_absolute(): p=ROOT/p
    if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest: input_diffs.append(str(p))
checks['latest_hardware_snapshot_matches_current_files']=not input_diffs
firmware_checks={}
for tag,rel,digest in [
 ('A','prj/VinylFPGA_Runs/save_success_phrase_20261022/release/VinylFPGA.bit','1801a8d36429fe767c0d7e510db0edfed86faaccdba966c8843e043aba39dad5'),
 ('B','prj/VinylFPGA_Runs/lyric_focus_20261022/release/VinylFPGA.bit','8edae18e61d0bff6c732295039082755870b43ebb0d11f1f2cf2c1326dbff41a')]:
    actual=hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()
    firmware_checks[tag]={'path':rel,'expected':digest,'actual':actual,'matches':actual==digest}
checks['release_bit_file_hashes_match']=all(x['matches'] for x in firmware_checks.values())
checks['final_report_numbers_match']=all(x in (ROOT/'prj/VinylFPGA_Runs/lyric_focus_20261022/final.timing').read_text(encoding='utf-8') for x in ['0.143ns','0.037ns']) and '17964' in (ROOT/'prj/VinylFPGA_Runs/lyric_focus_20261022/final.area').read_text(encoding='utf-8')

evidence={'date':'2026-10-23','scope':'拍摄材料一致性、时间轴与既有产物哈希核对；不是新的RTL/构建/板卡测试',
 'checks':checks,'all_passed':all(checks.values()),'scenes':35,'feature_families_and_branches':len(FEATURES),
 'hardware_input_hashes_checked':len(manifest['hardware_inputs_sha256']), 'hardware_input_differences':input_diffs,
 'firmware_file_hashes':firmware_checks,'hardware_download_performed':False,'physical_sd_write_performed':False,
 'tts_generated':False,'actual_footage_recorded':False}
(OUT/'制作源文件/交付检查.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf-8')
assert all(checks.values()),json.dumps(checks,ensure_ascii=False)

archive=OUT/'VinylFPGA_完整拍摄执行包_20261023.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(OUT.rglob('*')):
        if p.is_file() and p.suffix not in ['.zip','.png'] and '__pycache__' not in p.parts:
            z.write(p,p.relative_to(OUT))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
print(json.dumps({'checks':checks,'features':len(FEATURES),'hardware_hashes':len(manifest['hardware_inputs_sha256']),'zip_bytes':archive.stat().st_size},ensure_ascii=False))
