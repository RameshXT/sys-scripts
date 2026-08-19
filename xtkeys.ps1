<#
.SYNOPSIS
    xtkeys is a command-line management tool for AutoHotkey-based system hotkeys.

.DESCRIPTION
    This script manages an AutoHotkey hotkey script. It allows checking the status of running
    hotkey scripts, restarting them, updating them from GitHub, performing clean uninstalls,
    and showing help.

.PARAMETER Command
    The action command to execute. Valid values are:
    - status: Displays the execution status of the hotkeys script and its running PID.
    - update: Pulls the latest version of the hotkeys and xtkeys script from GitHub and restarts them.
    - restart: Terminate and restart the running AutoHotkey instance of hotkeys.
    - uninstall: Stop the hotkeys process, delete installation directory, and clean up PATH/startup links.
    - help: Display help instructions and usage examples.

.EXAMPLE
    .\xtkeys.ps1 status
    Checks if hotkeys.ahk is currently running and prints its process ID.

.EXAMPLE
    .\xtkeys.ps1 update
    Downloads the latest release of hotkeys.ahk and xtkeys.ps1 and restarts the script.

.EXAMPLE
    .\xtkeys.ps1 restart
    Restarts the hotkeys application background process.

.EXAMPLE
    .\xtkeys.ps1 uninstall
    Uninstalls the application, removes the startup link, and cleans up the user PATH.

.EXAMPLE
    .\xtkeys.ps1 help
    Displays the user help screen.

.NOTES
    Author: RameshXT
    Repository: hotkeys
