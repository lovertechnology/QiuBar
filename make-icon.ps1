# Generate icon.ico: dark rounded square + mint bluetooth rune (multi-size PNG-in-ICO)
Add-Type -AssemblyName System.Drawing
$mint = [System.Drawing.Color]::FromArgb(255, 61, 255, 162)
$bg   = [System.Drawing.Color]::FromArgb(238, 13, 18, 23)

function Draw-Icon([int]$n) {
  $bmp = New-Object System.Drawing.Bitmap($n, $n)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $u = $n / 32.0
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $r = 7 * $u; $x = 1.5 * $u; $y = 1.5 * $u; $w = 29 * $u
  $p.AddArc($x, $y, $r, $r, 180, 90); $p.AddArc($x + $w - $r, $y, $r, $r, 270, 90)
  $p.AddArc($x + $w - $r, $y + $w - $r, $r, $r, 0, 90); $p.AddArc($x, $y + $w - $r, $r, $r, 90, 90)
  $p.CloseFigure()
  $g.FillPath((New-Object System.Drawing.SolidBrush($bg)), $p)
  $pen = New-Object System.Drawing.Pen($mint, [single](2.0 * $u))
  $pen.EndCap = 'Round'; $pen.StartCap = 'Round'
  $g.DrawPath($pen, $p)
  $L = {
    param($x1, $y1, $x2, $y2)
    $g.DrawLine($pen, [single]($x1 * $u), [single]($y1 * $u), [single]($x2 * $u), [single]($y2 * $u))
  }
  & $L 12.5 8.0 19.5 13.2; & $L 19.5 13.2 15.5 16.6
  & $L 15.5 5.0 19.5 8.6;  & $L 19.5 8.6 12.5 13.8
  & $L 12.5 13.8 15.5 16.6
  & $L 15.5 5.0 15.5 22.5
  & $L 12.5 19.6 15.5 22.5
  $g.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  ,$ms.ToArray()
}

$sizes = @(256, 48, 32, 16)
$pngs = @($sizes | ForEach-Object { Draw-Icon $_ })
$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($out)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]
  $dim = [byte]$(if ($s -ge 256) { 0 } else { $s })
  $bw.Write($dim); $bw.Write($dim)
  $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
  $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
  $offset += $pngs[$i].Length
}
$pngs | ForEach-Object { $bw.Write($_) }
$bw.Flush()
[System.IO.File]::WriteAllBytes("$PSScriptRoot\icon.ico", $out.ToArray())
Write-Output ("icon.ico written, " + (Get-Item "$PSScriptRoot\icon.ico").Length + " bytes")
