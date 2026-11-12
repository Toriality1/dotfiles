# Native Windows installer. Compatible with Windows PowerShell 5.1 and PowerShell 7.
[CmdletBinding()]
param(
    [Alias('h')][switch]$Help,
    [Alias('List')][switch]$Catalog,
    [Alias('n')][switch]$DryRun,
    [string[]]$Select = @(),
    [string[]]$Skip = @(),
    [string]$Preset = '',
    [switch]$NonInteractive,
    [Alias('y')][switch]$Yes,
    [switch]$Dotfiles,
    [ValidatePattern('^[0-9]{2,3}$')][string]$AndroidApi = '36',
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$AndroidBuildTools = '36.0.0',
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$AndroidNdkVersion = '27.1.12297006',
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$')][string]$AndroidAvdName = 'dotfiles-api36',
    [switch]$AcceptAndroidLicenses
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) {
    @'
Usage: .\install.ps1 [-Catalog] [-DryRun] [-Preset cli|desktop|server|ai|dev|mobile|empty]
                    [-Select git,node,codex] [-Skip node] [-Dotfiles]
                    [-NonInteractive] [-Yes]

Native Windows packages use WinGet; OpenCode, Gemini, Bun and pnpm use npm.
The default starting preset is cli. Select explicit IDs to start from empty.
Preset entries unavailable on Windows are listed and skipped. Explicit unsupported
choices fail before anything changes. Unchecked programs are always retained.
-Dotfiles copies selected Neovim/Alacritty configs with backups. Linux shell and
desktop configs are not deployed on Windows. Alacritty uses Consolas on Windows.
Dry-run and Catalog work without WinGet and never write files or run installers.
Non-interactive apply requires -Yes; interactive mode reviews and confirms first.
App installers may request UAC elevation. Docker Desktop needs WSL2/virtualization;
Android SDK/Studio: -Select android-studio,android-emulator,android-ndk
  -AndroidApi 36 -AndroidBuildTools 36.0.0 -AndroidNdkVersion 27.1.12297006
  -AndroidAvdName dotfiles-api36 -AcceptAndroidLicenses
SDK licenses: https://developer.android.com/studio#terms
The SDK is configured automatically; emulators are installed but never started.
'@
    return
}

$Choices = [ordered]@{}
foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'installer/windows.conf')) {
    if (!$line -or $line.StartsWith('#')) { continue }
    $fields = $line.Split('|')
    if ($fields.Count -ne 5 -or $fields[0] -notmatch '^[a-z0-9][a-z0-9.-]*$') { throw "Invalid Windows catalog row: $line" }
    $Choices[$fields[0]] = @{ Label = $fields[1]; Packages = $fields[2]; Npm = $fields[3]; Dependencies = $fields[4] }
}
if ($Catalog) {
    foreach ($id in $Choices.Keys) { '{0,-22} {1}' -f $id, $Choices[$id].Label }
    return
}

function Split-Ids([string[]]$Values) {
    foreach ($value in $Values) {
        foreach ($id in $value.Split(',')) {
            $id = $id.Trim()
            if ($id) {
                if ($id -notmatch '^[a-z0-9][a-z0-9.-]*$') { throw "Invalid software ID: $id" }
                $id
            }
        }
    }
}

$Presets = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'installer/presets.conf')) {
    if (!$line -or $line.StartsWith('#')) { continue }
    $fields = $line.Split('|')
    $Presets[$fields[0]] = $fields[1]
}
$Selected = @{}
if (!$Preset -and $Select.Count -eq 0) { $Preset = 'cli' }
if ($Preset) {
    if (!$Presets.ContainsKey($Preset)) { throw "Unknown preset: $Preset" }
    foreach ($id in @(Split-Ids @($Presets[$Preset]))) {
        if ($Choices.Contains($id)) { $Selected[$id] = $true }
        else { Write-Output "Preset choice unavailable on native Windows: $id (use WSL for Linux tools)" }
    }
}
foreach ($id in @(Split-Ids $Select)) {
    if (!$Choices.Contains($id)) { throw "Unsupported Windows choice: $id. Use -Catalog." }
    $Selected[$id] = $true
}
foreach ($id in @(Split-Ids $Skip)) {
    if (!$Choices.Contains($id) -and !($Presets.Values -match "(^|,)$([regex]::Escape($id))(,|$)")) { throw "Unknown choice: $id" }
    $Selected.Remove($id)
}

if (!$NonInteractive) {
    $ids = @($Choices.Keys)
    while ($true) {
        Write-Host "`nSoftware (unchecked applications are kept):"
        for ($i = 0; $i -lt $ids.Count; $i++) {
            $mark = ' '
            if ($Selected.ContainsKey($ids[$i])) { $mark = 'x' }
            Write-Host ('{0,2}) [{1}] {2}' -f ($i + 1), $mark, $Choices[$ids[$i]].Label)
        }
        $answer = Read-Host 'Toggle numbers (spaces/commas), none to clear, done to review, q to cancel'
        if ($answer -eq 'q') { Write-Output 'Cancelled.'; return }
        if ($answer -eq 'done') { break }
        if ($answer -eq 'none') { $Selected.Clear(); continue }
        $numbers = @($answer -split '[,\s]+' | Where-Object { $_ })
        if (@($numbers | Where-Object { $_ -notmatch '^\d{1,3}$' -or [int]$_ -lt 1 -or [int]$_ -gt $ids.Count }).Count) {
            Write-Host 'Enter valid item numbers.'
            continue
        }
        foreach ($number in $numbers) {
            $id = $ids[[int]$number - 1]
            if ($Selected.ContainsKey($id)) { $Selected.Remove($id) } else { $Selected[$id] = $true }
        }
    }
}

