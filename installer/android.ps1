# Native Windows SDK provisioning; package installation and AVD creation stay in
# the current user's directories. Studio itself is installed through WinGet.
function Get-AndroidDownload([string]$Url, [string]$Checksum, [string]$Destination) {
    $cached = $null
    if ($env:DOTFILES_DOWNLOAD_CACHE) { $cached = Join-Path $env:DOTFILES_DOWNLOAD_CACHE $Checksum }
    if ($cached -and (Test-Path -LiteralPath $cached -PathType Leaf)) { Copy-Item -LiteralPath $cached -Destination $Destination }
    else {
        $protocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = $protocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination
        } finally { [Net.ServicePointManager]::SecurityProtocol = $protocol }
    }
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Checksum) { throw "SHA-256 mismatch for $Url" }
}

function Expand-AndroidTools([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.StartsWith('/') -or $name.Contains(':') -or ($name.Split('/') -contains '..')) { throw "Unsafe Android archive path: $name" }
            $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($mode -notin @(0, 0x8000, 0x4000)) { throw 'Android archive contains a link or special file.' }
        }
    } finally { $zip.Dispose() }
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination
}

function Invoke-AndroidManager([string]$Manager, [string[]]$ManagerArguments, [bool]$Accept, [bool]$Headless) {
    if ($Accept) { @('y') * 100 | & $Manager @ManagerArguments }
    elseif ($Headless) { $null | & $Manager @ManagerArguments }
    else { & $Manager @ManagerArguments }
    if ($LASTEXITCODE -ne 0) { throw "sdkmanager failed with exit code $LASTEXITCODE" }
}

function Set-AndroidEnvironment([string]$Root) {
    [Environment]::SetEnvironmentVariable('ANDROID_HOME', $Root, 'User')
    $env:ANDROID_HOME = $Root
    foreach ($relative in @('cmdline-tools/latest/bin', 'platform-tools', 'emulator')) {
        $directory = Join-Path $Root $relative
        if (Test-Path -LiteralPath $directory -PathType Container) { Ensure-UserPath $directory }
    }
}

function New-AndroidVirtualDevice([string]$Manager, [string]$Name, [string]$Image, [string]$Device) {
    'no' | & $Manager create avd --name $Name --package $Image --path $Device
    if ($LASTEXITCODE -ne 0) { throw 'Android virtual device creation failed.' }
}

