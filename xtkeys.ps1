<#
.SYNOPSIS
    xtkeys is a command-line management tool and installer for AutoHotkey-based system hotkeys.

.DESCRIPTION
    This script manages an AutoHotkey hotkey script. It allows installing, checking the status
    of running hotkey scripts, restarting them, updating them from GitHub, performing clean uninstalls,
    and showing help.

.PARAMETER Command
    The action command to execute. Valid values are:
    - install: Downloads dependencies, registers PATH/startup, and launches hotkeys.
    - status: Displays the execution status of the hotkeys script and its running PID.
    - update: Pulls the latest version of the hotkeys and xtkeys script from GitHub and restarts them.
    - restart: Terminate and restart the running AutoHotkey instance of hotkeys.
    - uninstall: Stop the hotkeys process, delete installation directory, and clean up PATH/startup links.
    - help: Display help instructions and usage examples.

.PARAMETER IncludeAhk
    Switch parameter for `uninstall` to also uninstall the AutoHotkey compiler.

.PARAMETER Force
    Switch parameter to bypass prompts during uninstallation.

.EXAMPLE
    .\xtkeys.ps1 install
    Installs AutoHotkey, downloads hotkeys, and sets up startup shortcut & PATH.

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
    [ValidateSet('status', 'update', 'restart', 'uninstall', 'install', 'help', 'default', 'serve')]
    [string]$Command = 'default',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAhk,

    [Parameter(Mandatory = $false)]
    [switch]$Force
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

function Get-AhkVersion ([string]$ExePath) {
    try {
        $vi = (Get-Item $ExePath).VersionInfo
        $ver = $vi.ProductVersion
        if (-not $ver) { $ver = $vi.FileVersion }
        if ($ver -match '(\d+\.\d+\.\d+)') {
            return [Version]$Matches[1]
        }
        return $null
    } catch { return $null }
}

