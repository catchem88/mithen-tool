# Registers the bundled, offline Windhawk engine that backs MithenTool's
# "Windows customizations" page.
#
# The engine binaries are installed by Inno Setup from res\windhawk-payload;
# this script only seeds the registry, registers the service and maintains the
# "this is ours" sentinel. It never touches an existing Windhawk installation.
#
# All registry writes go through the explicit 64-bit view: Inno may launch us
# from a 32-bit PowerShell, where HKLM\SOFTWARE is redirected to WOW6432Node and
# the 64-bit app would never see the sentinel.

[CmdletBinding()]
param(
    [string]$AppRoot = '',
    [string]$DataRoot = '',
    [string]$EngineVersion = '2.0.0-alpha.7',
    [switch]$SkipIfExternal,
    [switch]$Uninstall
)

# NOTE: do not use $PSScriptRoot in a param() default - Windows PowerShell 5.1
# evaluates defaults before the script scope exists, leaving it empty.
if(-not $AppRoot) {
    $scriptDir = $PSScriptRoot
    if(-not $scriptDir) {
        $scriptDir = Join-Path $env:ProgramFiles 'MithenTool\windhawk'
    }
    $AppRoot = Join-Path (Split-Path -Parent $scriptDir) 'windhawk-engine'
}
if(-not $DataRoot) {
    $DataRoot = Join-Path $env:ProgramData 'Windhawk'
}

$ErrorActionPreference = 'Stop'
Write-Host "windhawk-deploy: app root: $AppRoot"
Write-Host "windhawk-deploy: data root: $DataRoot"
$sentinelPath = 'SOFTWARE\MithenTool'
$sentinelName = 'WindhawkEngine'
$uninstallPaths = @(
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Windhawk',
    'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Windhawk'
)

$hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    [Microsoft.Win32.RegistryView]::Registry64
)
$hklm32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    [Microsoft.Win32.RegistryView]::Registry32
)

function Write-Step([string]$Message) {
    Write-Host "windhawk-deploy: $Message"
}

function Get-RegValue($Hive,[string]$Path,[string]$Name) {
    $key = $Hive.OpenSubKey($Path)
    if(-not $key) {
        return $null
    }
    try {
        return $key.GetValue($Name, $null)
    } finally {
        $key.Close()
    }
}

function Set-RegValue($Hive,[string]$Path,[string]$Name,[string]$Type,$Value) {
    if($null -eq $Value) {
        if($Type -eq 'DWord' -or $Type -eq 'QWord') {
            $Value = 0
        } else {
            $Value = ''
        }
    }

    $kind = switch($Type) {
        'DWord' { [Microsoft.Win32.RegistryValueKind]::DWord }
        'QWord' { [Microsoft.Win32.RegistryValueKind]::QWord }
        default { [Microsoft.Win32.RegistryValueKind]::String }
    }
    $key = $Hive.CreateSubKey($Path, $true)
    if(-not $key) {
        throw "cannot create $Path"
    }
    try {
        $key.SetValue($Name, $Value, $kind)
    } finally {
        $key.Close()
    }
}

function Get-Sentinel {
    foreach($hive in @($hklm64, $hklm32)) {
        $value = Get-RegValue $hive $sentinelPath $sentinelName
        if($value) {
            return [string]$value
        }
    }
    return $null
}

function Set-Sentinel([string]$Value) {
    foreach($hive in @($hklm64, $hklm32)) {
        Set-RegValue $hive $sentinelPath $sentinelName 'String' $Value
    }
}

function Clear-Sentinel {
    foreach($hive in @($hklm64, $hklm32)) {
        try {
            $key = $hive.OpenSubKey($sentinelPath, $true)
            if($key) {
                $key.DeleteValue($sentinelName, $false)
                $key.Close()
            }
        } catch {
        }
    }
}

function Test-ExternalWindhawk {
    # A genuine Windhawk always lives in Program Files\Windhawk. Our engine is
    # deployed inside the MithenTool folder, so this can never be ours.
    $official = Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
    if(Test-Path -LiteralPath $official) {
        return $true
    }
    foreach($path in $uninstallPaths) {
        foreach($hive in @($hklm64, $hklm32)) {
            if(Get-RegValue $hive $path 'DisplayName') {
                return $true
            }
        }
    }
    # A service that points somewhere else is somebody else's engine too.
    $config = & sc.exe qc Windhawk 2>&1
    $pathLine = ($config | Select-String -Pattern 'BINARY_PATH_NAME' | Select-Object -First 1).Line
    if($pathLine -and ($pathLine -notlike "*$AppRoot*")) {
        return $true
    }
    return $false
}

