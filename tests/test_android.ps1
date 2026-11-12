# Mocked native Windows SDK provisioning. No registry or package changes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-android-tests-' + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $fixture | Out-Null
function Assert-True($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
$oldUser = $env:USERPROFILE; $oldCache = $env:DOTFILES_DOWNLOAD_CACHE
$oldAndroidUser = $env:ANDROID_USER_HOME; $oldAndroidAvd = $env:ANDROID_AVD_HOME
try {
    $env:USERPROFILE = $fixture; $env:ANDROID_USER_HOME = $null; $env:ANDROID_AVD_HOME = $null
    $plan = (& (Join-Path $repo 'install.ps1') -NonInteractive -DryRun -Select android-studio,android-emulator,android-ndk -AcceptAndroidLicenses) -join "`n"
    Assert-True ($plan -like '*Google.AndroidStudio*' -and $plan -like '*Temurin.21.JDK*' -and $plan -like '*android:*') 'Missing Android actions/dependencies'
    Assert-True ($plan -like '*27.1.12297006*' -and $plan -like '*dotfiles-api36*') 'Missing Android SDK options'
    . (Join-Path $repo 'installer/android.ps1')
    function Update-ProcessPath { }
    function Set-AndroidEnvironment([string]$Root) { $script:publishedRoot = $Root }
    $calls = New-Object 'System.Collections.Generic.List[object]'
    function Invoke-AndroidManager([string]$Manager, [string[]]$ManagerArguments, [bool]$Accept, [bool]$Headless) {
        $calls.Add($ManagerArguments)
        Assert-True ($Accept -and $Headless) 'License/headless flags were lost'
        $root = $ManagerArguments[0].Substring('--sdk_root='.Length)
        foreach ($package in $ManagerArguments[1..($ManagerArguments.Count - 1)]) {
            $directory = Join-Path $root ($package.Replace(';', '/'))
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $directory 'source.properties'), $package)
        }
    }
    $root = Join-Path $fixture 'SDK with spaces'
    New-Item -ItemType Directory -Path (Join-Path $root 'cmdline-tools/latest/bin') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'cmdline-tools/latest/bin/sdkmanager.bat'), '')
    New-Item -ItemType Directory -Path (Join-Path $root 'platform-tools') | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'platform-tools/source.properties'), 'manual platform tools')
    $device = Join-Path $fixture '.android/avd/keep_device.avd'
    New-Item -ItemType Directory -Path $device -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $device 'config.ini'), 'manual device')
    $arguments = @($root, '36', '36.0.0', 'on', '27.1.12297006', 'keep_device', 'on')
    Install-AndroidSdk $arguments | Out-Null
    Assert-True ($calls.Count -eq 1 -and $calls[0][0] -eq "--sdk_root=$root") 'SDK root argument boundaries changed'
    Assert-True ($calls[0] -contains 'ndk;27.1.12297006' -and $calls[0] -contains 'system-images;android-36;google_apis;x86_64') 'Missing optional SDK packages'
    Assert-True ($calls[0] -notcontains 'platform-tools') 'Manual platform tools were overwritten'
    Assert-True ($publishedRoot -eq $root) 'SDK environment was not configured'
    Install-AndroidSdk $arguments | Out-Null
    Assert-True ($calls.Count -eq 1) 'Installed packages were downloaded again'
    Assert-True ((Get-Content -LiteralPath (Join-Path $device 'config.ini') -Raw) -eq 'manual device') 'Existing AVD was overwritten'
    $created = 0
    function New-AndroidVirtualDevice([string]$Manager, [string]$Name, [string]$Image, [string]$Device) {
        $script:created++
        Assert-True ($env:ANDROID_HOME -eq $root -and $Image -eq 'system-images;android-36;google_apis;x86_64') 'AVD SDK/image environment was lost'
        Assert-True ($Name -eq 'new_device' -and $Device -like '*new_device.avd') 'AVD name/path boundaries changed'
        New-Item -ItemType Directory -Path $Device | Out-Null
        [IO.File]::WriteAllText((Join-Path $Device 'config.ini'), 'new device')
        [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME "$Name.ini"), 'new device index')
    }
    $arguments[5] = 'new_device'
    Install-AndroidSdk $arguments | Out-Null
    Install-AndroidSdk $arguments | Out-Null
    Assert-True ($created -eq 1 -and $calls.Count -eq 1) 'Fresh AVD was not created once and reused'
    Write-Output 'PASS Windows Android plans, SDK packages, NDK/emulator options, path handling and existing-install preservation'

    $env:DOTFILES_DOWNLOAD_CACHE = Join-Path $fixture 'cache'
    New-Item -ItemType Directory -Path $env:DOTFILES_DOWNLOAD_CACHE | Out-Null
    $file = Join-Path $fixture 'archive.data'
    [IO.File]::WriteAllText($file, 'verified artifact')
    $checksum = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $cached = Join-Path $env:DOTFILES_DOWNLOAD_CACHE $checksum
    Copy-Item -LiteralPath $file -Destination $cached
    $output = Join-Path $fixture 'downloaded.data'
    Get-AndroidDownload 'https://example.invalid/android.zip' $checksum $output
    [IO.File]::WriteAllText($cached, 'corrupt')
    $failed = $false
    try { Get-AndroidDownload 'https://example.invalid/android.zip' $checksum $output } catch { $failed = $_.Exception.Message -like '*SHA-256 mismatch*' }
    Assert-True $failed 'Invalid Android download checksum was accepted'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = Join-Path $fixture 'unsafe.zip'
    $zip = [IO.Compression.ZipFile]::Open($archive, [IO.Compression.ZipArchiveMode]::Create)
    try { $zip.CreateEntry('../outside') | Out-Null } finally { $zip.Dispose() }
    $failed = $false
    try { Expand-AndroidTools $archive (Join-Path $fixture 'expanded') } catch { $failed = $_.Exception.Message -like '*Unsafe Android archive path*' }
    Assert-True $failed 'Unsafe Android ZIP path was accepted'
    Write-Output 'PASS Windows Android download checksums and ZIP path validation'
} finally {
    $env:USERPROFILE = $oldUser; $env:DOTFILES_DOWNLOAD_CACHE = $oldCache
    $env:ANDROID_USER_HOME = $oldAndroidUser; $env:ANDROID_AVD_HOME = $oldAndroidAvd
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
