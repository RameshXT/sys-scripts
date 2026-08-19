<#
.SYNOPSIS
    xtkeys installer script.

.DESCRIPTION
    This script downloads and installs AutoHotkey, the hotkeys.ahk script, and the xtkeys CLI
    manager. It adds the installation folder to the user's PATH environment variable and
    creates a Startup shortcut to automatically run the hotkey script on login.

.EXAMPLE
    .\install.ps1
    Runs the full installation/re-installation workflow.

.NOTES
    Author: RameshXT
    Repository: hotkeys
#>
[CmdletBinding()]
[OutputType([void])]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$originalVerboseColor = $null
$originalWarningColor = $null
if ($host.PrivateData) {
    try {
        $originalVerboseColor = $host.PrivateData.VerboseForegroundColor
        $originalWarningColor = $host.PrivateData.WarningForegroundColor
        $host.PrivateData.VerboseForegroundColor = 'Cyan'
        $host.PrivateData.WarningForegroundColor = 'Cyan'
    } catch {}
}

$REPO_OWNER  = 'RameshXT'
$REPO_NAME   = 'hotkeys'
$INSTALL_DIR = Join-Path $env:LOCALAPPDATA 'xtkeys'
$AHK_FILE    = Join-Path $INSTALL_DIR 'hotkeys.ahk'
$CLI_FILE    = Join-Path $INSTALL_DIR 'xtkeys.ps1'
$CLI_BAT     = Join-Path $INSTALL_DIR 'xtkeys.cmd'
$PID_FILE    = Join-Path $INSTALL_DIR 'hotkeys.pid'
$STARTUP_LNK = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\xtkeys.lnk'
$RELEASE_BASE   = "https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download"
$AHK_URL        = "$RELEASE_BASE/hotkeys.ahk"
$HASH_URL       = "$RELEASE_BASE/hotkeys.sha256"
$AHK_WINGET_ID  = 'AutoHotkey.AutoHotkey'
$AHK_WINGET_VER = '2.0.26'           
$AHK_MIN_VER    = [Version]'2.0.26'  
$AHK_DIRECT_URL  = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26_setup.exe'
$AHK_PORTABLE_URL = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26.zip'
$AHK_PORTABLE_DIR = Join-Path $INSTALL_DIR 'ahk'

