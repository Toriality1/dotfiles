# CLI, trusted catalogs, platform detection and component dependency resolution.

fail() {
    printf 'Error: %s\n' "$*" >&2
    return 1
}
plan_error() {
    PLAN_ERROR=$*
    return 1
}
valid_id() { [[ $1 =~ ^[a-z0-9][a-z0-9.-]*$ ]]; }
valid_key() { [[ $1 =~ ^[a-z_]+$ ]]; }

csv_add() {
    local -n destination=$1
    local item
    local -a items=()
    IFS=',' read -r -a items <<<"$2"
    for item in "${items[@]}"; do
        [[ -n $item ]] || continue
        valid_id "$item" || {
            fail "Invalid choice ID: $item"
            return 1
        }
        destination["$item"]=1
    done
}

load_catalog() {
    declare -ga FEATURE_IDS=() CHOICE_IDS=() SERVICE_IDS=() SETTING_IDS=() PRESET_IDS=()
    declare -gA LABEL=() CATEGORY=() KIND=() REQUIRES=() REPOSITORY=() ARCHES=() NATIVE=() REMOVABLE=()
    declare -gA CHOICE_LABEL=() CHOICE_CATEGORY=() CHOICE_PARTS=() CHOICE_PROBES=() CHOSEN=()
    declare -gA SERVICE_LABEL=() SERVICE_UNITS=() SERVICE_OWNER=() SERVICES=() EFFECTIVE_SERVICES=()
    declare -gA SETTING_LABEL=() SETTING_OWNERS=() SETTING_HELP=() SETTING_LEVEL=() VALUES=() PRESETS=()
    declare -gA INSTALL=() REMOVE=() EXCLUDE=() CLI_INSTALL=() CLI_SKIP=() CLI_VALUES=() CLI_SERVICES=() SKIPPED=()
    local id label category kind dependencies repository arches native removable default owners description units level probes
    while IFS='|' read -r id label category kind dependencies repository arches native removable; do
        [[ -n $id && $id != \#* ]] || continue
        FEATURE_IDS+=("$id")
        LABEL["$id"]=$label KIND["$id"]=$kind REQUIRES["$id"]=$dependencies REPOSITORY["$id"]=$repository
        ARCHES["$id"]=$arches NATIVE["$id"]=$native REMOVABLE["$id"]=$removable
    done <"$REPO_DIR/installer/components.conf"
    while IFS='|' read -r id label category dependencies probes; do
        [[ -n $id && $id != \#* ]] || continue
        CHOICE_IDS+=("$id") CHOICE_LABEL["$id"]=$label CHOICE_CATEGORY["$id"]=$category
        CHOICE_PARTS["$id"]=$dependencies CHOICE_PROBES["$id"]=$probes
    done <"$REPO_DIR/installer/catalog.conf"
    while IFS='|' read -r id label units owners; do
        [[ -n $id && $id != \#* ]] || continue
        SERVICE_IDS+=("$id") SERVICE_LABEL["$id"]=$label SERVICE_UNITS["$id"]=$units SERVICE_OWNER["$id"]=$owners SERVICES["$id"]=auto
    done <"$REPO_DIR/installer/services.conf"
    while IFS='|' read -r id label default owners description level; do
        [[ -n $id && $id != \#* ]] || continue
        SETTING_IDS+=("$id") SETTING_LABEL["$id"]=$label VALUES["$id"]=$default
        SETTING_OWNERS["$id"]=$owners SETTING_HELP["$id"]=$description SETTING_LEVEL["$id"]=$level
    done <"$REPO_DIR/installer/settings.conf"
    while IFS='|' read -r id dependencies; do
        [[ -n $id && $id != \#* ]] || continue
        PRESET_IDS+=("$id") PRESETS["$id"]=$dependencies
    done <"$REPO_DIR/installer/presets.conf"
}

usage() {
    cat <<'HELP'
Usage: ./.install.sh [options]

Choose tools, not their individual packages. Debian, Ubuntu, Fedora and Arch.
Bash + whiptail/dialog; dialog setup is automatic when needed.

  -h, --help               Show help without making changes
  -n, --dry-run            Choose and review; never modify the machine
      --non-interactive    Use CLI/profile choices instead of dialogs
  -y, --yes                Apply a non-interactive plan
      --list               List software bundles and editable settings
      --preset NAME        Use empty, cli, desktop, server, ai, dev, or mobile
      --config FILE        Read a literal key=value profile
      --select ID,ID       Select software bundles; repeatable
      --skip ID,ID         Uncheck bundles, including preset choices
      --keep-unchecked     Leave unchecked software installed
      --remove-unchecked   Remove unchecked software (APT only; APT default)
      --set KEY=VALUE      Edit a setting; repeatable
      --service ID=STATE   Advanced override: auto/keep/enable/disable
      --verbose            Include package commands and generated files in review
      --target DISTRO      Preview debian/ubuntu/fedora/arch; needs --dry-run/--list
      --codename NAME      Preview release codename; requires --target
      --arch NAME          Preview amd64/arm64; requires --target

Interactive mode starts with installed software checked. A preset or profile
replaces that starting selection. Non-interactive choices describe the complete
desired selection. On APT, unchecked software is removed by default; shared
required components are kept. Use --keep-unchecked for additive installation.
Dry-run uses text menus if whiptail/dialog is missing; it installs nothing.
Fedora/Arch keep unchecked software; automatic cleanup is APT-only.
Native Windows uses install.ps1 (WinGet); WSL uses this Linux installer.
HELP
}

set_value() {
    local -n destination=$1
    local pair=$2 key value
    [[ $pair == *=* ]] || {
        fail "Expected NAME=VALUE: $pair"
        return 1
    }
    key=${pair%%=*} value=${pair#*=}
    if [[ $1 == *SERVICES ]]; then
        valid_id "$key" && [[ ${SERVICE_LABEL[$key]+present} ]] || {
            fail "Unknown service: $key"
            return 1
        }
        [[ $value == auto || $value == keep || $value == enable || $value == disable ]] || {
            fail 'Service state must be auto, keep, enable, or disable.'
            return 1
        }
    else
        valid_key "$key" && [[ ${SETTING_LABEL[$key]+present} ]] || {
            fail "Unknown setting: $key"
            return 1
        }
    fi
    [[ $value != *$'\n'* && $value != *$'\r'* ]] || {
        fail 'Settings must be single-line values.'
        return 1
    }
    destination["$key"]=$value
}

parse_arguments() {
    DRY_RUN=false NON_INTERACTIVE=false AUTO_YES=false LIST=false SHOW_HELP=false VERBOSE=false
    REMOVE_UNCHECKED=true CLI_POLICY='' PROFILE='' PRESET='' TARGET='' TARGET_CODENAME='' TARGET_ARCH=''
    while (($#)); do
        case $1 in
            -h | --help)
                SHOW_HELP=true
                shift
                ;;
            -n | --dry-run)
                DRY_RUN=true
                shift
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            -y | --yes)
                AUTO_YES=true
                shift
                ;;
            --list)
                LIST=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --keep-unchecked)
                CLI_POLICY=false
                shift
                ;;
            --remove-unchecked)
                CLI_POLICY=true
                shift
                ;;
            --preset | --config | --select | --skip | --set | --service | --target | --codename | --arch)
                (($# >= 2)) || {
                    fail "Missing value for $1"
                    return 1
                }
                case $1 in
                    --preset) PRESET=$2 ;;
                    --config) PROFILE=$2 ;;
                    --select) csv_add CLI_INSTALL "$2" || return ;;
                    --skip) csv_add CLI_SKIP "$2" || return ;;
                    --set) set_value CLI_VALUES "$2" || return ;;
                    --service) set_value CLI_SERVICES "$2" || return ;;
                    --target) TARGET=$2 ;;
                    --codename) TARGET_CODENAME=$2 ;;
                    --arch) TARGET_ARCH=$2 ;;
                esac
                shift 2
                ;;
            *)
                fail "Unknown argument: $1 (use --help)"
                return 1
                ;;
        esac
    done
    if [[ -n $TARGET ]]; then
        [[ $TARGET =~ ^(debian|ubuntu|fedora|arch)$ && ($DRY_RUN == true || $LIST == true) ]] || {
            fail '--target accepts debian/ubuntu/fedora/arch and is preview-only; use --dry-run or --list.'
            return 1
        }
    elif [[ -n $TARGET_ARCH || -n $TARGET_CODENAME ]]; then
        fail '--arch and --codename require --target.'
        return 1
    fi
    if [[ -n $PRESET ]]; then
        valid_id "$PRESET" && [[ ${PRESETS[$PRESET]+present} ]] || {
            fail "Unknown preset: $PRESET"
            return 1
        }
    fi
}

