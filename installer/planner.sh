# Build typed argument arrays in memory. No eval, downloads, writes, or sudo.

reset_plan() {
    local i
    for ((i = 0; i < ${#ACTION_KIND[@]}; i++)); do unset "ACTION_ARGS_$i"; done
    ACTION_KIND=() ACTION_LABEL=() PLAN_NOTES=() PLAN=''
}

add_action() {
    local kind=$1 label=$2 index=${#ACTION_KIND[@]}
    shift 2
    ACTION_KIND+=("$kind") ACTION_LABEL+=("$label")
    declare -ga "ACTION_ARGS_$index"
    local -n arguments="ACTION_ARGS_$index"
    arguments=("$@")
}

removal_visit() {
    local id=$1 dependency
    local -a dependencies=()
    [[ ! ${REMOVAL_SEEN[$id]+present} ]] || return 0
    REMOVAL_SEEN["$id"]=1
    IFS=',' read -r -a dependencies <<<"${REQUIRES[$id]}"
    for dependency in "${dependencies[@]}"; do
        [[ -z $dependency || ! ${REMOVE[$dependency]+present} ]] || removal_visit "$dependency"
    done
    REMOVAL_ORDER+=("$id")
}

build_plan() {
    reset_plan
    if [[ $BACKEND != apt && $REMOVE_UNCHECKED == true ]]; then
        plan_error 'Removal of unchecked software is APT-only. Use --keep-unchecked on Fedora/Arch.'
        return 1
    fi
    expand_choices || return
    derive_removals || return
    local id repository package i
    local -a distro_packages=() vendor_packages=() mapped_packages=()
    declare -A repositories=() seen_packages=()
    PACKAGE_INSTALL_COUNT=0
    declare -gA REMOVAL_SEEN=()
    declare -ga REMOVAL_ORDER=()
    for id in "${FEATURE_IDS[@]}"; do [[ ! ${REMOVE[$id]+present} ]] || removal_visit "$id"; done
    for ((i = ${#REMOVAL_ORDER[@]} - 1; i >= 0; i--)); do
        id=${REMOVAL_ORDER[$i]}
        if [[ -f $RECEIPT_DIR/$id.receipt ]]; then
            add_action remove_managed "Back up and remove ${LABEL[$id]}" "$id"
        fi
    done
    backend_remove "${PACKAGE_REMOVAL_ORDER[@]}"
    # Updating package indexes is an implementation detail, not a checkbox.
    if ((${#ORDERED[@]})); then
        for id in "${ORDERED[@]}"; do
            if [[ ${KIND[$id]} == package || $id == apt-upgrade ]]; then
                backend_update
                break
            fi
        done
    fi
    if [[ ${RESOLVED["apt-upgrade"]+present} ]]; then backend_upgrade; fi
    for id in "${ORDERED[@]}"; do
        [[ ${KIND[$id]} == package ]] || continue
        read -r -a mapped_packages <<<"$(backend_package_name "$id")"
        for package in "${mapped_packages[@]}"; do
            [[ ! ${seen_packages[$package]+present} ]] || continue
            seen_packages["$package"]=1
            if [[ -n ${REPOSITORY[$id]} && $BACKEND != arch ]]; then
                vendor_packages+=("$package")
                repositories["${REPOSITORY[$id]}"]=1
            else distro_packages+=("$package"); fi
        done
    done
    PACKAGE_INSTALL_COUNT=$((${#distro_packages[@]} + ${#vendor_packages[@]}))
    backend_install "${distro_packages[@]}"
    for repository in docker spotify vscodium antigravity tailscale google-chrome; do
        [[ ! ${repositories[$repository]+present} ]] || backend_repository "$repository" || return
    done
    if ((${#repositories[@]})); then backend_update; fi
    backend_install "${vendor_packages[@]}"
    for id in "${ORDERED[@]}"; do
        case $id in
            neovim | go | fnm | node | pnpm | nerd-font | oh-my-zsh | zsh-autosuggestions | zsh-syntax-highlighting | claude-code | codex | opencode | gemini-cli | bun) plan_application "$id" || return ;;
            discord)
                if [[ $BACKEND == arch ]]; then backend_install discord; PACKAGE_INSTALL_COUNT=$((PACKAGE_INSTALL_COUNT + 1))
                else add_action deb 'Download and install Discord' 'https://discord.com/api/download?platform=linux&format=deb'; fi
                ;;
            mongodb-compass) add_action deb 'Download and install MongoDB Compass' "https://downloads.mongodb.com/compass/mongodb-compass_${VALUES[compass_version]}_amd64.deb" ;;
            android-sdk | android-studio) plan_android_application "$id" || return ;;
            config-i3) ;; # Startup choices are rendered after all selections resolve.
            config-*) plan_config "$id" || return ;;
        esac
    done
    [[ ! ${RESOLVED["config-i3"]+present} ]] || plan_i3 || return
    [[ ! ${RESOLVED[android-sdk]+present} ]] || plan_android_sdk || return
    for id in "${ORDERED[@]}"; do
        [[ $id == github-login || $id == tailscale-login ]] || plan_setting "$id" || return
    done
    for id in "${SERVICE_IDS[@]}"; do
        [[ ${EFFECTIVE_SERVICES[$id]} == keep ]] || add_action service "${EFFECTIVE_SERVICES[$id]} ${SERVICE_LABEL[$id]}" "${EFFECTIVE_SERVICES[$id]}" "${SERVICE_UNITS[$id]}"
    done
    for id in github-login tailscale-login; do [[ ! ${RESOLVED[$id]+present} ]] || plan_setting "$id" || return; done
    PLAN_NOTES+=('Only software covered by this catalog is reconciled. Required shared components are retained.'
        'Package configuration and personal dotfiles are retained on removal. No autoremove or purge.'
        'Managed directories/links are backed up; Node/pnpm removal uses fnm/npm. No session restarts.')
    [[ $PREVIEW_TARGET == false ]] || PLAN_NOTES+=('Target preview: installed package state is unknown; removal candidates will be determined on the target machine.')
    [[ $SYSTEMD == true ]] || PLAN_NOTES+=('Systemd is inactive; automatic service setup is skipped.')
    render_plan
}

render_plan() {
    local id i token quoted action_line package file_count=0
    local policy='ON - unchecked catalog software will be removed if installed'
    [[ $REMOVE_UNCHECKED == true ]] || policy='OFF - unchecked software is kept'
    local -a lines=("Target: $PLATFORM" "Remove unchecked: $policy" '' 'Selected software:')
    for id in "${CHOICE_IDS[@]}"; do [[ ! ${CHOSEN[$id]+present} ]] || lines+=("  ${CHOICE_LABEL[$id]}"); done
    ((${#CHOSEN[@]})) || lines+=('  (none)')
    lines+=('' "Package removals (${#REMOVAL_PACKAGES[@]}):")
    for package in "${PACKAGE_REMOVAL_ORDER[@]}"; do lines+=("  $package"); done
    ((${#REMOVAL_PACKAGES[@]})) || lines+=('  (none installed)')
    if ((${#RETAINED_PACKAGES[@]})); then
        lines+=('' 'Shared packages kept because selected software needs them:')
        for package in "${RETAINED_PACKAGES[@]}"; do lines+=("  $package"); done
    fi
    lines+=('' 'Other changes:')
    for ((i = 0; i < ${#ACTION_KIND[@]}; i++)); do
        local -n arguments="ACTION_ARGS_$i"
        case ${ACTION_KIND[$i]} in
            copy | write) file_count=$((file_count + 1)) ;;
            remove_managed) lines+=("  ${ACTION_LABEL[$i]}") ;;
            service | git_config | merge_json | android_sdk | android_env | android_launcher) lines+=("  ${ACTION_LABEL[$i]}") ;;
            command | root_command)
                if [[ " ${arguments[*]} " == *' apt-get '* ]]; then
                    if [[ " ${arguments[*]} " == *' upgrade '* ]]; then lines+=("  ${ACTION_LABEL[$i]}"); fi
                elif [[ ${arguments[0]} != "$DATA_DIR/fnm/fnm" && ${arguments[0]} != fc-cache ]]; then
                    lines+=("  ${ACTION_LABEL[$i]}")
                fi
                ;;
        esac
    done
    lines+=("  Install/update $PACKAGE_INSTALL_COUNT required packages" "  Configuration files to deploy: $file_count")
    if ((${#UNMANAGED_TOOLS[@]})); then lines+=('' 'Manually installed tools left in place (no known uninstall recipe):' "${UNMANAGED_TOOLS[@]}"); fi
    lines+=('' "${PLAN_NOTES[@]}")
    if [[ $VERBOSE == true ]]; then
        lines+=('' "Detailed actions (${#ACTION_KIND[@]}):")
        for ((i = 0; i < ${#ACTION_KIND[@]}; i++)); do
            local -n arguments="ACTION_ARGS_$i"
            action_line=''
            for token in "${arguments[@]}"; do
                printf -v quoted '%q' "$token"
                action_line+="$quoted "
            done
            lines+=("$((i + 1)). ${ACTION_LABEL[$i]}" "   ${ACTION_KIND[$i]}: $action_line")
        done
    fi
    printf -v PLAN '%s\n' "${lines[@]}"
}
