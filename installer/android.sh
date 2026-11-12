# Android plans and apply helpers. Downloads come from Google's pinned releases.

load_android_metadata() {
    declare -gA ANDROID_RELEASE=()
    local key value
    while IFS='|' read -r key value; do
        [[ -n $key && $key != \#* ]] || continue
        ANDROID_RELEASE["$key"]=$value
    done <"$REPO_DIR/installer/android.conf"
}

validate_android_settings() {
    [[ ${VALUES[android_api]} =~ ^[0-9]{2,3}$ && ${VALUES[android_build_tools]} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        plan_error 'Android requires a numeric API level and a complete build-tools release.'; return 1;
    }
    [[ ${VALUES[android_accept_licenses]} == on || ${VALUES[android_accept_licenses]} == off ]] || {
        plan_error 'android_accept_licenses must be on or off.'; return 1;
    }
    if [[ ${RESOLVED[android-ndk]+present} && ! ${VALUES[android_ndk_version]} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        plan_error 'Invalid Android NDK version.'; return 1
    fi
    if [[ ${RESOLVED[android-emulator]+present} && ! ${VALUES[android_avd_name]} =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$ ]]; then
        plan_error 'Android AVD names must contain only letters, digits, underscores and hyphens.'; return 1
    fi
    if [[ $NON_INTERACTIVE == true && $DRY_RUN == false && ${VALUES[android_accept_licenses]} == off && ! -s $ANDROID_SDK_DIR/licenses/android-sdk-license ]]; then
        plan_error 'Review https://developer.android.com/studio#terms and set android_accept_licenses=on, or use interactive installation to accept SDK licenses.'
        return 1
    fi
}

plan_android_application() {
    load_android_metadata
    local destination source_path desktop quoted icon
    case $1 in
        android-sdk)
            if [[ $PREVIEW_TARGET == true || ! -f $ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager ]]; then
                # avdmanager discovers the SDK from the physical tools path.
                # Keep versioned tools inside the SDK, even when latest is a link.
                destination=$ANDROID_SDK_DIR/cmdline-tools/${ANDROID_RELEASE[cmdline_build]}
                plan_archive android-sdk "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_RELEASE[cmdline_build]}_latest.zip" \
                    "$destination" 1 bin/sdkmanager "${ANDROID_RELEASE[cmdline_linux_sha256]}"
                plan_link android-sdk "$destination" "$ANDROID_SDK_DIR/cmdline-tools/latest"
            else PLAN_NOTES+=('Reuse existing Android command-line tools; existing SDK packages and licenses are retained.'); fi
            ;;
        android-studio)
            destination=$DATA_DIR/android/studio
            plan_archive android-studio "https://dl.google.com/android/studio/ide-zips/${ANDROID_RELEASE[studio_release]}/${ANDROID_RELEASE[studio_archive]}" \
                "$destination" 1 bin/studio.sh "${ANDROID_RELEASE[studio_linux_sha256]}"
            add_action android_launcher 'Create Android Studio launcher with SDK environment' "$destination/bin/studio.sh" "$ANDROID_SDK_DIR" "$LOCAL_BIN/android-studio"
            quoted=${LOCAL_BIN//\\/\\\\}
            quoted=${quoted//\"/\\\"} quoted=${quoted//\$/\\\$} quoted=${quoted//\`/\\\`} quoted=${quoted//%/%%}
            icon=$destination/bin/studio.svg
            printf -v desktop '[Desktop Entry]\nType=Application\nName=Android Studio\nExec="%s/android-studio" %%f\nIcon=%s\nCategories=Development;IDE;\nTerminal=false\n' "$quoted" "$icon"
            source_path=$DATA_DIR/applications/dotfiles-android-studio.desktop
            add_action write 'Add Android Studio to the application launcher' "$source_path" "$desktop"
            add_action claim 'Record Android Studio launcher ownership' android-studio "$source_path"
            ;;
    esac
    add_action receipt "Record managed $1 files" "$1" ''
}

install_android_launcher() {
    local studio=$1 sdk=$2 launcher=$3 content quoted_studio quoted_sdk
    printf -v quoted_studio '%q' "$studio"
    printf -v quoted_sdk '%q' "$sdk"
    printf -v content '#!/usr/bin/env bash\nexport ANDROID_HOME=${ANDROID_HOME:-%s}\nexec %s "$@"\n' "$quoted_sdk" "$quoted_studio"
    write_file "$launcher" "$content" false
    chmod u+x -- "$launcher"
    claim_path android-studio "$launcher"
}

plan_android_sdk() {
    local ndk='' avd='' zsh_rc=${ZDOTDIR:-$INSTALL_HOME}/.zshrc
    [[ ! ${RESOLVED[android-ndk]+present} ]] || ndk=${VALUES[android_ndk_version]}
    [[ ! ${RESOLVED[android-emulator]+present} ]] || avd=${VALUES[android_avd_name]}
    [[ ! ${RESOLVED[config-zsh]+present} ]] || zsh_rc=$CONFIG_DIR/zsh/.zshrc
    [[ $zsh_rc == /* && $zsh_rc != *$'\n'* && $zsh_rc != *$'\r'* ]] || {
        plan_error 'ZDOTDIR must be an absolute single-line directory.'; return 1;
    }
    add_action android_sdk "Install Android API ${VALUES[android_api]}, build tools${ndk:+, NDK}${avd:+ and emulator/AVD}" \
        "${VALUES[android_api]}" "${VALUES[android_build_tools]}" "${VALUES[android_accept_licenses]}" "$ndk" "$avd"
    add_action android_env 'Configure Android SDK paths in Bash and Zsh' "$zsh_rc"
    PLAN_NOTES+=('Android SDK packages already present are retained. Only newly installed SDK files are owned by this installer.'
        'Android Studio GUI and emulators are not launched. Emulator acceleration requires working KVM access on Linux.')
    if [[ ${VALUES[android_accept_licenses]} == on ]]; then
        PLAN_NOTES+=('Accept the licenses displayed by sdkmanager for the requested Android SDK packages.')
    else PLAN_NOTES+=('Android SDK licenses require interactive acceptance unless already accepted: https://developer.android.com/studio#terms'); fi
}

android_java_env() {
    ANDROID_JAVA_ARGS=("ANDROID_HOME=$ANDROID_SDK_DIR")
    if [[ -n ${JAVA_HOME:-} && -x $JAVA_HOME/bin/java ]]; then ANDROID_JAVA_ARGS+=("JAVA_HOME=$JAVA_HOME")
    elif [[ -x $DATA_DIR/android/studio/jbr/bin/java ]]; then ANDROID_JAVA_ARGS+=("JAVA_HOME=$DATA_DIR/android/studio/jbr"); fi
}

install_android_packages() {
    local api=$1 build=$2 accept=$3 ndk=$4 avd=$5 id path package index status=0 marker image
    local sdkmanager=$ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager
    local -a packages=(platform-tools "platforms;android-$api" "build-tools;$build")
    local -a paths=("$ANDROID_SDK_DIR/platform-tools" "$ANDROID_SDK_DIR/platforms/android-$api" "$ANDROID_SDK_DIR/build-tools/$build")
    local -a owners=(android-sdk android-sdk android-sdk) missing=() missing_indexes=()
    if [[ -n $ndk ]]; then
        packages+=("ndk;$ndk") paths+=("$ANDROID_SDK_DIR/ndk/$ndk") owners+=(android-ndk)
    fi
    if [[ -n $avd ]]; then
        image="system-images;android-$api;google_apis;x86_64"
        packages+=(emulator "$image") paths+=("$ANDROID_SDK_DIR/emulator" "$ANDROID_SDK_DIR/system-images/android-$api/google_apis/x86_64")
        owners+=(android-emulator android-emulator)
    fi
    for ((index=0; index<${#packages[@]}; index++)); do
        path=${paths[$index]}
        [[ ! -f $path/source.properties ]] || { printf 'Keeping Android package %s\n' "${packages[$index]}"; continue; }
        [[ ! -e $path && ! -L $path ]] || { fail "Incomplete Android package directory: $path"; return 1; }
        missing+=("${packages[$index]}") missing_indexes+=("$index")
    done
    android_java_env
    if ((${#missing[@]})); then
        if [[ $accept == on ]]; then
            # With pipefail, yes normally receives SIGPIPE when sdkmanager exits.
            # Preserve sdkmanager's exit status rather than the producer's status.
            yes | env "${ANDROID_JAVA_ARGS[@]}" "$sdkmanager" --sdk_root="$ANDROID_SDK_DIR" "${missing[@]}" || status=${PIPESTATUS[1]}
        elif [[ $NON_INTERACTIVE == true ]]; then
            env "${ANDROID_JAVA_ARGS[@]}" "$sdkmanager" --sdk_root="$ANDROID_SDK_DIR" "${missing[@]}" </dev/null || status=$?
        else env "${ANDROID_JAVA_ARGS[@]}" "$sdkmanager" --sdk_root="$ANDROID_SDK_DIR" "${missing[@]}" || status=$?; fi
        # Retain ownership information even if a later package failed to install.
        for index in "${missing_indexes[@]}"; do
            path=${paths[$index]} id=${owners[$index]}
            if [[ -f $path/source.properties ]]; then claim_path "$id" "$path"
            else status=1; fi
        done
    fi
    record_receipt android-sdk ''
    [[ -z $ndk ]] || record_receipt android-ndk ''
    [[ -z $avd ]] || record_receipt android-emulator ''
    ((status == 0)) || { fail 'Android SDK setup did not complete. Review sdkmanager output and required licenses.'; return 1; }
    if [[ -n $avd ]]; then
        mkdir -p -- "$ANDROID_AVD_DIR"
        if [[ -e $ANDROID_AVD_DIR/$avd.ini || -e $ANDROID_AVD_DIR/$avd.avd ]]; then
            printf 'Keeping existing Android virtual device %s\n' "$avd"
        else
            env "${ANDROID_JAVA_ARGS[@]}" ANDROID_USER_HOME="$ANDROID_USER_DIR" ANDROID_AVD_HOME="$ANDROID_AVD_DIR" \
                "$ANDROID_SDK_DIR/cmdline-tools/latest/bin/avdmanager" create avd --name "$avd" --package "$image" --path "$ANDROID_AVD_DIR/$avd.avd" <<<no
            [[ -f $ANDROID_AVD_DIR/$avd.ini && -f $ANDROID_AVD_DIR/$avd.avd/config.ini ]] || { fail 'AVD creation did not complete.'; return 1; }
            claim_path android-emulator "$ANDROID_AVD_DIR/$avd.ini"
            claim_path android-emulator "$ANDROID_AVD_DIR/$avd.avd"
            record_receipt android-emulator ''
        fi
    fi
}

append_android_hook() {
    local destination=$1 hook=$2
    if [[ -f $destination && $(<"$destination") == *"$hook"* ]]; then return 0; fi
    new_temp
    local content=$TEMP_DIR/shell-config
    [[ ! -f $destination ]] || cat -- "$destination" >"$content"
    printf '\n# Android SDK environment managed by the dotfiles installer.\n%s\n' "$hook" >>"$content"
    install_file "$content" "$destination" false
}

install_android_environment() {
    local zsh_rc=$1 content sdk studio
    printf -v sdk '%q' "$ANDROID_SDK_DIR"
    printf -v studio '%q' "$DATA_DIR/android/studio"
    printf -v content 'export ANDROID_HOME=${ANDROID_HOME:-%s}\n' "$sdk"
    content+="if [ -z \"\${JAVA_HOME:-}\" ] && [ -x $studio/jbr/bin/java ]; then export JAVA_HOME=$studio/jbr; fi"$'\n'
    content+=$'for android_tool_dir in "$ANDROID_HOME/cmdline-tools/latest/bin" "$ANDROID_HOME/platform-tools" "$ANDROID_HOME/emulator" "${JAVA_HOME:+$JAVA_HOME/bin}"; do\n'
    content+=$'  [ -d "$android_tool_dir" ] || continue\n  case ":$PATH:" in *":$android_tool_dir:"*) ;; *) PATH="$android_tool_dir:$PATH" ;; esac\ndone\nexport PATH\nunset android_tool_dir\n'
    write_file "$CONFIG_DIR/android/env.sh" "$content" false
    local hook='[ ! -r "${XDG_CONFIG_HOME:-$HOME/.config}/android/env.sh" ] || . "${XDG_CONFIG_HOME:-$HOME/.config}/android/env.sh"'
    append_android_hook "$INSTALL_HOME/.bashrc" "$hook"
    append_android_hook "$zsh_rc" "$hook"
}