load_profile() {
    local line key value
    [[ -r $PROFILE ]] || {
        fail "Cannot read profile: $PROFILE"
        return 1
    }
    CHOSEN=()
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line && $line != \#* ]] || continue
        [[ $line == *=* ]] || {
            fail "Invalid profile line: $line"
            return 1
        }
        key=${line%%=*} value=${line#*=}
        case $key in
            install) csv_add CHOSEN "$value" || return ;;
            skip) csv_add SKIPPED "$value" || return ;;
            remove_unchecked)
                [[ $value == true || $value == false ]] || {
                    fail 'remove_unchecked must be true or false.'
                    return 1
                }
                REMOVE_UNCHECKED=$value
                ;;
            set.*) set_value VALUES "${key#set.}=$value" || return ;;
            service.*) set_value SERVICES "${key#service.}=$value" || return ;;
            *)
                fail "Unknown profile field: $key"
                return 1
                ;;
        esac
    done <"$PROFILE"
}

merge_choices() {
    local id
    [[ -z $PROFILE ]] || load_profile || return
    if [[ -n $PRESET ]]; then
        CHOSEN=()
        csv_add CHOSEN "${PRESETS[$PRESET]}" || return
    fi
    for id in "${!CLI_INSTALL[@]}"; do
        CHOSEN["$id"]=1
        unset 'SKIPPED[$id]'
    done
    for id in "${!CLI_SKIP[@]}"; do SKIPPED["$id"]=1; done
    for id in "${!CHOSEN[@]}" "${!SKIPPED[@]}"; do
        valid_id "$id" && [[ ${CHOICE_LABEL[$id]+present} ]] || {
            fail "Unknown software choice: $id"
            return 1
        }
    done
    for id in "${!SKIPPED[@]}"; do unset 'CHOSEN[$id]'; done
    for id in "${!CLI_VALUES[@]}"; do VALUES["$id"]=${CLI_VALUES[$id]}; done
    for id in "${!CLI_SERVICES[@]}"; do SERVICES["$id"]=${CLI_SERVICES[$id]}; done
    [[ -z $CLI_POLICY ]] || REMOVE_UNCHECKED=$CLI_POLICY
    return 0
}

