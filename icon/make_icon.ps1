# Draws the Time ISN't icon at every Windows icon size.
# Writes one single-image .ico per size (used by clock.asm), a combined
# TimeIsnt.ico, and preview.png.   Run:  powershell -File icon\make_icon.ps1
Add-Type -AssemblyName System.Drawing
$dir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$sizes = 16, 20, 24, 32, 40, 48, 64, 256

function Color([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

function Draw-Icon([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode   = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)

    # Logo: bright green tile, dark clock whose hands form a check mark
    # ("the time is right").  Two colours only, so it reads at 16 px and
    # stands out on both dark and light taskbars.
    $green = Color '#3CCF8E'
    $dark  = Color '#0E0F12'

    # rounded tile
    $m = if ($s -le 24) { 0 } else { $s * 0.03 }; $w = $s - 2 * $m; $r = $s * 0.23
    $tile = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tile.AddArc($m, $m, 2*$r, 2*$r, 180, 90)
    $tile.AddArc($m + $w - 2*$r, $m, 2*$r, 2*$r, 270, 90)
    $tile.AddArc($m + $w - 2*$r, $m + $w - 2*$r, 2*$r, 2*$r, 0, 90)
    $tile.AddArc($m, $m + $w - 2*$r, 2*$r, 2*$r, 90, 90)
    $tile.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush $green), $tile)

    # stopwatch ring, moved down a little to make room for the button
    $c = $s / 2.0
    $small  = $s -le 24
    $stroke = if ($small) { [Math]::Max(1.7, $s * 0.105) } else { $s * 0.09 }
    $ringR  = if ($small) { $s * 0.30 } else { $s * 0.275 }
    $rc     = $c + $s * $(if ($small) { 0.07 } else { 0.06 })     # ring centre y
    $ring = New-Object System.Drawing.Pen $dark, $stroke
    $g.DrawEllipse($ring, $c - $ringR, $rc - $ringR, 2 * $ringR, 2 * $ringR)

    # stopwatch button on top: stem + cap
    $ink = New-Object System.Drawing.SolidBrush $dark
    $ringTop = $rc - $ringR
    if ($small) {
        $g.FillRectangle($ink, [float]($c - $s * 0.11), [float]($ringTop - $s * 0.24), [float]($s * 0.22), [float]($s * 0.11))
        $g.FillRectangle($ink, [float]($c - $s * 0.05), [float]($ringTop - $s * 0.15), [float]($s * 0.10), [float]($s * 0.12))
    } else {
        $stemW = $s * 0.07
        $g.FillRectangle($ink, [float]($c - $stemW / 2), [float]($ringTop - $s * 0.10), [float]$stemW, [float]($s * 0.11))
        $cap = New-Object System.Drawing.Pen $dark, ($s * 0.075)
        $cap.StartCap = 'Round'; $cap.EndCap = 'Round'
        $g.DrawLine($cap, [float]($c - $s * 0.085), [float]($ringTop - $s * 0.125), [float]($c + $s * 0.085), [float]($ringTop - $s * 0.125))
    }

    # hour marks at 12 / 3 / 6 / 9 (only where there is room)
    if ($s -ge 128) {
        $tick = New-Object System.Drawing.Pen $dark, ($s * 0.045)
        $tick.StartCap = 'Round'; $tick.EndCap = 'Round'
        foreach ($deg in 0, 90, 180, 270) {
            $a = $deg * [Math]::PI / 180
            $r1 = $ringR - $stroke / 2 - $s * 0.035; $r2 = $r1 - $s * 0.045
            $g.DrawLine($tick, [float]($c + [Math]::Sin($a) * $r1), [float]($rc - [Math]::Cos($a) * $r1), [float]($c + [Math]::Sin($a) * $r2), [float]($rc - [Math]::Cos($a) * $r2))
        }
    }

    # hands: short one up-left, long one up-right = a check mark
    $hand = New-Object System.Drawing.Pen $dark, $stroke
    $hand.StartCap = 'Round'; $hand.EndCap = 'Round'; $hand.LineJoin = 'Round'
    $c  = $c - $s * 0.02                  # nudge left so the check looks centred
    $cy = $rc + $s * 0.04                 # joint a bit low, like a real check
    $a1 = -52 * [Math]::PI / 180; $l1 = $s * $(if ($small) { 0.12 } else { 0.11 })
    $a2 =  42 * [Math]::PI / 180; $l2 = $s * $(if ($small) { 0.21 } else { 0.20 })
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ($c + [Math]::Sin($a1) * $l1), ($cy - [Math]::Cos($a1) * $l1)),
        (New-Object System.Drawing.PointF $c, $cy),
        (New-Object System.Drawing.PointF ($c + [Math]::Sin($a2) * $l2), ($cy - [Math]::Cos($a2) * $l2)))
    $g.DrawLines($hand, $pts)

    $g.Dispose()
    return $bmp
}

function Write-Ico([string]$path, $pngs) {
    $fs = [System.IO.File]::Create($path)
    $bw = New-Object System.IO.BinaryWriter $fs
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)
    $offset = 6 + 16 * $pngs.Count
    foreach ($p in $pngs) {
        $dim = if ($p.Size -ge 256) { 0 } else { $p.Size }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$p.Bytes.Length); $bw.Write([uint32]$offset)
        $offset += $p.Bytes.Length
    }
    foreach ($p in $pngs) { $bw.Write($p.Bytes) }
    $bw.Close()
}

$all = @()
foreach ($s in $sizes) {
    $bmp = Draw-Icon $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $entry = @{ Size = $s; Bytes = $ms.ToArray(); Bitmap = $bmp }
    $all += $entry
    Write-Ico (Join-Path $dir "$s.ico") @($entry)
}
Write-Ico (Join-Path $dir 'TimeIsnt.ico') $all

# preview: every size at 1:1 on a dark and a light strip, plus a 4x zoom of 32 px
$pw = [int](40 + ($sizes | Measure-Object -Sum).Sum + 20 * $sizes.Count)
$prev = New-Object System.Drawing.Bitmap $pw, 640
$g = [System.Drawing.Graphics]::FromImage($prev)
$g.FillRectangle((New-Object System.Drawing.SolidBrush (Color '#202020')), 0, 0, $pw, 290)
$g.FillRectangle((New-Object System.Drawing.SolidBrush (Color '#F3F3F3')), 0, 290, $pw, 350)
foreach ($row in 0, 1) {
    $x = 20
    foreach ($e in $all) { $g.DrawImage($e.Bitmap, $x, 10 + $row * 290, $e.Size, $e.Size); $x += $e.Size + 20 }
}
$g.InterpolationMode = 'NearestNeighbor'
$g.DrawImage(($all | Where-Object { $_.Size -eq 32 }).Bitmap, 20, 470, 128, 128)
$g.DrawImage(($all | Where-Object { $_.Size -eq 16 }).Bitmap, 170, 470, 128, 128)
$prev.Save((Join-Path $dir 'preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
"icons written to $dir"
