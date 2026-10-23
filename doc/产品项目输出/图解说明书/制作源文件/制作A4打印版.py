"""Three A4 landscape sheets: original diagrams, embedded fonts, vector callouts."""
from pathlib import Path
import hashlib
import json
import math
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.lib.colors import HexColor, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader, PdfWriter
from pypdf.generic import NameObject, DictionaryObject, BooleanObject

ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / 'doc/产品项目输出/图解说明书'
SOURCES = ROOT / 'doc/相关素材/处理素材'
OUTPUT = BASE / 'A4打印版'
WORK = ROOT / 'tmp/pdfs/vinyl_a4_20261022'
OUTPUT.mkdir(exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)
FINAL = OUTPUT / 'VinylFPGA_图解操作说明_A4横向_打印版.pdf'
pdfmetrics.registerFont(TTFont('ManualSans', 'C:/Windows/Fonts/msyh.ttc', subfontIndex=0))
pdfmetrics.registerFont(TTFont('ManualSansBold', 'C:/Windows/Fonts/msyhbd.ttc', subfontIndex=0))
BLUE, GRAY, MUTED = map(HexColor, ('#1867B7', '#303944', '#647281'))
PW, PH = landscape(A4)
RAW = WORK / 'a4_vector_source.pdf'
c = canvas.Canvas(str(RAW), pagesize=(PW, PH), pageCompression=1,
                  initialFontName='ManualSans', initialFontSize=8, invariant=1,
                  pdfVersion=(1,7))
c.setTitle('VinylFPGA - A4 Landscape Operation Guides')
c.setAuthor('VinylFPGA')
c.setCreator('VinylFPGA A4 Print Layout')
c.setSubject('Three A4 landscape printable diagram operation guides')
TEXTS, LINES, IMAGES = [], [], []
PAGE = 0
DIAGRAM = None

def text(s, x, y, size=8.0, bold=False, color=GRAY, kind='body'):
    """Coordinates are millimetres from the top left; font sizes are points."""
    font = 'ManualSansBold' if bold else 'ManualSans'
    width = pdfmetrics.stringWidth(s, font, size) / mm
    height = size * 1.08 / mm
    assert x >= 6.8 and x + width <= 290.2, (PAGE, s, x, width)
    assert y >= 6.8 and y + height <= 203.2, (PAGE, s, y, height)
    c.setFillColor(color)
    c.setFont(font, size)
    c.drawString(x * mm, PH - y * mm - size * .83, s)
    TEXTS.append(dict(page=PAGE, text=s, x=x, y=y, width=width, height=height,
                      font=font, size=size, kind=kind))
    return x + width

def wrap(s, width, size=8.0):
    lines, current = [], ''
    for ch in s:
        if ch == '\n':
            lines.append(current); current = ''; continue
        trial = current + ch
        if current and pdfmetrics.stringWidth(trial, 'ManualSans', size) / mm > width:
            lines.append(current.rstrip()); current = ch.lstrip()
        else:
            current = trial
    if current:
        lines.append(current)
    return lines

def block(title, x, y, bodies, width, title_size=9.4, body_size=8.0,
          gap=5.2, line_gap=3.6, body_color=GRAY):
    end = text(title, x, y, title_size, True, BLUE, 'heading')
    yy = y + gap
    for body in bodies:
        for line in wrap(body, width, body_size):
            text(line, x, yy, body_size, color=body_color)
            yy += line_gap
    return end, yy

def xy(p):
    return p[0]*mm, PH-p[1]*mm

def leader(points, dot=True, width=.23):
    assert all(6.8 <= x <= 290.2 and 6.8 <= y <= 203.2 for x,y in points), points
    c.setStrokeColor(BLUE); c.setLineWidth(width*mm)
    path = c.beginPath(); path.moveTo(*xy(points[0]))
    current = points[0]
    for corner, nxt in zip(points[1:-1], points[2:]):
        l1 = math.dist(current, corner); l2 = math.dist(corner, nxt)
        rr = min(.75, l1/3, l2/3)
        if rr > 0:
            enter = tuple(corner[j]-(corner[j]-current[j])*rr/l1 for j in (0,1))
            leave = tuple(corner[j]+(nxt[j]-corner[j])*rr/l2 for j in (0,1))
            path.lineTo(*xy(enter)); path.curveTo(*xy(corner), *xy(corner), *xy(leave))
            current = leave
    path.lineTo(*xy(points[-1])); c.drawPath(path)
    if dot:
        x,y = xy(points[-1]); c.setFillColor(white); c.circle(x,y,.57*mm,stroke=0,fill=1)
        c.setFillColor(BLUE); c.circle(x,y,.32*mm,stroke=0,fill=1)
    LINES.append(dict(page=PAGE, points=points, width_mm=width))