function Test-AhkVersionOk ([string]$ExePath) {
    $v = Get-AhkVersion $ExePath
    if ($null -eq $v) { return $false }
    return $v -ge $AHK_MIN_VER
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
        Write-Warning "winget could not install v$AHK_WINGET_VER. Falling back to direct portable download..."
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

function Get-HotkeysPid {
    if (Test-Path $PID_FILE) {
        $raw = (Get-Content $PID_FILE -Raw -ErrorAction SilentlyContinue)
        if ($raw) {
            $raw = $raw.Trim()
            if ($raw -match '^\d+$') {
                $pidVal = [int]$raw
                try {
                    $proc = Get-Process -Id $pidVal -ErrorAction Stop
                    if ($proc.ProcessName -like '*AutoHotkey*') {
                        return $pidVal
                    }
                } catch {}
            }
        }
    }
    try {
        $ahkProcs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue
        foreach ($p in $ahkProcs) {
            if ($p.CommandLine -and ($p.CommandLine -like "*hotkeys.ahk*" -or $p.CommandLine -like "*$INSTALL_DIR*")) {
                return [int]$p.ProcessId
            }
        }
    } catch {}
    return $null
}

function Test-HotkeysRunning {
    $hpid = Get-HotkeysPid
    return ($null -ne $hpid)
}

function Stop-Hotkeys {
    $hpid = Get-HotkeysPid
    if ($null -ne $hpid) {
        try { Stop-Process -Id $hpid -Force -ErrorAction SilentlyContinue } catch {}
    }
    try {
        $ahkProcs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue
        foreach ($p in $ahkProcs) {
            if ($p.CommandLine -and ($p.CommandLine -like "*hotkeys.ahk*" -or $p.CommandLine -like "*$INSTALL_DIR*")) {
                try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
    } catch {}
    if (Test-Path $PID_FILE) {
        Remove-Item $PID_FILE -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
}

function Start-Hotkeys ([string]$AhkExe) {
    Start-Process -FilePath $AhkExe -ArgumentList "`"$AHK_FILE`"" -WorkingDirectory $INSTALL_DIR -WindowStyle Hidden
}

function Register-SessionFunction {
    try {
        Set-Item -Path "Function:\global:xtkeys" -Value {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$ArgumentList
            )
            $script = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'xtkeys\xtkeys.ps1'
            if (Test-Path $script) {
                & $script @ArgumentList
            } else {
                Write-Error "xtkeys script not found at '$script'."
            }
        }.GetNewClosure() -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Add-ToUserPath ([string]$Dir) {
    try {
        $cur = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($null -eq $cur) { $cur = '' }
        $parts = $cur -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false }
        if ($parts -notcontains $Dir) {
            $newPath = (($parts + $Dir) -join ';')
            [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
        }
        $curProc = $env:PATH
        if ($null -eq $curProc) { $curProc = '' }
        $procParts = $curProc -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false }
        if ($procParts -notcontains $Dir) {
            $env:PATH = (($procParts + $Dir) -join ';')
        }
        Register-SessionFunction
    } catch {
        throw "Failed to add '$Dir' to User PATH. Details: $($_.Exception.Message)"
    }
}

function Remove-FromUserPath ([string]$Dir) {
    try {
        $cur = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if ($null -ne $cur) {
            $parts = $cur -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false -and $_ -ne $Dir }
            [Environment]::SetEnvironmentVariable('PATH', ($parts -join ';'), 'User')
        }
        $curProc = $env:PATH
        if ($null -ne $curProc) {
            $procParts = $curProc -split ';' | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false -and $_ -ne $Dir }
            $env:PATH = ($procParts -join ';')
        }
        Remove-Item Function:\xtkeys -ErrorAction SilentlyContinue
    } catch {
        throw "Failed to remove '$Dir' from User PATH. Details: $($_.Exception.Message)"
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
    } catch {
        Write-Warning "SHA-256 check skipped or failed: $($_.Exception.Message)"
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
    
    $self = $MyInvocation.ScriptName
    $scriptDir = if ($self) { Split-Path $self -Parent } else { $null }
    $localCli = if ($scriptDir) { Join-Path $scriptDir 'xtkeys.ps1' } else { $null }
    $localInstaller = if ($scriptDir) { Join-Path $scriptDir 'install.ps1' } else { $null }
    $localAhk = if ($scriptDir) { Join-Path $scriptDir 'hotkeys.ahk' } else { $null }

    if ($localAhk -and (Test-Path $localAhk)) {
        Write-Verbose "Using local hotkeys.ahk -> $AHK_FILE"
        Copy-Item $localAhk $AHK_FILE -Force
    } else {
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
    }
    Write-Verbose "hotkeys.ahk -> $AHK_FILE"

    try {
        if ($localCli -and (Test-Path $localCli)) {
            Copy-Item $localCli $CLI_FILE -Force
        } else {
            Write-Verbose 'Downloading xtkeys.ps1 for CLI...'
            Invoke-SecureDownload "$RELEASE_BASE/xtkeys.ps1" $CLI_FILE
        }
        if ($localInstaller -and (Test-Path $localInstaller)) {
            Copy-Item $localInstaller (Join-Path $INSTALL_DIR 'install.ps1') -Force
        } else {
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
        $hpid = Get-HotkeysPid
        Write-Host "  OK hotkeys.ahk is RUNNING! (PID: $hpid)" -ForegroundColor Green
    } else {
        Write-Warning 'hotkeys.ahk may not have started yet - run `xtkeys status` to check.'
    }
    Write-Host ''
    Write-Host '  ========================================' -ForegroundColor Cyan
    Write-Host '  Installation complete!' -ForegroundColor Cyan
    Write-Host '  Commands are available immediately in this shell:' -ForegroundColor White
    Write-Host '    xtkeys status      - check if hotkeys are running'    -ForegroundColor Cyan
    Write-Host '    xtkeys update      - download latest version & restart' -ForegroundColor Cyan
    Write-Host '    xtkeys restart     - restart hotkeys'                 -ForegroundColor Cyan
    Write-Host '    xtkeys uninstall   - remove everything cleanly'        -ForegroundColor Cyan
    Write-Host '    xtkeys help        - show help message'               -ForegroundColor Cyan
    Write-Host '  ========================================' -ForegroundColor Cyan
    Write-Host ''
}

function Invoke-Status {
    Write-Host ''
    $hpid = Get-HotkeysPid
    if ($null -ne $hpid) {
        Write-Host "  OK  hotkeys.ahk is RUNNING  (PID: $hpid)" -ForegroundColor Green
    } else {
        Write-Host '  XX  hotkeys.ahk is NOT running.' -ForegroundColor Red
        Write-Host '      Run `xtkeys restart` to start it.' -ForegroundColor Yellow
    }
    $ahkExe = Get-AhkExe
    if ($null -ne $ahkExe) {
        $v = Get-AhkVersion $ahkExe
        Write-Host "  AHK    : $ahkExe (v$v)" -ForegroundColor DarkGray
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
    if (-not (Test-Path $INSTALL_DIR) -or -not (Test-Path $AHK_FILE)) {
        Write-Host '  xtkeys is not installed yet. Running installation...' -ForegroundColor Yellow
        Invoke-Install
        return
    }
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) {
        Write-Warning 'AutoHotkey not found. Attempting repair install...'
        $ahkExe = Install-AutoHotkey
    }
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
    $tmpCli = Join-Path $env:TEMP 'xtkeys_update.ps1'
    $tmpInst = Join-Path $env:TEMP 'install_update.ps1'
    try {
        Invoke-SecureDownload "$RELEASE_BASE/xtkeys.ps1" $tmpCli
        Invoke-SecureDownload "$RELEASE_BASE/install.ps1" $tmpInst
        Copy-Item $tmpCli $CLI_FILE -Force
        Copy-Item $tmpInst (Join-Path $INSTALL_DIR 'install.ps1') -Force
    } catch {
        Write-Warning "Failed to download update scripts: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tmpCli) { Remove-Item $tmpCli -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tmpInst) { Remove-Item $tmpInst -Force -ErrorAction SilentlyContinue }
    }
    Write-CliWrapper
    Set-ScriptExecutionPolicy   
    Add-ToUserPath $INSTALL_DIR
    Write-Verbose 'xtkeys CLI updated.'
    Write-Verbose 'Restarting hotkeys...'
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    if (Test-HotkeysRunning) {
        $hpid = Get-HotkeysPid
        Write-Host "  OK hotkeys.ahk running on latest version. (PID: $hpid)" -ForegroundColor Green
    } else {
        Write-Warning 'hotkeys may not have started - run `xtkeys status`.'
    }
    Write-Host ''
}

function Invoke-Restart {
    Write-Banner
    Write-Host '  Restarting hotkeys...' -ForegroundColor White
    Write-Host ''
    $ahkExe = Get-AhkExe
    if ($null -eq $ahkExe) {
        Write-Warning 'AutoHotkey not found. Attempting repair install...'
        $ahkExe = Install-AutoHotkey
    }
    Write-Verbose 'Stopping hotkeys...'
    Stop-Hotkeys
    Write-Verbose 'Starting hotkeys...'
    Start-Hotkeys $ahkExe
    Start-Sleep -Seconds 1
    if (Test-HotkeysRunning) {
        $hpid = Get-HotkeysPid
        Write-Host "  OK hotkeys.ahk restarted. (PID: $hpid)" -ForegroundColor Green
    } else {
        Write-Warning 'hotkeys may not have started - run `xtkeys status`.'
    }
    Write-Host ''
}

function Invoke-Uninstall {
    Write-Host ''
    Write-Host '  Uninstalling hotkeys...' -ForegroundColor Cyan
    Write-Host ''
    $uninstallAhk = [bool]$IncludeAhk
    if (-not $uninstallAhk -and -not $Force -and [Environment]::UserInteractive) {
        try {
            $hostUI = $Host.UI.RawUI
            if ($hostUI -ne $null) {
                $response = Read-Host "  Do you want to uninstall AutoHotkey (compiler) as well? [y/N]"
                if ($response -match '^[yY]') {
                    $uninstallAhk = $true
                }
            }
        } catch {}
    }
    Write-Verbose 'Stopping hotkeys process...'
    Stop-Hotkeys
    Write-Verbose 'Process stopped.'
    try {
        if (Test-Path $STARTUP_LNK) {
            Remove-Item $STARTUP_LNK -Force -ErrorAction SilentlyContinue
            Write-Verbose 'Startup shortcut removed.'
        }
        Write-Verbose 'Removing from User PATH...'
        Remove-FromUserPath $INSTALL_DIR
        Write-Verbose 'PATH entry removed.'
        if (Test-Path $INSTALL_DIR) {
            Get-ChildItem -Path $INSTALL_DIR -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue } catch {}
            }
            if (Test-Path $AHK_PORTABLE_DIR) {
                try { Remove-Item $AHK_PORTABLE_DIR -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            }
            try {
                Remove-Item $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
            } catch {}
            if (Test-Path $INSTALL_DIR) {
                Start-Process -FilePath 'cmd.exe' -ArgumentList "/c timeout /t 1 /nobreak >nul & rmdir /s /q `"$INSTALL_DIR`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
            }
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
        Write-Host '  Note: AutoHotkey compiler was NOT uninstalled.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-Help {
    Write-Banner
    Write-Host '  Commands:' -ForegroundColor White
    Write-Host '    xtkeys status      Check if hotkeys are running'     -ForegroundColor Cyan
    Write-Host '    xtkeys update      Download latest and restart'      -ForegroundColor Cyan
    Write-Host '    xtkeys restart     Kill and re-launch hotkeys'       -ForegroundColor Cyan
    Write-Host '    xtkeys uninstall   Remove everything cleanly'        -ForegroundColor Cyan
    Write-Host '    xtkeys install     Install or reinstall hotkeys'     -ForegroundColor Cyan
    Write-Host '    xtkeys serve       Start local API for app detection' -ForegroundColor Cyan
    Write-Host '    xtkeys help        Show this help message'           -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Web install (any Windows machine):' -ForegroundColor White
    Write-Host "    irm https://github.com/$REPO_OWNER/$REPO_NAME/releases/latest/download/install.ps1 | iex" -ForegroundColor DarkCyan
    Write-Host ''
}

function Send-JsonResponse ([System.Net.HttpListenerContext]$ctx, [string]$body, [int]$status = 200) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.StatusCode = $status
    $ctx.Response.ContentType = 'application/json; charset=utf-8'
    $ctx.Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $ctx.Response.Headers.Add('Access-Control-Allow-Methods', 'GET, OPTIONS')
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.OutputStream.Close()
}

function Search-InstalledApps ([string]$query) {
    $results = [System.Collections.Generic.List[hashtable]]::new()
    $seen    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $regPaths) {
        try {
            Get-ItemProperty $path -ErrorAction SilentlyContinue | ForEach-Object {
                $name = $_.DisplayName
                $loc  = $_.InstallLocation
                if (-not $name -or $name -notmatch [regex]::Escape($query)) { return }
                if ($loc -and (Test-Path $loc)) {
                    $exe = Get-ChildItem $loc -Filter '*.exe' -Depth 1 -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -notmatch 'unins|setup|update|crash|helper' } |
                           Sort-Object Length -Descending | Select-Object -First 1
                    if ($exe -and $seen.Add($exe.FullName)) {
                        $results.Add(@{ name = $name; path = $exe.FullName })
                    }
                }
            }
        } catch {}
    }

    $scanDirs = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        (Join-Path $env:LOCALAPPDATA 'Programs')
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($dir in $scanDirs) {
        try {
            Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match [regex]::Escape($query)
            } | ForEach-Object {
                $exe = Get-ChildItem $_.FullName -Filter '*.exe' -Depth 1 -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -notmatch 'unins|setup|update|crash|helper' } |
                       Sort-Object Length -Descending | Select-Object -First 1
                if ($exe -and $seen.Add($exe.FullName)) {
                    $results.Add(@{ name = $_.Name; path = $exe.FullName })
                }
            }
        } catch {}
    }

    return $results | Select-Object -First 15
}