#>
[CmdletBinding()]
[OutputType([void])]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('status', 'update', 'restart', 'uninstall', 'help')]
    [string]$Command = 'help'
)

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
    Write-Host '               xtkeys CLI                ' -ForegroundColor White
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
function Remove-FromUserPath ([string]$Dir) {
    try {
        $cur   = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($null -eq $cur) { return }
        $parts = $cur -split ';' | Where-Object { $_ -ne '' -and $_ -ne $Dir }
        [Environment]::SetEnvironmentVariable('PATH', ($parts -join ';'), 'User')
    } catch {
        throw "Failed to remove '$Dir' from User PATH. Details: $($_.Exception.Message)"
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
function Invoke-Status {
    Write-Host ''
    if (Test-HotkeysRunning) {
        $hpid = Get-HotkeysPid
        Write-Host "  OK  hotkeys.ahk is RUNNING  (PID: $hpid)" -ForegroundColor Green
    } else {
        Write-Host '  XX  hotkeys.ahk is NOT running.' -ForegroundColor Red
        Write-Host '      Run `xtkeys restart` to start it.' -ForegroundColor Yellow
    }
    Write-Host "  Dir    : $INSTALL_DIR" -ForegroundColor DarkGray
    Write-Host "  Script : $AHK_FILE"   -ForegroundColor DarkGray
    Write-Host ''
}
function Invoke-Update {
    Write-Banner
    Write-Host '  Updating hotkeys...' -ForegroundColor White
    Write-Host ''
    Set-SecureTls
    if (-not (Test-Path $INSTALL_DIR)) {
        throw "xtkeys is not installed. Run the web installer first:`n  irm https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download/install.ps1 | iex"
    }
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) { throw 'AutoHotkey not found. Reinstall xtkeys.' }
    $tmp = Get-LatestHotkeys
    Stop-Hotkeys
    try {
        Copy-Item $tmp $AHK_FILE -Force
    } catch {
        throw "Failed to update hotkeys.ahk at '$AHK_FILE'. Details: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tmp) {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Verbose 'hotkeys.ahk updated.'
    Write-Verbose 'Updating xtkeys CLI...'
    try {
        Invoke-SecureDownload "$RELEASE_BASE/xtkeys.ps1" $CLI_FILE
        Invoke-SecureDownload "$RELEASE_BASE/install.ps1" (Join-Path $INSTALL_DIR 'install.ps1')
    } catch {
        throw "Failed to download update scripts. Details: $($_.Exception.Message)"
    }
    Write-CliWrapper
    Set-ScriptExecutionPolicy   
    Write-Verbose 'xtkeys CLI updated.'
    Write-Verbose 'Restarting hotkeys...'
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    if (Test-HotkeysRunning) {
        Write-Host '  OK hotkeys.ahk running on latest version.' -ForegroundColor Green
    } else {
        Write-Warning 'hotkeys may not have started - run `xtkeys status`.'
    }
    Write-Host ''
}
function Invoke-Restart {
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) {
        throw 'AutoHotkey not found. Please reinstall xtkeys.'
    }
    Write-Verbose 'Stopping hotkeys...'
    Stop-Hotkeys
    Write-Verbose 'Starting hotkeys...'
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    if (Test-HotkeysRunning) {
        Write-Host '  OK hotkeys.ahk restarted.' -ForegroundColor Green
    } else {
        Write-Warning 'hotkeys may not have started - run `xt status`.'
    }
}
function Invoke-Uninstall {
    Write-Host ''
    Write-Host '  Uninstalling hotkeys...' -ForegroundColor Cyan
    Write-Host ''
    $uninstallAhk = $false
    if ($Host.UI.RawUI -ne $null -and $MyInvocation.ScriptName) {
        $response = Read-Host "  Do you want to uninstall AutoHotkey (compiler) as well? [y/N]"
        if ($response -match '^[yY]') {
            $uninstallAhk = $true
        }
    }
    Write-Verbose 'Stopping hotkeys process...'
    Stop-Hotkeys
    Write-Verbose 'Process stopped.'
    try {
        if (Test-Path $STARTUP_LNK) {
            Remove-Item $STARTUP_LNK -Force
            Write-Verbose 'Startup shortcut removed.'
        }
        Write-Verbose 'Removing from User PATH...'
        Remove-FromUserPath $INSTALL_DIR
        Write-Verbose 'PATH entry removed.'
        if (Test-Path $INSTALL_DIR) {
            Remove-Item $INSTALL_DIR -Recurse -Force
            Write-Verbose "Deleted: $INSTALL_DIR"
        }
    } catch {
        throw "Failed to clean up files during uninstallation. Details: $($_.Exception.Message)"
    }
    if ($uninstallAhk) {
        Write-Verbose 'Uninstalling AutoHotkey...'
        $uninstalled = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                winget uninstall --id $AHK_WINGET_ID --silent --accept-source-agreements 2>&1 | Out-Null
                Write-Verbose 'AutoHotkey uninstalled via winget.'
                $uninstalled = $true
            } catch {
                Write-Warning 'winget uninstall failed. Trying manual uninstaller...'
            }
        }
        if (-not $uninstalled) {
            $regPath = @(
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            $ahkReg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*AutoHotkey*' } | Select-Object -First 1
            if ($ahkReg -and $ahkReg.UninstallString) {
                Write-Verbose 'Launching AutoHotkey uninstaller...'
                try {
                    if ($ahkReg.UninstallString -match '^"([^"]+)"\s+(.*)$') {
                        $exe = $Matches[1]
                        $uninstallArgs = $Matches[2]
                        Start-Process -FilePath $exe -ArgumentList "$uninstallArgs /silent" -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
                    } else {
                        Start-Process -FilePath $ahkReg.UninstallString -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
                    }
                    Write-Verbose 'AutoHotkey uninstaller executed.'
                } catch {
                    Write-Warning 'AutoHotkey registry uninstaller execution failed. Please uninstall manually via Settings.'
                }
            } else {
                Write-Warning 'Could not find AutoHotkey uninstaller in registry. Please uninstall manually via Settings.'
            }
        }
    }
    Write-Host ''
    Write-Host '  OK  Uninstall complete. hotkeys and xtkeys fully removed.' -ForegroundColor Green
    if (-not $uninstallAhk) {
        Write-Host '  Note: AutoHotkey was NOT uninstalled (may be used elsewhere).' -ForegroundColor DarkGray
    }
    Write-Host ''
}
function Invoke-Help {
    Write-Host ''
    Write-Host '  xtkeys - Hotkeys Installer & CLI' -ForegroundColor White
    Write-Host ''
    Write-Host '  Commands:' -ForegroundColor White
    Write-Host '    xtkeys status      Check if hotkeys are running'     -ForegroundColor Cyan
    Write-Host '    xtkeys update      Download latest and restart'      -ForegroundColor Cyan
    Write-Host '    xtkeys restart     Kill and re-launch hotkeys'       -ForegroundColor Cyan
    Write-Host '    xtkeys uninstall   Remove everything cleanly'        -ForegroundColor Cyan
    Write-Host '    xtkeys help        Show this help message'           -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Web install (any Windows machine):' -ForegroundColor White
    Write-Host "    irm https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download/install.ps1 | iex" -ForegroundColor DarkCyan
    Write-Host ''
}

try {
    switch ($Command) {
        'status'    { Invoke-Status }
        'update'    { Invoke-Update }
        'restart'   { Invoke-Restart }
        'uninstall' { Invoke-Uninstall }
        'help'      { Invoke-Help }
        Default {
            throw "Invalid command received: $Command"
        }
    }
} finally {
    if ($host.PrivateData) {
        if ($originalVerboseColor) { $host.PrivateData.VerboseForegroundColor = $originalVerboseColor }
        if ($originalWarningColor) { $host.PrivateData.WarningForegroundColor = $originalWarningColor }
    }
}
