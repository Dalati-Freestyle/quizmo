# Dot-source this script in the terminal used for an explicitly requested build.
$ErrorActionPreference = 'Stop'
$signingDirectory = Join-Path $env:USERPROFILE '.quizmo/signing/android'
$signingSecrets = Get-Content (Join-Path $signingDirectory 'github-secrets.json') -Raw | ConvertFrom-Json
$signingKeystore = Join-Path $signingDirectory 'quizmo-release.jks'
if (-not (Test-Path $signingKeystore)) { throw 'Android release keystore is missing.' }
foreach ($name in @('ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')) {
    if ([string]::IsNullOrWhiteSpace($signingSecrets.$name)) { throw "Missing signing setting: $name" }
}
$env:ANDROID_KEYSTORE_PATH = $signingKeystore
$env:ANDROID_KEYSTORE_PASSWORD = $signingSecrets.ANDROID_KEYSTORE_PASSWORD
$env:ANDROID_KEY_ALIAS = $signingSecrets.ANDROID_KEY_ALIAS
$env:ANDROID_KEY_PASSWORD = $signingSecrets.ANDROID_KEY_PASSWORD
$env:REQUIRE_RELEASE_SIGNING = 'true'
Remove-Variable signingSecrets
Write-Output 'This terminal now uses the permanent Quizmo Android release key. Close it to clear the signing environment.'