detect_platform() {
    OS=$(uname -s) ARCH=$(uname -m) DISTRO='' CODENAME='' VERSION_ID='' WSL=false SYSTEMD=false PREVIEW_TARGET=false
    case $ARCH in x86_64 | amd64) ARCH=amd64 ;; aarch64 | arm64) ARCH=arm64 ;; esac
    local key value ubuntu_codename='' distro_like=''
    if [[ $OS == Linux && -r /etc/os-release ]]; then
        while IFS='=' read -r key value; do
            value=${value#\"} value=${value%\"} value=${value#\'} value=${value%\'}
            case $key in ID) DISTRO=$value ;; VERSION_CODENAME) CODENAME=$value ;; VERSION_ID) VERSION_ID=$value ;; UBUNTU_CODENAME) ubuntu_codename=$value ;; ID_LIKE) distro_like=$value ;; esac
        done </etc/os-release
        if [[ ${WSL_DISTRO_NAME:-} || $(uname -r) == *[Mm]icrosoft* ]]; then WSL=true; fi
        [[ ! -d /run/systemd/system ]] || SYSTEMD=true
    fi
    # Ubuntu derivatives expose the base codename separately (e.g. Linux Mint).
    if [[ $DISTRO != ubuntu && -n $ubuntu_codename && " $distro_like " == *' ubuntu '* ]]; then
        DISTRO=ubuntu CODENAME=$ubuntu_codename
    elif [[ $DISTRO != arch && " $distro_like " == *' arch '* ]]; then DISTRO=arch; fi
    if [[ -n $TARGET ]]; then
        OS=Linux DISTRO=$TARGET CODENAME=$TARGET_CODENAME VERSION_ID='' ARCH=${TARGET_ARCH:-amd64} SYSTEMD=true WSL=false PREVIEW_TARGET=true
        case $DISTRO in
            debian) CODENAME=${CODENAME:-trixie} ;;
            ubuntu) CODENAME=${CODENAME:-noble} ;;
            fedora) CODENAME=${CODENAME:-fedora} ;;
            arch) CODENAME=${CODENAME:-rolling} ;;
        esac
        [[ $ARCH == amd64 || $ARCH == arm64 ]] || {
            fail 'Preview architecture must be amd64 or arm64.'
            return 1
        }
    fi
    PLATFORM="$OS $DISTRO $CODENAME $ARCH"
    [[ $WSL == false ]] || PLATFORM+=' / WSL'
    INSTALL_HOME=${HOME:?HOME must be set}
    CONFIG_DIR=${XDG_CONFIG_HOME:-$INSTALL_HOME/.config}
    DATA_DIR=${XDG_DATA_HOME:-$INSTALL_HOME/.local/share}
    STATE_DIR=${XDG_STATE_HOME:-$INSTALL_HOME/.local/state}
    LOCAL_BIN=$INSTALL_HOME/.local/bin APPS_DIR=$DATA_DIR/dotfiles/apps RECEIPT_DIR=$DATA_DIR/dotfiles/receipts
    ANDROID_SDK_DIR=${ANDROID_HOME:-$DATA_DIR/android/sdk}
    ANDROID_USER_DIR=${ANDROID_USER_HOME:-$INSTALL_HOME/.android}
    ANDROID_AVD_DIR=${ANDROID_AVD_HOME:-$ANDROID_USER_DIR/avd}
    [[ $ANDROID_SDK_DIR == /* && $ANDROID_SDK_DIR != *$'\n'* && $ANDROID_SDK_DIR != *$'\r'* && /$ANDROID_SDK_DIR/ != *'/../'* ]] || {
        fail 'ANDROID_HOME must be an absolute, single-line path without traversal.'; return 1;
    }
    if [[ -n ${ANDROID_SDK_ROOT:-} && $ANDROID_SDK_ROOT != "$ANDROID_SDK_DIR" ]]; then
        fail 'ANDROID_HOME and ANDROID_SDK_ROOT must identify the same SDK.'; return 1
    fi
    for path in "$ANDROID_USER_DIR" "$ANDROID_AVD_DIR"; do
        [[ $path == /* && $path != *$'\n'* && $path != *$'\r'* && /$path/ != *'/../'* ]] || {
            fail 'Android user/AVD directories must be absolute single-line paths without traversal.'; return 1;
        }
    done
    local path
    for path in "$INSTALL_HOME" "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR"; do
        [[ $path == /* && $path != *$'\n'* && $path != *$'\r'* ]] || {
            fail 'HOME and XDG directories must be absolute, single-line paths.'
            return 1
        }
    done
    INSTALL_USER=$(id -un)
}

select_backend() {
    BACKEND=''
    if [[ $OS == Linux && ( $DISTRO == debian || $DISTRO == ubuntu ) ]]; then
        [[ $CODENAME =~ ^[a-z][a-z0-9-]+$ ]] || { fail 'Missing or invalid distribution codename.'; return 1; }
        BACKEND=apt
        # shellcheck source=installer/backends/debian.sh
        source "$REPO_DIR/installer/backends/debian.sh"
    elif [[ $OS == Linux && ( $DISTRO == fedora || $DISTRO == arch ) ]]; then
        BACKEND=$DISTRO
        source "$REPO_DIR/installer/backends/native.sh"
        # Cross-distro dependency protection/removal is deliberately opt-in only
        # where implemented. Installing portable bundles must never cascade-remove.
        REMOVE_UNCHECKED=false
    else
        fail "No backend for $PLATFORM. Supported: Debian, Ubuntu, Fedora, Arch; Windows: install.ps1."
        return 1
    fi
}

feature_available() {
    local id=$1
    if [[ $id == deskflow && ( $CODENAME == bookworm || $DISTRO == ubuntu ) ]]; then return 1; fi
    if [[ ${BACKEND:-apt} != apt ]]; then backend_feature_available "$id" || return 1; fi
    [[ ${ARCHES[$id]} == '' || ,${ARCHES[$id]}, == *",$ARCH,"* ]] || return 1
    [[ ${NATIVE[$id]} != yes || $WSL == false ]]
}

resolve_feature() {
    local id=$1 dependency
    local -a dependencies=()
    valid_id "$id" && [[ ${LABEL[$id]+present} ]] || {
        plan_error "Unknown feature: $id"
        return 1
    }
    [[ ! ${EXCLUDE[$id]+present} ]] || {
        plan_error "Required dependency $id is excluded or marked for removal."
        return 1
    }
    [[ ! ${RESOLVED[$id]+present} ]] || return 0
    [[ ! ${VISITING[$id]+present} ]] || {
        plan_error "Dependency cycle: $id"
        return 1
    }
    feature_available "$id" || {
        plan_error "$id is unavailable for $PLATFORM."
        return 1
    }
    VISITING["$id"]=1
    IFS=',' read -r -a dependencies <<<"${REQUIRES[$id]}"
    for dependency in "${dependencies[@]}"; do [[ -z $dependency ]] || resolve_feature "$dependency" || return; done
    unset 'VISITING[$id]'
    RESOLVED["$id"]=1 ORDERED+=("$id")
}

validate_settings() {
    local key value
    declare -gA ACTIVE_SETTINGS=()
    [[ ! ${RESOLVED[android-sdk]+present} ]] || validate_android_settings || return
    for key in claude-code codex opencode gemini-cli; do
        [[ ${RESOLVED[$key]+present} ]] || continue
        value=${VALUES[node_version]%%.*}
        [[ $value =~ ^[0-9]+$ ]] && ((10#$value >= 22)) || {
            plan_error 'AI command-line tools require Node 22 or newer.'
            return 1
        }
    done
    [[ ! ${RESOLVED[neovim]+present} ]] || ACTIVE_SETTINGS[neovim_version]=1
    [[ ! ${RESOLVED[go]+present} ]] || ACTIVE_SETTINGS[go_version]=1
    [[ ! ${RESOLVED[fnm]+present} ]] || ACTIVE_SETTINGS[fnm_version]=1
    [[ ! ${RESOLVED[node]+present} ]] || ACTIVE_SETTINGS[node_version]=1
    [[ ! ${RESOLVED[pnpm]+present} ]] || ACTIVE_SETTINGS[pnpm_version]=1
    [[ ! ${RESOLVED["nerd-font"]+present} ]] || ACTIVE_SETTINGS[font_version]=1
    [[ ! ${RESOLVED["mongodb-compass"]+present} ]] || ACTIVE_SETTINGS[compass_version]=1
    for key in neovim_version go_version fnm_version font_version compass_version node_version; do
        [[ ${ACTIVE_SETTINGS[$key]+present} ]] || continue
        [[ ${VALUES[$key]} =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
            plan_error "Invalid release number: $key"
            return 1
        }
    done
    [[ ! ${ACTIVE_SETTINGS[pnpm_version]+present} || ${VALUES[pnpm_version]} =~ ^[a-zA-Z0-9_.+-]+$ ]] || {
        plan_error 'Invalid pnpm version or dist-tag.'
        return 1
    }
    if [[ ${RESOLVED[neovim]+present} ]]; then
        local major minor patch
        IFS='.' read -r major minor patch <<<"${VALUES[neovim_version]}"
        major=${major:-0} minor=${minor:-0} patch=${patch:-0}
        ((10#$major > 0 || 10#$minor > 11 || (10#$minor == 11 && 10#$patch >= 2))) || {
            plan_error 'The config requires Neovim 0.11.2 or newer.'
            return 1
        }
    fi
    if [[ ${RESOLVED["git-branch"]+present} ]]; then
        value=${VALUES[git_branch]}
        [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && $value != *..* && $value != */ && $value != *.lock ]] || {
            plan_error 'Invalid Git branch name.'
            return 1
        }
    fi
    if [[ ${RESOLVED[hostname]+present} ]]; then [[ ${VALUES[hostname]} =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || {
        plan_error 'Invalid hostname.'
        return 1
    }; fi
    if [[ ${RESOLVED[timezone]+present} || ${RESOLVED[hostname]+present} ]]; then [[ $SYSTEMD == true ]] || {
        plan_error 'Hostname and timezone changes require systemd.'
        return 1
    }; fi
    if [[ ${RESOLVED[timezone]+present} ]]; then [[ ${VALUES[timezone]} =~ ^[a-zA-Z0-9_+/-]+$ && ${VALUES[timezone]} != *..* && ${VALUES[timezone]} != /* ]] || {
        plan_error 'Invalid IANA timezone.'
        return 1
    }; fi
    if [[ ${RESOLVED["i3-display"]+present} ]]; then [[ ${VALUES[display_output]} =~ ^[a-zA-Z0-9_.-]+$ && ${VALUES[display_mode]} =~ ^[0-9]+x[0-9]+$ ]] || {
        plan_error 'Set a monitor connector and WIDTHxHEIGHT mode.'
        return 1
    }; fi
    if [[ ${RESOLVED["i3-keyboard"]+present} ]]; then
        for key in keyboard_layouts keyboard_variants keyboard_options; do [[ ${VALUES[$key]} =~ ^[a-zA-Z0-9_:+,.-]*$ ]] || {
            plan_error "Invalid X11 setting: $key"
            return 1
        }; done
    fi
    for key in screen_blanking display_power; do
        [[ ${CHOSEN[i3]+present} ]] || continue
        [[ ${VALUES[$key]} == keep || ${VALUES[$key]} == on || ${VALUES[$key]} == off ]] || {
            plan_error "$key must be keep, on, or off."
            return 1
        }
    done
    return 0
}

list_catalog() {
    local id
    printf 'Software choices (packages are bundled):\n'
    local availability
    for id in "${CHOICE_IDS[@]}"; do
        availability=''
        if [[ -n ${BACKEND:-} ]] && ! choice_available "$id"; then availability=' [unavailable on this target]'; fi
        printf '%-22s %-30s %s%s\n' "$id" "${CHOICE_CATEGORY[$id]}" "${CHOICE_LABEL[$id]}" "$availability"
    done
    printf '\nSettings (--set KEY=VALUE):\n'
    for id in "${SETTING_IDS[@]}"; do printf '  %s=%s - %s\n' "$id" "${VALUES[$id]}" "${SETTING_HELP[$id]}"; done
    printf '\nAPT removes unchecked software by default (--keep-unchecked to disable); Fedora/Arch keep it.\n'
}
