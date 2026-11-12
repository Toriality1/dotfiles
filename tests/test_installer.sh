#!/usr/bin/env bash
# Shell-only regression tests. No real packages, settings, or user files are changed.
set -Eeuo pipefail
REPO=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/home" "$FIXTURE/bin"
export TEST_LOG=$FIXTURE/commands TEST_INSTALLED=$FIXTURE/installed
: >"$TEST_LOG"
cat >"$TEST_INSTALLED" <<'PACKAGES'
git|installed
gh|installed
curl|installed
wget|installed
btop|installed||dependency-helper (>= 1)
dependency-helper|installed||python3 (>= 3.11) | python3-venv (>= 3.11)
python3|installed
python3-pip|installed
python3-venv|installed
docker-ce|installed
docker-ce-cli|installed
containerd.io|installed
docker-buildx-plugin|installed
docker-compose-plugin|installed
unrelated-app|installed
nodejs|installed
npm|installed
golang-go|installed
golang-1.24-go|installed
neovim-runtime|installed
cups|config-files
PACKAGES
for tool in bash dirname cat uname id awk stty; do ln -s "$(command -v "$tool")" "$FIXTURE/bin/$tool"; done
cat >"$FIXTURE/bin/dpkg-query" <<'STUB'
#!/bin/bash
cat "$TEST_INSTALLED"
STUB
chmod +x "$FIXTURE/bin/dpkg-query"
for tool in apt-get sudo curl wget python python3 pip pip3; do
    cat >"$FIXTURE/bin/$tool" <<'STUB'
#!/bin/bash
printf '%s\n' "$0 $*" >> "$TEST_LOG"
exit 97
STUB
    chmod +x "$FIXTURE/bin/$tool"
done
preview() {
    env -i HOME="$FIXTURE/home" PATH="$FIXTURE/bin" TERM=xterm LC_ALL=C TEST_LOG="$TEST_LOG" TEST_INSTALLED="$TEST_INSTALLED" /bin/bash "$REPO/.install.sh" "$@"
}
contains() { [[ $(<"$1") == *"$2"* ]] || {
    printf 'Missing expected text: %s\nOutput:\n%s\n' "$2" "$(<"$1")" >&2
    exit 1
}; }
lacks() { [[ $(<"$1") != *"$2"* ]] || {
    printf 'Unexpected text: %s\n' "$2" >&2
    exit 1
}; }
removes() {
    local line
    while IFS= read -r line; do
        if [[ $line == '   remove_packages:'* ]]; then
            [[ " $line " == *" $2 "* ]]
            return
        fi
    done <"$1"
    return 1
}

rejects() {
    if preview "$@" >"$FIXTURE/out" 2>"$FIXTURE/error"; then
        printf 'Unexpected success: %s\n' "$*" >&2
        exit 1
    fi
}

preview --help >"$FIXTURE/out"
contains "$FIXTURE/out" '--keep-unchecked'
preview --list >"$FIXTURE/out"
contains "$FIXTURE/out" 'Docker with Compose and Buildx'
lacks "$FIXTURE/out" 'docker-ce-cli'
preview --non-interactive --dry-run --select docker --verbose >"$FIXTURE/out"
contains "$FIXTURE/out" 'diffutils'
contains "$FIXTURE/out" 'docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
for package in wget git gh python3 python3-venv python3-pip btop nodejs npm golang-go golang-1.24-go neovim-runtime; do removes "$FIXTURE/out" "$package"; done
if removes "$FIXTURE/out" curl; then exit 1; fi
lacks "$FIXTURE/out" 'remove_packages: docker'
lacks "$FIXTURE/out" 'unrelated-app'
lacks "$FIXTURE/out" '  cups'
contains "$FIXTURE/out" 'enable Docker and Containerd'
preview --non-interactive --dry-run --keep-unchecked --select docker >"$FIXTURE/out"
contains "$FIXTURE/out" 'Package removals (0)'
contains "$FIXTURE/out" 'OFF - unchecked software is kept'
preview --non-interactive --dry-run --preset empty --verbose >"$FIXTURE/out"
for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do removes "$FIXTURE/out" "$package"; done
contains "$FIXTURE/out" 'Remove unchecked: ON'
printf 'PASS bundled Docker, implicit removal, opt-out, and catalog-limited scope\n'