def bracket(points):
    leader(points, dot=False, width=.20)

def badge(s, x, y, radius=1.55, size=6.4):
    # Single-digit references stay legible on A4 without obscuring the diagram.
    if s.isdigit():
        s = str(int(s))
        size = max(size, 7.0)
    c.setFillColor(white); c.circle(x*mm,PH-y*mm,(radius+.14)*mm,stroke=0,fill=1)
    c.setFillColor(BLUE); c.circle(x*mm,PH-y*mm,radius*mm,stroke=0,fill=1)
    c.setFillColor(white); c.setFont('ManualSansBold',size)
    c.drawCentredString(x*mm,PH-y*mm-size*.40,s)

def begin_page(name, source, sw, sh, height=186):
    global PAGE, DIAGRAM
    PAGE += 1
    c.bookmarkPage(str(PAGE)); c.addOutlineEntry(name,str(PAGE),level=0)
    width = sw * height/sh; left = (297-width)/2; top = 9
    source_path = SOURCES/source
    c.drawImage(str(source_path),left*mm,PH-(top+height)*mm,
                width=width*mm,height=height*mm,preserveAspectRatio=True,mask='auto')
    DIAGRAM = dict(left=left,top=top,unit=height/sh,width=width,height=height)
    IMAGES.append(dict(page=PAGE,source=str(source_path),left=left,top=top,
                       width=width,height=height,dpi=sh/(height/25.4),
                       sha256=hashlib.sha256(source_path.read_bytes()).hexdigest()))

def src(x,y):
    d=DIAGRAM; return (d['left']+x*d['unit'],d['top']+y*d['unit'])

def finish_page():
    c.showPage()

# 1. FPGA development board.
begin_page('开发板操作说明','开发板功能图.png',3060,4096)
end,_=block('SD 卡槽',7,42.8,['插入存放歌曲、封面与 MV 的 SD 卡。'],68)
leader([(end+2,44.6),src(260,785)])
text('系统按键 · 对照图中 1–4',7,59.8,8.8,True,BLUE,'heading')
keys=[('01',1315,'一键静音 · KEY4','按下静音，再次按下恢复原音量。'),
      ('02',1500,'保存参数 · KEY3','保存当前五项参数，供重启后恢复。'),
      ('03',1685,'恢复默认 · KEY2','恢复五项默认参数，并保存默认配置。'),
      ('04',1870,'系统重启 · KEY1','重启系统，重新加载音视频与界面。')]
for i,(ident,cy,title,body) in enumerate(keys):
    p=src(695,cy);badge(ident,*p,1.45,6.3)
    leader([src(665,cy),src(658,cy)],False,.18)
    yy=66.5+i*10;badge(ident,8.65,yy+1.55,1.6,7.0)
    block(title,12,yy,[body],63,title_size=8.8,gap=4.8,line_gap=3.5)
switches=[(2195,'系统告警 · SW4','拨动开关，开启／关闭故障告警。'),
          (2425,'自动保存 · SW3','拨上开启，参数停变 5 秒后自动保存。'),
          (2650,'跳过开机动画 · SW2','拨上跳过动画；拨下播放开机动画。'),
          (2875,'数码管总控 · SW1','拨上点亮数码管；拨下关闭显示。'),
          (3105,'蜂鸣器开关 · BUZ_SW','物理控制蜂鸣器供电与提示音。')]
for cy,title,body in switches:
    anchor=src(285,cy);end,_=block(title,7,anchor[1]-1.8,[body],68)
    leader([(end+2,anchor[1]),anchor])
anchor=src(360,3615);end,_=block('蜂鸣器',7,anchor[1]-1.8,
                            ['发出操作反馈短音与故障告警音。'],68)
leader([(end+2,anchor[1]),anchor])
text('保存项 · VOL / BRI / CON / ROT / WSL',7,188,8.5,True,BLUE,'heading')
text('音量／亮度／对比度／轮播周期／灯带亮度。',7,193,7.5)
text('保存完成：LED3 熄灭，LED2 点亮。',7,197,7.5,color=MUTED)
block('交互扩展接口',227,22.0,['通过排线连接交互扩展板。'],63)
leader([(225.2,23.8),src(2500,325),src(2425,325)])
block('状态指示灯 · LED1–LED4',227,56.8,
      ['LED1 加载：恢复有效配置后亮。','LED2 保存：改参灭，保存完成亮。',
       'LED3 Flash 忙：初始化或擦写时亮。','LED4 故障：异常保持到复位。'],63,
      body_size=7.8,line_gap=3.8)
