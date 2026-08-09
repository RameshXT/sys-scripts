Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
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
function Write-Step    ([string]$m) { Write-Host "  -> $m" -ForegroundColor Cyan   }
function Write-OK      ([string]$m) { Write-Host "  OK $m" -ForegroundColor Green  }
function Write-Warn    ([string]$m) { Write-Host "  !! $m" -ForegroundColor Yellow }
function Write-Fail    ([string]$m) { Write-Host "  XX $m" -ForegroundColor Red    }
function Write-Banner {
    Write-Host ''
    Write-Host '  ========================================' -ForegroundColor Magenta
    Write-Host '         xtkeys  .  Hotkeys Installer        ' -ForegroundColor Magenta
    Write-Host '  ========================================' -ForegroundColor Magenta
    Write-Host ''
}
function Set-SecureTls {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor
        [Net.SecurityProtocolType]::Tls13
}
function Invoke-SecureDownload ([string]$Url, [string]$OutFile) {
    if ($Url -notmatch '^https://') { throw "Security: refusing non-HTTPS URL: $Url" }
    $wc = [System.Net.WebClient]::new()
    $wc.Headers.Add('User-Agent', "xt-installer/1.0 (github.com/$REPO_OWNER/$REPO_NAME)")
    $wc.DownloadFile($Url, $OutFile)
}
function Write-Bar {
    param([double]$Percent, [int]$Width = 56)
    $pct    = [math]::Min(100, [math]::Max(0, $Percent))
    $pctStr = '{0:0.1}%' -f $pct
    $fill   = [math]::Min($Width, [math]::Round($pct / 100 * $Width))
    $bar    = ('=' * $fill) + (' ' * ($Width - $fill))
    $mid    = [math]::Floor(($Width - $pctStr.Length) / 2)
    $bar    = $bar.Substring(0, $mid) + $pctStr + $bar.Substring($mid + $pctStr.Length)
    [Console]::Write("`r[$bar]")
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
    $wc = [System.Net.WebClient]::new()
    $wc.Headers.Add('User-Agent', "xt-installer/1.0 (github.com/$REPO_OWNER/$REPO_NAME)")
    try {
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
    } finally {
        $wc.Dispose()
    }
}
function Confirm-FileHash ([string]$File, [string]$Expected) {
    $actual = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToUpper()
    $expect = ($Expected.Trim().ToUpper() -replace '\s.*$', '')
    if ($actual -ne $expect) {
        throw "SHA-256 MISMATCH - aborting for security.`n  Expected: $expect`n  Got     : $actual"
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
    $cur   = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($null -eq $cur) { $cur = '' }
    $parts = $cur -split ';' | Where-Object { $_ -ne '' }
    if ($parts -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('PATH', (($parts + $Dir) -join ';'), 'User')
        $env:PATH = $env:PATH + ';' + $Dir
    }
}
function Remove-FromUserPath ([string]$Dir) {
    $cur   = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($null -eq $cur) { return }
    $parts = $cur -split ';' | Where-Object { $_ -ne '' -and $_ -ne $Dir }
    [Environment]::SetEnvironmentVariable('PATH', ($parts -join ';'), 'User')
}
function New-StartupShortcut ([string]$AhkExe) {
    $wsh      = New-Object -ComObject WScript.Shell
    $lnk      = $wsh.CreateShortcut($STARTUP_LNK)
    $lnk.TargetPath       = $AhkExe
    $lnk.Arguments        = "`"$AHK_FILE`""
    $lnk.WorkingDirectory = $INSTALL_DIR
    $lnk.Description      = 'xt Hotkeys - AutoHotkey'
    $lnk.IconLocation     = "$AhkExe,0"
    $lnk.Save()
}
function Write-CliWrapper {
    $bat = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0xtkeys.ps1`" %*`r`n"
    [System.IO.File]::WriteAllText($CLI_BAT, $bat, [System.Text.Encoding]::ASCII)
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
            Write-OK 'Execution policy set to RemoteSigned (CurrentUser).'
        } catch {
            Write-Warn 'Could not set execution policy automatically.'
            Write-Warn 'If `xtkeys` fails, run this once in PowerShell:'
            Write-Warn '  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
        }
    } else {
        Write-OK "Execution policy OK ($cur - CurrentUser)."
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
    Write-Step "Checking for AutoHotkey >= v$AHK_WINGET_VER..."
    $existing = Get-AhkExe
    if ($null -ne $existing) {
        if (Test-AhkVersionOk $existing) {
            $v = Get-AhkVersion $existing
            Write-OK "AutoHotkey v$v found (meets v$AHK_WINGET_VER requirement): $existing"
            return $existing
        } else {
            $v = Get-AhkVersion $existing
            Write-Warn "AutoHotkey v$v found but is too old (need >= v$AHK_WINGET_VER). Installing correct version..."
        }
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Step "Trying winget install --force for AutoHotkey v$AHK_WINGET_VER..."
        try {
            winget install --id $AHK_WINGET_ID --version $AHK_WINGET_VER `
                --silent --force --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $exe = Get-AhkExe
            if ($null -ne $exe -and (Test-AhkVersionOk $exe)) {
                $v = Get-AhkVersion $exe
                Write-OK "AutoHotkey v$v installed via winget: $exe"
                return $exe
            }
        } catch { Write-Warn "winget install failed: $($_.Exception.Message)" }
        Write-Step 'Trying winget upgrade --force...'
        try {
            winget upgrade --id $AHK_WINGET_ID --version $AHK_WINGET_VER `
                --silent --force --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $exe = Get-AhkExe
            if ($null -ne $exe -and (Test-AhkVersionOk $exe)) {
                $v = Get-AhkVersion $exe
                Write-OK "AutoHotkey v$v upgraded via winget: $exe"
                return $exe
            }
        } catch { Write-Warn "winget upgrade failed: $($_.Exception.Message)" }
        Write-Warn 'winget could not install v2.0.26+. Falling back to direct download...'
    }
    $tmpZip = Join-Path $env:TEMP "ahk-v${AHK_WINGET_VER}.zip"
    Write-Step "Downloading AutoHotkey v$AHK_WINGET_VER portable ZIP from GitHub Releases..."
    Invoke-SecureDownloadWithProgress $AHK_PORTABLE_URL $tmpZip "Downloading AutoHotkey v$AHK_WINGET_VER"
    Write-Step 'Extracting AutoHotkey portable...'
    if (Test-Path $AHK_PORTABLE_DIR) {
        Remove-Item $AHK_PORTABLE_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $AHK_PORTABLE_DIR -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $AHK_PORTABLE_DIR -Force
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
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
    Write-OK "AutoHotkey v$v ready: $exe"
    return $exe
}
function Get-LatestHotkeys {
    $tmpAhk  = Join-Path $env:TEMP 'hotkeys_dl.ahk'
    $tmpHash = Join-Path $env:TEMP 'hotkeys_dl.sha256'
    Write-Step 'Downloading hotkeys.ahk from GitHub Releases...'
    Invoke-SecureDownloadWithProgress $AHK_URL $tmpAhk 'Downloading hotkeys.ahk'
    Write-Step 'Verifying SHA-256 checksum...'
    try {
        Invoke-SecureDownload $HASH_URL $tmpHash
        $expected = Get-Content $tmpHash -Raw
        Confirm-FileHash $tmpAhk $expected
        Write-OK 'Integrity check passed.'
        Remove-Item $tmpHash -Force -ErrorAction SilentlyContinue
    } catch [System.Net.WebException] {
        Write-Warn 'No SHA-256 file found in release - skipping hash check.'
        Write-Warn 'Add hotkeys.sha256 to release assets to enable verification.'
    }
    return $tmpAhk
}
function Invoke-Install {
    Write-Banner
    Write-Host '  Installing hotkeys...' -ForegroundColor White
    Write-Host ''
    Set-SecureTls
    $totalSteps = 8
    $step       = 0
    $step++
    Write-Step "Setting up install directory: $INSTALL_DIR"
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    Write-OK 'Directory ready.'
    $step++
    $ahkExe = Install-AutoHotkey
    $step++
    $tmp = Get-LatestHotkeys
    Copy-Item $tmp $AHK_FILE -Force
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-OK "hotkeys.ahk -> $AHK_FILE"
    $step++
    $self   = $MyInvocation.ScriptName
    $isSelf = $self -and
              (Resolve-Path $self -ErrorAction SilentlyContinue) -eq
              (Resolve-Path $CLI_FILE -ErrorAction SilentlyContinue)
    if ($self -and (Test-Path $self) -and -not $isSelf) {
        Copy-Item $self $CLI_FILE -Force
    } else {
        Write-Step 'Downloading xtkeys.ps1 for CLI...'
        Invoke-SecureDownload "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/xtkeys.ps1" $CLI_FILE
    }
    Write-OK "xtkeys CLI -> $CLI_FILE"
    $step++
    Write-CliWrapper
    Set-ScriptExecutionPolicy
    Write-OK 'xtkeys.cmd wrapper created.'
    $step++
    Write-Step 'Adding to User PATH...'
    Add-ToUserPath $INSTALL_DIR
    Write-OK "$INSTALL_DIR added to User PATH."
    $step++
    Write-Step 'Creating Startup shortcut...'
    New-StartupShortcut $ahkExe
    Write-OK "Startup shortcut: $STARTUP_LNK"
    $step++
    Write-Step 'Launching hotkeys now...'
    Stop-Hotkeys
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    Write-Host ''
    if (Test-HotkeysRunning) {
        Write-OK 'hotkeys.ahk is RUNNING!'
    } else {
        Write-Warn 'hotkeys.ahk may not have started yet - run `xtkeys status` to check.'
    }
    Write-Host ''
    Write-Host '  ========================================' -ForegroundColor Green
    Write-Host '  Installation complete!' -ForegroundColor Green
    Write-Host '  Restart your terminal, then use:' -ForegroundColor White
    Write-Host '    xtkeys status    - check if running'    -ForegroundColor Cyan
    Write-Host '    xtkeys update    - pull latest version' -ForegroundColor Cyan
    Write-Host '    xtkeys uninstall - remove everything'   -ForegroundColor Cyan
    Write-Host '    xtkeys help      - show this help message' -ForegroundColor Cyan
    Write-Host '  ========================================' -ForegroundColor Green
    Write-Host ''
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
        Write-Fail 'xtkeys is not installed. Run the web installer first:'
        Write-Host "  irm https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download/xtkeys.ps1 | iex"
        exit 1
    }
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) { throw 'AutoHotkey not found. Reinstall xtkeys.' }
    $tmp = Get-LatestHotkeys
    Stop-Hotkeys
    Copy-Item $tmp $AHK_FILE -Force
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-OK 'hotkeys.ahk updated.'
    Write-Step 'Updating xtkeys CLI...'
    Invoke-SecureDownload "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/xtkeys.ps1" $CLI_FILE
    Write-CliWrapper
    Set-ScriptExecutionPolicy   
    Write-OK 'xtkeys CLI updated.'
    Write-Step 'Restarting hotkeys...'
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    if (Test-HotkeysRunning) { Write-OK 'hotkeys.ahk running on latest version.' }
    else                     { Write-Warn 'hotkeys may not have started - run `xtkeys status`.' }
    Write-Host ''
}
function Invoke-Restart {
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) { Write-Fail 'AutoHotkey not found.'; exit 1 }
    Write-Step 'Stopping hotkeys...'
    Stop-Hotkeys
    Write-Step 'Starting hotkeys...'
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    if (Test-HotkeysRunning) { Write-OK 'hotkeys.ahk restarted.' }
    else                     { Write-Warn 'hotkeys may not have started - run `xt status`.' }
}
function Invoke-Uninstall {
    Write-Host ''
    Write-Host '  Uninstalling hotkeys...' -ForegroundColor Yellow
    Write-Host ''
    $uninstallAhk = $false
    if ($Host.UI.RawUI -ne $null -and $MyInvocation.ScriptName) {
        $response = Read-Host "  Do you want to uninstall AutoHotkey (compiler) as well? [y/N]"
        if ($response -match '^[yY]') {
            $uninstallAhk = $true
        }
    }
    Write-Step 'Stopping hotkeys process...'
    Stop-Hotkeys
    Write-OK 'Process stopped.'
    if (Test-Path $STARTUP_LNK) {
        Remove-Item $STARTUP_LNK -Force
        Write-OK 'Startup shortcut removed.'
    }
    Write-Step 'Removing from User PATH...'
    Remove-FromUserPath $INSTALL_DIR
    Write-OK 'PATH entry removed.'
    if (Test-Path $INSTALL_DIR) {
        Remove-Item $INSTALL_DIR -Recurse -Force
        Write-OK "Deleted: $INSTALL_DIR"
    }
    if ($uninstallAhk) {
        Write-Step 'Uninstalling AutoHotkey...'
        $uninstalled = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                winget uninstall --id $AHK_WINGET_ID --silent --accept-source-agreements 2>&1 | Out-Null
                Write-OK 'AutoHotkey uninstalled via winget.'
                $uninstalled = $true
            } catch {
                Write-Warn 'winget uninstall failed. Trying manual uninstaller...'
            }
        }
        if (-not $uninstalled) {
            $regPath = @(
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            $ahkReg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*AutoHotkey*' } | Select-Object -First 1
            if ($ahkReg -and $ahkReg.UninstallString) {
                Write-Step 'Launching AutoHotkey uninstaller...'
                if ($ahkReg.UninstallString -match '^"([^"]+)"\s+(.*)$') {
                    $exe = $Matches[1]
                    $args = $Matches[2]
                    Start-Process -FilePath $exe -ArgumentList "$args /silent" -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Start-Process -FilePath $ahkReg.UninstallString -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
                }
                Write-OK 'AutoHotkey uninstaller executed.'
            } else {
                Write-Warn 'Could not find AutoHotkey uninstaller in registry. Please uninstall manually via Settings.'
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
    Write-Host '  xtkeys - Hotkeys Installer & CLI' -ForegroundColor Magenta
    Write-Host ''
    Write-Host '  Commands:' -ForegroundColor White
    Write-Host '    xtkeys install     Install hotkeys on this machine'  -ForegroundColor Cyan
    Write-Host '    xtkeys status      Check if hotkeys are running'     -ForegroundColor Cyan
    Write-Host '    xtkeys update      Download latest and restart'      -ForegroundColor Cyan
    Write-Host '    xtkeys restart     Kill and re-launch hotkeys'       -ForegroundColor Cyan
    Write-Host '    xtkeys uninstall   Remove everything cleanly'        -ForegroundColor Cyan
    Write-Host '    xtkeys help        Show this help message'           -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Web install (any Windows machine):' -ForegroundColor White
    Write-Host "    irm https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download/xtkeys.ps1 | iex" -ForegroundColor DarkCyan
    Write-Host ''
}
$scriptName = $MyInvocation.ScriptName
$cmd        = if ($args.Count -gt 0) { $args[0].ToLower() } else { '' }
$isPiped    = [string]::IsNullOrEmpty($scriptName) -and ($cmd -eq '' -or $cmd -eq 'install')
if     ($isPiped -or $cmd -eq 'install')   { Invoke-Install   }
elseif ($cmd -eq 'status')                 { Invoke-Status    }
elseif ($cmd -eq 'update')                 { Invoke-Update    }
elseif ($cmd -eq 'restart')                { Invoke-Restart   }
elseif ($cmd -eq 'uninstall')              { Invoke-Uninstall }
elseif ($cmd -eq 'help' -or $cmd -eq '-h' -or $cmd -eq '--help') { Invoke-Help }
else {
    Invoke-Help
}