function Start-EngineService {
    $service = Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue
    if($service) {
        # A previous build may have registered the service for another folder.
        $config = & sc.exe qc Windhawk 2>&1
        $pathLine = ($config | Select-String -Pattern 'BINARY_PATH_NAME' | Select-Object -First 1).Line
        if($pathLine -and ($pathLine -notlike "*$AppRoot*")) {
            Write-Step "service points at an old location ($pathLine) - recreating"
            Stop-EngineService
            $service = $null
        }
    }
    if(-not $service) {
        $binary = Join-Path $AppRoot 'windhawk.exe'
        $binaryPath = "`"$binary`" -service"
        try {
            New-Service -Name 'Windhawk' -BinaryPathName $binaryPath -DisplayName 'Windhawk' `
                -StartupType Automatic -Description 'Windhawk mod engine' | Out-Null
            Write-Step 'service created (New-Service)'
        } catch {
            Write-Step "New-Service failed: $($_.Exception.Message)"
            # Fallback for hosts where New-Service is unavailable.
            $created = & cmd.exe /c "sc create Windhawk binPath= \`"$binary\`" -service start= auto DisplayName= Windhawk obj= LocalSystem" 2>&1
            if($LASTEXITCODE -ne 0) {
                Write-Error ("sc create failed: " + ($created -join ' '))
                exit 1
            }
            Write-Step 'service created (sc.exe)'
        }
    }

    $service = Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue
    if($service -and $service.Status -eq 'Running') {
        return
    }

    $start = & sc.exe start Windhawk 2>&1
    for($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 500
        $service = Get-Service -Name 'Windhawk' -ErrorAction SilentlyContinue
        if($service -and $service.Status -eq 'Running') {
            Write-Step 'service started'
            return
        }
    }

    $query = & sc.exe query Windhawk 2>&1
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Service Control Manager'
        StartTime = (Get-Date).AddMinutes(-3)
    } -ErrorAction SilentlyContinue | Select-Object -First 3
    $details = @($start) + @($query)
    foreach($event in $events) {
        $details += $event.Message
    }
    Write-Error ('service did not start: ' + ($details -join ' | '))
    exit 1
}

function Stop-EngineService {
    & sc.exe stop Windhawk | Out-Null
    Start-Sleep -Milliseconds 500
    & sc.exe delete Windhawk | Out-Null
    Write-Step 'service removed'
}

function Remove-EngineData {
    foreach($path in @('SOFTWARE\Windhawk','SOFTWARE\WOW6432Node\Windhawk')) {
        try {
            $hklm64.DeleteSubKeyTree($path, $false)
            Write-Step "registry removed: $path"
        } catch {
        }
    }
    foreach($root in @((Join-Path $env:ProgramData 'Windhawk'), $DataRoot)) {
        if($root -and (Test-Path -LiteralPath $root)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            Write-Step "data removed: $root"
        }
    }
}

if($Uninstall) {
    # Only tear down an engine that lives in our own folder. A Windhawk the user
    # installed shares these paths - its registry and data must never be touched.
    $serviceConfig = & sc.exe qc Windhawk 2>&1
    $servicePath = ($serviceConfig | Select-String -Pattern 'BINARY_PATH_NAME' | Select-Object -First 1).Line
    $ownedService = [bool]($servicePath -and ($servicePath -like "*$AppRoot*"))

    if($ownedService) {
        Stop-EngineService
    } else {
        Write-Step 'the Windhawk service is not ours - leaving it running'
    }

    $official = Join-Path $env:ProgramFiles 'Windhawk\windhawk.exe'
    if((Get-Sentinel) -eq $EngineVersion -and -not (Test-Path -LiteralPath $official)) {
        Remove-EngineData
    }
    Clear-Sentinel
    exit 0
}

if(Test-ExternalWindhawk) {
    Write-Step 'a Windhawk installation was found - leaving the mini engine dormant'
    Set-Sentinel 'skipped-external'
    exit 0
}

if((Get-Sentinel) -eq 'skipped-external') {
    # The user may have uninstalled their Windhawk since - take over then.
    if(Get-RegValue $hklm64 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Windhawk' 'DisplayName') {
        Write-Step 'external Windhawk detected - staying dormant'
        exit 0
    }
    Clear-Sentinel
}

if(-not (Test-Path -LiteralPath (Join-Path $AppRoot 'windhawk.exe'))) {
    Write-Step "engine files are missing under $AppRoot"
    exit 1
}

# --- application settings: dark, hidden tray, no update check, no UI -----------
foreach($pair in @(
    @('Language','en','String'),
    @('LoggingVerbosity',0,'DWord'),
    @('HideTrayIcon',1,'DWord'),
    @('DontAutoShowToolkit',1,'DWord'),
    @('ModTasksDialogDelay',2000,'DWord'),
    @('SafeMode',0,'DWord'),
    @('DisableUpdateCheck',1,'DWord'),
    @('DevModeOptOut',1,'DWord'),
    @('AlwaysCompileModsLocally',0,'DWord'),
    @('DisableToolkitHotkey',1,'DWord')
)) {
    Set-RegValue $hklm64 'SOFTWARE\Windhawk\Settings' $pair[0] $pair[2] $pair[1]
}

foreach($pair in @(
    @('LoggingVerbosity',2,'DWord'),
    @('Include','','String'),
    @('Exclude','','String'),
    @('ThreadAttachExempt','','String'),
    @('InjectIntoCriticalProcesses',0,'DWord'),
    @('InjectIntoIncompatiblePrograms',0,'DWord'),
    @('InjectIntoGames',0,'DWord')
)) {
    Set-RegValue $hklm64 'SOFTWARE\Windhawk\Engine\Settings' $pair[0] $pair[2] $pair[1]
}

# --- mods: compiled locally, so they match this Windows build ----------------
# Windhawk's own design: mod DLLs are compiled on the machine that runs them.
# A DLL compiled against another Windows build fails to attach to most targets.
$mods = @(
    @{ Id = 'explorer-context-menu-classic'; Settings = @{ overrideWithCtrl = 1 } },
    @{ Id = 'classic-menu-corners'; Source = 'classic-menu-corners.wh.cpp'; Settings = @{
        cornerStyle = '3'
        removeBorder = 1
    } },
    @{ Id = 'explorer-frame-classic'; Settings = @{ explorerStyle = 'classicNavigationBar' } },
    @{ Id = 'legacy-file-copy'; Settings = @{} },
    @{ Id = 'modernize-folder-picker-dialog'; Settings = @{} },
    @{ Id = 'pinned-only-on-start-menu'; Settings = @{} },
    @{ Id = 'start-menu-size'; Settings = @{
        width = 666
        height = 750
        searchWidth = 0
        searchHeight = 0
    } },
    @{ Id = 'taskbar-classic-menu'; Settings = @{ oldTaskbarOnWin11 = 0 } },
    @{ Id = 'taskbar-icon-size'; Settings = @{
        TaskbarHeight = 40
        IconSize = 17
        TaskbarButtonWidth = 35
        IconSizeSmall = 16
        TaskbarButtonWidthSmall = 32
    } },
    @{ Id = 'windows-11-notification-center-styler'; Settings = @{
        theme = ''
        'styleConstants[0]' = ''
        'controlStyles[0].target' = 'Windows.UI.Xaml.Controls.Grid#NotificationCenterGrid'
        'controlStyles[0].styles[0]' = 'Visibility=Collapsed'
        'themeResourceVariables[0]' = ''
    } },
    @{ Id = 'windows-11-start-menu-styler'; Settings = @{
        theme = 'NoRecommendedSection'
        disableNewStartMenuLayout = ''
        'controlStyles[0].target' = ''
        'controlStyles[0].styles[0]' = ''
        'webContentStyles[0].target' = ''
        'webContentStyles[0].styles[0]' = ''
        'webContentCustomJs' = ''
        'styleConstants[0]' = ''
        'themeResourceVariables[0]' = ''
    } }
)

$cli = Join-Path $AppRoot 'windhawk-cli.exe'
$sources = Join-Path $DataRoot 'ModsSource'
$modsRoot = 'SOFTWARE\Windhawk\Engine\Mods'
$modsDir64 = Join-Path $DataRoot 'Engine\Mods\64'

# The bundled compiler links mods (and windhawk-mod-shim.dll) against the
# Windhawk C++ runtime, whose import names are libc++.whl and libunwind.whl.
# Windows resolves those imports from the directory the mod is loaded from, so
# the runtime has to sit next to the mods - ModsRuntime alone is not on the
# search path. Without this, every mod built by the bundled compiler fails to
# load with error 126 and the customizations silently do nothing.
foreach($arch in @('32','64')) {
    $runtimeDir = Join-Path (Join-Path $AppRoot 'ModsRuntime') $arch
    $modsDir = Join-Path (Join-Path $DataRoot 'Engine\Mods') $arch
    if(-not (Test-Path -LiteralPath $runtimeDir)) {
        continue
    }
    if(-not (Test-Path -LiteralPath $modsDir)) {
        New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
    }
    foreach($runtime in @('libc++.whl','libunwind.whl')) {
        $runtimePath = Join-Path $runtimeDir $runtime
        $destination = Join-Path $modsDir $runtime
        if(-not (Test-Path -LiteralPath $runtimePath)) {
            continue
        }
        # A repair runs while the engine is live, and the runtime files are
        # mapped then. Same version: leave the installed copy alone. New
        # version: the caller moved the mods folder aside first, so the copy
        # has an empty destination.
        if((Test-Path -LiteralPath $destination) -and
           ((Get-Item -LiteralPath $destination).Length -eq
            (Get-Item -LiteralPath $runtimePath).Length)) {
            continue
        }
        try {
            Copy-Item -LiteralPath $runtimePath -Destination $destination -Force
        } catch {
            Write-Step "runtime file is in use, keeping the installed copy: $runtime"
        }
    }
}

foreach($mod in $mods) {
    $sourceFile = "$($mod.Id).wh.cpp"
    if($mod.ContainsKey('Source')) {
        $sourceFile = $mod.Source
    }
    $source = Join-Path $sources $sourceFile
    if(-not (Test-Path -LiteralPath $source)) {
        Write-Error "mod source missing: $source"
        exit 1
    }

    # A local file install is registered as local@<id> by the bundled CLI,
    # while an install from an older build uses the bare id. Prefer the
    # local@ key when it exists and keep using it below.
    $plainKey = "$modsRoot\$($mod.Id)"
    $localKey = "$modsRoot\local@$($mod.Id)"
    $plainVersion = Get-RegValue $hklm64 $plainKey 'Version'
    $localVersion = Get-RegValue $hklm64 $localKey 'Version'
    if($localVersion) {
        $modKey = $localKey
        $installedId = "local@$($mod.Id)"
    } else {
        $modKey = $plainKey
        $installedId = $mod.Id
    }

    $version = Get-RegValue $hklm64 $modKey 'Version'
    $registered = [bool]$version
    # When migrating from an old bare-id registration, its Disabled value is
    # the state the user chose; the new local@ key starts disabled.
    $previousDisabled = Get-RegValue $hklm64 $modKey 'Disabled'
    $plainDisabled = Get-RegValue $hklm64 $plainKey 'Disabled'
    if($null -ne $plainDisabled) {
        $previousDisabled = $plainDisabled
    }
    $dllName = Get-RegValue $hklm64 $modKey 'LibraryFileName'
    $dllPresent = $false
    if($dllName) {
        $dllPresent = Test-Path -LiteralPath (Join-Path $modsDir64 $dllName)
    }

    # A registration without its DLL (left over from an older build) counts as
    # not installed - the engine silently skips such mods.
    if((-not $version) -or (-not $dllPresent)) {
        Write-Step "compiling $($mod.Id) for this Windows build"
        # The CLI prints progress to stderr; with $ErrorActionPreference=Stop
        # that becomes a terminating NativeCommandError and aborts the whole
        # deploy before any mod is installed.
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $install = & $cli mod install --file $source --disabled --yes 2>&1
        $installExit = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorAction
        if($installExit -ne 0) {
            Write-Error ("mod install failed for $($mod.Id): " + ($install -join ' '))
            exit 1
        }
        if(Get-RegValue $hklm64 $localKey 'Version') {
            $modKey = $localKey
            $installedId = "local@$($mod.Id)"
        }
        $dllName = Get-RegValue $hklm64 $modKey 'LibraryFileName'
        if(-not $dllName -or -not (Test-Path -LiteralPath (Join-Path $modsDir64 $dllName))) {
            Write-Error "mod $($mod.Id) compiled but its DLL is missing in $modsDir64"
            exit 1
        }
    }

    if($mod.Settings.Count -gt 0) {
        $jsonPath = Join-Path $env:TEMP "mithen-windhawk-$($mod.Id).json"
        ($mod.Settings | ConvertTo-Json -Compress) |
            Set-Content -LiteralPath $jsonPath -Encoding UTF8
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $apply = & $cli mod settings write $installedId $jsonPath --yes 2>&1
        $applyExit = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorAction
        if($applyExit -ne 0) {
            Write-Step ("settings write failed for $($mod.Id): " + ($apply -join ' '))
        }
        Remove-Item -LiteralPath $jsonPath -Force -ErrorAction SilentlyContinue
    }

    # New mods start disabled; an existing mod keeps the state the user chose,
    # so upgrading does not turn every customization off.
    if($registered -and ($null -ne $previousDisabled)) {
        Set-RegValue $hklm64 $modKey 'Disabled' 'DWord' $previousDisabled
    } else {
        Set-RegValue $hklm64 $modKey 'Disabled' 'DWord' 1
    }
    Set-RegValue $hklm64 $modKey 'LoggingEnabled' 'DWord' 1

    # The engine would otherwise keep trying to load the old bare-id entry,
    # whose DLL now lives in the renamed folder.
    if(($modKey -eq $localKey) -and $plainVersion) {
        try {
            $hklm64.DeleteSubKeyTree($plainKey, $false)
        } catch {
        }
    }
}

Start-EngineService

# Remove the engine copy an older MithenTool build left in Program Files.
$stale = Join-Path $env:ProgramFiles 'Windhawk'
if((Test-Path -LiteralPath $stale) -and ($stale -ne $AppRoot)) {
    Remove-Item -LiteralPath $stale -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "removed stale engine folder: $stale"
}

Set-Sentinel $EngineVersion
Write-Step 'done'
exit 0
