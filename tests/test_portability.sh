#!/usr/bin/env bash
# Read-only target planning plus mocked native package-manager operations.
set -Eeuo pipefail
REPO=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$FIXTURE"' EXIT
contains() { [[ $1 == *"$2"* ]] || { printf 'Missing: %s\n' "$2" >&2; exit 1; }; }
for target in debian ubuntu fedora arch; do
    for preset in empty cli desktop server ai dev mobile; do
        output=$(bash "$REPO/install.sh" --non-interactive --dry-run --keep-unchecked --target "$target" --preset "$preset" --verbose)
        contains "$output" 'Package removals (0)'
        [[ $preset != empty ]] || continue
        case $preset in cli | desktop | ai | dev) contains "$output" 'nvim-linux-x86_64.tar.gz' ;; esac
        case $target in
            debian | ubuntu) contains "$output" 'apt-get' ;;
            fedora) contains "$output" 'dnf --assumeyes install'; [[ $output != *apt-get* ]] ;;
            arch) contains "$output" 'pacman --sync --refresh --sysupgrade'; [[ $output != *apt-get* ]] ;;
        esac
        if [[ $preset == dev ]]; then
            contains "$output" '@anthropic-ai/claude-code'
            contains "$output" '@openai/codex'
            contains "$output" 'composer'
        fi
        if [[ $preset == mobile ]]; then
            contains "$output" 'commandlinetools-linux-'
            contains "$output" 'android-studio-rabbit1-linux.tar.gz'
            contains "$output" 'android_sdk: 36 36.0.0 off 27.1.12297006 dotfiles-api36'
        fi
    done
done
output=$(bash "$REPO/install.sh" --non-interactive --dry-run --target ubuntu --select docker,tailscale,chromium --verbose)
contains "$output" 'https://download.docker.com/linux/ubuntu'
contains "$output" 'https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg'
contains "$output" 'chromium-browser'
for target in fedora arch; do
    if bash "$REPO/install.sh" --non-interactive --dry-run --target "$target" --select git --remove-unchecked >"$FIXTURE/out" 2>&1; then exit 1; fi
    contains "$(<"$FIXTURE/out")" 'APT-only'
    if bash "$REPO/install.sh" --non-interactive --dry-run --target "$target" --select spotify >"$FIXTURE/out" 2>&1; then exit 1; fi
    contains "$(<"$FIXTURE/out")" 'unavailable'
done
if bash "$REPO/install.sh" --non-interactive --dry-run --target debian --select claude-code --set node_version=20 >"$FIXTURE/out" 2>&1; then exit 1; fi
contains "$(<"$FIXTURE/out")" 'Node 22 or newer'
printf 'PASS portable presets, Ubuntu sources, unavailable software and cleanup guards\n'

installer_root=$REPO
source "$REPO/installer/main.sh"
for target in fedora arch; do
    load_catalog
    parse_arguments --non-interactive --dry-run --target "$target" --select python,android-tools,docker
    detect_platform
    select_backend
    PREVIEW_TARGET=false
    rpm() { printf 'python3\nandroid-tools\ndocker-ce\n'; }
    pacman() { printf 'python\nandroid-tools\ndocker\n'; }
    backend_scan_installed
    component_installed python3
    component_installed adb
    component_installed fastboot
    if component_installed tmux; then exit 1; fi
    PREVIEW_TARGET=true
    merge_choices
    build_plan
    # Canonical components that map to the same native package are deduplicated.
    android_count=0
    for ((i=0; i<${#ACTION_KIND[@]}; i++)); do
        [[ ${ACTION_KIND[$i]} == root_command ]] || continue
        declare -n action="ACTION_ARGS_$i"
        for arg in "${action[@]}"; do [[ $arg != android-tools ]] || android_count=$((android_count+1)); done
    done
    [[ $android_count == 1 ]]
    unset -n action
    run_privileged() { printf '%s\n' "$*" >>"$FIXTURE/bootstrap"; }
    backend_bootstrap_ui
    contains "$(<"$FIXTURE/bootstrap")" 'dialog'
    unset -f rpm pacman run_privileged
done
printf 'PASS installed-package discovery, native package deduplication and UI bootstrap\n'

# AI tools are tied to the Node version in their receipt. Uninstall must use it.
load_catalog
parse_arguments --non-interactive --dry-run --target debian
HOME=$FIXTURE/home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
detect_platform
select_backend
backend_scan_installed
mkdir -p "$DATA_DIR/fnm"
export RUNTIME_LOG=$FIXTURE/runtime
cat >"$DATA_DIR/fnm/fnm" <<'STUB'
#!/usr/bin/env bash
if [[ $* == *'node --version' ]]; then printf 'v22.1.0\n'
else printf '%s\n' "$*" >>"$RUNTIME_LOG"; fi
STUB
chmod +x "$DATA_DIR/fnm/fnm"
BACKUP_DIR=$FIXTURE/backups
declare -A BACKED_UP=() BACKUP_LOCATIONS=()
declare -a CLAIM_IDS=() CLAIM_PATHS=()
trap 'cleanup; rm -rf -- "$FIXTURE"' EXIT
for id in claude-code codex opencode gemini-cli bun; do
    record_receipt "$id" 22
    read_receipt "$id"
    [[ ${RECEIPT_VERSIONS[0]} == v22.1.0 ]]
    remove_managed "$id"
    [[ -f ${BACKUP_LOCATIONS[$RECEIPT_DIR/$id.receipt]} ]]
    contains "$(<"$RUNTIME_LOG")" "exec --using v22.1.0 npm uninstall --global $(npm_package_for "$id")"
done
printf 'PASS AI tool receipts and removal through their recorded Node runtime\n'