function Invoke-Serve {
    $port   = 7878
    $prefix = "http://localhost:$port/"

    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)

    try {
        $listener.Start()
        Write-Host ''
        Write-Host "  xtkeys serve  -  listening on $prefix" -ForegroundColor Green
        Write-Host '  Open the XT KEYS customizer in your browser and live app detection will activate.' -ForegroundColor Cyan
        Write-Host '  Press Ctrl+C to stop.' -ForegroundColor DarkGray
        Write-Host ''

        while ($listener.IsListening) {
            $ctx = $listener.GetContext()
            $req = $ctx.Request
            $url = $req.Url

            if ($req.HttpMethod -eq 'OPTIONS') {
                $ctx.Response.Headers.Add('Access-Control-Allow-Origin', '*')
                $ctx.Response.Headers.Add('Access-Control-Allow-Methods', 'GET, OPTIONS')
                $ctx.Response.StatusCode = 204
                $ctx.Response.OutputStream.Close()
                continue
            }

            $path = $url.AbsolutePath

            if ($path -eq '/ping') {
                Send-JsonResponse $ctx '{"ok":true}'
            }
            elseif ($path -eq '/apps') {
                $qs = [System.Web.HttpUtility]::ParseQueryString($url.Query)
                $q  = $qs['q']
                if (-not $q -or $q.Trim().Length -lt 1) {
                    Send-JsonResponse $ctx '{"apps":[]}'
                } else {
                    $apps  = Search-InstalledApps $q.Trim()
                    $items = $apps | ForEach-Object {
                        [PSCustomObject]@{ name = $_.name; path = $_.path }
                    }
                    $json  = [PSCustomObject]@{ apps = @($items) } | ConvertTo-Json -Compress -Depth 3
                    Send-JsonResponse $ctx $json
                }
            }
            else {
                Send-JsonResponse $ctx '{"error":"not found"}' 404
            }
        }
    } catch [System.Net.HttpListenerException] {
        # Ctrl+C — clean exit
    } finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
        Write-Host '  xtkeys serve stopped.' -ForegroundColor DarkGray
    }
}

try {
    switch ($Command) {
        'default' {
            if (Test-Path $AHK_FILE) {
                Invoke-Help
            } else {
                Invoke-Install
            }
        }
        'install'   { Invoke-Install }
        'status'    { Invoke-Status }
        'update'    { Invoke-Update }
        'restart'   { Invoke-Restart }
        'uninstall' { Invoke-Uninstall }
        'serve'     { Invoke-Serve }
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
