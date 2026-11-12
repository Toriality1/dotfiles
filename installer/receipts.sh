# Literal NUL-delimited receipts. Never load installed data as shell code.

receipt_path_allowed() {
    local id=$1 path=$2
    [[ $path != *'/../'* && $path != */.. && $path != *'/./'* ]] || return 1
    case $id in
        neovim) [[ $path == "$APPS_DIR/neovim/"* || $path == "$LOCAL_BIN/nvim" ]] ;;
        go) [[ $path == "$APPS_DIR/go/"* || $path == "$LOCAL_BIN/go" || $path == "$LOCAL_BIN/gofmt" ]] ;;
        fnm) [[ $path == "$APPS_DIR/fnm/"* || $path == "$LOCAL_BIN/fnm" || $path == "$DATA_DIR/fnm/fnm" ]] ;;
        nerd-font) [[ $path == "$DATA_DIR/fonts/JetBrainsMono/"* ]] ;;
        android-sdk)
            [[ $path == "$APPS_DIR/android-sdk/"* || $path == "$ANDROID_SDK_DIR/cmdline-tools/"* || $path == "$ANDROID_SDK_DIR/platform-tools" || $path == "$ANDROID_SDK_DIR/build-tools/"* || $path == "$ANDROID_SDK_DIR/platforms/android-"* ]]
            ;;
        android-studio) [[ $path == "$DATA_DIR/android/studio" || $path == "$LOCAL_BIN/android-studio" || $path == "$DATA_DIR/applications/dotfiles-android-studio.desktop" ]] ;;
        android-ndk) [[ $path == "$ANDROID_SDK_DIR/ndk/"* ]] ;;
        android-emulator) [[ $path == "$ANDROID_SDK_DIR/emulator" || $path == "$ANDROID_SDK_DIR/system-images/"* || $path == "$ANDROID_AVD_DIR/"* ]] ;;
        oh-my-zsh) [[ $path == "$DATA_DIR/.oh-my-zsh" ]] ;;
        zsh-autosuggestions | zsh-syntax-highlighting) [[ $path == "$DATA_DIR/.oh-my-zsh/custom/plugins/$id" ]] ;;
        *) return 1 ;;
    esac
}

read_receipt() {
    local id=$1 file=$RECEIPT_DIR/$1.receipt token value
    RECEIPT_ERROR="No valid installer receipt for $id; leave manually installed tools alone."
    declare -ga RECEIPT_PATHS=() RECEIPT_VERSIONS=() RECEIPT_DEPS=()
    [[ -f $file && ! -L $file ]] || return 1
    local -a fields=()
    while IFS= read -r -d '' value; do fields+=("$value"); done <"$file"
    [[ ${fields[0]:-} == dotfiles-v1 && ${fields[1]:-} == "$id" && ${fields[2]:-} == "$INSTALL_HOME" ]] || return 1
    [[ -z $value && $((${#fields[@]} % 2)) == 1 ]] || return 1
    local i
    for ((i = 3; i < ${#fields[@]}; i += 2)); do
        token=${fields[$i]} value=${fields[$((i + 1))]:-}
        case $token in
            path)
                receipt_path_allowed "$id" "$value" || return 1
                RECEIPT_PATHS+=("$value")
                ;;
            version)
                [[ ($id == node || $id == pnpm || $(npm_package_for "$id" || true)) && $value =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
                RECEIPT_VERSIONS+=("$value")
                ;;
            dependency)
                valid_id "$value" && [[ ${LABEL[$value]+present} ]] || return 1
                RECEIPT_DEPS+=("$value")
                ;;
            *) return 1 ;;
        esac
    done
    RECEIPT_ERROR=''
}

claim_path() {
    local id=$1 path=$2
    receipt_path_allowed "$id" "$path" || {
        fail "Unexpected managed path for $id: $path"
        return 1
    }
    CLAIM_IDS+=("$id") CLAIM_PATHS+=("$path")
}

record_receipt() {
    local id=$1 version=$2 i value temp dependency
    local -a paths=() versions=() dependencies=()
    if [[ -e $RECEIPT_DIR/$id.receipt ]]; then
        read_receipt "$id" || {
            fail "$RECEIPT_ERROR"
            return 1
        }
        paths=("${RECEIPT_PATHS[@]}") versions=("${RECEIPT_VERSIONS[@]}")
    fi
    for ((i = 0; i < ${#CLAIM_IDS[@]}; i++)); do [[ ${CLAIM_IDS[$i]} != "$id" ]] || paths+=("${CLAIM_PATHS[$i]}"); done
    if [[ $id == node || $id == pnpm || $(npm_package_for "$id" || true) ]]; then
        value=$("$DATA_DIR/fnm/fnm" --fnm-dir "$DATA_DIR/fnm" exec --using "$version" node --version)
        [[ $value =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
            fail 'Cannot resolve installed Node version.'
            return 1
        }
        versions+=("$value")
    fi
    mkdir -p -- "$RECEIPT_DIR"
    new_temp
    temp=$TEMP_DIR/receipt
    {
        printf '%s\0' dotfiles-v1 "$id" "$INSTALL_HOME"
        declare -A seen=()
        for value in "${paths[@]}"; do
            [[ ! ${seen[$value]+present} ]] || continue
            seen["$value"]=1
            printf '%s\0' path "$value"
        done
        seen=()
        for value in "${versions[@]}"; do
            [[ ! ${seen[$value]+present} ]] || continue
            seen["$value"]=1
            printf '%s\0' version "$value"
        done
        IFS=',' read -r -a dependencies <<<"${REQUIRES[$id]}"
        for dependency in "${dependencies[@]}"; do [[ -z $dependency ]] || printf '%s\0' dependency "$dependency"; done
    } >"$temp"
    chmod 600 "$temp"
    install_file "$temp" "$RECEIPT_DIR/$id.receipt" false
}

preflight_managed_removal() {
    local id dependency file
    ((${#REMOVE[@]})) || return 0
    for file in "$RECEIPT_DIR"/*.receipt; do
        [[ -f $file ]] || continue
        id=${file##*/}
        id=${id%.receipt}
        valid_id "$id" && [[ ${LABEL[$id]+present} ]] || {
            fail "Unrecognized receipt: $file"
            return 1
        }
        [[ ! ${REMOVE[$id]+present} ]] || continue
        read_receipt "$id" || {
            fail "$RECEIPT_ERROR"
            return 1
        }
        for dependency in "${RECEIPT_DEPS[@]}"; do
            [[ ! ${REMOVE[$dependency]+present} ]] || {
                fail "Managed $id still needs $dependency. Select both for removal."
                return 1
            }
        done
    done
}

remove_managed() {
    local id=$1 path version
    read_receipt "$id" || {
        fail "$RECEIPT_ERROR"
        return 1
    }
    for version in "${RECEIPT_VERSIONS[@]}"; do
        case $id in
            node) "$DATA_DIR/fnm/fnm" --fnm-dir "$DATA_DIR/fnm" uninstall "$version" ;;
            pnpm) "$DATA_DIR/fnm/fnm" --fnm-dir "$DATA_DIR/fnm" exec --using "$version" npm uninstall --global pnpm ;;
            claude-code | codex | opencode | gemini-cli | bun)
                "$DATA_DIR/fnm/fnm" --fnm-dir "$DATA_DIR/fnm" exec --using "$version" npm uninstall --global "$(npm_package_for "$id")"
                ;;
        esac
    done
    for path in "${RECEIPT_PATHS[@]}"; do backup_path "$path" false move; done
    backup_path "$RECEIPT_DIR/$id.receipt" false move
}