text('图内“系统繁忙／故障”指 Flash 状态。',227,78.9,7.2,color=MUTED)
bracket([src(2180,960),src(2210,960),src(2210,1640),src(2180,1640)])
leader([(225.2,src(2210,1090)[1]),src(2210,1090)])
block('数码管 · 时长与曲目编号',227,93.0,
      ['时长区：播放时间（分／秒）。','编号区：当前曲目编号。','异常时可显示状态码。'],63)
leader([(225.2,src(2120,1890)[1]),src(2150,1890),src(2125,1920)])
text('板载接口 · 对照图中 A–F',227,116.8,8.8,True,BLUE,'heading')
ports=[('A','HDMI A','HDMI 音视频连接。',650,[(3094,650),(2875,650)]),
       ('B','电源开关 · POWER','开启或关闭整机电源。',1420,[(3094,1420),(2870,1420),(2838,1390)]),
       ('C','USB-JTAG','下载 FPGA 程序，连接调试工具。',1850,[(3094,1850),(2890,1850)]),
       ('D','USB-UART','串口通信与调试连接。',2240,[(3094,2240),(2890,2240),(2855,2205)]),
       ('E','HDMI B','HDMI 音视频连接。',2750,[(3094,2750),(2910,2750),(2870,2690)]),
       ('F','VGA','板载 VGA 视频接口。',3280,[(3094,3280),(3050,3280)])]
for i,(ident,title,body,cy,pts) in enumerate(ports):
    badge(ident,*src(3125,cy),1.35,7.0);leader([src(*p) for p in pts])
    yy=123.3+i*10;badge(ident,228.5,yy+1.5,1.5,7.2)
    block(title,232,yy,[body],58,title_size=8.7,body_size=7.7,gap=4.4,line_gap=3.4)
block('唱片机扩展接口',227,187.5,['连接唱片机扩展部件。'],63)
leader([(225.2,189.3),(221,189.3),(221,src(2470,3815)[1]),src(2470,3815),src(2418,3830)])
finish_page()

# 2. Expansion board, matching the approved v3 definitions and grouping.
begin_page('扩展板操作说明','拓展板功能图.png',3300,4096)
text('图内名称说明',7,10.0,8.8,True,BLUE,'heading')
text('上方“播放方式”：返回选歌。',7,15.0,7.5,color=MUTED)
text('最下方“播放方式”：播完策略。',7,18.8,7.5,color=MUTED)
dip_data=[(655,'灯带总开关 · DIP6',['拨上开启两路灯带；拨下关闭。']),
          (982,'红外接收 · DIP5',['拨上启用遥控器；拨下屏蔽。']),
          (1310,'自动息屏 · DIP4',['开启后，60 秒无操作自动息屏。','音频继续，任意操作可唤醒。']),
          (1638,'指示灯总控 · DIP3',['拨上显示状态；拨下熄灭指示灯。']),
          (1966,'自动切图 · DIP2',['拨上自动轮播封面；拨下停止。']),
          (2298,'扩展板总控 · DIP1',['拨下屏蔽扩展板控制，防止误触。'])]
for source_top,title,bodies in dip_data:
    horizontal=src(518,source_top-30);end,_=block(title,7,horizontal[1]-1.8,bodies,63)
    leader([(end+2,horizontal[1]),horizontal,src(542,source_top+5)])
text('功能按键 · 对照图中 1–7',7,123.0,8.8,True,BLUE,'heading')
exp_keys=[('01',1045,'歌词动效 · KEY6 / SW9','滚动歌词／逐字高亮。'),
          ('02',1380,'封面与 MV · KEY8 / SW17','切换静态封面与动态视频。'),
          ('03',1715,'返回选歌 · KEY7 / SW16','退出播放，返回选歌界面。'),
          ('04',2045,'转场效果 · KEY9 / SW18','淡入淡出／百叶窗／直切。'),
          ('05',2380,'灯光效果 · KEY10 / SW19','关闭／音频电平律动。'),
          ('06',2715,'播放背景 · KEY11 / SW20','循环切换四种背景。'),
          ('07',3045,'播完策略 · KEY12 / SW3','播完暂停／单曲循环／列表循环。')]
for i,(ident,cy,title,body) in enumerate(exp_keys):
    badge(ident,*src(959,cy),1.42,6.3)
    leader([src(988,cy),src(993,cy)],False,.18)
    yy=130+i*8.8;badge(ident,8.6,yy+1.5,1.55,6.8)
    block(title,12,yy,[body],58,title_size=8.5,body_size=7.7,gap=4.3,line_gap=3.4)
