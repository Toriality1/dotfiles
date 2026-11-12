# Run with Windows PowerShell 5.1 or pwsh. No live package installs or PATH edits.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repo 'install.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-tests-' + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $fixture | Out-Null
function Assert-True($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Get-Plan([hashtable]$Options) { (& $installer -NonInteractive -DryRun @Options) -join "`n" }
function Assert-Rejected([hashtable]$Options, [string]$Expected) {
    $caught = $false
    try { & $installer -NonInteractive @Options | Out-Null }
    catch { $caught = $true; Assert-True ($_.Exception.Message -like "*$Expected*") "Unexpected error: $_" }
    Assert-True $caught "Expected rejection: $Expected"
}
$calls = New-Object 'System.Collections.Generic.List[object]'
function winget.exe { throw 'Planner invoked WinGet' }
function npm.cmd { throw 'Planner invoked npm' }
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $fixture
    $output = (& $installer -Help) -join "`n"
    Assert-True ($output -like '*WinGet*') 'Missing Windows help'
    $output = (& $installer -Catalog) -join "`n"
    Assert-True ($output -like '*android-studio*') 'Missing Windows catalog'
    $output = Get-Plan @{ Select = @('opencode,gemini-cli,codex,bun') }
    Assert-True ($output -like '*OpenJS.NodeJS.LTS*') 'Node dependency missing'
    Assert-True (([regex]::Matches($output, 'Install OpenJS.NodeJS.LTS')).Count -eq 1) 'Duplicate Node installation'
    Assert-True ($output -like '*Git.Git*' -and $output -like '*@google/gemini-cli*') 'AI dependencies missing'
    Assert-True ($output.IndexOf('Install OpenJS.NodeJS.LTS') -lt $output.IndexOf('Install opencode-ai')) 'Wrong dependency order'
    Assert-True ($output -like '*--prefix*%APPDATA%*') 'npm must install for the current user'
    foreach ($preset in @('cli', 'desktop', 'server', 'ai', 'dev', 'mobile', 'empty')) { Get-Plan @{ Preset = $preset } | Out-Null }
    $output = Get-Plan @{ Preset = 'ai'; Skip = @('gemini-cli,tmux') }
    Assert-True ($output -notlike '*@google/gemini-cli*') 'Skip did not override preset'
    $output = Get-Plan @{ Select = @('neovim,alacritty'); Dotfiles = $true }
    Assert-True ($output -like '*%LOCALAPPDATA%*nvim*' -and $output -like '*Consolas*') 'Wrong Windows config targets'
    Assert-True ($output -notlike '*machine.conf*' -and $output -notlike '*.zshrc*') 'Linux config leaked to Windows'
    Assert-Rejected @{ DryRun = $true; Select = @('i3') } 'Unsupported Windows choice'
    Assert-Rejected @{ DryRun = $true; Select = @('$(Write-Output unsafe)') } 'Invalid software ID'
    Assert-Rejected @{ DryRun = $true; Preset = 'missing' } 'Unknown preset'
    Assert-Rejected @{ Select = @('git') } 'requires -Yes'
    Assert-True (@(Get-ChildItem -LiteralPath $fixture -Force).Count -eq 0) 'Dry-run wrote files'
    Write-Output 'PASS Windows catalog, dependency plans, presets, overrides and read-only previews'

    . (Join-Path $repo 'installer/windows-executor.ps1')
    function Update-ProcessPath { }
    function Ensure-NpmPath([string]$Path) { $calls.Add(@('path', $Path)) }
    function winget.exe { $calls.Add(@('winget') + $args); $global:LASTEXITCODE = 0 }
    function npm.cmd { $calls.Add(@('npm') + $args); $global:LASTEXITCODE = 0 }
    function node.exe { $global:LASTEXITCODE = 0; 'v22.1.0' }
    $actions = @(
        [pscustomobject]@{ Kind = 'winget'; Label = 'Test WinGet'; Arguments = @('install', '--id', 'Git.Git', '--exact') },
        [pscustomobject]@{ Kind = 'npm'; Label = 'Test npm'; Arguments = @('install', '--global', 'opencode-ai') }
    )
    $oldAppData = $env:APPDATA
    try {
        $env:APPDATA = $fixture
        Invoke-WindowsPlan $actions | Out-Null
    } finally { $env:APPDATA = $oldAppData }
    Assert-True ($calls.Count -eq 3) 'Missing apply calls'
    Assert-True ($calls[0][1] -eq 'install' -and $calls[0][3] -eq 'Git.Git') 'WinGet argument boundaries changed'
    Assert-True ($calls[1][1] -eq 'install' -and $calls[1][3] -eq 'opencode-ai') 'npm argument boundaries changed'
    function winget.exe { $global:LASTEXITCODE = -1978335189 }
    Invoke-WindowsPlan @($actions[0]) | Out-Null
    function winget.exe { $global:LASTEXITCODE = 99 }
    $failed = $false
    try { Invoke-WindowsPlan $actions | Out-Null } catch { $failed = $true }
    Assert-True $failed 'Package-manager errors must stop the run'
    function node.exe { $global:LASTEXITCODE = 0; 'v18.20.0' }
    $failed = $false
    try { Invoke-WindowsPlan @($actions[1]) | Out-Null } catch { $failed = $_.Exception.Message -like '*Node.js 22*' }
    Assert-True $failed 'Outdated Node must be rejected before installing npm tools'
    Write-Output 'PASS mocked Windows apply, exact arguments, already-installed status and failures'

    $source = Join-Path $repo '.config/alacritty/alacritty.toml'
    $destination = Join-Path $fixture 'config/alacritty.toml'
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) | Out-Null
    [IO.File]::WriteAllText($destination, 'original')
    $backups = Join-Path $fixture 'backups'
    Copy-ManagedFile $source $destination $true $backups | Out-Null
    Assert-True ((Get-Content -LiteralPath $destination -Raw) -like '*Consolas*') 'Windows font was not adapted'
    $backup = @(Get-ChildItem -LiteralPath $backups -File)
    Assert-True ($backup.Count -eq 1 -and (Get-Content -LiteralPath $backup[0].FullName -Raw) -eq 'original') 'Original config was not backed up'
    Write-Output 'PASS real configuration copy, Windows font and backups in a disposable directory'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
