# Dotfiles

Personal Bash, Zsh, Neovim, Tmux, i3, Alacritty, Rofi and Dunst configurations, with a software installer for Debian, Ubuntu, Fedora, Arch and native Windows.

```sh
./install.sh
```

Linux uses Bash 4.4+ and a **whiptail/dialog** checklist. It reuses either tool or installs the UI through the native package manager. The installer needs no Python, pip or virtual environment. `.install.sh` remains a compatible Linux entry point. Git Bash/MSYS/Cygwin `install.sh` forwards to native PowerShell; WSL uses the Linux backend.

Select complete tools: **Docker** includes Engine, CLI, Compose, Buildx and Containerd; **Node.js** includes fnm and pnpm; **Python** includes pip and virtual environments; **virtual machines** includes QEMU/KVM, libvirt and virt-manager. Related packages and shared dependencies are handled automatically.

The catalog also includes frequently used **Claude Code, Codex CLI, OpenCode, Gemini CLI, Composer, SSH, Rsync, MariaDB client, FFmpeg, Blender, Chrome, Deskflow and VNC**, plus Java, Android Studio, SDK, NDK and emulator setup. AI tools on Linux include a user-owned Node runtime automatically; their npm installations are tracked for removal. Existing native/manual AI installations are detected and retained if no installer receipt exists. The `ai` preset contains the terminal/AI stack; `dev` adds Composer, Python, containers and other development tools. No account tokens, SSH keys, databases, containers or project files are copied.

Installed tools start checked. Use one software checklist, edit settings for selected tools, then review changes. Matching dotfiles are applied by default, package indexes refresh when needed, and related services are managed together. Versions and service overrides live under **Advanced**. Keyboard/display defaults are left alone unless configured. Authentication, login-shell changes, system upgrades and privileged group membership remain optional.

**On Debian/Ubuntu, unchecked software is removed by default if installed.** Change **Remove unchecked** in the main menu, or pass `--keep-unchecked` to make installation additive. A preset replaces the initial software selection. Required shared components are retained even if another bundle that uses them is unchecked. Fedora, Arch and Windows keep unchecked software; automatic dependency-protected cleanup is currently APT-only. Explicit requests to remove unchecked software on Fedora/Arch fail before applying changes.

Cleanup covers the software in this catalog, not every package on the computer. It removes installed catalog packages, including packages installed outside this installer, and removes archive/clone/runtime installations recorded in its receipts. Manually unpacked tools without receipts are listed for manual removal. Personal configuration files and package configuration are retained; there is no purge or autoremove. Application data, containers, images and virtual machines are not deleted. The review names the installed packages and managed tools scheduled for removal. APT stops if removal would also uninstall software outside that plan.

## Preview and automation

```sh
./.install.sh --help
./.install.sh --list
./.install.sh --dry-run
./.install.sh --non-interactive --dry-run --preset desktop
./.install.sh --non-interactive --dry-run --select docker,node --keep-unchecked
```

Dry-run never installs the UI, downloads files, invokes sudo, writes backups or changes settings. Without a dialog tool it uses text menus. `--help` and `--list` also work without the UI. Use `--verbose` to see exact commands and generated content.

On APT, non-interactive choices describe the **complete desired software selection**; omitted catalog software is removed unless `--keep-unchecked` is supplied. Profiles are literal text, never executed:

```ini
install=git,tmux,docker
remove_unchecked=false
set.git_name=Your Name
set.git_email=you@example.com
set.docker_access=off
```

```sh
./.install.sh --non-interactive --dry-run --config machine.conf
./.install.sh --non-interactive --yes --config machine.conf
```

CLI `--select`, `--skip`, `--set`, `--service` and removal-policy flags override profile values. `--skip` unchecks a bundle, including one selected by a preset. `--list` shows software IDs and settings. Advanced `--service ID=auto|keep|enable|disable` controls related units together; automatic service setup is skipped without active systemd.

## Platforms and maintenance

Linux backends use **APT on Debian/Ubuntu**, **DNF on Fedora**, and **pacman on Arch**. Ubuntu derivatives exposing `UBUNTU_CODENAME` use the Ubuntu base repositories; Arch derivatives use pacman. Other distributions fail with a clear supported-platform message. Hardware virtualization is unavailable under WSL. Package availability depends on architecture, release and enabled distro repositories.

