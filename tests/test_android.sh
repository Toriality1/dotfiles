#!/usr/bin/env bash
# Android setup against disposable SDK tools; no downloads or host settings.
set -Eeuo pipefail
REPO=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$FIXTURE"' EXIT
unset ANDROID_HOME ANDROID_SDK_ROOT ANDROID_USER_HOME ANDROID_AVD_HOME JAVA_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME ZDOTDIR
export HOME="$FIXTURE/home with spaces"
mkdir -p "$HOME"
installer_root=$REPO
source "$REPO/installer/main.sh"
trap 'cleanup; rm -rf -- "$FIXTURE"' EXIT
load_catalog
parse_arguments --non-interactive --dry-run --target debian --keep-unchecked --select android-studio,android-emulator,android-ndk
detect_platform
select_backend
backend_scan_installed
merge_choices
build_plan
[[ ${RESOLVED[android-sdk]+present} && ${RESOLVED[default-jdk]+present} && $PLAN == *'Android API 36'* ]]
DRY_RUN=false
if build_plan; then exit 1; fi
[[ $PLAN_ERROR == *android_accept_licenses=on* && ${#ACTION_KIND[@]} == 0 ]]
DRY_RUN=true
VALUES[android_accept_licenses]=on
VALUES[android_avd_name]='../unsafe'
if build_plan; then exit 1; fi
VALUES[android_avd_name]=smoke_device
VERBOSE=true
build_plan
printf 'PASS Android dependencies, release plans, license preflight and validation\n'

# A stored ZIP with cmdline-tools/bin/sdkmanager containing "fixture". Ensure
# the extracted tools physically live under SDK/cmdline-tools/<version>, since
# real avdmanager derives the SDK from that path even with ANDROID_HOME set.
printf '%s' 'UEsDBBQAAAAAAMKBU13uQOUFBwAAAAcAAAAcAAAAY21kbGluZS10b29scy9iaW4vc2RrbWFuYWdlcmZpeHR1cmVQSwECFAMUAAAAAADCgVNd7kDlBQcAAAAHAAAAHAAAAAAAAAAAAAAAgAEAAAAAY21kbGluZS10b29scy9iaW4vc2RrbWFuYWdlclBLBQYAAAAAAQABAEoAAABBAAAAAAA=' | base64 --decode >"$FIXTURE/tools.zip"
new_temp
mkdir "$FIXTURE/extracted"
extract_archive "$FIXTURE/tools.zip" "$FIXTURE/extracted" 1 zip
[[ $(<"$FIXTURE/extracted/bin/sdkmanager") == fixture ]]
printf -v expected_tools_path '%q' "$ANDROID_SDK_DIR/cmdline-tools/15859902"
[[ $PLAN == *"$expected_tools_path 1 bin/sdkmanager"* ]]
printf 'PASS Android command-line tools archive layout for SDK discovery\n'

mkdir "$FIXTURE/archives"
fixture_checksum=$(sha256sum "$FIXTURE/tools.zip"); fixture_checksum=${fixture_checksum%% *}
cp "$FIXTURE/tools.zip" "$FIXTURE/archives/$fixture_checksum"
fixture_destination=$ANDROID_SDK_DIR/cmdline-tools/test-build
DOTFILES_DOWNLOAD_CACHE="$FIXTURE/archives" install_archive android-sdk https://example.invalid/tools.zip "$fixture_destination" 1 bin/sdkmanager "$fixture_checksum"
[[ -x $fixture_destination/bin/sdkmanager && $(<"$fixture_destination/bin/sdkmanager") == fixture ]]
printf 'retained local tools' >"$fixture_destination/bin/sdkmanager"
DOTFILES_DOWNLOAD_CACHE="$FIXTURE/archives" install_archive android-sdk https://example.invalid/tools.zip "$fixture_destination" 1 bin/sdkmanager "$fixture_checksum"
[[ $(<"$fixture_destination/bin/sdkmanager") == 'retained local tools' ]]
printf 'PASS staged Android archive installation and existing-tools preservation\n'

mkdir -p "$ANDROID_SDK_DIR/cmdline-tools/latest/bin" "$ANDROID_SDK_DIR/platform-tools"
printf 'original manual platform tools\n' >"$ANDROID_SDK_DIR/platform-tools/source.properties"
export ANDROID_TEST_LOG=$FIXTURE/packages
cat >"$ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager" <<'STUB'
#!/usr/bin/env bash
set -eu
root=${1#--sdk_root=}
shift
for package in "$@"; do
    printf '%s\n' "$package" >>"$ANDROID_TEST_LOG"
    directory=$root/${package//;/\/}
    mkdir -p "$directory"
    printf '%s\n' "$package" >"$directory/source.properties"
done
STUB
cat >"$ANDROID_SDK_DIR/cmdline-tools/latest/bin/avdmanager" <<'STUB'
#!/usr/bin/env bash
set -eu
while (($#)); do
    case $1 in --name) name=$2; shift 2 ;; --path) directory=$2; shift 2 ;; *) shift ;; esac
done
mkdir -p "$directory"
printf 'created device\n' >"$directory/config.ini"
printf 'path=%s\n' "$directory" >"$ANDROID_AVD_HOME/$name.ini"
STUB
chmod +x "$ANDROID_SDK_DIR/cmdline-tools/latest/bin/"*
BACKUP_DIR=$FIXTURE/backups
declare -A BACKED_UP=() BACKUP_LOCATIONS=()
declare -a CLAIM_IDS=() CLAIM_PATHS=()
trap 'cleanup; rm -rf -- "$FIXTURE"' EXIT
install_android_packages 36 36.0.0 on 27.1.12297006 smoke_device
[[ $(<"$ANDROID_SDK_DIR/platform-tools/source.properties") == 'original manual platform tools' ]]
[[ $(<"$ANDROID_TEST_LOG") != *platform-tools* ]]
read_receipt android-sdk
[[ " ${RECEIPT_PATHS[*]} " != *" $ANDROID_SDK_DIR/platform-tools "* ]]
[[ -f $ANDROID_AVD_DIR/smoke_device.avd/config.ini && -f $ANDROID_SDK_DIR/ndk/27.1.12297006/source.properties ]]
printf 'user device settings\n' >"$ANDROID_AVD_DIR/smoke_device.avd/config.ini"
sum_before=$(sha256sum "$ANDROID_TEST_LOG")
install_android_packages 36 36.0.0 on 27.1.12297006 smoke_device
[[ $(sha256sum "$ANDROID_TEST_LOG") == "$sum_before" ]]
[[ $(<"$ANDROID_AVD_DIR/smoke_device.avd/config.ini") == 'user device settings' ]]
printf 'PASS SDK package selection, SIGPIPE handling, NDK/AVD setup and reuse\n'

mkdir -p "$HOME/.config/zsh"
printf '# custom bash profile\n' >"$HOME/.bashrc"
install_android_environment "$HOME/.config/zsh/.zshrc"
[[ $(<"$HOME/.bashrc") == *'custom bash profile'* ]]
[[ $(<"${BACKUP_LOCATIONS[$HOME/.bashrc]}") == '# custom bash profile' ]]
rc_before=$(sha256sum "$HOME/.bashrc")
install_android_environment "$HOME/.config/zsh/.zshrc"
[[ $(sha256sum "$HOME/.bashrc") == "$rc_before" ]]
mkdir -p "$DATA_DIR/android/studio/bin"
# shellcheck disable=SC2016 # The generated fixture expands variables when executed.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$ANDROID_HOME" "$@"\n' >"$DATA_DIR/android/studio/bin/studio.sh"
chmod +x "$DATA_DIR/android/studio/bin/studio.sh"
install_android_launcher "$DATA_DIR/android/studio/bin/studio.sh" "$ANDROID_SDK_DIR" "$LOCAL_BIN/android-studio"
[[ $(ANDROID_HOME='' "$LOCAL_BIN/android-studio" 'file with spaces') == "$ANDROID_SDK_DIR"$'\nfile with spaces' ]]
bash -c '. "$1"; [[ $ANDROID_HOME == "$2" && :$PATH: == *":$2/cmdline-tools/latest/bin:"* ]]' bash "$CONFIG_DIR/android/env.sh" "$ANDROID_SDK_DIR"
BACKED_UP=() BACKUP_LOCATIONS=()
BACKUP_DIR=$FIXTURE/removal-backups
remove_managed android-emulator
[[ ! -e $ANDROID_AVD_DIR/smoke_device.avd ]]
[[ $(<"${BACKUP_LOCATIONS[$ANDROID_AVD_DIR/smoke_device.avd]}/config.ini") == 'user device settings' ]]
remove_managed android-ndk
remove_managed android-sdk
[[ -f $ANDROID_SDK_DIR/platform-tools/source.properties && -f $ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager ]]
printf 'PASS backed-up shell integration and ownership-limited removal, preserving manual SDK files\n'

mkdir "$FIXTURE/cache"
printf archive >"$FIXTURE/data"
checksum=$(sha256sum "$FIXTURE/data"); checksum=${checksum%% *}
cp "$FIXTURE/data" "$FIXTURE/cache/$checksum"
DOTFILES_DOWNLOAD_CACHE=$FIXTURE/cache
download_verified https://example.invalid/tools.zip "$checksum" "$FIXTURE/output"
printf corrupt >"$FIXTURE/cache/$checksum"
if download_verified https://example.invalid/tools.zip "$checksum" "$FIXTURE/output"; then exit 1; fi
printf 'PASS SHA-256 verified Android downloads, including cached artifacts\n'
