<#
    ALVR idle-hold patch installer
    ------------------------------
    Stops VRChat avatar hands from snapping to the default pose when you put a
    controller down. Replaces one file: driver_alvr_server.dll

    Just run INSTALL.bat - you do not need to use this script directly.

    Parameters (optional):
      -Mode Install|Uninstall|Status   default Install
      -InstallPath <path>              ALVR install folder, if auto-detect fails
      -Force                           skip the version-match safety check
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status')]
    [string] $Mode = 'Install',
    [string] $InstallPath,
    [switch] $Force,
    [switch] $Elevated,
    [switch] $NoPause
)

$ErrorActionPreference = 'Stop'

# --- the exact build this patcher ships -------------------------------------
$SUPPORTED_VERSION = 'v20.14.1'
$HASH_STOCK   = '5B2DC0012254FA3C45268ED655C3F589B2D460A62907C620670CFB5D22A48FA8'
$HASH_PATCHED = '28514EA68F12C825C1D756F67707E2D00F68CC9CCA2A4B0008F2DF7E6D11EC60'
# Superseded builds we still recognise, so uninstall can clean them up.
$HASH_SUPERSEDED = @(
    # which tested one can still be upgraded or cleanly reverted.
    '0DC254863DE800AA37FFDD9614850FDEE6164360B1089DB517BFF601DF6E425E'  # pre-1.0: input stayed live during a hold
    '001444D2C5F2B9085BE3E91A4218E66FE110D7DED5F0B321523FF12D1A6554DE'  # pre-1.0: 10 s cap, no duration logging
)
$MARKER       = 'source inactive, holding last pose'