Arch package installation always includes a full system upgrade (`-Syu`) because partial upgrades are unsupported. Fedora uses its native FFmpeg build (`ffmpeg-free`). Docker/Tailscale use their vendor repositories on APT/Fedora and distro packages on Arch. Native package mappings live in `installer/backends/native.conf`. Some vendor applications are APT/Windows-only; unsupported choices are hidden in the Linux checklist, marked in `--list`, and rejected if explicitly selected. Deskflow requires Debian 13 or a supported Fedora/Arch repository. On Ubuntu, Chromium installs through the distribution's `chromium-browser` package (which may use Snap).

```sh
./.install.sh --non-interactive --dry-run --target debian --codename trixie --arch arm64 --preset cli
./install.sh --non-interactive --dry-run --target ubuntu --codename noble --preset dev
./install.sh --non-interactive --dry-run --target fedora --preset ai
./install.sh --non-interactive --dry-run --target arch --preset desktop
```

A target preview cannot inspect the future machine's installed packages, so removal is determined when running on that target.

`installer/catalog.conf` defines user-facing bundles; `components.conf` describes their internal components. `selection.sh` expands choices and computes cleanup, `planner.sh` builds the read-only plan, and `backends/` handles package managers and installed-package discovery. `ui.sh` provides the menus; `executor.sh` and `receipts.sh` apply changes and preserve backups.

Changed managed files and removed managed directories/links are backed up in `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/`. Runtime removal uses fnm/npm. Release archives are installed under `${XDG_DATA_HOME:-$HOME/.local/share}` with executables linked in `~/.local/bin`. Only allowlisted dotfiles are copied. i3 startup configuration is generated from selected tools and device settings; the checkout's machine-specific monitor file is not copied automatically.

A failed run stops at the failed action; earlier system changes are not automatically rolled back. Open a new session for shell/group changes. Runtime requirements are Bash 4.4+ and standard GNU/Linux utilities on a glibc-based distribution. Alpine/musl and macOS are not supported.

## Native Windows

