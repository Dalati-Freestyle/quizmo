# Run from any directory on Windows: powershell -File tool/generate_app_icons.ps1
# The supplied original in assets/branding/logo.png is the source of every icon.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = [System.Drawing.Image]::FromFile((Join-Path $projectRoot 'assets/branding/logo.png'))

function Write-Icon([string]$relativePath, [int]$size, [double]$contentScale = 1) {
    $target = Join-Path $projectRoot $relativePath
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb))
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(52, 62, 68))
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $extent = [int][Math]::Round($size * $contentScale)
        $offset = [int][Math]::Floor(($size - $extent) / 2)
        $graphics.DrawImage($source, $offset, $offset, $extent, $extent)
        $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    $densities = @{ mdpi = 1; hdpi = 1.5; xhdpi = 2; xxhdpi = 3; xxxhdpi = 4 }
    foreach ($density in $densities.Keys) {
        Write-Icon "android/app/src/main/res/mipmap-$density/ic_launcher.png" (48 * $densities[$density])
        # Keep the entire square within Android's central 66dp safe circle.
        Write-Icon "android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png" (108 * $densities[$density]) 0.42
    }
    foreach ($platform in @('ios', 'macos')) {
        $catalog = "$platform/Runner/Assets.xcassets/AppIcon.appiconset"
        $contents = Get-Content -Raw (Join-Path $projectRoot "$catalog/Contents.json") | ConvertFrom-Json
        foreach ($entry in $contents.images) {
            if ($entry.filename) {
                $points = [double]::Parse(($entry.size -split 'x')[0], [System.Globalization.CultureInfo]::InvariantCulture)
                $scale = [double]::Parse(($entry.scale -replace 'x', ''), [System.Globalization.CultureInfo]::InvariantCulture)
                Write-Icon "$catalog/$($entry.filename)" ([int]($points * $scale))
            }
        }
    }
    foreach ($size in @(192, 512)) {
        Write-Icon "web/icons/Icon-$size.png" $size
        # A maskable icon's safe zone is a circle with radius 40% of its size.
        Write-Icon "web/icons/Icon-maskable-$size.png" $size 0.56
    }
    Write-Icon 'web/favicon.png' 32
    Write-Output 'Generated Android, iOS, macOS and web icons from assets/branding/logo.png.'
} finally {
    $source.Dispose()
}