function Install-AndroidSdk([string[]]$PlanArguments) {
    $root = [Environment]::ExpandEnvironmentVariables($PlanArguments[0])
    $api = $PlanArguments[1]; $build = $PlanArguments[2]; $accept = $PlanArguments[3] -eq 'on'
    $ndk = $PlanArguments[4]; $avd = $PlanArguments[5]; $headless = $PlanArguments[6] -eq 'on'
    if (![IO.Path]::IsPathRooted($root)) { throw 'ANDROID_HOME must be an absolute path.' }
    Update-ProcessPath
    $metadata = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'android.conf')) {
        if (!$line -or $line.StartsWith('#')) { continue }
        $fields = $line.Split('|'); $metadata[$fields[0]] = $fields[1]
    }
    $manager = Join-Path $root 'cmdline-tools/latest/bin/sdkmanager.bat'
    if (!(Test-Path -LiteralPath $manager -PathType Leaf)) {
        $latest = Join-Path $root 'cmdline-tools/latest'
        if (Test-Path -LiteralPath $latest) { throw "Incomplete Android command-line tools: $latest" }
        $scratch = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-android-' + [Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $scratch | Out-Null
        try {
            $archive = Join-Path $scratch 'tools.zip'
            Get-AndroidDownload "https://dl.google.com/android/repository/commandlinetools-win-$($metadata.cmdline_build)_latest.zip" $metadata.cmdline_windows_sha256 $archive
            $expanded = Join-Path $scratch 'expanded'
            Expand-AndroidTools $archive $expanded
            if (!(Test-Path -LiteralPath (Join-Path $expanded 'cmdline-tools/bin/sdkmanager.bat'))) { throw 'Android archive is missing sdkmanager.bat.' }
            New-Item -ItemType Directory -Path (Split-Path -Parent $latest) -Force | Out-Null
            Move-Item -LiteralPath (Join-Path $expanded 'cmdline-tools') -Destination $latest
        } finally { Remove-Item -LiteralPath $scratch -Recurse -Force }
    }
    $packages = New-Object 'System.Collections.Generic.List[string]'
    $paths = New-Object 'System.Collections.Generic.List[string]'
    $packages.Add('platform-tools'); $paths.Add((Join-Path $root 'platform-tools'))
    $packages.Add("platforms;android-$api"); $paths.Add((Join-Path $root "platforms/android-$api"))
    $packages.Add("build-tools;$build"); $paths.Add((Join-Path $root "build-tools/$build"))
    if ($ndk) { $packages.Add("ndk;$ndk"); $paths.Add((Join-Path $root "ndk/$ndk")) }
    $image = "system-images;android-$api;google_apis;x86_64"
    if ($avd) {
        $packages.Add('emulator'); $paths.Add((Join-Path $root 'emulator'))
        $packages.Add($image); $paths.Add((Join-Path $root "system-images/android-$api/google_apis/x86_64"))
    }
    $missing = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $packages.Count; $i++) {
        if (!(Test-Path -LiteralPath (Join-Path $paths[$i] 'source.properties'))) {
            if (Test-Path -LiteralPath $paths[$i]) { throw "Incomplete Android package directory: $($paths[$i])" }
            $missing.Add($packages[$i])
        } else { Write-Output "Keeping Android package $($packages[$i])" }
    }
    if ($missing.Count) {
        Invoke-AndroidManager $manager (@("--sdk_root=$root") + $missing.ToArray()) $accept $headless
        foreach ($directory in $paths) {
            if (!(Test-Path -LiteralPath (Join-Path $directory 'source.properties'))) { throw "Android package did not install: $directory. Review required SDK licenses." }
        }
    }
    if ($avd) {
        $userDirectory = Join-Path $env:USERPROFILE '.android'
        if ($env:ANDROID_USER_HOME) { $userDirectory = $env:ANDROID_USER_HOME }
        $avdDirectory = Join-Path $userDirectory 'avd'
        if ($env:ANDROID_AVD_HOME) { $avdDirectory = $env:ANDROID_AVD_HOME }
        New-Item -ItemType Directory -Path $avdDirectory -Force | Out-Null
        $device = Join-Path $avdDirectory "$avd.avd"
        if ((Test-Path -LiteralPath $device) -or (Test-Path -LiteralPath (Join-Path $avdDirectory "$avd.ini"))) { Write-Output "Keeping existing Android virtual device $avd" }
        else {
            $previousUser = $env:ANDROID_USER_HOME; $previousAvd = $env:ANDROID_AVD_HOME; $previousHome = $env:ANDROID_HOME
            try {
                $env:ANDROID_USER_HOME = $userDirectory; $env:ANDROID_AVD_HOME = $avdDirectory; $env:ANDROID_HOME = $root
                $avdManager = Join-Path $root 'cmdline-tools/latest/bin/avdmanager.bat'
                New-AndroidVirtualDevice $avdManager $avd $image $device
                if (!(Test-Path -LiteralPath (Join-Path $device 'config.ini')) -or !(Test-Path -LiteralPath (Join-Path $avdDirectory "$avd.ini"))) { throw 'Android virtual device creation did not complete.' }
            } finally { $env:ANDROID_USER_HOME = $previousUser; $env:ANDROID_AVD_HOME = $previousAvd; $env:ANDROID_HOME = $previousHome }
        }
    }
    Set-AndroidEnvironment $root
    Write-Output "Android SDK ready at $root. Emulators have not been started."
}