$REL_DRIVER = 'bin\win64\driver_alvr_server.dll'
$BACKUP_SUFFIX = '.stock-backup'

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------
function Say  ([string]$m) { Write-Host $m }
function HoldOpen { if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null } }
function Good ([string]$m) { Write-Host "  [ OK ]  $m" -ForegroundColor Green }
function Warn2([string]$m) { Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function Bad  ([string]$m) { Write-Host "  [FAIL]  $m" -ForegroundColor Red }
function Step ([string]$m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }

function Stop-WithMessage([string]$message) {
    Write-Host ""
    Bad $message
    Write-Host ""
    Write-Host "Nothing was changed." -ForegroundColor Yellow
    Write-Host ""
    HoldOpen
    exit 1
}

function Get-Sha256([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpper()
}

# ---------------------------------------------------------------------------
# elevation - relaunch ourselves as admin if needed
# ---------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin) -and $Mode -ne 'Status') {
    Say ""
    Say "Administrator rights are needed to write into the ALVR folder."
    Say "Windows will now ask for permission - please click Yes."
    Say ""
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-Mode', $Mode, '-Elevated'
    )
    if ($InstallPath) { $argList += @('-InstallPath', "`"$InstallPath`"") }
    if ($Force)       { $argList += '-Force' }
    if ($NoPause)     { $argList += '-NoPause' }
    try {
        $p = Start-Process powershell -Verb RunAs -ArgumentList $argList -PassThru -Wait
        exit $p.ExitCode
    } catch {
        Say ""
        Bad "Could not get Administrator rights (you may have clicked No)."
        Say ""
        HoldOpen
        exit 1
    }
}

# ---------------------------------------------------------------------------
# find the ALVR installation
# ---------------------------------------------------------------------------
function Find-AlvrInstall {
    $found = New-Object System.Collections.ArrayList

    # 1. Most reliable: SteamVR records the registered ALVR driver here.
    $vrpath = Join-Path $env:LOCALAPPDATA 'openvr\openvrpaths.vrpath'
    if (Test-Path $vrpath) {
        try {
            $j = Get-Content $vrpath -Raw | ConvertFrom-Json
            foreach ($d in $j.external_drivers) {
                if ($d -and $d -match 'alvr') {
                    $cand = Join-Path $d $REL_DRIVER
                    if (Test-Path $cand) { [void]$found.Add((Resolve-Path $d).Path) }
                }
            }
        } catch { }
    }

    # 2. Launcher default locations.
    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA,
        $env:APPDATA,
        'C:\'
    ) | Where-Object { $_ }

    foreach ($r in $roots) {
        $glob = Join-Path $r 'alvr_launcher_windows\installations\*'
        try {
            foreach ($d in (Get-ChildItem $glob -Directory -ErrorAction SilentlyContinue)) {
                if (Test-Path (Join-Path $d.FullName $REL_DRIVER)) { [void]$found.Add($d.FullName) }
            }
        } catch { }
    }

    return ($found | Select-Object -Unique)
}

Say ""
Say "==========================================================="
Say "  ALVR idle-hold patch  -  $Mode"
Say "  Keeps VRChat hands in place when you set a controller down"
Say "==========================================================="

Step "[1/5] Locating your ALVR installation..."

if ($InstallPath) {
    if (-not (Test-Path (Join-Path $InstallPath $REL_DRIVER))) {
        Stop-WithMessage "No driver_alvr_server.dll under: $InstallPath"
    }
    $target = $InstallPath
} else {
    $hits = @(Find-AlvrInstall)
    if ($hits.Count -eq 0) {
        Say ""
        Bad "Could not find ALVR automatically."
        Say ""
        Say "Open the ALVR Launcher, note where it installed ALVR, then re-run"
        Say "this from PowerShell with the folder spelled out, for example:"
        Say ""
        Say '    .\Patch-ALVR.ps1 -InstallPath "C:\Program Files\alvr_launcher_windows\installations\v20.14.1"'
        Say ""
        HoldOpen
        exit 1
    } elseif ($hits.Count -eq 1) {
        $target = $hits[0]
    } else {
        Say ""
        Say "  Found more than one ALVR installation:"
        for ($i = 0; $i -lt $hits.Count; $i++) { Say ("    [{0}] {1}" -f ($i + 1), $hits[$i]) }
        Say ""
        if ($NoPause) { Stop-WithMessage "More than one install found; re-run with -InstallPath to choose one." }
        $sel = Read-Host "  Which one? Enter a number (1-$($hits.Count))"
        $n = 0
        if (-not [int]::TryParse($sel, [ref]$n) -or $n -lt 1 -or $n -gt $hits.Count) {
            Stop-WithMessage "That was not one of the listed numbers."
        }
        $target = $hits[$n - 1]
    }
}

$driver = Join-Path $target $REL_DRIVER
$backup = "$driver$BACKUP_SUFFIX"
Good "ALVR found: $target"

# ---------------------------------------------------------------------------
# inspect current state
# ---------------------------------------------------------------------------
Step "[2/5] Checking the installed driver..."

$current = Get-Sha256 $driver
if     ($current -eq $HASH_PATCHED)      { $state = 'Patched' }
elseif ($HASH_SUPERSEDED -contains $current) { $state = 'Superseded' }
elseif ($current -eq $HASH_STOCK)       { $state = 'Stock'   }
else                                    { $state = 'Unknown' }

switch ($state) {
    'Patched'    { Good "Currently PATCHED, current version (idle-hold active)." }
    'Superseded' { Warn2 "An OLDER version of this patch is installed - it should be replaced." }
    'Stock'      { Good "Currently STOCK $SUPPORTED_VERSION (unpatched)." }
    'Unknown'    { Warn2 "Unrecognised driver - not stock $SUPPORTED_VERSION and not our patch." }
}

if ($Mode -eq 'Status') {
    Say ""
    Say "  Folder : $target"
    Say "  SHA256 : $current"
    Say "  State  : $state"
    if (Test-Path $backup) { Say "  Backup : present" } else { Say "  Backup : none" }
    Say ""
    HoldOpen
    exit 0
}

# ---------------------------------------------------------------------------
# make sure nothing is using the file
# ---------------------------------------------------------------------------
Step "[3/5] Checking that SteamVR and ALVR are closed..."

$busy = @()
foreach ($n in 'vrserver', 'vrmonitor', 'vrcompositor', 'vrdashboard', 'ALVR Dashboard', 'alvr_dashboard', 'VRChat') {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) { $busy += $n }
}
if ($busy.Count -gt 0) {
    Say ""
    Bad "These are still running: $($busy -join ', ')"
    Say ""
    Say "  Please close SteamVR, the ALVR Dashboard and VRChat completely,"
    Say "  then run this again. The driver file cannot be replaced while"
    Say "  SteamVR has it open."
    Say ""
    HoldOpen
    exit 1
}
Good "Nothing is holding the driver open."

# ===========================================================================
#  UNINSTALL
# ===========================================================================
if ($Mode -eq 'Uninstall') {
    Step "[4/5] Restoring the original driver..."

    if ($state -eq 'Stock') {
        Good "Already the stock driver - nothing to undo."
        Say ""
        HoldOpen
        exit 0
    }
    if (-not (Test-Path $backup)) {
        # No sidecar backup. That happens if the patch was put in by hand, or
        # if the backup was deleted. We can still recover safely: find any copy
        # of the stock driver, verify it by hash, and restore that. Nothing is
        # guessed - a candidate is only used if it matches $HASH_STOCK exactly.
        Warn2 "No backup beside the driver - looking for a verified stock copy..."

        $candidates = @()
        $candidates += Join-Path $PSScriptRoot 'driver_alvr_server.dll.stock'
        $candidates += (Join-Path $PSScriptRoot 'stock\driver_alvr_server.dll')
        foreach ($d in (Get-ChildItem (Split-Path $target -Parent) -Directory -ErrorAction SilentlyContinue)) {
            $candidates += Join-Path $d.FullName $REL_DRIVER
        }

        $source = $null
        foreach ($c in $candidates) {
            if ($c -and (Test-Path $c) -and ((Get-Sha256 $c) -eq $HASH_STOCK)) { $source = $c; break }
        }

        if (-not $source) {
            Say ""
            Bad "No backup, and no verified copy of the original driver on this PC."
            Say ""
            Say "  You are not stuck - ALVR can restore the file itself:"
            Say ""
            Say "    1. Open the ALVR Launcher."
            Say "    2. Reinstall $SUPPORTED_VERSION (or remove it and add it again)."
            Say ""
            Say "  That replaces driver_alvr_server.dll with the original and"
            Say "  undoes this patch completely. Your ALVR settings are kept."
            Say ""
            HoldOpen
            exit 1
        }

        Good "Verified stock driver found: $source"
        Copy-Item -LiteralPath $source -Destination $backup -Force
    }

    $bh = Get-Sha256 $backup
    if ($bh -ne $HASH_STOCK -and -not $Force) {
        Stop-WithMessage "The backup file is not the expected stock driver. Use -Force to restore it anyway."
    }

    Copy-Item -LiteralPath $backup -Destination $driver -Force
    Good "Original driver restored."

    Step "[5/5] Verifying..."
    $after = Get-Sha256 $driver
    if ($after -ne $bh) { Stop-WithMessage "Verification failed - the restored file does not match the backup." }
    Good "Verified."
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue

    Say ""
    Say "==========================================================="
    Say "  DONE - ALVR is back to its original driver."
    Say "==========================================================="
    Say ""
    HoldOpen
    exit 0
}

# ===========================================================================
#  INSTALL
# ===========================================================================
if ($state -eq 'Patched') {
    Say ""
    Good "The patch is already installed - nothing to do."
    Say ""
    Say "  To remove it, run UNINSTALL.bat"
    Say ""
    HoldOpen
    exit 0
}

if ($state -eq 'Unknown' -and -not $Force) {
    Say ""
    Bad "This driver is not the $SUPPORTED_VERSION build this patch was made for."
    Say ""
    Say "  Your driver SHA256 : $current"
    Say "  Expected           : $HASH_STOCK"
    Say ""
    Say "  This almost always means you are on a different ALVR version."
    Say "  Installing anyway could stop ALVR from starting, so it is blocked."
    Say ""
    Say "  What to do: install ALVR $SUPPORTED_VERSION from the ALVR Launcher,"
    Say "  or get a patcher built for your version."
    Say ""
    HoldOpen
    exit 1
}

$payload = Join-Path $PSScriptRoot 'driver_alvr_server.dll'
if (-not (Test-Path $payload)) {
    Stop-WithMessage "driver_alvr_server.dll is missing from this folder. Unzip the whole download and try again."
}
$ph = Get-Sha256 $payload
if ($ph -ne $HASH_PATCHED -and -not $Force) {
    Stop-WithMessage "The bundled driver_alvr_server.dll is damaged (hash mismatch). Download the patcher again."
}

Step "[4/5] Backing up your original driver..."

if (-not (Test-Path $backup)) {
    Copy-Item -LiteralPath $driver -Destination $backup -Force
    if ((Get-Sha256 $backup) -ne $current) { Stop-WithMessage "Backup verification failed." }
    Good "Saved to: $backup"
} else {
    Good "Backup already exists - keeping the existing one."
}

Step "[5/5] Installing the patched driver..."

try {
    Copy-Item -LiteralPath $payload -Destination $driver -Force
} catch {
    Say ""
    Bad "Could not write the file: $($_.Exception.Message)"
    Say ""
    Say "  Restoring your original driver..."
    Copy-Item -LiteralPath $backup -Destination $driver -Force
    Good "Original restored - ALVR is unchanged."
    Say ""
    HoldOpen
    exit 1
}

$after = Get-Sha256 $driver
if ($after -ne $HASH_PATCHED) {
    Copy-Item -LiteralPath $backup -Destination $driver -Force
    Stop-WithMessage "Verification failed - your original driver has been put back."
}
Good "Installed and verified."

Say ""
Say "==========================================================="
Say "  SUCCESS - the idle-hold patch is active."
Say "==========================================================="
Say ""
Say "  Try it out:"
Say "    1. Start the ALVR Dashboard and begin streaming, then SteamVR."
Say "    2. In VRChat, put a controller down on a table."
Say "    3. Wait 10-15 seconds."
Say "       Your avatar's hand should STAY where the controller is,"
Say "       instead of the arm dropping to your side."
Say ""
Say "  To undo this at any time: run UNINSTALL.bat"
Say ""
Say "  Note: if the ALVR Launcher updates ALVR, the update replaces this"
Say "  file and the patch is gone. Just run INSTALL.bat again if the new"
Say "  version is still $SUPPORTED_VERSION."
Say ""
HoldOpen
exit 0
