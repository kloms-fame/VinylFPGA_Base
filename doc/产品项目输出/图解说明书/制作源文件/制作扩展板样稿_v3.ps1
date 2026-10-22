Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$root = 'D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA'
$sourcePath = Join-Path $root 'doc\相关素材\处理素材\拓展板功能图.png'
$outputDirectory = Join-Path $root 'doc\产品项目输出\图解说明书'
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$outputPath = Join-Path $outputDirectory '扩展板_图解操作说明_样稿_v3.png'
$previewPath = Join-Path $outputDirectory '制作源文件\扩展板_样稿_v3_预览.png'
$source = [Drawing.Bitmap]::FromFile($sourcePath)
$page = [Drawing.Bitmap]::new(7000, 4336, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
$page.SetResolution(300, 300)
$g = [Drawing.Graphics]::FromImage($page)
$g.Clear([Drawing.Color]::White)
$g.PageUnit = [Drawing.GraphicsUnit]::Pixel
$g.DrawImage($source, [Drawing.Rectangle]::new(1850,120,3300,4096), 0,0,3300,4096,[Drawing.GraphicsUnit]::Pixel)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$blue = [Drawing.ColorTranslator]::FromHtml('#1867B7')
$gray = [Drawing.ColorTranslator]::FromHtml('#303944')
$muted = [Drawing.ColorTranslator]::FromHtml('#647281')
$blueBrush = [Drawing.SolidBrush]::new($blue)
$grayBrush = [Drawing.SolidBrush]::new($gray)
$mutedBrush = [Drawing.SolidBrush]::new($muted)
$whiteBrush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
$pen = [Drawing.Pen]::new($blue, 4)
$pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
$titleFont = [Drawing.Font]::new('Microsoft YaHei', 62, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$bodyFont = [Drawing.Font]::new('Microsoft YaHei', 49, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$smallFont = [Drawing.Font]::new('Microsoft YaHei', 43, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$rowTitleFont = [Drawing.Font]::new('Microsoft YaHei', 54, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$markerFont = [Drawing.Font]::new('Microsoft YaHei', 32, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$format = [Drawing.StringFormat]::GenericTypographic.Clone()
$format.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
$center = [Drawing.StringFormat]::new()
$center.Alignment = [Drawing.StringAlignment]::Center
$center.LineAlignment = [Drawing.StringAlignment]::Center
$center.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
$overlayBounds = [Collections.Generic.List[object]]::new()
function TextAt([string]$Text, [float]$X, [float]$Y, $Font = $bodyFont, $Brush = $grayBrush) {
    $size = $g.MeasureString($Text, $Font, 10000, $format)
    if ($X + $size.Width -gt 6940) { throw "Text exceeds page width: $Text" }
    $g.DrawString($Text, $Font, $Brush, [Drawing.PointF]::new($X, $Y), $format)
}
function Leader($Points, [bool]$Dot = $true) {
    $p = [Drawing.PointF[]]@($Points | ForEach-Object { [Drawing.PointF]::new($_[0], $_[1]) })
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $current = $p[0]
    for ($i=1; $i -lt $p.Count-1; $i++) {
        $corner = $p[$i]
        $next = $p[$i+1]
        $dx1 = $corner.X-$current.X; $dy1 = $corner.Y-$current.Y
        $dx2 = $next.X-$corner.X; $dy2 = $next.Y-$corner.Y
        $length1 = [Math]::Sqrt($dx1*$dx1+$dy1*$dy1)
        $length2 = [Math]::Sqrt($dx2*$dx2+$dy2*$dy2)
        $radius = [Math]::Min(24,[Math]::Min($length1/3,$length2/3))
        if ($radius -gt 0) {
            $enter = [Drawing.PointF]::new($corner.X-$dx1/$length1*$radius,$corner.Y-$dy1/$length1*$radius)
            $leave = [Drawing.PointF]::new($corner.X+$dx2/$length2*$radius,$corner.Y+$dy2/$length2*$radius)
            $path.AddLine($current,$enter)
            $path.AddBezier($enter,$corner,$corner,$leave)
            $current = $leave
        }
    }
    $path.AddLine($current,$p[-1])
    $g.DrawPath($pen,$path)
    $path.Dispose()
    if ($Dot) { $end = $p[-1]; $g.FillEllipse($whiteBrush,$end.X-12,$end.Y-12,24,24); $g.FillEllipse($blueBrush,$end.X-8,$end.Y-8,16,16) }
}
function Badge([string]$Value, [float]$X, [float]$Y, [float]$Radius = 33) {
    $g.FillEllipse($whiteBrush,$X-$Radius-4,$Y-$Radius-4,2*$Radius+8,2*$Radius+8)
    $g.FillEllipse($blueBrush,$X-$Radius,$Y-$Radius,2*$Radius,2*$Radius)
    $g.DrawString($Value,$markerFont,$whiteBrush,[Drawing.RectangleF]::new($X-$Radius,$Y-$Radius,2*$Radius,2*$Radius),$center)
}

# Six switch leaders approach through the whitespace ABOVE the original labels.
$switches = @(
    @{Top=655;Title='灯带总开关 · DIP6';Lines=@('拨上开启两路灯带；拨下关闭。')},
    @{Top=982;Title='红外接收 · DIP5';Lines=@('拨上启用遥控器；拨下屏蔽。')},
    @{Top=1310;Title='自动息屏 · DIP4';Lines=@('60 秒无操作后黑屏，音频继续。','任意操作可唤醒。')},
    @{Top=1638;Title='指示灯总控 · DIP3';Lines=@('拨上显示状态；拨下熄灭指示灯。')},
    @{Top=1966;Title='自动切图 · DIP2';Lines=@('拨上自动轮播封面；拨下停止。')},
    @{Top=2298;Title='扩展板总控 · DIP1';Lines=@('拨下屏蔽扩展板控制，防止误触。')}
)
foreach ($s in $switches) {
    $y = [float]($s.Top + 35)
    TextAt $s.Title 120 $y $titleFont $blueBrush
    for ($i=0;$i -lt $s.Lines.Count;$i++) { TextAt $s.Lines[$i] 120 ($y+95+$i*78) }
    $titleWidth = $g.MeasureString($s.Title,$titleFont,10000,$format).Width
    Leader @(@((120+$titleWidth+45),($s.Top+90)),@(2368,($s.Top+90)),@(2392,($s.Top+125)))
}

# One precise leader to the first of the eight LED packages, not the strip frame.
TextAt 'WS2812B 氛围灯' 5560 1300 $titleFont $blueBrush
TextAt '8 颗彩灯呈现音乐律动。' 5560 1395
Leader @(@(5520,1345),@(5230,1345),@(5230,1165),@(5025,1165))

TextAt '播控旋钮 · EC1 / SW1' 5560 900 $titleFont $blueBrush
TextAt '旋转：选曲／调整播放进度。' 5560 995
TextAt '按下：确认播放／暂停／继续。' 5560 1073
Leader @(@(5520,945),@(4390,945),@(4390,1090),@(4350,1090))

# Function keys use seven short, independently verified leaders and matching IDs.
# The original seven controls are at x~1100, NOT at the slide switches or D-pad.
TextAt '功能按键 · 对照图中 01–07' 120 2590 $rowTitleFont $blueBrush
$keys = @(
    @{Id='01';Y=1045;Title='歌词动效 · KEY6 / SW9';Body='滚动歌词／逐字高亮。'},
    @{Id='02';Y=1380;Title='封面与 MV · KEY8 / SW17';Body='切换静态封面与动态视频。'},
    @{Id='03';Y=1715;Title='返回选歌 · KEY7 / SW16';Body='退出播放，返回选歌界面。'},
    @{Id='04';Y=2045;Title='转场效果 · KEY9 / SW18';Body='淡入淡出／百叶窗／直切。'},
    @{Id='05';Y=2380;Title='灯光效果 · KEY10 / SW19';Body='关闭／音频电平律动。'},
    @{Id='06';Y=2715;Title='播放背景 · KEY11 / SW20';Body='循环切换四种背景。'},
    @{Id='07';Y=3045;Title='播完策略 · KEY12 / SW3';Body='播完暂停／单曲循环／列表循环。'}
)
for ($i=0;$i -lt $keys.Count;$i++) {
    $key = $keys[$i]
    $cy = [float]($key.Y + 120)
    Badge $key.Id 2809 $cy 28
    Leader @(@(2838,$cy),@(2843,$cy)) $false
    $rowY = [float](2730 + $i*178)
    Badge $key.Id 151 ($rowY+35) 31
    TextAt $key.Title 220 $rowY $rowTitleFont $blueBrush
    TextAt $key.Body 220 ($rowY+77) $smallFont
}

# All five original navigation buttons remain intact; identify them as a group.
TextAt '五向导航 · KEY1–KEY5' 5560 1515 $titleFont $blueBrush
TextAt '浏览：选曲、移动、确认播放。' 5560 1610
TextAt '播放：左右调进度，确定暂停／继续。' 5560 1688 $smallFont
TextAt '上、下键用于前后滚动／翻行。' 5560 1760 $smallFont
$g.DrawLines($pen,[Drawing.PointF[]]@([Drawing.PointF]::new(3990,1660),[Drawing.PointF]::new(4030,1660),[Drawing.PointF]::new(4030,2690),[Drawing.PointF]::new(3990,2690)))
Leader @(@(5520,1560),@(4030,1560),@(4030,1660))

TextAt '状态指示灯 · LED1–LED4' 5560 2655 $titleFont $blueBrush
TextAt 'LED1 播放　 LED2 暂停' 5560 2750
TextAt 'LED3 MV　　LED4 故障' 5560 2828
TextAt '原图“红外指示”对应暂停；' 5560 2915 $smallFont $mutedBrush
TextAt '原图“交互反馈”对应故障。' 5560 2985 $smallFont $mutedBrush
# Below the printed strip label, between two LED packages, to the status group edge.
$g.DrawLines($pen,[Drawing.PointF[]]@([Drawing.PointF]::new(4650,1970),[Drawing.PointF]::new(4680,1970),[Drawing.PointF]::new(4680,2360),[Drawing.PointF]::new(4650,2360)))
Leader @(@(5520,2700),@(4720,2700),@(4720,2180),@(4680,2180))

TextAt '调参旋钮 · EC2 / SW2' 5560 3170 $titleFont $blueBrush
TextAt '旋转调数值；按下打开浮窗、' 5560 3265
TextAt '切换参数或关闭浮窗，无需长按。' 5560 3343 $smallFont
TextAt 'VOL 音量　BRI 亮度　CON 对比度' 5560 3440 $smallFont
TextAt 'ROT 轮播周期　WSL 灯带亮度' 5560 3510 $smallFont
TextAt 'WSL 为 0 时关灯，不关闭电机。' 5560 3590 $smallFont $mutedBrush
Leader @(@(5520,3215),@(4390,3215),@(4350,3210))

TextAt '红外接收头 · U10' 120 4070 $titleFont $blueBrush
TextAt '遥控器朝向此处使用。' 120 4165
$irTitleWidth = $g.MeasureString('红外接收头 · U10',$titleFont,10000,$format).Width
Leader @(@((120+$irTitleWidth+45),4115),@(2100,4115),@(2390,3745),@(2482,3745))

# The picture's internal printed labels are retained; clarify its repeated wording.
TextAt '图内名称说明' 120 240 $rowTitleFont $blueBrush
TextAt '上方“播放方式”：返回选歌。' 120 330 $smallFont $mutedBrush
TextAt '最下方“播放方式”：播完策略。' 120 400 $smallFont $mutedBrush

$page.Save($outputPath,[Drawing.Imaging.ImageFormat]::Png)
$preview = [Drawing.Bitmap]::new(2100,1301)
$pg = [Drawing.Graphics]::FromImage($preview)
$pg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$pg.DrawImage($page,0,0,2100,1301)
$preview.Save($previewPath,[Drawing.Imaging.ImageFormat]::Png)
$pg.Dispose();$preview.Dispose();$g.Dispose();$page.Dispose();$source.Dispose()
[pscustomobject]@{Output=$outputPath;Preview=$previewPath;Width=7000;Height=4336;SourceWidth=3300;SourceHeight=4096;SourceOffsetX=1850;SourceOffsetY=120;FunctionKeys=7;NavigationKeys=5} | ConvertTo-Json