end,_=block('红外接收头 · U10',7,194.0,['遥控器朝向此处使用。'],63,body_size=7.8)
leader([(end+2,195.8),(src(250,3995)[0],195.8),src(540,3625),src(632,3625)])
block('播控旋钮 · EC1 / SW1',231,43.8,
      ['旋转：选曲／调整播放进度。','按下：确认播放／暂停／继续。'],59)
leader([(229.2,src(2540,815)[1]),src(2540,815),src(2540,995),src(2478,995)])
block('WS2812B 氛围灯',231,60.5,['8 颗彩灯呈现音乐律动。'],59)
leader([(229.2,62.3),(225.7,62.3),(225.7,src(3175,1045)[1]),src(3175,1045)])
block('五向导航 · KEY1–KEY5',231,72.6,
      ['浏览：选曲、移动、确认播放。','播放：左右调进度，确定暂停／继续。',
       '上、下键用于前后滚动／翻行。'],59,body_size=7.8,line_gap=3.6)
bracket([src(2140,1540),src(2180,1540),src(2180,2570),src(2140,2570)])
leader([(229.2,src(2180,1440)[1]),src(2180,1440),src(2180,1540)])
block('状态指示灯 · LED1–LED4',231,124.4,
      ['LED1 播放　LED2 暂停','LED3 MV　　LED4 故障'],59)
text('图内“红外指示”对应暂停；',231,138.1,7.4,color=MUTED)
text('“交互反馈”对应故障。',231,141.8,7.4,color=MUTED)
bracket([src(2800,1850),src(2830,1850),src(2830,2240),src(2800,2240)])
leader([(229.2,src(2870,2580)[1]),src(2870,2580),src(2870,2060),src(2830,2060)])
block('调参旋钮 · EC2 / SW2',231,147.8,
      ['旋转调数值；按下打开浮窗、','切换参数或关闭浮窗，无需长按。'],59,
      body_size=7.8,line_gap=3.6)
text('VOL 音量 · BRI 亮度 · CON 对比度',231,163.0,7.5)
text('ROT 轮播周期 · WSL 灯带亮度',231,167.0,7.5)
text('WSL 为 0 关灯，不关闭电机。',231,172.0,7.5,color=MUTED)
leader([(229.2,src(2540,3095)[1]),src(2540,3095),src(2478,3090)])
finish_page()

# 3. Infrared remote, following the already confirmed document convention.
begin_page('红外遥控器操作说明','红外遥控功能图.jpg',490,1024)
left_data=[('重播 · CH',18.0,['进度清零，从头重新播放当前歌曲。'],
            [(185,75),(185,104),(210,104)]),
           ('上一首 · CH−',32.8,['切换到上一首歌曲。'],[(70,141)]),
           ('进度− · NEXT',42.1,['快退 5 秒；长按连续快退。'],[(185,192),(185,225),(210,225)]),
           ('进度＋ · PREV',54.6,['快进 5 秒；长按连续快进。'],[(70,261)]),
           ('音量− · 图中“＋”键',63.9,['减小音量，联动显示音量浮窗。'],[(185,312),(185,346),(210,346)]),
           ('音量＋ · 图中“−”键',76.4,['增大音量，联动显示音量浮窗。'],[(70,381)]),
           ('保存参数 · 100＋',86.9,['保存当前五项参数，供下次开机恢复。'],[(185,439),(185,461),(210,461)]),
           ('系统重启 · 0',97.3,['重启系统并重新加载。'],[(70,496)]),
           ('静音 · 1',118.2,['按下静音，再次按下恢复原音量。'],[(70,611)]),
           ('转场特效 · 7',160.3,['切换淡入淡出、百叶窗或直切效果。'],[(70,843)])]
for title,yy,bodies,source_points in left_data:
    end,_=block(title,7,yy,bodies,93,body_size=8.2)
    pp=[src(*p) for p in source_points]
    leader([(end+2,pp[0][1])]+pp)
right_data=[('下一首 · CH＋',32.8,['切换到下一首歌曲。'],(430,141)),
            ('暂停／播放 · PLAY/PAUSE',54.6,['切换暂停与继续播放。'],(430,261)),
            ('息屏 · EQ',76.4,['切换黑屏显示，音频继续播放。'],(430,381)),
            ('恢复默认并保存 · 200＋',97.3,['恢复五项默认参数，并写入 Flash。'],(430,496)),
            ('返回选歌 · 3',118.2,['退出播放，返回选歌浏览界面。'],(430,611)),
            ('方向与确认 · 灰色方向区',139.0,
             ['2／8：向上／向下移动或滚动。','4／6：左右选曲；播放时快退／快进 2 秒。',
              '5：确认播放；播放时暂停／继续。'],(432,726)),
            ('播放背景 · 9',160.3,['循环切换四种播放界面背景。'],(430,843))]