preview --non-interactive --dry-run --select neovim --verbose >"$FIXTURE/out"
# Git and curl are required by selected tools, even when their own bundle is off.
removes "$FIXTURE/out" wget
removes "$FIXTURE/out" gh
removes "$FIXTURE/out" python3
if removes "$FIXTURE/out" git || removes "$FIXTURE/out" curl || removes "$FIXTURE/out" neovim-runtime; then exit 1; fi
preview --non-interactive --dry-run --select node --verbose >"$FIXTURE/out"
if removes "$FIXTURE/out" nodejs || removes "$FIXTURE/out" npm; then exit 1; fi
removes "$FIXTURE/out" golang-go
preview --non-interactive --dry-run --target debian --preset desktop --verbose >"$FIXTURE/out"
contains "$FIXTURE/out" 'i3/installer.conf'
contains "$FIXTURE/out" 'nvim-linux-x86_64.tar.gz'
contains "$FIXTURE/out" 'xss-lock --transfer-sleep-lock'
lacks "$FIXTURE/out" 'install -- python3'
preview --non-interactive --dry-run --target debian --select node --verbose >"$FIXTURE/out"
contains "$FIXTURE/out" 'fnm-linux.zip'
contains "$FIXTURE/out" 'npm install --global pnpm@latest'
contains "$FIXTURE/out" 'default 22'
preview --non-interactive --dry-run --target debian --select python --verbose >"$FIXTURE/out"
contains "$FIXTURE/out" 'python3'
contains "$FIXTURE/out" 'python3-pip'
contains "$FIXTURE/out" 'python3-venv'
preview --non-interactive --dry-run --preset cli --skip node >"$FIXTURE/out"
lacks "$FIXTURE/out" 'Node.js with fnm and pnpm'
preview --non-interactive --dry-run --select cli-tools --verbose >"$FIXTURE/out"
if removes "$FIXTURE/out" python3 || removes "$FIXTURE/out" python3-venv; then exit 1; fi
removes "$FIXTURE/out" python3-pip
contains "$FIXTURE/out" 'Shared packages kept'
preview --non-interactive --dry-run --select yt-dlp --verbose >"$FIXTURE/out"
if removes "$FIXTURE/out" python3; then exit 1; fi
printf 'PASS shared dependencies, Python/Node bundles, presets and dotfiles\n'

rejects --non-interactive --dry-run --select docker-ce
contains "$FIXTURE/error" 'Unknown software choice'
rejects --non-interactive --dry-run --select git --set git_name=OnlyName
contains "$FIXTURE/error" 'Fill both Git name and email'
rejects --non-interactive --dry-run --select neovim --set neovim_version=0.10.0
contains "$FIXTURE/error" '0.11.2 or newer'
rejects --non-interactive --dry-run --target debian --arch arm64 --select discord
contains "$FIXTURE/error" 'unavailable'
rejects --non-interactive --select docker --keep-unchecked
contains "$FIXTURE/error" 'requires --yes'
rejects --non-interactive --target debian --yes
contains "$FIXTURE/error" 'preview-only'
rejects --non-interactive --dry-run --set use_dotfiles=invalid
contains "$FIXTURE/error" 'on or off'
rejects --non-interactive --dry-run --select '$(touch BAD)'
contains "$FIXTURE/error" 'Invalid choice ID'
printf 'PASS validation, architecture and preview guards\n'

cat >"$FIXTURE/profile" <<'PROFILE'
install=git
remove_unchecked=false
set.git_name=$(touch SHOULD_NOT_EXIST); `echo literal`
set.git_email=a@example.com
PROFILE
preview --non-interactive --dry-run --verbose --config "$FIXTURE/profile" >"$FIXTURE/out"
contains "$FIXTURE/out" 'SHOULD_NOT_EXIST'
contains "$FIXTURE/out" 'Package removals (0)'
[[ ! -e SHOULD_NOT_EXIST ]]
preview --non-interactive --dry-run --config "$FIXTURE/profile" --remove-unchecked >"$FIXTURE/out"
contains "$FIXTURE/out" 'Remove unchecked: ON'
[[ ! -s $TEST_LOG ]]
[[ $(find "$FIXTURE/home" -mindepth 1 -print -quit) == '' ]]
printf 'PASS literal profiles, CLI precedence, and dry-run with blocked mutation commands\n'

