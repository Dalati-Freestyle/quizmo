$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$tool = Join-Path $temp 'tool'
$pubspec = Join-Path $temp 'pubspec.yaml'
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-Equal($Actual, $Expected) {
    if ($Actual -cne $Expected) { throw "Expected '$Expected', got '$Actual'" }
}

try {
    New-Item $tool -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'bump_version.ps1') $tool
    $script = Join-Path $tool 'bump_version.ps1'
    foreach ($newline in @("`n", "`r`n")) {
        $source = "name: quizmo${newline}version: 1.2.3+7${newline}publish_to: 'none'${newline}"
        foreach ($part in @('minor', 'patch', 'major')) {
            $expected = switch ($part) {
                'minor' { '1.3.0+8' }
                'patch' { '1.2.4+8' }
                'major' { '2.0.0+8' }
            }
            [IO.File]::WriteAllText($pubspec, $source, $utf8)
            Assert-Equal (& $script -Part $part -DryRun) $expected
            Assert-Equal ([IO.File]::ReadAllText($pubspec)) $source
            Assert-Equal (& $script -Part $part) $expected
            Assert-Equal ([IO.File]::ReadAllText($pubspec)) ($source.Replace('1.2.3+7', $expected))
            if ([IO.File]::ReadAllBytes($pubspec)[0] -ne [byte][char]'n') {
                throw 'Unexpected byte order mark'
            }
        }
        [IO.File]::WriteAllText($pubspec, $source, $utf8)
        Assert-Equal (& $script) '1.3.0+8'
    }

    foreach ($invalid in @('version: invalid', 'version: 1.2.3', 'version: 1.2.3+65535')) {
        [IO.File]::WriteAllText($pubspec, $invalid, $utf8)
        $failed = $false
        try { & $script | Out-Null } catch { $failed = $true }
        if (-not $failed) { throw "Invalid version accepted: $invalid" }
        Assert-Equal ([IO.File]::ReadAllText($pubspec)) $invalid
    }
    Write-Output 'Version helper tests passed.'
} finally {
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
}