for title,yy,bodies,target in right_data:
    block(title,197,yy,bodies,93,body_size=8.2,line_gap=3.9)
    p=src(*target);leader([(195.2,p[1]),p])
text('按键标注说明',7,187.0,8.8,True,BLUE,'heading')
text('本页按《产品交互.md》的中文功能标注。',7,192.0,7.7,color=MUTED)
text('进度、音量以中文功能为准，勿按箭头或加减符号判断。',7,196.0,7.7,color=MUTED)
text('使用提示',197,187.0,8.8,True,BLUE,'heading')
text('开启扩展板 DIP5，遥控器朝向红外接收头。',197,192.0,7.7)
text('保存项：VOL 音量、BRI 亮度、CON 对比度、',197,196.0,7.7)
text('ROT 轮播周期、WSL 灯带亮度。',197,200.0,7.7)
finish_page()
c.save()

# Explicit A4 boxes and viewer print preferences; all fonts stay embedded.
writer=PdfWriter(clone_from=str(RAW))
writer.pdf_header = '%PDF-1.7'
for key in ('/CreationDate','/ModDate'):
    writer._info.get_object().pop(NameObject(key),None)
writer._root_object[NameObject('/ViewerPreferences')]=DictionaryObject({
    NameObject('/PrintScaling'):NameObject('/None'),
    NameObject('/Duplex'):NameObject('/Simplex'),
    NameObject('/PickTrayByPDFSize'):BooleanObject(True),
})
for p in writer.pages:
    p.cropbox=p.mediabox
    p.trimbox=p.mediabox
with FINAL.open('wb') as f:
    writer.write(f)

# Check page geometry, readable text, font embedding and preserved sources.
reader=PdfReader(str(FINAL))
assert len(reader.pages)==3
page_results=[]
for i,p in enumerate(reader.pages,1):
    w,h=float(p.mediabox.width),float(p.mediabox.height)
    assert abs(w-PW)<.01 and abs(h-PH)<.01
    fonts=[]
    for f in p['/Resources']['/Font'].values():
        font=f.get_object();fd=font.get('/FontDescriptor')
        assert fd, font
        desc=fd.get_object()
        assert any(k in desc for k in ('/FontFile','/FontFile2','/FontFile3')),font
        fonts.append(str(font['/BaseFont']))
    extracted=p.extract_text()
    must_have={1:['KEY1','SW2','LED4','USB-JTAG'],
               2:['DIP6','KEY12','EC2','WSL'],
               3:['100','200','NEXT','PREV','DIP5']}[i]
    assert all(s in extracted for s in must_have),(i,must_have)
    assert len(p.images)==1,(i,len(p.images))
    page_results.append(dict(page=i,width_mm=round(w/mm,6),height_mm=round(h/mm,6),
                             embedded_fonts=fonts,source_diagram_count=len(p.images),
                             extractable_text_characters=len(extracted)))
for info in IMAGES:
    assert hashlib.sha256(Path(info['source']).read_bytes()).hexdigest()==info['sha256']
overlaps=[]
for i,a in enumerate(TEXTS):
    for b in TEXTS[i+1:]:
        if a['page']!=b['page']:continue
        dx=min(a['x']+a['width'],b['x']+b['width'])-max(a['x'],b['x'])
        dy=min(a['y']+a['height'],b['y']+b['height'])-max(a['y'],b['y'])
        if dx>.1 and dy>.1:overlaps.append((a['page'],a['text'],b['text'],round(dy,3)))
assert not overlaps,overlaps
report=dict(file=str(FINAL),pages=page_results,safe_margin_mm=7,
            body_font_size_pt=8.0,remote_body_font_size_pt=8.2,
            smallest_auxiliary_font_size_pt=min(t['size'] for t in TEXTS),
            vector_line_width_mm=.23,text_box_overlap_count=len(overlaps),
            original_diagrams=IMAGES,all_sources_unchanged=True,
            native_vector_text_and_leaders=True,print_scaling='None',duplex='Simplex')
(OUTPUT/'A4打印版_检查记录.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(WORK/'layout_geometry.json').write_text(json.dumps(dict(text=TEXTS,lines=LINES),ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
