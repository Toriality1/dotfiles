# Public software choices expand into private components and related configuration.

choice_available() {
    local part
    local -a parts=()
    IFS=',' read -r -a parts <<<"${CHOICE_PARTS[$1]}"
    for part in "${parts[@]}"; do feature_available "$part" || return 1; done
}

component_installed() {
    local id=$1 executable
    [[ -z $(backend_installed_component_packages "$id") ]] || return 0
    [[ $PREVIEW_TARGET == false ]] || return 1
    [[ ! -f $RECEIPT_DIR/$id.receipt ]] || return 0
    case $id in
        neovim) executable=nvim ;; go | fnm | node | pnpm) executable=$id ;;
        claude-code) executable=claude ;; codex | opencode | bun) executable=$id ;; gemini-cli) executable=gemini ;;
        android-sdk) [[ -f $ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager ]]; return ;;
        android-studio) [[ -f $DATA_DIR/android/studio/bin/studio.sh ]]; return ;;
        android-emulator) [[ -f $ANDROID_SDK_DIR/emulator/emulator ]]; return ;;
        android-ndk) [[ -d $ANDROID_SDK_DIR/ndk && -n $(find "$ANDROID_SDK_DIR/ndk" -mindepth 2 -maxdepth 2 -name source.properties -print -quit) ]]; return ;;
        oh-my-zsh)
            [[ -d $DATA_DIR/.oh-my-zsh ]]
            return
            ;;
        *) return 1 ;;
    esac
    command -v "$executable" >/dev/null 2>&1
}

select_installed_choices() {
    local id part
    local -a parts=()
    for id in "${CHOICE_IDS[@]}"; do
        choice_available "$id" || continue
        IFS=',' read -r -a parts <<<"${CHOICE_PROBES[$id]}"
        for part in "${parts[@]}"; do
            if component_installed "$part"; then
                CHOSEN["$id"]=1
                break
            fi
        done
    done
}

setting_relevant() {
    local owner
    case $1 in keyboard_* | display_* | screen_blanking) [[ ${VALUES[use_dotfiles]} == on ]] || return 1 ;; esac
    local -a owners=()
    [[ ${SETTING_OWNERS[$1]} != '*' ]] || return 0
    IFS=',' read -r -a owners <<<"${SETTING_OWNERS[$1]}"
    for owner in "${owners[@]}"; do [[ ! ${CHOSEN[$owner]+present} ]] || return 0; done
    return 1
}

