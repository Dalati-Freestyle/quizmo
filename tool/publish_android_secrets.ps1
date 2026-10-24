param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository
)

$ErrorActionPreference = 'Stop'
$gh = (Get-Command gh -ErrorAction Stop).Source
$secretsPath = Join-Path $env:USERPROFILE '.quizmo/signing/android/github-secrets.json'
$secrets = Get-Content $secretsPath -Raw | ConvertFrom-Json
try {
    $names = @('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')
    foreach ($name in $names) {
        if ([string]::IsNullOrWhiteSpace($secrets.$name)) { throw "Missing secret: $name" }
    }
    foreach ($name in $names) {
        # Send values on stdin, never as command-line arguments or terminal output.
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $gh
        $start.Arguments = "secret set $name --repo $Repository"
        $start.UseShellExecute = $false
        $start.RedirectStandardInput = $true
        $process = [Diagnostics.Process]::Start($start)
        try {
            $process.StandardInput.Write([string]$secrets.$name)
            $process.StandardInput.Close()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "Could not upload $name. Check gh authentication and repository permissions." }
        } finally {
            $process.Dispose()
        }
        Write-Output "Configured $name for $Repository"
    }
} finally {
    $secrets = $null
}
