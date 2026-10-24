param(
    [ValidateSet('minor', 'patch', 'major')]
    [string]$Part = 'minor',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$pubspec = Join-Path $PSScriptRoot '../pubspec.yaml'
$text = [IO.File]::ReadAllText($pubspec)
$pattern = '(?m)^version: (\d+)\.(\d+)\.(\d+)\+(\d+)\r?$'
$match = [regex]::Match($text, $pattern)
if (-not $match.Success) { throw 'Expected version: MAJOR.MINOR.PATCH+BUILD in pubspec.yaml.' }

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$build = [int]$match.Groups[4].Value + 1
switch ($Part) {
    'major' { $major++; $minor = 0; $patch = 0 }
    'minor' { $minor++; $patch = 0 }
    'patch' { $patch++ }
}
if ($major -gt 65535 -or $minor -gt 65535 -or $patch -gt 65535 -or $build -gt 65535) {
    throw 'Version components must fit the Windows 16-bit file version fields.'
}
$version = "$major.$minor.$patch+$build"
if (-not $DryRun) {
    $newline = if ($match.Value.EndsWith("`r")) { "`r" } else { '' }
    $updated = [regex]::Replace($text, $pattern, "version: $version$newline")
    [IO.File]::WriteAllText($pubspec, $updated, [Text.UTF8Encoding]::new($false))
}
Write-Output $version