all_ids=''
while IFS='|' read -r id _; do [[ -z $id || $id == \#* ]] || all_ids+="${all_ids:+,}$id"; done <"$REPO/installer/catalog.conf"
preview --non-interactive --dry-run --verbose --target debian --select "$all_ids" \
    --set git_name=Test --set git_email=test@example.com --set hostname=test-box \
    --set timezone=America/New_York --set display_output=HDMI-1 --set keyboard_layouts=us \
    --set docker_access=on --set virtualization_access=on --set tailscale_login=on \
    --set github_login=on --set default_shell=on --set discord_updates=on >"$FIXTURE/out"
contains "$FIXTURE/out" 'Connect Tailscale'
contains "$FIXTURE/out" 'download_key:'
contains "$FIXTURE/out" 'merge_json:'
contains "$FIXTURE/out" 'setxkbmap'
contains "$FIXTURE/out" 'xrandr --output'
contains "$FIXTURE/out" 'hostnamectl set-hostname test-box'
contains "$FIXTURE/out" 'archive:'
[[ ! -s $TEST_LOG ]]
printf 'PASS complete public catalog plans without mutation\n'

# Source modules to test apply operations against disposable files only.
export REPO FIXTURE
/bin/bash <<'UNIT'
set -Eeuo pipefail
installer_root=$REPO
source "$REPO/installer/main.sh"
load_catalog
parse_arguments --non-interactive --dry-run --target debian
HOME=$FIXTURE/home
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME GIT_CONFIG_GLOBAL
detect_platform
select_backend
backend_scan_installed
merge_choices
RUN_ID=test
BACKUP_DIR=$STATE_DIR/dotfiles/backups/$RUN_ID
declare -gA BACKED_UP=() BACKUP_LOCATIONS=()
declare -ga CLAIM_IDS=() CLAIM_PATHS=()
trap cleanup EXIT

# Installed bundles start checked, including a partially installed Docker suite.
INSTALLED_PACKAGES=([docker-ce-cli]=1 [python3]=1)
select_installed_choices
[[ ${CHOSEN[docker]+present} && ${CHOSEN[python]+present} && ! ${CHOSEN[printing]+present} ]]
CHOSEN=()
if setting_relevant node_version; then exit 1; fi
CHOSEN=([node]=1)
setting_relevant node_version
if setting_relevant docker_access; then exit 1; fi
CHOSEN=()
INSTALLED_PACKAGES=()
# No UI bootstrap in dry-run; existing whiptail/dialog always reused.
command() {
    if [[ $1 == -v && ( $2 == whiptail || $2 == dialog ) ]]; then return 1; fi
    builtin command "$@"
}
backend_bootstrap_ui() { printf bootstrap >> "$FIXTURE/bootstrap"; }
choose_ui
[[ -z $UI_TOOL && ! -e $FIXTURE/bootstrap ]]
DRY_RUN=false
# Simulate bootstrap making whiptail available.
backend_bootstrap_ui() {
    printf bootstrap >> "$FIXTURE/bootstrap"
    command() { if [[ $1 == -v && $2 == whiptail ]]; then return 0; fi; builtin command "$@"; }
}
choose_ui
[[ $UI_TOOL == whiptail && $(< "$FIXTURE/bootstrap") == bootstrap ]]
choose_ui
[[ $(< "$FIXTURE/bootstrap") == bootstrap ]]
# Reuse dialog when whiptail is absent.
command() {
    if [[ $1 == -v && $2 == whiptail ]]; then return 1; fi
    if [[ $1 == -v && $2 == dialog ]]; then return 0; fi
    builtin command "$@"
}
choose_ui
[[ $UI_TOOL == dialog && $(< "$FIXTURE/bootstrap") == bootstrap ]]
unset -f command
# The real Debian bootstrap invokes only APT update + install via elevation.
source "$REPO/installer/backends/debian.sh"
run_privileged() { printf '%q ' "$@" >> "$FIXTURE/bootstrap-commands"; printf '\n' >> "$FIXTURE/bootstrap-commands"; }
backend_bootstrap_ui
[[ $(< "$FIXTURE/bootstrap-commands") == *'apt-get update'* ]]
[[ $(< "$FIXTURE/bootstrap-commands") == *'install whiptail'* ]]
source "$REPO/installer/executor.sh"

# Apply a real allowlisted config to the temporary home; keep originals.
mkdir -p "$CONFIG_DIR/tmux"
printf 'original config\n' > "$CONFIG_DIR/tmux/tmux.conf"
reset_plan
REMOVE=()
add_action copy 'Deploy Tmux configuration' "$REPO/.config/tmux/tmux.conf" "$CONFIG_DIR/tmux/tmux.conf"
apply_plan
cmp "$CONFIG_DIR/tmux/tmux.conf" "$REPO/.config/tmux/tmux.conf"
[[ $(< "${BACKUP_LOCATIONS[$CONFIG_DIR/tmux/tmux.conf]}") == 'original config' ]]

# Versioned receipts safely remove only owned paths and preserve dependencies.
mkdir -p "$APPS_DIR/go/1.2.3" "$LOCAL_BIN"
printf binary > "$APPS_DIR/go/1.2.3/go"
ln -s "$APPS_DIR/go/1.2.3/go" "$LOCAL_BIN/go"
claim_path go "$APPS_DIR/go/1.2.3"
claim_path go "$LOCAL_BIN/go"
record_receipt go 22
read_receipt go
[[ ${#RECEIPT_PATHS[@]} == 2 ]]
PREVIEW_TARGET=false
# An unchecked managed archive is removed by default, and kept with the opt-out.
CHOSEN=()
VALUES[use_dotfiles]=off
build_plan
[[ ${REMOVE[go]+present} ]]
REMOVE_UNCHECKED=false
build_plan
[[ ${#REMOVE[@]} == 0 ]]
REMOVE_UNCHECKED=true
# Restore apply bookkeeping; remove the fixture directly.
BACKED_UP=()
remove_managed go
PREVIEW_TARGET=true
[[ ! -e $LOCAL_BIN/go && ! -L $LOCAL_BIN/go && ! -e $APPS_DIR/go/1.2.3 ]]
[[ -f ${BACKUP_LOCATIONS[$APPS_DIR/go/1.2.3]}/go ]]
# Parent/child backups cannot overwrite or nest inside each other.
mkdir -p "$DATA_DIR/nested/plugin"
printf child > "$DATA_DIR/nested/plugin/file"
printf parent > "$DATA_DIR/nested/file"
backup_path "$DATA_DIR/nested/plugin" false move
backup_path "$DATA_DIR/nested" false move
[[ -f ${BACKUP_LOCATIONS[$DATA_DIR/nested/plugin]}/file ]]
[[ -f ${BACKUP_LOCATIONS[$DATA_DIR/nested]}/file ]]
# Invalid receipts never permit removing arbitrary user files.
printf '%s\0' dotfiles-v1 neovim "$INSTALL_HOME" path "$INSTALL_HOME/.ssh" > "$RECEIPT_DIR/neovim.receipt"
if read_receipt neovim; then exit 1; fi

# Refuse APT removal of anything beyond the explicit package list.
apt-get() { printf 'Remv btop [1.0]\nRemv tmux [1.0]\n'; }
if check_package_removal btop; then exit 1; fi
check_package_removal btop tmux
unset -f apt-get

# Reject archive traversal and special files before extraction.
mkdir "$FIXTURE/archive"
printf content > "$FIXTURE/archive/file"
ln -s /etc/passwd "$FIXTURE/archive/link"
tar -cf "$FIXTURE/unsafe.tar" -C "$FIXTURE/archive" link
new_temp
mkdir "$TEMP_DIR/out"
if extract_archive "$FIXTURE/unsafe.tar" "$TEMP_DIR/out" 0 tar; then exit 1; fi
if safe_archive_path '../outside'; then exit 1; fi
if safe_archive_path '/absolute'; then exit 1; fi
# Real archive extraction and link creation produce removable receipts.
tar -cf "$FIXTURE/safe.tar" -C "$FIXTURE/archive" file
extract_archive "$FIXTURE/safe.tar" "$TEMP_DIR/out" 0 tar
[[ $(< "$TEMP_DIR/out/file") == content ]]

# Minimal Fedora/Arch images may use the C locale. Printable Unicode names in
# official Go archives must not be mistaken for escaped unsafe archive paths.
printf unicode > "$FIXTURE/archive/Þfoo.go"
tar -cf "$FIXTURE/unicode.tar" -C "$FIXTURE/archive" 'Þfoo.go'
LC_ALL=C extract_archive "$FIXTURE/unicode.tar" "$TEMP_DIR/out" 0 tar
[[ $(< "$TEMP_DIR/out/Þfoo.go") == unicode ]]

# Existing repositories are reused, including deb822 multiline fields.
APT_ROOT=$FIXTURE/apt
mkdir -p "$APT_ROOT/sources.list.d"
PREVIEW_TARGET=false
cat > "$APT_ROOT/sources.list.d/existing.sources" <<'SOURCE'
Types: deb
URIs:
 https://download.docker.com/linux/debian/
Suites: trixie
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
SOURCE
backend_existing_repository https://download.docker.com/linux/debian trixie
reset_plan
backend_repository docker
[[ ${#ACTION_KIND[@]} == 0 ]]
printf 'PASS UI reuse/bootstrap, backed-up config apply, receipts, APT removal and archive guards\n'
UNIT
[[ ! -s $TEST_LOG ]]
printf 'All installer tests passed.\n'