Run from Windows PowerShell 5.1 or PowerShell 7 with [WinGet/App Installer](https://learn.microsoft.com/en-us/windows/package-manager/winget/). `-Help`, `-Catalog` and previews work without WinGet or WSL:

```powershell
.\install.ps1
.\install.ps1 -Catalog
.\install.ps1 -NonInteractive -DryRun -Preset ai
.\install.ps1 -NonInteractive -DryRun -Select git,node,codex,claude-code
.\install.ps1 -NonInteractive -Yes -Select git,node,codex,claude-code
.\install.ps1 -NonInteractive -DryRun -Select neovim,alacritty -Dotfiles
```

The Windows checklist starts from `cli` unless a preset or explicit selection is supplied. `-Select` adds choices, and `-Skip` overrides them. Presets skip Linux-only tools and report them; explicit unsupported choices fail. Windows-specific mappings are in `installer/windows.conf` and shown by `-Catalog`. There are no Linux profile, service or `--set` options on Windows.

Windows uses Node.js LTS from WinGet, pnpm/npm tools under `%APPDATA%/npm`, native Claude/Codex packages, and Docker Desktop. WinGet keeps existing packages with `--no-upgrade`; npm installs the current package release and requires Node 22+. Older existing Node installations must be upgraded before continuing. PATH refreshes between actions and npm's user directory is persisted. Installers may request UAC elevation. Docker requires working WSL2/virtualization. Android provisioning is described below.

Windows config deployment is optional with `-Dotfiles`: Neovim goes to `%LOCALAPPDATA%/nvim`, Alacritty to `%APPDATA%/alacritty`, and Alacritty uses Consolas. Existing files are backed up under `%LOCALAPPDATA%/dotfiles/backups`. Windows shell settings and Linux desktop configs are not copied. Use WSL for Tmux, Zsh and the Linux desktop/service workflow.

Installation references: [Claude Code](https://code.claude.com/docs/en/setup), [Codex CLI](https://developers.openai.com/codex/cli/), [OpenCode](https://opencode.ai/docs/), [WinGet install options](https://learn.microsoft.com/en-us/windows/package-manager/winget/install).

## Android development

Choose `android-studio` for Studio plus command-line tools, platform-tools, API 36 and build-tools 36.0.0. Add `android-emulator` for the emulator, a Google APIs x86_64 image and an AVD; add `android-ndk` for NDK 27.1.12297006. The `mobile` preset includes all three plus development tools. `android-sdk` installs the SDK alone; `android-tools` remains the smaller distro ADB/Fastboot bundle. Studio and emulators are never launched by the installer. These Android choices require x86-64 Linux or Windows.

```sh
./install.sh --non-interactive --dry-run --keep-unchecked --preset mobile
# After reviewing the SDK licenses:
./install.sh --non-interactive --yes --keep-unchecked --preset mobile --set android_accept_licenses=on
```

```powershell
.\install.ps1 -NonInteractive -DryRun -Preset mobile
.\install.ps1 -NonInteractive -Yes -Preset mobile -AcceptAndroidLicenses
```

Interactive installation prompts for the [Android SDK licenses](https://developer.android.com/studio#terms). Unattended installation requires the explicit acceptance option unless licenses already exist. Customize Linux with `--set android_api=36`, `android_build_tools=36.0.0`, `android_ndk_version=27.1.12297006` or `android_avd_name=dotfiles-api36`; Windows provides `-AndroidApi`, `-AndroidBuildTools`, `-AndroidNdkVersion` and `-AndroidAvdName`.

Linux installs Studio under `${XDG_DATA_HOME:-$HOME/.local/share}/android/studio` and the SDK under the neighboring `android/sdk` directory. Windows uses WinGet for Studio and `%LOCALAPPDATA%/Android/Sdk` for the SDK. An existing `ANDROID_HOME` overrides the SDK location; if `ANDROID_SDK_ROOT` is also set, both must match. Linux configures Bash/Zsh and an application launcher; Windows persists the user SDK environment and PATH. Open a new terminal afterward.

Existing SDK packages, command-line tools and AVDs are reused without overwriting them. Linux receipts track newly installed paths; managed removal moves these files and AVDs into backups, preserving preexisting SDK packages. Pinned Google command-line tools and the Linux Studio archive are SHA-256 checked; update pins in `installer/android.conf` when maintaining releases. Rerunning the installer does not upgrade existing Studio or SDK packages. Emulator acceleration requires [Linux KVM or Windows virtualization support](https://developer.android.com/studio/run/emulator-acceleration).

Provisioning follows Google's [sdkmanager](https://developer.android.com/tools/sdkmanager), [AVD management](https://developer.android.com/studio/run/managing-avds), and [Studio installation](https://developer.android.com/studio/install) documentation.

## Validation

```sh
bash tests/test_installer.sh
bash tests/test_portability.sh
bash tests/test_android.sh
pwsh -NoProfile -File tests/test_windows.ps1
pwsh -NoProfile -File tests/test_android.ps1
```

Tests use disposable files and mocked package-manager operations. Portability tests preview every preset on all four Linux backends. PowerShell tests cover Windows plans, argument passing, dependency order, package-manager failures and config backups; they run on Windows or a Linux PowerShell installation.

For real package installation tests using Docker:

```sh
bash tests/test_docker.sh
bash tests/test_docker.sh --desktop-only ubuntu:24.04
bash tests/test_docker.sh --android-full ubuntu:24.04
bash tests/test_docker.sh --android-only debian:13 fedora:latest archlinux:base
```

The Docker suite installs development/AI tools, Go, Java and Android device tools as a normal user, checks fresh Bash/Zsh sessions, repeats installation, verifies backups and receipts, tests managed removal on APT, and installs desktop packages/fonts with an i3 configuration check. Each container is limited to 3 GB RAM and two CPUs and is removed after its test, including failures and interruptions. Official images stay cached; logs stay in the printed temporary report directory. Only a read-only source snapshot is mounted, with credentials, projects and the Docker socket excluded. The Android modes additionally test Studio runtime libraries, real SDK/build tools, shell integration, reruns and receipts; `--android-full` also creates an AVD, installs the NDK and checks backed-up removal on APT. GUI sessions, emulator boot and systemd service startup require separate VM testing. Native Windows package installation has not been tested on a Windows host.

Real x86-64 installation checks passed on **Ubuntu 24.04, Debian 13, Fedora 44 and Arch Linux** on 2026-10-19. Ubuntu's development and desktop phases ran in separate fresh containers. These runs caught a Go archive inspection failure under the C locale; archive inspection now uses a fixed UTF-8 locale, with a regression test for Unicode filenames.

Android Studio/SDK installation, native runtime dependencies, fresh-shell commands, repeated installation and receipt stability also passed on all four distributions. Ubuntu additionally passed NDK installation, emulator image/AVD creation, emulator library checks and managed removal that preserved edited AVD settings in backups. These runs caught SDK discovery through an incorrectly placed command-line tools symlink and missing `cmp` on minimal Fedora/Arch images; tools now live inside the SDK and missing file-comparison utilities are installed automatically. Windows SDK provisioning passed mocked tests, and Google's real Windows tools ZIP passed extraction checks in PowerShell on Linux; native Windows execution and GUI/emulator boot remain unverified.
