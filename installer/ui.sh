# whiptail/dialog frontend, with a dependency-free text fallback for dry-run.

choose_ui() {
    UI_TOOL=''
    if command -v whiptail >/dev/null 2>&1; then
        UI_TOOL=whiptail
    elif command -v dialog >/dev/null 2>&1; then
        UI_TOOL=dialog
    elif [[ $DRY_RUN == false ]]; then
        backend_bootstrap_ui
        if command -v whiptail >/dev/null 2>&1; then UI_TOOL=whiptail
        elif command -v dialog >/dev/null 2>&1; then UI_TOOL=dialog
        else
            fail 'UI setup did not provide whiptail or dialog.'
            return 1
        fi
    else
        printf '%s\n' 'No dialog tool found. Dry-run will use text menus without installing anything.' >&2
    fi
    UI_HEIGHT=22 UI_WIDTH=78 UI_LIST_HEIGHT=12
    local rows columns
    if read -r rows columns < <(stty size 2>/dev/null); then
        ((rows < 24)) || rows=24
        ((columns < 90)) || columns=90
        ((rows >= 16 && columns >= 60)) || {
            fail 'Please resize the terminal to at least 60 columns by 16 rows.'
            return 1
        }
        UI_HEIGHT=$((rows - 2)) UI_WIDTH=$((columns - 2)) UI_LIST_HEIGHT=$((rows - 12))
    fi
}

