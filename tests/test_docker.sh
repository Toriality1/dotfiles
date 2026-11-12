#!/usr/bin/env bash
# Real installs in disposable containers. Host images and /tmp logs are retained.
set -Eeuo pipefail
REPO=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

require_container() {
    [[ -f /.dockerenv && ${DOTFILES_SMOKE_CONTAINER:-} == yes ]] || {
        printf '%s\n' 'Internal test phases must run inside the disposable smoke container.' >&2
        exit 1
    }
}

desktop_smoke() {
    printf '\nSMOKE: desktop packages, Nerd Font and generated i3 configuration\n'
    # Browser sessions and systemd services need a VM; no display is exposed here.
    bash ./install.sh --non-interactive --yes --keep-unchecked --select i3,alacritty,flameshot,picom,pavucontrol
    bash -ic 'i3 --version && alacritty --version && QT_QPA_PLATFORM=offscreen flameshot --version && picom --version'
    i3 -C -c "$HOME/.config/i3/config"
    local font_match
    font_match=$(fc-match 'JetBrainsMono Nerd Font')
    printf '%s\n' "$font_match"
    [[ $font_match == *JetBrainsMono* ]]
}

android_smoke() {
    local selections=android-studio
    [[ ${DOTFILES_SMOKE_MODE:-} != android-full ]] || selections+=,android-emulator,android-ndk
    printf '\nSMOKE: Android Studio and SDK (%s)\n' "$selections"
    local -a android_choices=(--non-interactive --yes --keep-unchecked --select "$selections" --set android_accept_licenses=on)
    bash ./install.sh "${android_choices[@]}"
    bash -ic '
        set -e
        sdkmanager --version
        adb version
        test -x "$(command -v android-studio)"
        test -f "$ANDROID_HOME/platforms/android-36/android.jar"
        test -x "$ANDROID_HOME/build-tools/36.0.0/aapt2"
        "$ANDROID_HOME/build-tools/36.0.0/aapt2" version
        "$HOME/.local/share/android/studio/jbr/bin/java" --version
        # The JVM loads these bundled libraries itself; ldd needs their paths
        # explicitly when inspecting an individual AWT library.
        dependencies=$(LD_LIBRARY_PATH="$HOME/.local/share/android/studio/jbr/lib/server:$HOME/.local/share/android/studio/jbr/lib" ldd "$HOME/.local/share/android/studio/jbr/lib/libawt_xawt.so")
        printf "%s\n" "$dependencies"
        [[ $dependencies != *"not found"* ]]
    '
    if [[ ${DOTFILES_SMOKE_MODE:-} == android-full ]]; then
        bash -ic '
            set -e
            emulator -version
            avdmanager list avd
            test -f "$ANDROID_HOME/ndk/27.1.12297006/source.properties"
            test -f "$HOME/.android/avd/dotfiles-api36.avd/config.ini"
            for library in "$ANDROID_HOME"/emulator/qemu/linux-x86_64/qemu-system-x86_64 "$ANDROID_HOME"/emulator/lib64/qt/plugins/platforms/*xcb*.so; do
                [[ -f $library ]] || continue
                dependencies=$(LD_LIBRARY_PATH="$ANDROID_HOME/emulator/lib64:$ANDROID_HOME/emulator/lib64/qt/lib" ldd "$library")
                printf "%s\n" "$dependencies"
                [[ $dependencies != *"not found"* ]]
            done
        '
        printf '\n# preserve user device settings\n' >>"$HOME/.android/avd/dotfiles-api36.avd/config.ini"
    fi
    find "$HOME/.local/share/dotfiles/receipts" -type f -print0 | sort -z | xargs -0 sha256sum >/tmp/android-receipts-before
    bash ./install.sh "${android_choices[@]}"
    find "$HOME/.local/share/dotfiles/receipts" -type f -print0 | sort -z | xargs -0 sha256sum >/tmp/android-receipts-after
    cmp /tmp/android-receipts-before /tmp/android-receipts-after
    if [[ $BACKEND == apt && ${DOTFILES_SMOKE_MODE:-} == android-full ]]; then
        bash ./install.sh --non-interactive --yes --remove-unchecked --preset empty
        [[ ! -f $HOME/.local/share/android/studio/bin/studio.sh && ! -e $HOME/.local/share/android/sdk/cmdline-tools/latest ]]
        grep -R -l --fixed-strings 'preserve user device settings' "$HOME/.local/state/dotfiles/backups" --include=config.ini
    fi
}

if [[ ${1:-} == --inside ]]; then
    require_container
    ((EUID == 0)) || exit 1
    # The image is the only system being changed. Never mount a Docker socket.
    if command -v apt-get >/dev/null; then
        printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d
        chmod +x /usr/sbin/policy-rc.d
        apt-get update
        env DEBIAN_FRONTEND=noninteractive apt-get --yes --no-install-recommends install sudo ca-certificates
    elif command -v dnf >/dev/null; then
        dnf --assumeyes install sudo shadow-utils ca-certificates
    elif command -v pacman >/dev/null; then
        pacman --sync --refresh --sysupgrade --needed --noconfirm sudo shadow ca-certificates
    else
        printf '%s\n' 'Unsupported smoke-test image.' >&2
        exit 1
    fi
    useradd --uid 12345 --create-home --user-group --shell /bin/bash installer
    printf 'installer ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/installer-smoke
    chmod 440 /etc/sudoers.d/installer-smoke
    cp -a /snapshot /home/installer/dotfiles
    chown -R installer:installer /home/installer/dotfiles
    exec sudo --preserve-env=DOTFILES_SMOKE_CONTAINER,DOTFILES_SMOKE_MODE,DOTFILES_DOWNLOAD_CACHE -H -u installer bash /home/installer/dotfiles/tests/test_docker.sh --user
fi

if [[ ${1:-} == --user ]]; then
    require_container
    ((EUID != 0)) || exit 1
    cd "$REPO"
    printf '\nSMOKE: native UI bootstrap\n'
    installer_root=$REPO
    source "$REPO/installer/main.sh"
    load_catalog
    parse_arguments --non-interactive --keep-unchecked
    detect_platform
    select_backend
    backend_bootstrap_ui
    command -v whiptail || command -v dialog
    if [[ ${DOTFILES_SMOKE_MODE:-} == android || ${DOTFILES_SMOKE_MODE:-} == android-full ]]; then
        android_smoke
        printf '\nSMOKE PASS: %s; Android Studio, SDK, environment, package reuse and receipts\n' "$PLATFORM"
        exit 0
    fi
    if [[ ${DOTFILES_SMOKE_MODE:-all} == desktop ]]; then
        desktop_smoke
        printf '\nSMOKE PASS: %s; desktop packages, fonts and i3 config\n' "$PLATFORM"
        exit 0
    fi
    mkdir -p "$HOME/.config/tmux"
    printf 'original smoke tmux config\n' >"$HOME/.config/tmux/tmux.conf"
    choices=(--non-interactive --yes --keep-unchecked --preset dev --select 'go,gemini-cli,bun,android-tools,java'
        --set 'git_name=Installer Test' --set git_email=installer@example.invalid)
    printf '\nSMOKE: first real install on %s\n' "$PLATFORM"
    bash ./install.sh "${choices[@]}"
    printf '\nSMOKE: executable and fresh-shell verification\n'
    bash -ic '
        set -e
        for smoke_tool in git gh tmux zsh nvim node npm pnpm claude codex opencode gemini bun go composer python3 ssh rsync ffmpeg adb java docker; do
            command -v "$smoke_tool"
        done
        nvim --headless --clean +quit
        node --version
        npm --version
        pnpm --version
        claude --version
        codex --version
        opencode --version
        gemini --version
        bun --version
        go version
        composer --version
        python3 -m venv /tmp/installer-python-venv
        docker --version
        docker compose version
        docker buildx version
        adb version
        java --version
        test "$(git config user.name)" = "Installer Test"
    '
    zsh -ic 'command -v node && command -v claude && command -v nvim && node --version'
    rg --hidden --files-with-matches --fixed-strings 'original smoke tmux config' "$HOME/.local/state/dotfiles/backups"
    find "$HOME/.local/share/dotfiles/receipts" -type f -print0 | sort -z | xargs -0 sha256sum >/tmp/receipts-before
    printf '\nSMOKE: repeated real install\n'
    bash ./install.sh "${choices[@]}"
    find "$HOME/.local/share/dotfiles/receipts" -type f -print0 | sort -z | xargs -0 sha256sum >/tmp/receipts-after
    cmp /tmp/receipts-before /tmp/receipts-after
    cmp .config/tmux/tmux.conf "$HOME/.config/tmux/tmux.conf"
    if [[ $BACKEND == apt ]]; then
        printf '\nSMOKE: managed Go/Bun removal while retaining selected tools\n'
        bash ./install.sh --non-interactive --yes --remove-unchecked --preset dev --select gemini-cli,android-tools,java
        [[ ! -e $HOME/.local/bin/go && ! -L $HOME/.local/bin/go ]]
        [[ ! -e $HOME/.local/share/dotfiles/receipts/bun.receipt ]]
        bash -ic 'node --version && codex --version && ! command -v bun'
    fi
    desktop_smoke
    printf '\nSMOKE PASS: %s; install, runtime checks, shell setup, backups and repeat install\n' "$PLATFORM"
    exit 0
fi

if [[ ${1:-} == --help ]]; then
    printf '%s\n' 'Usage: bash tests/test_docker.sh [--desktop-only|--android-only|--android-full] [IMAGE ...]' \
        'Runs real networked installs as a normal user in each disposable Docker container.' \
        'Containers are memory/CPU limited, expose no ports, and are always removed.' \
        'Only an allowlisted source snapshot is mounted read-only. Images/logs are retained.'
    exit 0
fi
command -v docker >/dev/null
command -v timeout >/dev/null
REPORT=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-smoke.XXXXXXXX")
mkdir "$REPORT/snapshot"
container=''
cleanup_smoke() {
    [[ -z $container ]] || docker rm --force "$container" >/dev/null 2>&1 || true
    rm -rf -- "$REPORT/snapshot"
}
trap cleanup_smoke EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Never mount this repository's home directory, credentials, projects or .git.
while IFS= read -r -d '' file; do
    [[ -f $REPO/$file && ! -L $REPO/$file ]] || continue
    (cd "$REPO"; cp --parents -p -- "$file" "$REPORT/snapshot")
done < <(git -C "$REPO" ls-files -z --cached --others --exclude-standard -- install.sh .install.sh .bashrc .zshenv \
    .config/nvim .config/tmux .config/zsh .config/i3 .config/alacritty .config/rofi .config/dunst installer tests)
printf 'Smoke-test logs: %s\n' "$REPORT"
mode=all
case ${1:-} in
    --desktop-only) mode=desktop; shift ;;
    --android-only) mode=android; shift ;;
    --android-full) mode=android-full; shift ;;
esac
cache_mount=()
if [[ -n ${DOTFILES_DOWNLOAD_CACHE:-} ]]; then
    cache_mount=(--env DOTFILES_DOWNLOAD_CACHE=/download-cache --mount "type=bind,src=$DOTFILES_DOWNLOAD_CACHE,dst=/download-cache,readonly")
fi
images=("$@")
((${#images[@]})) || images=(ubuntu:24.04 debian:13 fedora:latest archlinux:base)
failures=0
for image in "${images[@]}"; do
    [[ $image =~ ^[a-zA-Z0-9][a-zA-Z0-9./:@_-]*$ ]] || { printf 'Invalid image: %s\n' "$image" >&2; exit 1; }
    slug=${image//[^a-zA-Z0-9]/-}
    container=dotfiles-smoke-$slug-$$
    printf '\nTesting %s (%s)\n' "$image" "$container"
    if timeout --foreground 25m docker run --rm --name "$container" --label dotfiles.installer-smoke=true \
        --memory 3g --memory-swap 3g --cpus 2 --pids-limit 1024 \
        --env DOTFILES_SMOKE_CONTAINER=yes --env "DOTFILES_SMOKE_MODE=$mode" --mount "type=bind,src=$REPORT/snapshot,dst=/snapshot,readonly" \
        "${cache_mount[@]}" \
        "$image" bash /snapshot/tests/test_docker.sh --inside >"$REPORT/$slug.log" 2>&1; then
        printf 'PASS %s\n' "$image"
        tail -n 8 "$REPORT/$slug.log"
    else
        failures=$((failures + 1))
        printf 'FAIL %s (see %s/%s.log)\n' "$image" "$REPORT" "$slug"
        tail -n 60 "$REPORT/$slug.log"
    fi
    docker rm --force "$container" >/dev/null 2>&1 || true
    container=''
done
printf '\nFinished: %s failed. Logs: %s\n' "$failures" "$REPORT"
((failures == 0))