expand_choices() {
    INSTALL=() REMOVE=()
    declare -gA RESOLVED=() VISITING=() EFFECTIVE_SERVICES=()
    declare -ga ORDERED=()
    PLAN_ERROR=''
    local id part state value
    # Minimal Fedora/Arch images omit cmp, which protects unchanged files from
    # unnecessary writes and backups. Target previews cannot probe that host.
    if [[ $PREVIEW_TARGET == true ]] || ! command -v cmp >/dev/null 2>&1; then INSTALL[diffutils]=1; fi
    for id in "${CHOICE_IDS[@]}"; do
        [[ ${CHOSEN[$id]+present} ]] || continue
        choice_available "$id" || {
            plan_error "${CHOICE_LABEL[$id]} is unavailable for $PLATFORM."
            return 1
        }
        csv_add INSTALL "${CHOICE_PARTS[$id]}" || return
    done
    for id in use_dotfiles upgrade github_login default_shell tailscale_login docker_access virtualization_access discord_updates; do
        setting_relevant "$id" || continue
        [[ ${VALUES[$id]} == on || ${VALUES[$id]} == off ]] || {
            plan_error "$id must be on or off."
            return 1
        }
    done
    for id in "${SETTING_IDS[@]}"; do
        value=${VALUES[$id]}
        [[ $value != *$'\n'* && $value != *$'\r'* ]] || {
            plan_error "$id must be a single line."
            return 1
        }
    done
    if [[ ${VALUES[use_dotfiles]} == on ]]; then
        INSTALL["config-bash"]=1
        for id in zsh neovim tmux i3 alacritty; do
            [[ ${CHOSEN[$id]+present} ]] || continue
            part=$id
            [[ $id != neovim ]] || part=nvim
            INSTALL["config-$part"]=1
        done
        if [[ ${CHOSEN[i3]+present} ]]; then
            csv_add INSTALL 'config-rofi,config-dunst,autostart-lock,autostart-network,autostart-dunst,autostart-keyring,autostart-polkit'
            for id in flameshot picom; do [[ ! ${CHOSEN[$id]+present} ]] || INSTALL["autostart-$id"]=1; done
            [[ -z ${VALUES[keyboard_layouts]} ]] || INSTALL["i3-keyboard"]=1
            [[ -z ${VALUES[display_output]} ]] || INSTALL["i3-display"]=1
            [[ ${VALUES[screen_blanking]} == keep && ${VALUES[display_power]} == keep ]] || INSTALL["i3-power"]=1
        fi
    fi
    [[ ${VALUES[upgrade]} != on ]] || INSTALL["apt-upgrade"]=1
    for id in hostname timezone; do [[ -z ${VALUES[$id]} ]] || INSTALL["$id"]=1; done
    if [[ ${CHOSEN[git]+present} ]]; then
        if [[ -n ${VALUES[git_name]} || -n ${VALUES[git_email]} ]]; then
            [[ -n ${VALUES[git_name]} && -n ${VALUES[git_email]} ]] || {
                plan_error 'Fill both Git name and email, or leave both blank.'
                return 1
            }
            INSTALL["git-identity"]=1
        fi
        [[ -z ${VALUES[git_branch]} ]] || INSTALL["git-branch"]=1
        [[ ${VALUES[github_login]} != on ]] || INSTALL["github-login"]=1
    fi
    [[ ! ${CHOSEN[zsh]+present} || ${VALUES[default_shell]} != on ]] || INSTALL["default-shell"]=1
    [[ ! ${CHOSEN[tailscale]+present} || ${VALUES[tailscale_login]} != on ]] || INSTALL["tailscale-login"]=1
    [[ ! ${CHOSEN[docker]+present} || ${VALUES[docker_access]} != on ]] || INSTALL["docker-group"]=1
    [[ ! ${CHOSEN[virtualization]+present} || ${VALUES[virtualization_access]} != on ]] || csv_add INSTALL 'libvirt-group,kvm-group'
    [[ ! ${CHOSEN[discord]+present} || ${VALUES[discord_updates]} != on ]] || INSTALL["discord-updates"]=1
    for id in "${FEATURE_IDS[@]}"; do [[ ! ${INSTALL[$id]+present} ]] || resolve_feature "$id" || return; done
    for id in "${SERVICE_IDS[@]}"; do
        state=${SERVICES[$id]}
        if [[ $state == auto ]]; then
            state=keep
            [[ ! ${CHOSEN[${SERVICE_OWNER[$id]}]+present} || $SYSTEMD == false || $id == network-wait ]] || state=enable
        fi
        if [[ $state != keep ]]; then
            [[ $SYSTEMD == true ]] || {
                plan_error "${SERVICE_LABEL[$id]} controls require systemd."
                return 1
            }
            [[ $state != enable || ${CHOSEN[${SERVICE_OWNER[$id]}]+present} ]] || {
                plan_error "Select ${SERVICE_OWNER[$id]} before enabling its service."
                return 1
            }
        fi
        EFFECTIVE_SERVICES["$id"]=$state
    done
    validate_settings
}

derive_removals() {
    declare -gA REMOVAL_PACKAGES=() MANAGED_SCOPE=()
    declare -ga UNMANAGED_TOOLS=() PACKAGE_REMOVAL_ORDER=() RETAINED_PACKAGES=()
    local id part package has_package
    local -a parts=()
    [[ $REMOVE_UNCHECKED == true && $PREVIEW_TARGET == false ]] || return 0
    backend_protect_dependencies
    for id in "${CHOICE_IDS[@]}"; do
        IFS=',' read -r -a parts <<<"${CHOICE_PARTS[$id]}"
        for part in "${parts[@]}"; do MANAGED_SCOPE["$part"]=1; done
    done
    for part in "${FEATURE_IDS[@]}"; do
        [[ ${MANAGED_SCOPE[$part]+present} && ! ${RESOLVED[$part]+present} ]] || continue
        has_package=false
        while IFS= read -r package; do
            [[ -n $package ]] || continue
            has_package=true
            if [[ ${PROTECTED_PACKAGES[$package]+present} ]]; then
                RETAINED_PACKAGES+=("$package")
                continue
            fi
            if [[ ! ${REMOVAL_PACKAGES[$package]+present} ]]; then PACKAGE_REMOVAL_ORDER+=("$package"); fi
            REMOVE["$part"]=1 REMOVAL_PACKAGES["$package"]=1
        done < <(backend_installed_component_packages "$part")
        if [[ ${KIND[$part]} != package && ${REMOVABLE[$part]} == yes ]]; then
            if [[ -e $RECEIPT_DIR/$part.receipt || -L $RECEIPT_DIR/$part.receipt ]]; then
                read_receipt "$part" || {
                    plan_error "$RECEIPT_ERROR"
                    return 1
                }
                REMOVE["$part"]=1
            elif [[ $has_package == false ]] && component_installed "$part"; then
                UNMANAGED_TOOLS+=("${LABEL[$part]} (no installer receipt)")
            fi
        fi
    done
}