$Actions = New-Object 'System.Collections.Generic.List[object]'
$Resolved = @{}
$Visiting = @{}
$PackageSeen = @{}
$NpmSeen = @{}
function Add-Action([string]$Kind, [string]$Label, [string[]]$Arguments) {
    $script:Actions.Add([pscustomobject]@{ Kind = $Kind; Label = $Label; Arguments = $Arguments })
}
function Resolve-Choice([string]$Id) {
    if ($script:Resolved.ContainsKey($Id)) { return }
    if ($script:Visiting.ContainsKey($Id)) { throw "Dependency cycle: $Id" }
    if (!$script:Choices.Contains($Id)) { throw "Missing dependency: $Id" }
    $script:Visiting[$Id] = $true
    $choice = $script:Choices[$Id]
    foreach ($dependency in @(Split-Ids @($choice.Dependencies))) { Resolve-Choice $dependency }
    foreach ($package in @($choice.Packages.Split(',') | Where-Object { $_ })) {
        if ($script:PackageSeen.ContainsKey($package)) { continue }
        $script:PackageSeen[$package] = $true
        $packageArgs = @('install', '--id', $package, '--exact', '--source', 'winget', '--silent', '--no-upgrade', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        if ($Id -eq 'build-tools') { $packageArgs += @('--override', '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended') }
        Add-Action 'winget' "Install $package" $packageArgs
    }
    foreach ($package in @($choice.Npm.Split(',') | Where-Object { $_ })) {
        if ($script:NpmSeen.ContainsKey($package)) { continue }
        $script:NpmSeen[$package] = $true
        Add-Action 'npm' "Install $package for the current user" @('install', '--global', '--prefix', '%APPDATA%\npm', $package)
    }
    $script:Visiting.Remove($Id)
    $script:Resolved[$Id] = $true
}
foreach ($id in $Choices.Keys) { if ($Selected.ContainsKey($id)) { Resolve-Choice $id } }

if ($Resolved.ContainsKey('android-sdk')) {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { throw 'Android Studio/SDK setup requires Windows x64.' }
    $sdkRoot = '%LOCALAPPDATA%/Android/Sdk'
    if ($env:ANDROID_HOME) { $sdkRoot = $env:ANDROID_HOME }
    if ($env:ANDROID_SDK_ROOT -and $env:ANDROID_SDK_ROOT -ne [Environment]::ExpandEnvironmentVariables($sdkRoot)) { throw 'ANDROID_HOME and ANDROID_SDK_ROOT must identify the same SDK.' }
    if (!$DryRun -and $NonInteractive -and !$AcceptAndroidLicenses -and !(Test-Path -LiteralPath (Join-Path ([Environment]::ExpandEnvironmentVariables($sdkRoot)) 'licenses/android-sdk-license'))) {
        throw 'Review https://developer.android.com/studio#terms and use -AcceptAndroidLicenses, or install interactively.'
    }
    $licenseMode = 'off'; if ($AcceptAndroidLicenses) { $licenseMode = 'on' }
    $headless = 'off'; if ($NonInteractive) { $headless = 'on' }
    $ndk = ''; if ($Resolved.ContainsKey('android-ndk')) { $ndk = $AndroidNdkVersion }
    $avd = ''; if ($Resolved.ContainsKey('android-emulator')) { $avd = $AndroidAvdName }
    Add-Action 'android' 'Configure Android SDK, selected packages, shell paths and optional AVD' @($sdkRoot, $AndroidApi, $AndroidBuildTools, $licenseMode, $ndk, $avd, $headless)
}

if ($Dotfiles) {
    if ($Resolved.ContainsKey('neovim')) {
        $sourceRoot = Join-Path $PSScriptRoot '.config/nvim'
        foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File) {
            $relative = $file.FullName.Substring($sourceRoot.Length + 1)
            if ($relative -in @('init.lua', 'lazy-lock.json', 'stylua.toml') -or ($relative -match '^lua[\\/]toriality[\\/](?:lazy[\\/])?[^\\/]+\.lua$')) {
                Add-Action 'copy' "Deploy Neovim $relative" @($file.FullName, (Join-Path '%LOCALAPPDATA%/nvim' $relative))
            }
        }
    }
    if ($Resolved.ContainsKey('alacritty')) {
        Add-Action 'alacritty' 'Deploy Alacritty with the Windows Consolas font' @((Join-Path $PSScriptRoot '.config/alacritty/alacritty.toml'), '%APPDATA%/alacritty/alacritty.toml')
    }
}
Write-Output "`nTarget: native Windows (WinGet). Unchecked applications are kept."
foreach ($id in $Choices.Keys) { if ($Selected.ContainsKey($id)) { Write-Output "  $($Choices[$id].Label)" } }
Write-Output "`nPlanned actions ($($Actions.Count)):"
foreach ($action in $Actions) {
    Write-Output "  $($action.Label)"
    Write-Output ('    {0}: {1}' -f $action.Kind, (($action.Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '))
}
if ($DryRun -or $Actions.Count -eq 0) { return }
if ($NonInteractive -and !$Yes) { throw 'Non-interactive apply requires -Yes. Use -DryRun to preview.' }
if (!$NonInteractive -and !$Yes -and (Read-Host 'Type yes to apply this plan') -ne 'yes') { Write-Output 'Cancelled.'; return }
if ($env:OS -ne 'Windows_NT') { throw 'Apply requires native Windows. Linux uses ./install.sh.' }
if ($PackageSeen.Count -and !(Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'WinGet is missing. Install/update App Installer from https://aka.ms/getwinget and retry.'
}

. (Join-Path $PSScriptRoot 'installer/windows-executor.ps1')
Invoke-WindowsPlan $Actions