function Write-Banner {
    Write-Host ''
    Write-Host '  ========================================' -ForegroundColor White
    Write-Host '         xtkeys  .  Hotkeys Installer        ' -ForegroundColor White
    Write-Host '  ========================================' -ForegroundColor White
    Write-Host ''
}
function Set-SecureTls {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor
        [Net.SecurityProtocolType]::Tls13
}
function Invoke-SecureDownload ([string]$Url, [string]$OutFile) {
    if ($Url -notmatch '^https://') { throw "Security: refusing non-HTTPS URL: $Url" }
    $wc = $null
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Headers.Add('User-Agent', "xt-installer/1.0 (github.com/$REPO_OWNER/$REPO_NAME)")
        $wc.DownloadFile($Url, $OutFile)
    } catch {
        throw "Failed to download from '$Url' to '$OutFile'. Details: $($_.Exception.Message)"
    } finally {
        if ($null -ne $wc) { $wc.Dispose() }
    }
}
function Write-Bar {
    param([double]$Percent, [int]$Width = 56)
    $pct    = [math]::Min(100, [math]::Max(0, $Percent))
    $pctStr = '{0:0}%' -f $pct
    $fill   = [math]::Min($Width, [math]::Round($pct / 100 * $Width))
    $bar    = ('=' * $fill) + (' ' * ($Width - $fill))
    $mid    = [math]::Floor(($Width - $pctStr.Length) / 2)
    $bar    = $bar.Substring(0, $mid) + $pctStr + $bar.Substring($mid + $pctStr.Length)
    Write-Host ("`r[$bar]") -NoNewline -ForegroundColor Cyan
}
function Invoke-SecureDownloadWithProgress ([string]$Url, [string]$OutFile, [string]$Label = 'Downloading') {
    if ($Url -notmatch '^https://') { throw "Security: refusing non-HTTPS URL: $Url" }
    $totalBytes = -1
    try {
        $head = [System.Net.HttpWebRequest]::CreateHttp($Url)
        $head.Method    = 'HEAD'
        $head.UserAgent = "xt-installer/1.0 (github.com/$REPO_OWNER/$REPO_NAME)"
        $resp = $head.GetResponse()
        $totalBytes = $resp.ContentLength
        $resp.Close()
    } catch { }
    
    $wc = $null
    try {
        $wc = [System.Net.WebClient]::new()
        $wc.Headers.Add('User-Agent', "xt-installer/1.0 (github.com/$REPO_OWNER/$REPO_NAME)")
        $task = $wc.DownloadFileTaskAsync($Url, $OutFile)
        while (-not $task.IsCompleted) {
            try   { $received = if (Test-Path $OutFile) { (Get-Item $OutFile).Length } else { 0 } }
            catch { $received = 0 }
            if ($totalBytes -gt 0) {
                $pct = [math]::Min(99.9, $received / $totalBytes * 100)
            } else {
                $pct = 50 
            }
            Write-Bar -Percent $pct
            Start-Sleep -Milliseconds 150
        }
        if ($task.IsFaulted) { throw $task.Exception.InnerException }
        Write-Bar -Percent 100
        [Console]::WriteLine('')
    } catch {
        throw "Failed to download with progress from '$Url' to '$OutFile'. Details: $($_.Exception.Message)"
    } finally {
        if ($null -ne $wc) { $wc.Dispose() }
    }
}
function Confirm-FileHash ([string]$File, [string]$Expected) {
    try {
        $actual = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToUpper()
        $expect = ($Expected.Trim().ToUpper() -replace '\s.*$', '')
        if ($actual -ne $expect) {
            throw "SHA-256 MISMATCH - aborting for security.`n  Expected: $expect`n  Got     : $actual"
        }
    } catch {
        throw "Hash confirmation failed for file '$File'. Details: $($_.Exception.Message)"
    }
}
function Get-AhkExe {
    $candidates = @(
        (Join-Path $AHK_PORTABLE_DIR 'AutoHotkey64.exe'),
        (Join-Path $AHK_PORTABLE_DIR 'AutoHotkey32.exe'),
        (Join-Path $AHK_PORTABLE_DIR 'AutoHotkey.exe'),
        'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe',
        'C:\Program Files\AutoHotkey\v2\AutoHotkey.exe',
        'C:\Program Files\AutoHotkey\AutoHotkey64.exe',
        'C:\Program Files\AutoHotkey\AutoHotkey.exe',
        'C:\Program Files (x86)\AutoHotkey\AutoHotkey.exe'
    )
    $f64 = Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue
    if ($f64) { $candidates += $f64.Source }
    $f32 = Get-Command 'AutoHotkey.exe'   -ErrorAction SilentlyContinue
    if ($f32) { $candidates += $f32.Source }
    $best     = $null
    $bestVer  = $null
    foreach ($c in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path $c)) { continue }
        $v = Get-AhkVersion $c
        if ($null -eq $v) { continue }
        if ($null -eq $bestVer -or $v -gt $bestVer) {
            $best    = $c
            $bestVer = $v
        }
    }
    return $best
}
function Get-HotkeysPid {
    if (-not (Test-Path $PID_FILE)) { return $null }
    $raw = (Get-Content $PID_FILE -Raw -ErrorAction SilentlyContinue).Trim()
    if ($raw -match '^\d+$') { return [int]$raw }
    return $null
}
function Test-HotkeysRunning {
    $hpid = Get-HotkeysPid
    if ($null -eq $hpid) { return $false }
    return ($null -ne (Get-Process -Id $hpid -ErrorAction SilentlyContinue))
}
function Stop-Hotkeys {
    $hpid = Get-HotkeysPid
    if ($null -ne $hpid) { Stop-Process -Id $hpid -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
}
function Start-Hotkeys ([string]$AhkExe) {
    Start-Process -FilePath $AhkExe -ArgumentList "`"$AHK_FILE`"" -WindowStyle Hidden
}
function Add-ToUserPath ([string]$Dir) {
    try {
        $cur   = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($null -eq $cur) { $cur = '' }
        $parts = $cur -split ';' | Where-Object { $_ -ne '' }
        if ($parts -notcontains $Dir) {
            [Environment]::SetEnvironmentVariable('PATH', (($parts + $Dir) -join ';'), 'User')
            $env:PATH = $env:PATH + ';' + $Dir
        }
    } catch {
        throw "Failed to add '$Dir' to User PATH. Details: $($_.Exception.Message)"
    }
}
function New-StartupShortcut ([string]$AhkExe) {
    try {
        $wsh      = New-Object -ComObject WScript.Shell
        $lnk      = $wsh.CreateShortcut($STARTUP_LNK)
        $lnk.TargetPath       = $AhkExe
        $lnk.Arguments        = "`"$AHK_FILE`""
        $lnk.WorkingDirectory = $INSTALL_DIR
        $lnk.Description      = 'xt Hotkeys - AutoHotkey'
        $lnk.IconLocation     = "$AhkExe,0"
        $lnk.Save()
    } catch {
        throw "Failed to create Startup shortcut at '$STARTUP_LNK'. Details: $($_.Exception.Message)"
    }
}
function Write-CliWrapper {
    try {
        $bat = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0xtkeys.ps1`" %*`r`n"
        [System.IO.File]::WriteAllText($CLI_BAT, $bat, [System.Text.Encoding]::ASCII)
    } catch {
        throw "Failed to write CLI wrapper to '$CLI_BAT'. Details: $($_.Exception.Message)"
    }
}
function Set-ScriptExecutionPolicy {
    foreach ($f in @($CLI_FILE, $CLI_BAT)) {
        if (Test-Path $f) {
            try   { Unblock-File $f -ErrorAction Stop }
            catch { }  
        }
    }
    $cur = Get-ExecutionPolicy -Scope CurrentUser
    if ($cur -eq 'Undefined' -or $cur -eq 'Restricted' -or $cur -eq 'AllSigned') {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Verbose 'Execution policy set to RemoteSigned (CurrentUser).'
        } catch {
            Write-Warning 'Could not set execution policy automatically.'
            Write-Warning 'If `xtkeys` fails, run this once in PowerShell:'
            Write-Warning '  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
        }
    } else {
        Write-Verbose "Execution policy OK ($cur - CurrentUser)."
    }
}
function Get-AhkVersion ([string]$ExePath) {
    try {
        $ver = (Get-Item $ExePath).VersionInfo.FileVersion
        return [Version]($ver -replace '^(\d+\.\d+\.\d+).*$', '$1')
    } catch { return $null }
}
function Test-AhkVersionOk ([string]$ExePath) {
    $v = Get-AhkVersion $ExePath
    if ($null -eq $v) { return $false }
    return $v -ge $AHK_MIN_VER
}
function Install-AutoHotkey {
    Write-Verbose "Checking for AutoHotkey >= v$AHK_WINGET_VER..."
    $existing = Get-AhkExe
    if ($null -ne $existing) {
        if (Test-AhkVersionOk $existing) {
            $v = Get-AhkVersion $existing
            Write-Verbose "AutoHotkey v$v found (meets v$AHK_WINGET_VER requirement): $existing"
            return $existing
        } else {
            $v = Get-AhkVersion $existing
            Write-Warning "AutoHotkey v$v found but is too old (need >= v$AHK_WINGET_VER). Installing correct version..."
        }
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Verbose "Trying winget install --force for AutoHotkey v$AHK_WINGET_VER..."
        try {
            winget install --id $AHK_WINGET_ID --version $AHK_WINGET_VER `
                --silent --force --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $exe = Get-AhkExe
            if ($null -ne $exe -and (Test-AhkVersionOk $exe)) {
                $v = Get-AhkVersion $exe
                Write-Verbose "AutoHotkey v$v installed via winget: $exe"
                return $exe
            }
        } catch { Write-Warning "winget install failed: $($_.Exception.Message)" }
        Write-Verbose 'Trying winget upgrade --force...'
        try {
            winget upgrade --id $AHK_WINGET_ID --version $AHK_WINGET_VER `
                --silent --force --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $exe = Get-AhkExe
            if ($null -ne $exe -and (Test-AhkVersionOk $exe)) {
                $v = Get-AhkVersion $exe
                Write-Verbose "AutoHotkey v$v upgraded via winget: $exe"
                return $exe
            }
        } catch { Write-Warning "winget upgrade failed: $($_.Exception.Message)" }
        Write-Warning 'winget could not install v2.0.26+. Falling back to direct download...'
    }
    $tmpZip = Join-Path $env:TEMP "ahk-v${AHK_WINGET_VER}.zip"
    Write-Verbose "Downloading AutoHotkey v$AHK_WINGET_VER portable ZIP from GitHub Releases..."
    Invoke-SecureDownloadWithProgress $AHK_PORTABLE_URL $tmpZip "Downloading AutoHotkey v$AHK_WINGET_VER"
    Write-Verbose 'Extracting AutoHotkey portable...'
    try {
        if (Test-Path $AHK_PORTABLE_DIR) {
            Remove-Item $AHK_PORTABLE_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $AHK_PORTABLE_DIR -Force | Out-Null
        Expand-Archive -Path $tmpZip -DestinationPath $AHK_PORTABLE_DIR -Force
    } catch {
        throw "Failed to extract AutoHotkey portable ZIP. Details: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tmpZip) {
            Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        }
    }
    $exe = Get-AhkExe
    if ($null -eq $exe) {
        throw 'AutoHotkey install failed - exe not found after extraction. Check https://www.autohotkey.com/download/'
    }
    if (-not (Test-AhkVersionOk $exe)) {
        $v = Get-AhkVersion $exe
        throw ("AutoHotkey v$v was found but does not meet the v$AHK_WINGET_VER requirement.`n" +
               "  Please install v$AHK_WINGET_VER manually: https://www.autohotkey.com/download/")
    }
    $v = Get-AhkVersion $exe
    Write-Verbose "AutoHotkey v$v ready: $exe"
    return $exe
}
function Get-LatestHotkeys {
    $tmpAhk  = Join-Path $env:TEMP 'hotkeys_dl.ahk'
    $tmpHash = Join-Path $env:TEMP 'hotkeys_dl.sha256'
    Write-Verbose 'Downloading hotkeys.ahk from GitHub Releases...'
    Invoke-SecureDownloadWithProgress $AHK_URL $tmpAhk 'Downloading hotkeys.ahk'
    Write-Verbose 'Verifying SHA-256 checksum...'
    try {
        Invoke-SecureDownload $HASH_URL $tmpHash
        $expected = Get-Content $tmpHash -Raw
        Confirm-FileHash $tmpAhk $expected
        Write-Verbose 'Integrity check passed.'
        Remove-Item $tmpHash -Force -ErrorAction SilentlyContinue
    } catch [System.Net.WebException] {
        Write-Warning 'No SHA-256 file found in release - skipping hash check.'
        Write-Warning 'Add hotkeys.sha256 to release assets to enable verification.'
    }
    return $tmpAhk
}
function Invoke-Install {
    Write-Banner
    Write-Host '  Installing hotkeys...' -ForegroundColor White
    Write-Host ''
    Set-SecureTls
    Write-Verbose "Setting up install directory: $INSTALL_DIR"
    try {
        New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    } catch {
        throw "Failed to create install directory '$INSTALL_DIR'. Details: $($_.Exception.Message)"
    }
    Write-Verbose 'Directory ready.'
    $ahkExe = Install-AutoHotkey
    $tmp = Get-LatestHotkeys
    try {
        Copy-Item $tmp $AHK_FILE -Force
    } catch {
        throw "Failed to copy hotkeys.ahk to '$AHK_FILE'. Details: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tmp) {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Verbose "hotkeys.ahk -> $AHK_FILE"
    
    $self = $MyInvocation.ScriptName
    $scriptDir = if ($self) { Split-Path $self -Parent } else { $null }
    $localCli = if ($scriptDir) { Join-Path $scriptDir 'xtkeys.ps1' } else { $null }
    
    try {
        if ($self -and (Test-Path $self) -and $localCli -and (Test-Path $localCli)) {
            Copy-Item $localCli $CLI_FILE -Force
            Copy-Item $self (Join-Path $INSTALL_DIR 'install.ps1') -Force
        } else {
            Write-Verbose 'Downloading xtkeys.ps1 for CLI...'
            Invoke-SecureDownload "$RELEASE_BASE/xtkeys.ps1" $CLI_FILE
            Write-Verbose 'Downloading install.ps1...'
            Invoke-SecureDownload "$RELEASE_BASE/install.ps1" (Join-Path $INSTALL_DIR 'install.ps1')
        }
    } catch {
        throw "Failed to copy installer files. Details: $($_.Exception.Message)"
    }
    Write-Verbose "xtkeys CLI -> $CLI_FILE"
    Write-CliWrapper
    Set-ScriptExecutionPolicy
    Write-Verbose 'xtkeys.cmd wrapper created.'
    Write-Verbose 'Adding to User PATH...'
    Add-ToUserPath $INSTALL_DIR
    Write-Verbose "$INSTALL_DIR added to User PATH."
    Write-Verbose 'Creating Startup shortcut...'
    New-StartupShortcut $ahkExe
    Write-Verbose "Startup shortcut: $STARTUP_LNK"
    Write-Verbose 'Launching hotkeys now...'
    Stop-Hotkeys
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    Write-Host ''
    if (Test-HotkeysRunning) {
        Write-Host '  OK hotkeys.ahk is RUNNING!' -ForegroundColor Green
    } else {
        Write-Warning 'hotkeys.ahk may not have started yet - run `xtkeys status` to check.'
    }
    Write-Host ''
    Write-Host '  ========================================' -ForegroundColor Cyan
    Write-Host '  Installation complete!' -ForegroundColor Cyan
    Write-Host '  Restart your terminal, then use:' -ForegroundColor White
    Write-Host '    xtkeys status    - check if running'    -ForegroundColor Cyan
    Write-Host '    xtkeys update    - pull latest version' -ForegroundColor Cyan
    Write-Host '    xtkeys uninstall - remove everything'   -ForegroundColor Cyan
    Write-Host '    xtkeys help      - show this help message' -ForegroundColor Cyan
    Write-Host '  ========================================' -ForegroundColor Cyan
    Write-Host ''
}

try {
    Invoke-Install
} finally {
    if ($host.PrivateData) {
        if ($originalVerboseColor) { $host.PrivateData.VerboseForegroundColor = $originalVerboseColor }
        if ($originalWarningColor) { $host.PrivateData.WarningForegroundColor = $originalWarningColor }
    }
}
