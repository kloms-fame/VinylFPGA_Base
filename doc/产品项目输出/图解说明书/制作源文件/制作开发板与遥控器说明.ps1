$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives -TypeDefinition @'
using System.Drawing;
public static class ManualDeliveryCheck {
    public static int Region(Bitmap a, Bitmap b, Rectangle r, int ox, int oy) {
        int changes=0;
        for(int y=r.Top;y<r.Bottom;y++) for(int x=r.Left;x<r.Right;x++)
            if(a.GetPixel(x,y).ToArgb()!=b.GetPixel(x+ox,y+oy).ToArgb())changes++;
        return changes;
    }
    public static int Disk(Bitmap a, Bitmap b, int cx, int cy, int radius, int ox, int oy) {
        int changes=0;
        for(int y=cy-radius;y<=cy+radius;y++) for(int x=cx-radius;x<=cx+radius;x++)
            if((x-cx)*(x-cx)+(y-cy)*(y-cy)<=radius*radius && a.GetPixel(x,y).ToArgb()!=b.GetPixel(x+ox,y+oy).ToArgb())changes++;
        return changes;
    }
}
'@
$root = 'D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA'
$outDir = Join-Path $root 'doc\产品项目输出\图解说明书'
$workDir = Join-Path $outDir '制作源文件'
$blue = [Drawing.ColorTranslator]::FromHtml('#1867B7')
$gray = [Drawing.ColorTranslator]::FromHtml('#303944')
$muted = [Drawing.ColorTranslator]::FromHtml('#647281')
$blueBrush = [Drawing.SolidBrush]::new($blue)
$grayBrush = [Drawing.SolidBrush]::new($gray)
$mutedBrush = [Drawing.SolidBrush]::new($muted)
$whiteBrush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
$pen = [Drawing.Pen]::new($blue,4)
$pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
$titleFont = [Drawing.Font]::new('Microsoft YaHei',62,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
$bodyFont = [Drawing.Font]::new('Microsoft YaHei',49,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
$smallFont = [Drawing.Font]::new('Microsoft YaHei',43,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
$rowFont = [Drawing.Font]::new('Microsoft YaHei',54,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
$markerFont = [Drawing.Font]::new('Microsoft YaHei',32,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
$format = [Drawing.StringFormat]::GenericTypographic.Clone()
$format.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
$center = [Drawing.StringFormat]::new()
$center.Alignment = [Drawing.StringAlignment]::Center
$center.LineAlignment = [Drawing.StringAlignment]::Center
$center.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
$deliveries = [Collections.Generic.List[object]]::new()

function BeginPage([string]$SourceName,[string]$OutputStem,[int]$OffsetX,[int]$Scale=1) {
    $script:stem = $OutputStem
    $script:sourcePath = Join-Path $root ('doc\相关素材\处理素材\'+$SourceName)
    $script:sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $script:source = [Drawing.Bitmap]::FromFile($sourcePath)
    $script:ox=$OffsetX; $script:oy=120; $script:scale=$Scale
    $script:page=[Drawing.Bitmap]::new(7000,4336,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $page.SetResolution(300,300)
    $script:g=[Drawing.Graphics]::FromImage($page)
    $g.PageUnit=[Drawing.GraphicsUnit]::Pixel
    $g.Clear([Drawing.Color]::White)
    if($Scale -gt 1) { $g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic }
    $dest=[Drawing.Rectangle]::new($ox,$oy,$source.Width*$Scale,$source.Height*$Scale)
    $g.DrawImage($source,$dest,0,0,$source.Width,$source.Height,[Drawing.GraphicsUnit]::Pixel)
    $script:baseline=$page.Clone($dest,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint=[Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $script:checks=[Collections.Generic.List[object]]::new()
}
function TextAt([string]$Text,[float]$X,[float]$Y,$Font=$bodyFont,$Brush=$grayBrush) {
    $size=$g.MeasureString($Text,$Font,10000,$format)
    if($X+$size.Width -gt 6940 -or $Y+$size.Height -gt 4290) { throw "Text exceeds safe bounds: $Text" }
    $g.DrawString($Text,$Font,$Brush,[Drawing.PointF]::new($X,$Y),$format)
}
function Leader($Points,[bool]$Dot=$true) {
    $p=[Drawing.PointF[]]@($Points | ForEach-Object { [Drawing.PointF]::new($_[0],$_[1]) })
    $path=[Drawing.Drawing2D.GraphicsPath]::new()
    $current=$p[0]
    for($i=1;$i -lt $p.Count-1;$i++) {
        $corner=$p[$i];$next=$p[$i+1]
        $dx1=$corner.X-$current.X;$dy1=$corner.Y-$current.Y
        $dx2=$next.X-$corner.X;$dy2=$next.Y-$corner.Y
        $len1=[Math]::Sqrt($dx1*$dx1+$dy1*$dy1);$len2=[Math]::Sqrt($dx2*$dx2+$dy2*$dy2)
        $r=[Math]::Min(24,[Math]::Min($len1/3,$len2/3))
        if($r -gt 0) {
            $enter=[Drawing.PointF]::new($corner.X-$dx1/$len1*$r,$corner.Y-$dy1/$len1*$r)
            $leave=[Drawing.PointF]::new($corner.X+$dx2/$len2*$r,$corner.Y+$dy2/$len2*$r)
            $path.AddLine($current,$enter);$path.AddBezier($enter,$corner,$corner,$leave);$current=$leave
        }
    }
    $path.AddLine($current,$p[-1]);$g.DrawPath($pen,$path);$path.Dispose()
    if($Dot) { $end=$p[-1];$g.FillEllipse($whiteBrush,$end.X-12,$end.Y-12,24,24);$g.FillEllipse($blueBrush,$end.X-8,$end.Y-8,16,16) }
}
function Badge([string]$Value,[float]$X,[float]$Y,[float]$Radius=30) {
    $g.FillEllipse($whiteBrush,$X-$Radius-4,$Y-$Radius-4,2*$Radius+8,2*$Radius+8)
    $g.FillEllipse($blueBrush,$X-$Radius,$Y-$Radius,2*$Radius,2*$Radius)
    $g.DrawString($Value,$markerFont,$whiteBrush,[Drawing.RectangleF]::new($X-$Radius,$Y-$Radius,2*$Radius,2*$Radius),$center)
}
function LeftText([string]$Title,[int]$Y,[string[]]$Lines,[bool]$Small=$false) {
    TextAt $Title 120 $Y $titleFont $blueBrush
    for($j=0;$j -lt $Lines.Count;$j++) { if($Small) { TextAt $Lines[$j] 120 ($Y+95+$j*74) $smallFont } else { TextAt $Lines[$j] 120 ($Y+95+$j*78) } }
}
function RightText([string]$Title,[int]$Y,[string[]]$Lines,[int]$X=5370) {
    TextAt $Title $X $Y $titleFont $blueBrush
    for($j=0;$j -lt $Lines.Count;$j++) { TextAt $Lines[$j] $X ($Y+95+$j*78) }
}
function LeftStart([string]$Title) { return (120+$g.MeasureString($Title,$titleFont,10000,$format).Width+45) }
function Protect([string]$Name,[int]$X,[int]$Y,[int]$W,[int]$H) {
    $changed=[ManualDeliveryCheck]::Region($baseline,$page,[Drawing.Rectangle]::new($X*$scale,$Y*$scale,$W*$scale,$H*$scale),$ox,$oy)
    $checks.Add(@{Region=$Name;ChangedPixels=$changed})
}
function EndPage {
    $path=Join-Path $outDir ($stem+'.png')
    $page.Save($path,[Drawing.Imaging.ImageFormat]::Png)
    $preview=[Drawing.Bitmap]::new(2100,1301)
    $pg=[Drawing.Graphics]::FromImage($preview)
    $pg.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $pg.DrawImage($page,0,0,2100,1301)
    $preview.Save((Join-Path $workDir ($stem+'_预览.png')),[Drawing.Imaging.ImageFormat]::Png)
    $pg.Dispose();$preview.Dispose()
    $unchanged=((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -eq $sourceHash)
    $report=@{Output=$path;Width=7000;Height=4336;SourceUnchanged=$unchanged;SourceOffset=@($ox,$oy);Scale=$scale;ProtectedRegions=$checks;Passed=($unchanged -and @($checks | Where-Object {$null -eq $_.ChangedPixels -or $_.ChangedPixels -ne 0}).Count -eq 0)}
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $workDir ($stem+'_校验.json')) -Encoding utf8
    $deliveries.Add(@{Output=$path;Checks=$checks.Count;Passed=$report.Passed})
    $g.Dispose();$page.Dispose();$baseline.Dispose();$source.Dispose()
    if(-not $report.Passed) { throw "Original control preservation check failed: $stem" }
}

# Development board: original source at 1:1 resolution, all controls retained.
BeginPage '开发板功能图.png' '开发板_图解操作说明_v1' 1970
LeftText 'SD 卡槽' 850 @('插入存放歌曲、封面与 MV 的 SD 卡。')
Leader @(@((LeftStart 'SD 卡槽'),905),@(2230,905))
TextAt '系统按键 · 对照图中 01–04' 120 1165 $rowFont $blueBrush
$boardKeys=@(
    @{Id='01';Cy=1315;Title='一键静音 · KEY4';Body='按下静音，再次按下恢复原音量。'},
    @{Id='02';Cy=1500;Title='保存参数 · KEY3';Body='保存当前五项参数，供重启后恢复。'},
    @{Id='03';Cy=1685;Title='恢复默认 · KEY2';Body='恢复五项默认参数，并保存默认配置。'},
    @{Id='04';Cy=1870;Title='系统重启 · KEY1';Body='重启系统，重新加载音视频与界面。'}
)
for($i=0;$i -lt $boardKeys.Count;$i++) {
    $k=$boardKeys[$i];$cy=$k.Cy+120;$row=1310+$i*215
    Badge $k.Id 2665 $cy 28
    Leader @(@(2634,$cy),@(2630,$cy)) $false
    Badge $k.Id 151 ($row+35) 31
    TextAt $k.Title 220 $row $rowFont $blueBrush
    TextAt $k.Body 220 ($row+77) $smallFont
}
$switches=@(
    @{Cy=2195;Title='系统告警 · SW4';Lines=@('拨动开关，开启／关闭故障告警。')},
    @{Cy=2425;Title='自动保存 · SW3';Lines=@('拨上开启，参数停变 5 秒后自动保存。')},
    @{Cy=2650;Title='跳过开机动画 · SW2';Lines=@('拨上跳过动画；拨下播放开机动画。')},
    @{Cy=2875;Title='数码管总控 · SW1';Lines=@('拨上点亮数码管；拨下关闭显示。')},
    @{Cy=3105;Title='蜂鸣器开关 · BUZ_SW';Lines=@('物理控制蜂鸣器供电，开启／关闭提示音。')}
)
foreach($s in $switches) {
    $y=$s.Cy+65
    LeftText $s.Title $y $s.Lines
    Leader @(@((LeftStart $s.Title),($y+55)),@(2255,($s.Cy+120)))
}
LeftText '蜂鸣器' 3680 @('发出操作反馈短音与故障告警音。')
Leader @(@((LeftStart '蜂鸣器'),3735),@(2330,3735))
TextAt '保存项 · VOL / BRI / CON / ROT / WSL' 120 3960 $rowFont $blueBrush
TextAt '音量／亮度／对比度／轮播周期／灯带亮度。' 120 4050 $smallFont
TextAt '保存完成：LED3 熄灭，LED2 点亮。' 120 4125 $smallFont $mutedBrush

RightText '交互扩展接口' 420 @('通过排线连接交互扩展板。')
Leader @(@(5330,465),@(4470,465),@(4395,445))
RightText '状态指示灯 · LED1–LED4' 1165 @(
    'LED1 配置加载：启动成功恢复配置后亮。',
    'LED2 参数已保存：改参灭，保存后亮。',
    'LED3 Flash 忙：初始化或擦写时亮。',
    'LED4 Flash 故障：故障保持到复位。'
)
TextAt '原图“系统繁忙／故障”指 Flash 状态。' 5370 1590 $smallFont $mutedBrush
$g.DrawLines($pen,[Drawing.PointF[]]@([Drawing.PointF]::new(4150,1080),[Drawing.PointF]::new(4180,1080),[Drawing.PointF]::new(4180,1760),[Drawing.PointF]::new(4150,1760)))
Leader @(@(5330,1210),@(4180,1210))
RightText '数码管 · 时长与曲目编号' 1965 @('时长区：播放时间（分／秒）。','编号区：当前曲目编号。','异常时可显示状态码。')
Leader @(@(5330,2010),@(4120,2010),@(4095,2040))
TextAt '板载接口 · 对照图中 A–F' 5370 2440 $rowFont $blueBrush
$ports=@(
    @{Id='A';Title='HDMI A';Body='HDMI 音视频连接。';Cy=770;Pts=@(@(5064,770),@(4845,770))},
    @{Id='B';Title='电源开关 · POWER';Body='开启或关闭整机电源。';Cy=1540;Pts=@(@(5064,1540),@(4840,1540),@(4808,1510))},
    @{Id='C';Title='USB-JTAG';Body='下载 FPGA 程序，连接调试工具。';Cy=1970;Pts=@(@(5064,1970),@(4860,1970))},
    @{Id='D';Title='USB-UART';Body='串口通信与调试连接。';Cy=2360;Pts=@(@(5064,2360),@(4860,2360),@(4825,2325))},
    @{Id='E';Title='HDMI B';Body='HDMI 音视频连接。';Cy=2870;Pts=@(@(5064,2870),@(4880,2870),@(4840,2810))},
    @{Id='F';Title='VGA';Body='板载 VGA 视频接口。';Cy=3400;Pts=@(@(5064,3400),@(5020,3400))}
)
for($i=0;$i -lt $ports.Count;$i++) {
    $port=$ports[$i];Badge $port.Id 5095 $port.Cy 28;Leader $port.Pts
    $row=2580+$i*180;Badge $port.Id 5401 ($row+35) 31
    TextAt $port.Title 5470 $row $rowFont $blueBrush
    TextAt $port.Body 5470 ($row+77) $smallFont
}
RightText '唱片机扩展接口' 3890 @('连接唱片机扩展部件。')
Leader @(@(5330,3935),@(4440,3935),@(4388,3950))

foreach($k in $boardKeys) { Protect ('Key '+$k.Id) 490 ($k.Cy-40) 160 80 }
foreach($s in $switches) { Protect $s.Title 310 ($s.Cy-60) 350 120 }
Protect 'SD slot content' 285 645 610 520
Protect 'Eight-digit display' 1705 1940 405 1710
Protect 'Top IDC pins' 745 350 1600 150
Protect 'Bottom IDC pins' 745 3805 1600 120
foreach($cy in @(1015,1200,1390,1580)) { Protect ('LED caption '+$cy) 1380 ($cy-45) 810 90 }
EndPage

# Remote: retain every original key. Source labels and this page follow the
# user's selected 产品交互.md convention; English arrows/signs are not remapped.
BeginPage '红外遥控功能图.jpg' '红外遥控器_图解操作说明_v1' 2520 4
$remoteLeft=@(
    @{Title='重播 · CH';Y=350;Lines=@('进度清零，从头重新播放当前歌曲。');Pts=@(@(2350,395),@(2460,395),@(2460,420),@(3260,420),@(3260,536),@(3360,536))},
    @{Title='上一首 · CH−';Y=639;Lines=@('切换到上一首歌曲。');Pts=@(@(2350,684),@(2800,684))},
    @{Title='进度− · NEXT';Y=843;Lines=@('快退 5 秒；长按连续快退。');Pts=@(@(2350,888),@(3260,888),@(3260,1020),@(3360,1020))},
    @{Title='进度＋ · PREV';Y=1119;Lines=@('快进 5 秒；长按连续快进。');Pts=@(@(2350,1164),@(2800,1164))},
    @{Title='音量− · 图中“＋”键';Y=1323;Lines=@('减小音量，联动显示音量浮窗。');Pts=@(@(2350,1368),@(3260,1368),@(3260,1504),@(3360,1504))},
    @{Title='音量＋ · 图中“−”键';Y=1599;Lines=@('增大音量，联动显示音量浮窗。');Pts=@(@(2350,1644),@(2800,1644))},
    @{Title='保存参数 · 100＋';Y=1831;Lines=@('保存当前五项参数，供下次开机恢复。');Pts=@(@(2350,1876),@(3260,1876),@(3260,1964),@(3360,1964))},
    @{Title='系统重启 · 0';Y=2059;Lines=@('重启系统并重新加载。');Pts=@(@(2350,2104),@(2800,2104))},
    @{Title='静音 · 1';Y=2519;Lines=@('按下静音，再次按下恢复原音量。');Pts=@(@(2350,2564),@(2800,2564))},
    @{Title='转场特效 · 7';Y=3447;Lines=@('切换淡入淡出、百叶窗或直切效果。');Pts=@(@(2350,3492),@(2800,3492))}
)
foreach($item in $remoteLeft) {
    LeftText $item.Title $item.Y $item.Lines
    $points=@($item.Pts)
    $points[0]=@((LeftStart $item.Title),$points[0][1])
    Leader $points
}
RightText '下一首 · CH＋' 639 @('切换到下一首歌曲。') 4880
Leader @(@(4840,684),@(4240,684))
RightText '暂停／播放 · PLAY/PAUSE' 1119 @('切换暂停与继续播放。') 4880
Leader @(@(4840,1164),@(4240,1164))
RightText '息屏 · EQ' 1599 @('切换黑屏显示，音频继续播放。') 4880
Leader @(@(4840,1644),@(4240,1644))
RightText '恢复默认并保存 · 200＋' 2059 @('恢复五项默认参数，并写入 Flash。') 4880
Leader @(@(4840,2104),@(4240,2104))
RightText '返回选歌 · 3' 2519 @('退出播放，返回选歌浏览界面。') 4880
Leader @(@(4840,2564),@(4240,2564))
RightText '方向与确认 · 灰色方向区' 2979 @(
    '2／8：向上／向下移动或滚动。',
    '4／6：左右选曲；播放时快退／快进 2 秒。',
    '5：确认播放；播放时暂停／继续。'
) 4880
Leader @(@(4840,3024),@(4248,3024))
RightText '播放背景 · 9' 3447 @('循环切换四种播放界面背景。') 4880
Leader @(@(4840,3492),@(4240,3492))

TextAt '按键标注说明' 120 3850 $rowFont $blueBrush
TextAt '本页按《产品交互.md》的中文功能标注。' 120 3940 $smallFont $mutedBrush
TextAt '进度、音量以中文功能为准，勿按箭头或加减符号判断。' 120 4015 $smallFont $mutedBrush
TextAt '使用提示' 4880 3850 $rowFont $blueBrush
TextAt '开启扩展板 DIP5，遥控器朝向红外接收头。' 4880 3940 $smallFont
TextAt '保存项：VOL 音量、BRI 亮度、CON 对比度、' 4880 4015 $smallFont
TextAt 'ROT 轮播周期、WSL 灯带亮度。' 4880 4090 $smallFont

$rowCenters=@(141,261,381,496,611,726,843)
$columnCenters=@(122,250,378)
for($r=0;$r -lt 7;$r++) { for($c=0;$c -lt 3;$c++) {
    $changed=[ManualDeliveryCheck]::Disk($baseline,$page,$columnCenters[$c]*4,$rowCenters[$r]*4,180,$ox,$oy)
    $checks.Add(@{Region=('Remote key row '+($r+1)+' col '+($c+1));ChangedPixels=$changed})
} }
EndPage
$deliveries | ConvertTo-Json -Depth 5
