$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run this setup on Windows.' }
$keytool = (Get-Command keytool -ErrorAction Stop).Source
$directory = Join-Path $env:USERPROFILE '.quizmo/signing/android'
$keystore = Join-Path $directory 'quizmo-release.jks'
$secretsFile = Join-Path $directory 'github-secrets.json'
if (Test-Path $directory) {
    throw "Signing directory already exists: $directory. Reuse/back up its key; do not regenerate it."
}

New-Item $directory -ItemType Directory -Force | Out-Null
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $directory /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not restrict access to the signing directory.' }

$bytes = New-Object byte[] 48
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($bytes)
$previousPassword = $env:QUIZMO_SETUP_KEY_PASSWORD
try {
    $env:QUIZMO_SETUP_KEY_PASSWORD = $password
    & $keytool -genkeypair -noprompt -storetype JKS -keystore $keystore `
        -alias quizmo -keyalg RSA -keysize 3072 -sigalg SHA256withRSA `
        -validity 10000 -dname 'CN=Quizmo' `
        -storepass:env QUIZMO_SETUP_KEY_PASSWORD -keypass:env QUIZMO_SETUP_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Signing key creation failed. Do not delete a successfully created key.' }
    $secrets = [ordered]@{
        ANDROID_KEYSTORE_BASE64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))
        ANDROID_KEYSTORE_PASSWORD = $password
        ANDROID_KEY_ALIAS = 'quizmo'
        ANDROID_KEY_PASSWORD = $password
    }
    [IO.File]::WriteAllText($secretsFile, ($secrets | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    & $keytool -exportcert -rfc -alias quizmo -keystore $keystore `
        -storepass:env QUIZMO_SETUP_KEY_PASSWORD -file (Join-Path $directory 'quizmo-release.cer')
    if ($LASTEXITCODE -ne 0) { throw 'Certificate export failed.' }
} finally {
    $env:QUIZMO_SETUP_KEY_PASSWORD = $previousPassword
    $password = $null
    $secrets = $null
}
Write-Output "Signing key created: $keystore"
Write-Output "GitHub secret values saved privately: $secretsFile"
Write-Output 'Back up this directory securely. Never commit or share its private files.'
Write-Output 'For local release builds, dot-source tool/use_android_signing.ps1 first.'
