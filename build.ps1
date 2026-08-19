Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ROOT     = $PSScriptRoot
$DIST     = Join-Path $ROOT 'dist'
$AHK_SRC  = Join-Path $ROOT 'hotkeys.ahk'
$CLI_SRC  = Join-Path $ROOT 'xtkeys.ps1'
$INSTALL_SRC = Join-Path $ROOT 'install.ps1'

if (-not (Test-Path $AHK_SRC)) { throw "Missing source: $AHK_SRC" }
if (-not (Test-Path $CLI_SRC)) { throw "Missing source: $CLI_SRC" }
if (-not (Test-Path $INSTALL_SRC)) { throw "Missing source: $INSTALL_SRC" }

Write-Host ''
Write-Host '  Linting PowerShell scripts with PSScriptAnalyzer...' -ForegroundColor Cyan
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    $issues = @()
    foreach ($file in @($CLI_SRC, $INSTALL_SRC)) {
        $issues += Invoke-ScriptAnalyzer -Path $file -Severity Error, Warning -ErrorAction SilentlyContinue
    }
    if ($issues) {
        $errors = $issues | Where-Object { $_.Severity -eq 'Error' }
        if ($errors) {
            Write-Host '  XX Linting failed! Errors found:' -ForegroundColor Red
            $issues | Out-String | Write-Host -ForegroundColor Yellow
            throw "Build aborted: Linting errors found in scripts."
        } else {
            Write-Host '  !! Linting warnings found (ignoring):' -ForegroundColor Yellow
            $issues | Out-String | Write-Host -ForegroundColor DarkGray
            Write-Host '  OK Linting passed (no errors).' -ForegroundColor Green
        }
    } else {
        Write-Host '  OK Linting passed.' -ForegroundColor Green
    }
} else {
    Write-Host '  !! PSScriptAnalyzer module not found. Skipping linting step.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  Building release artifacts...' -ForegroundColor Cyan
Write-Host ''
if (Test-Path $DIST) {
    Remove-Item $DIST -Recurse -Force
}
New-Item -ItemType Directory -Path $DIST -Force | Out-Null
Write-Host '  -> dist/ cleaned and ready.' -ForegroundColor DarkGray
$AHK_DEST = Join-Path $DIST 'hotkeys.ahk'
Copy-Item $AHK_SRC $AHK_DEST -Force
Write-Host '  OK dist/hotkeys.ahk' -ForegroundColor Green
$hash     = (Get-FileHash -Path $AHK_DEST -Algorithm SHA256).Hash.ToUpper()
$hashLine = "$hash  hotkeys.ahk"
$HASH_DEST = Join-Path $DIST 'hotkeys.sha256'
[System.IO.File]::WriteAllText($HASH_DEST, $hashLine, [System.Text.Encoding]::ASCII)
Write-Host "  OK dist/hotkeys.sha256  ($hash)" -ForegroundColor Green

$devTag = $env:DEV_TAG
if ($devTag) {
    Write-Host "  -> Custom Dev Tag set: $devTag. Adjusting release URLs in scripts..." -ForegroundColor Cyan
}

$utf8 = New-Object System.Text.UTF8Encoding($false)

$CLI_DEST = Join-Path $DIST 'xtkeys.ps1'
$cliContent = Get-Content $CLI_SRC -Raw
if ($devTag) {
    $cliContent = $cliContent -replace 'releases/latest/download', "releases/download/$devTag"
}
[System.IO.File]::WriteAllText($CLI_DEST, $cliContent, $utf8)
Write-Host '  OK dist/xtkeys.ps1' -ForegroundColor Green

$INSTALL_DEST = Join-Path $DIST 'install.ps1'
$installContent = Get-Content $INSTALL_SRC -Raw
if ($devTag) {
    $installContent = $installContent -replace 'releases/latest/download', "releases/download/$devTag"
}
[System.IO.File]::WriteAllText($INSTALL_DEST, $installContent, $utf8)
Write-Host '  OK dist/install.ps1' -ForegroundColor Green

# Authenticode Script Signing Step
Write-Host ''
Write-Host '  Checking for Code Signing Certificate...' -ForegroundColor Cyan
$certThumbprint = $env:SIGNING_CERT_THUMBPRINT
$cert = $null
if ($certThumbprint) {
    $cert = Get-Item "Cert:\CurrentUser\My\$certThumbprint" -ErrorAction SilentlyContinue
}
if (-not $cert) {
    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($cert) {
    Write-Host "  -> Found signing certificate: $($cert.Subject)" -ForegroundColor Cyan
    Write-Host '  Signing scripts...' -ForegroundColor Cyan
    foreach ($file in @($CLI_DEST, $INSTALL_DEST)) {
        $sig = Set-AuthenticodeSignature -FilePath $file -Certificate $cert -TimestampServer 'http://timestamp.digicert.com' -ErrorAction SilentlyContinue
        if ($sig.Status -eq 'Valid') {
            Write-Host "  OK Signed: $($file | Split-Path -Leaf)" -ForegroundColor Green
        } else {
            Write-Warning "Failed to sign $($file | Split-Path -Leaf). Status: $($sig.Status)"
        }
    }
} else {
    Write-Host '  -> No code-signing certificate found. Skipping script signing.' -ForegroundColor DarkGray
}

Write-Host ''
$ZIP_DEST = Join-Path $DIST 'hotkeys.zip'
Compress-Archive -Path $AHK_DEST, $CLI_DEST, $INSTALL_DEST -DestinationPath $ZIP_DEST -Force
Write-Host '  OK dist/hotkeys.zip' -ForegroundColor Green
Write-Host ''
Write-Host '  Release artifacts ready in dist/:' -ForegroundColor White
Get-ChildItem $DIST | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 1)
    Write-Host "    $($_.Name.PadRight(22)) $size KB" -ForegroundColor Cyan
}
Write-Host ''
