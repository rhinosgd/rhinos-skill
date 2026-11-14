# setup_windows.ps1 - Dual WorkBuddy account setup for Windows
#
# Creates a SECOND local Windows user, clones your WorkBuddy local history
# (conversation records) into that user's profile, and builds a 2-window
# launcher so you can run account A (current user) and account B (second user)
# at the same time - each with its OWN on-this-device history.
#
# WHY a second Windows user? WorkBuddy stores the login/auth token per Windows
# user (homedir) and locks a single instance per config dir. Same user => same
# account. A different Windows user => its own auth + its own config dir.
#
# Run AS ADMINISTRATOR:
#   powershell -ExecutionPolicy Bypass -File setup_windows.ps1 [-SecondUser WBUser2] [-Password Pwd]

[CmdletBinding()]
param(
  [string]$SecondUser = 'WBUser2',
  [string]$Password   = '',
  [string]$WbExe      = '',
  [switch]$SkipUserCreate
)

$ErrorActionPreference = 'Continue'

# --- locate WorkBuddy.exe ---
if (-not $WbExe) {
  $candidates = @(
    'C:\Program Files\WorkBuddy\WorkBuddy.exe',
    'C:\Program Files (x86)\WorkBuddy\WorkBuddy.exe'
  )
  foreach ($c in $candidates) { if (Test-Path $c) { $WbExe = $c; break } }
}
if (-not $WbExe -or -not (Test-Path $WbExe)) {
  Write-Warning "Could not find WorkBuddy.exe. Pass -WbExe '<full path>'."
  exit 1
}
if (-not $Password) { $Password = 'WorkBuddy@2026' }

$curUser      = $env:USERNAME
$curProfile   = $env:USERPROFILE
$secondProfile= "C:\Users\$SecondUser"
$src          = Join-Path $curProfile '.workbuddy'
$dst          = Join-Path $secondProfile '.workbuddy'

Write-Host "=================================================="
Write-Host " Dual WorkBuddy setup (Windows)"
Write-Host "   Account A (current) : $curUser"
Write-Host "   Account B (second)  : $SecondUser"
Write-Host "   WorkBuddy.exe       : $WbExe"
Write-Host "=================================================="

# --- 1) create / verify second user ---
if (-not $SkipUserCreate) {
  net user $SecondUser 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[1/4] Creating Windows user '$SecondUser' ..."
    net user $SecondUser $Password /add /y 2>&1 | Out-Null
    net localgroup Users $SecondUser /add 2>&1 | Out-Null
    Write-Host "      Created. Password = $Password"
  } else {
    Write-Host "[1/4] User '$SecondUser' already exists."
  }
  # ensure enabled + password never expires
  net user $SecondUser /active:yes 2>&1 | Out-Null
  net user $SecondUser $Password 2>&1 | Out-Null
  net user $SecondUser /expires:never 2>&1 | Out-Null
} else {
  Write-Host "[1/4] Skipping user creation (-SkipUserCreate)."
}

if (-not (Test-Path $secondProfile)) {
  New-Item -ItemType Directory -Path $secondProfile -Force | Out-Null
}

# --- 2) clone local history (targeted: exclude heavy/regenerable dirs) ---
Write-Host "[2/4] Cloning WorkBuddy local history into $SecondUser ..."
if (-not (Test-Path $src)) {
  Write-Warning "Source $src not found - nothing to clone. Continuing."
} else {
  $xd = @('workspace','binaries','app','logs','plugins','projects','traces',
          'connectors-marketplace-sources','cache','Crashpad','node_modules',
          'external-packages','native-runtimes')
  $argList = @($src, $dst, '/E','/R:1','/W:1','/NP','/COPY:DAT','/MIR')
  foreach ($x in $xd) { $argList += @('/XD', $x) }
  & robocopy.exe $argList
  # robocopy exit 0=nothing copied,1=copied ok,11=ok+copied+some skipped/failed
  Write-Host "      robocopy finished (exit $LASTEXITCODE)."
  # verify db copied
  $sf = Join-Path $src 'workbuddy.db'; $df = Join-Path $dst 'workbuddy.db'
  if ((Test-Path $sf) -and (Test-Path $df)) {
    $ss=(Get-Item $sf).Length; $ds=(Get-Item $df).Length
    Write-Host ("      workbuddy.db src=$ss dst=$ds " + $(if($ss-eq$ds){'OK (match)'}else{'MISMATCH'}))
  }
}

# --- 3) build launcher ---
$launcherDir = Join-Path $curProfile 'WorkBuddyDualLaunch'
if (-not (Test-Path $launcherDir)) { New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null }
$launcher = Join-Path $launcherDir 'launch_2workbuddy.ps1'
$machine = $env:COMPUTERNAME
$launchContent = @"
# Auto-generated dual-account launcher (do not edit manually)
`$exe = '$WbExe'
`$secondUser = '$SecondUser'
`$machine = '$machine'
`$pwd = '$Password'
@('https_proxy','http_proxy','HTTPS_PROXY','HTTP_PROXY','all_proxy','ALL_PROXY') | ForEach-Object {
  if (Test-Path "Env:`$_") { Remove-Item "Env:`$_" -ErrorAction SilentlyContinue }
}
Write-Host 'Opening account A (current user)...'
Start-Process `$exe
Start-Sleep -Seconds 4
Write-Host "Opening account B as `$machine\`$secondUser (first time: enter password '$Password')..."
runas.exe /savecred /profile /user:`$machine\`$secondUser "`$exe"
Start-Sleep -Seconds 2
"@
Set-Content -Path $launcher -Value $launchContent -Encoding utf8
Write-Host "[3/4] Launcher written: $launcher"

# --- 4) desktop shortcut ---
Write-Host "[4/4] Creating desktop shortcut 'WorkBuddy 2Accounts.lnk' ..."
try {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $lnkPath = Join-Path $desktop 'WorkBuddy 2Accounts.lnk'
  $Wsh = New-Object -ComObject WScript.Shell
  $lnk = $Wsh.CreateShortcut($lnkPath)
  $lnk.TargetPath = 'powershell.exe'
  $lnk.Arguments = "-ExecutionPolicy Bypass -File `"$launcher`""
  $lnk.WorkingDirectory = 'C:\Windows\System32'
  $lnk.IconLocation = "$WbExe,0"
  $lnk.Description = 'WorkBuddy 双账号并行启动器'
  $lnk.Save()
  Write-Host "      Shortcut: $lnkPath"
} catch {
  Write-Warning "Could not create shortcut via COM ($_). You can run the launcher manually: $launcher"
}

Write-Host ""
Write-Host "================== DONE =================="
Write-Host "Double-click 'WorkBuddy 2Accounts' on the desktop:"
Write-Host "  - Window 1: account A (current user) - full history."
Write-Host "  - Window 2: account B (user $SecondUser) - log in with your SECOND account there."
