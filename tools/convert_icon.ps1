# 把用户提供的 PNG 图标转成多尺寸 ICO（16/24/32/48/64/128/256）。
# 用途：替换托盘图标（assets/icons/tray.ico）与应用图标
#      （assets/icons/app_icon.ico、windows/runner/resources/app_icon.ico）。
# 用法：powershell -ExecutionPolicy Bypass -File tools/convert_icon.ps1
param(
    [string]$Source = "$PSScriptRoot\..\assets\user_assets\iClass_icon.png",
    [string]$OutIco = "$PSScriptRoot\..\build\iClass_icon.ico"
)

Add-Type -AssemblyName System.Drawing

$img = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$entries = New-Object 'System.Collections.Generic.List[object]'

foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($img, 0, 0, $s, $s)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $entries.Add(@{ size = $s; data = $ms.ToArray() })
    $ms.Dispose()
    $bmp.Dispose()
}
$img.Dispose()

$out = [System.IO.Path]::GetFullPath($OutIco)
$fs = New-Object System.IO.FileStream($out, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($fs)
$count = $entries.Count
$offset = 6 + 16 * $count
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$count)
foreach ($e in $entries) {
    $s = if ($e.size -ge 256) { 0 } else { $e.size }
    $bw.Write([byte]$s); $bw.Write([byte]$s)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$e.data.Length); $bw.Write([uint32]$offset)
    $offset += $e.data.Length
}
foreach ($e in $entries) { $bw.Write($e.data) }
$bw.Close(); $fs.Close()

Write-Host "OK: $out ($count sizes)"
