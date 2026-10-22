$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives -TypeDefinition @'
using System.Drawing;
public static class ManualImageCheck {
    public static int CountChanged(Bitmap source, Bitmap page, Rectangle region) {
        int changed=0;
        for(int y=region.Top;y<region.Bottom;y++)
            for(int x=region.Left;x<region.Right;x++)
                if(source.GetPixel(x,y).ToArgb()!=page.GetPixel(x+1850,y+120).ToArgb())changed++;
        return changed;
    }
}
'@
$root = 'D:\Data_Backup\VinylFPGA_Workspace_Base\VinylFPGA'
$source = [Drawing.Bitmap]::FromFile((Join-Path $root 'doc\相关素材\处理素材\拓展板功能图.png'))
$page = [Drawing.Bitmap]::FromFile((Join-Path $root 'doc\产品项目输出\图解说明书\扩展板_图解操作说明_样稿_v2.png'))
$results = [Collections.Generic.List[object]]::new()
$dpadChanged = [ManualImageCheck]::CountChanged($source,$page,[Drawing.Rectangle]::new(1350,1555,810,1000))
$results.Add(@{Region='All five navigation buttons';ChangedPixels=$dpadChanged})
foreach($cy in @(1045,1380,1715,2045,2380,2715,3045)) {
    $changed = [ManualImageCheck]::CountChanged($source,$page,[Drawing.Rectangle]::new(1005,$cy-135,205,270))
    $results.Add(@{Region="Function key at source y=$cy";ChangedPixels=$changed})
}
$report = @{Width=$page.Width;Height=$page.Height;OriginalEmbeddedAtOriginalResolution=$true;ProtectedRegions=$results;Passed=(@($results | Where-Object {$null -eq $_.ChangedPixels -or $_.ChangedPixels -gt 0}).Count -eq 0)}
$report | ConvertTo-Json -Depth 5 | Tee-Object -FilePath (Join-Path $root 'doc\产品项目输出\图解说明书\制作源文件\原图保留校验.json')
$page.Dispose();$source.Dispose()
if(-not $report.Passed) { throw 'A protected original control region changed.' }
