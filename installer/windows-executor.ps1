# Apply only a reviewed Windows plan. External commands are mockable for tests.
function Update-ProcessPath {
    $paths = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:Path)
    $env:Path = ($paths | Where-Object { $_ }) -join ';'
}
function Ensure-NpmPath([string]$Path) {
    Ensure-UserPath $Path
}
function Ensure-UserPath([string]$Path) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($Path -notin @($userPath -split ';')) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath, $Path | Where-Object { $_ }) -join ';'), 'User')
    }
    Update-ProcessPath
}
function Copy-ManagedFile([string]$Source, [string]$Destination, [bool]$Alacritty, [string]$BackupRoot) {
    if (Test-Path -LiteralPath $Destination -PathType Container) { throw "Expected a file: $Destination" }
    if (Test-Path -LiteralPath $Destination) {
        $backup = Join-Path $BackupRoot ([Guid]::NewGuid().ToString() + '-' + [IO.Path]::GetFileName($Destination))
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        Copy-Item -LiteralPath $Destination -Destination $backup
        Write-Output "Backup: $Destination -> $backup"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    if ($Alacritty) {
        $content = (Get-Content -LiteralPath $Source -Raw).Replace('JetBrainsMono Nerd Font', 'Consolas')
        [IO.File]::WriteAllText($Destination, $content, (New-Object Text.UTF8Encoding $false))
    } else { Copy-Item -LiteralPath $Source -Destination $Destination -Force }
}
function Invoke-WindowsPlan($Actions) {
    $backupRoot = Join-Path $env:LOCALAPPDATA ('dotfiles/backups/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))
    foreach ($action in $Actions) {
        Write-Output "`n$($action.Label)"
        switch ($action.Kind) {
            'winget' {
                $arguments = @($action.Arguments)
                & winget.exe @arguments
                # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE: installed/no upgrade.
                if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "WinGet failed with exit code $LASTEXITCODE" }
                Update-ProcessPath
            }
            'npm' {
                Update-ProcessPath
                if (!(Get-Command node.exe -ErrorAction SilentlyContinue)) { throw 'node.exe is missing. Install Node.js LTS and retry.' }
                $nodeVersion = & node.exe --version
                if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 22) {
                    throw 'npm tools require Node.js 22 or newer. Upgrade Node.js LTS and retry.'
                }
                if (!(Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'npm.cmd is missing after Node installation. Open a new PowerShell session and retry.' }
                $arguments = @($action.Arguments | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
                & npm.cmd @arguments
                if ($LASTEXITCODE -ne 0) { throw "npm failed with exit code $LASTEXITCODE" }
                Ensure-NpmPath (Join-Path $env:APPDATA 'npm')
            }
            { $_ -in @('copy', 'alacritty') } {
                $destination = [Environment]::ExpandEnvironmentVariables($action.Arguments[1])
                Copy-ManagedFile $action.Arguments[0] $destination ($action.Kind -eq 'alacritty') $backupRoot
            }
            'android' {
                . (Join-Path $PSScriptRoot 'android.ps1')
                Install-AndroidSdk $action.Arguments
            }
            default { throw "Unknown action: $($action.Kind)" }
        }
    }
    Write-Output "`nCompleted. Open a new terminal to pick up PATH changes."
}