ui_menu() {
    local title=$1 prompt=$2 answer index i
    shift 2
    local -a options=("$@")
    if [[ -n $UI_TOOL ]]; then
        "$UI_TOOL" --backtitle "Dotfiles installer - $PLATFORM" --title "$title" --menu "$prompt" "$UI_HEIGHT" "$UI_WIDTH" "$UI_LIST_HEIGHT" "${options[@]}" 3>&1 1>&2 2>&3
    else
        printf '\n%s\n%s\n' "$title" "$prompt" >&2
        for ((i = 0; i < ${#options[@]}; i += 2)); do printf '%2s) %s - %s\n' "$((i / 2 + 1))" "${options[$i]}" "${options[$((i + 1))]}" >&2; done
        printf 'Number (empty to go back): ' >&2
        read -r answer || return 1
        [[ $answer =~ ^[0-9]{1,3}$ ]] || return 1
        index=$((10#$answer * 2 - 2))
        ((index >= 0 && index < ${#options[@]})) || return 1
        printf '%s' "${options[$index]}"
    fi
}

ui_checklist() {
    local title=$1 prompt=$2 answer id i number
    shift 2
    local -a options=("$@") numbers=()
    if [[ -n $UI_TOOL ]]; then
        "$UI_TOOL" --backtitle 'Dotfiles installer' --title "$title" --separate-output --checklist "$prompt" "$UI_HEIGHT" "$UI_WIDTH" "$UI_LIST_HEIGHT" "${options[@]}" 3>&1 1>&2 2>&3
    else
        printf '\n%s\n%s\n' "$title" "$prompt" >&2
        for ((i = 0; i < ${#options[@]}; i += 3)); do
            printf '%2s) [%s] %s - %s\n' "$((i / 3 + 1))" "${options[$((i + 2))]}" "${options[$i]}" "${options[$((i + 1))]}" >&2
        done
        printf 'Enter ALL desired item numbers, separated by spaces (none to clear, empty to cancel): ' >&2
        read -r answer || return 1
        [[ -n $answer ]] || return 1
        [[ $answer != none ]] || return 0
        read -r -a numbers <<<"$answer"
        for number in "${numbers[@]}"; do
            [[ $number =~ ^[0-9]{1,3}$ ]] || return 1
            i=$((10#$number * 3 - 3))
            ((i >= 0 && i < ${#options[@]})) || return 1
            id=${options[$i]}
            printf '%s\n' "$id"
        done
    fi
}

ui_input() {
    local title=$1 prompt=$2 current=$3 value
    if [[ -n $UI_TOOL ]]; then
        "$UI_TOOL" --title "$title" --inputbox "$prompt" "$UI_HEIGHT" "$UI_WIDTH" "$current" 3>&1 1>&2 2>&3
    else
        printf '\n%s\n%s\nCurrent: %s\nNew value (empty clears it): ' "$title" "$prompt" "$current" >&2
        read -r value || return 1
        printf '%s' "$value"
    fi
}

ui_message() {
    if [[ -n $UI_TOOL ]]; then
        local -a scroll=()
        [[ $UI_TOOL != whiptail ]] || scroll=(--scrolltext)
        local message=$2
        if [[ $UI_TOOL == whiptail ]]; then message=$'Arrow keys scroll. Tab, then Enter continues.\n\n'"$message"; fi
        "$UI_TOOL" --title "$1" "${scroll[@]}" --msgbox "$message" "$UI_HEIGHT" "$UI_WIDTH"
    else
        printf '\n%s\n%s\nPress Enter to return. ' "$1" "$2" >&2
        read -r _ || true
    fi
}

ui_confirm() {
    if [[ -n $UI_TOOL ]]; then
        "$UI_TOOL" --title "$1" --defaultno --yesno "$2" "$UI_HEIGHT" "$UI_WIDTH"
    else
        local answer
        printf '\n%s\n%s\nType yes to continue: ' "$1" "$2" >&2
        read -r answer && [[ $answer == yes ]]
    fi
}

ui_software() {
    local id state result
    local -a options=()
    for id in "${CHOICE_IDS[@]}"; do
        choice_available "$id" || continue
        state=OFF
        [[ ! ${CHOSEN[$id]+present} ]] || state=ON
        options+=("$id" "${CHOICE_LABEL[$id]}" "$state")
    done
    local policy='Unchecked software will be REMOVED if installed.'
    [[ $REMOVE_UNCHECKED == true ]] || policy='Unchecked software will be KEPT.'
    if result=$(ui_checklist 'Software' "Space toggles; Tab then Enter accepts. $policy Shared dependencies stay while needed. Review removals before applying." "${options[@]}"); then
        CHOSEN=()
        while IFS= read -r id; do [[ -z $id ]] || CHOSEN["$id"]=1; done <<<"$result"
    fi
    return 0
}

ui_settings() {
    local level=$1 key choice value display
    local -a options=()
    while true; do
        options=()
        for key in "${SETTING_IDS[@]}"; do
            [[ ${SETTING_LEVEL[$key]} == "$level" ]] && setting_relevant "$key" || continue
            display=${VALUES[$key]:-unchanged}
            options+=("$key" "${SETTING_LABEL[$key]}: $display")
        done
        if ((${#options[@]} == 0)); then
            ui_message 'Settings' 'Select software to see its settings.'
            return 0
        fi
        choice=$(ui_menu 'Settings for selected software' 'Blank optional values leave existing settings unchanged. Cancel returns.' "${options[@]}") || break
        case $choice in
            use_dotfiles | upgrade | github_login | default_shell | tailscale_login | docker_access | virtualization_access | discord_updates | android_accept_licenses)
                value=$(ui_menu "${SETTING_LABEL[$choice]}" "${SETTING_HELP[$choice]} Current: ${VALUES[$choice]}" on Yes off No) || continue
                ;;
            screen_blanking | display_power)
                value=$(ui_menu "${SETTING_LABEL[$choice]}" "${SETTING_HELP[$choice]} Current: ${VALUES[$choice]}" keep 'Leave unchanged' on Enable off Disable) || continue
                ;;
            *) value=$(ui_input "${SETTING_LABEL[$choice]}" "${SETTING_HELP[$choice]}" "${VALUES[$choice]}") || continue ;;
        esac
        VALUES["$choice"]=$value
    done
}

ui_services() {
    local id choice state
    local -a options=()
    while true; do
        options=()
        for id in "${SERVICE_IDS[@]}"; do
            [[ ${CHOSEN[${SERVICE_OWNER[$id]}]+present} ]] || continue
            options+=("$id" "${SERVICE_LABEL[$id]}: ${SERVICES[$id]}")
        done
        if ((${#options[@]} == 0)); then
            ui_message 'Services' 'No selected software has service controls.'
            return 0
        fi
        choice=$(ui_menu 'Advanced service overrides' 'Related units are managed together. Auto enables selected services when systemd is active.' "${options[@]}") || break
        if state=$(ui_menu "${SERVICE_LABEL[$choice]}" 'Enable/disable also starts/stops the service.' auto 'Automatic setup' keep 'Leave unchanged' enable 'Enable and start' disable 'Disable and stop'); then SERVICES["$choice"]=$state; fi
    done
}

ui_advanced() {
    local choice preset id
    local -a options=()
    while choice=$(ui_menu 'Advanced options' 'Defaults handle dependencies, package indexes, configs and related service units.' \
        settings 'Versions and less common settings for selected tools' \
        services 'Override automatic service setup' \
        preset 'Replace software choices with a preset' \
        details "Detailed plan: $VERBOSE"); do
        case $choice in
            settings) ui_settings advanced ;;
            services) ui_services ;;
            preset)
                options=()
                for id in "${PRESET_IDS[@]}"; do options+=("$id" "${PRESETS[$id]:-No software}"); done
                if preset=$(ui_menu 'Starting preset' 'Replaces software selection; keeps your settings and removal policy.' "${options[@]}"); then
                    CHOSEN=()
                    csv_add CHOSEN "${PRESETS[$preset]}"
                fi
                ;;
            details) if [[ $VERBOSE == true ]]; then VERBOSE=false; else VERBOSE=true; fi ;;
        esac
    done
}

interactive_choices() {
    local choice state policy
    while true; do
        policy='ON - remove unchecked software'
        [[ $REMOVE_UNCHECKED == true ]] || policy='OFF - keep unchecked software'
        choice=$(ui_menu 'Machine setup' "Selected tools: ${#CHOSEN[@]}. Remove unchecked: $policy. Existing tools start checked; nothing is applied until review." \
            software 'Select tools and applications' \
            settings 'Settings for selected tools' \
            cleanup "Remove unchecked: $policy" \
            advanced 'Presets, versions and service overrides' \
            finish 'Review changes and finish' \
            cancel 'Exit without applying') || return 1
        case $choice in
            software) ui_software ;;
            settings) ui_settings basic ;;
            cleanup)
                if [[ $BACKEND != apt ]]; then
                    ui_message 'Unchecked software' 'Fedora/Arch keep unchecked software. Automatic removal with dependency protection is APT-only.'
                    continue
                fi
                if state=$(ui_menu 'Unchecked software' 'Applies to installed catalog software. Required shared components and personal configuration files are kept.' true 'Remove unchecked software (default)' false 'Keep unchecked software'); then REMOVE_UNCHECKED=$state; fi
                ;;
            advanced) ui_advanced ;;
            finish)
                if build_plan; then
                    ui_message 'Review changes' "$PLAN" || continue
                    [[ $DRY_RUN == false ]] || return 0
                    if ui_confirm 'Apply these changes?' "Apply the reviewed software and settings? ${#REMOVAL_PACKAGES[@]} installed packages will be removed. Remove unchecked is $REMOVE_UNCHECKED. Personal config files are retained."; then return 0; fi
                else ui_message 'Choices need attention' "${PLAN_ERROR:-Unable to build a plan.}"; fi
                ;;
            cancel) return 1 ;;
        esac
    done
}
