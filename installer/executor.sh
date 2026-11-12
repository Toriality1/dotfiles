# Apply a reviewed plan. All mutations are kept in this layer.

run_privileged() {
    if ((EUID == 0)); then "$@"; else sudo -- "$@"; fi
}

new_temp() {
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-installer.XXXXXXXX")
    TEMP_DIRS+=("$TEMP_DIR")
}
cleanup() {
    local path
    for path in "${TEMP_DIRS[@]}"; do [[ ! -d $path ]] || rm -rf -- "$path"; done
}

backup_path() {
    local path=$1 privileged=$2 operation=${3:-copy} destination slot
    [[ -e $path || -L $path ]] || return 0
    [[ ! ${BACKED_UP[$path]+present} ]] || {
        # The original was already backed up. Preserve a later removal too.
        [[ $operation != move ]] || {
            fail "Path changed twice before removal: $path"
            return 1
        }
        return 0
    }
    # Separate entries avoid collisions when both a plugin and its parent
    # application directory are backed up in the same run.
    printf -v slot '%04d' "$((${#BACKED_UP[@]} + 1))"
    destination=$BACKUP_DIR/$slot$path
    BACKUP_LOCATIONS["$path"]=$destination
    mkdir -p -- "${destination%/*}"
    if [[ $privileged == true ]]; then
        if [[ $operation == move ]]; then
            run_privileged mv -- "$path" "$destination"
        else run_privileged cp -a -- "$path" "$destination"; fi
    elif [[ $operation == move ]]; then
        mv -- "$path" "$destination"
    else cp -a -- "$path" "$destination"; fi
    BACKED_UP["$path"]=1
}

install_file() {
    local source=$1 destination=$2 privileged=$3
    [[ ! -d $destination ]] || {
        fail "Expected a file, found a directory: $destination"
        return 1
    }
    if [[ $privileged == true ]]; then
        if [[ -f $destination && ! -L $destination ]] && cmp -s -- "$source" "$destination"; then return 0; fi
        backup_path "$destination" true
        run_privileged install -D -m 644 -- "$source" "$destination"
    else
        if [[ -f $destination && ! -L $destination ]] && cmp -s -- "$source" "$destination"; then return 0; fi
        # A config symlink may point into another checkout. Preserve both ends.
        if [[ -L $destination ]]; then
            local target
            target=$(readlink -f -- "$destination") || {
                fail "Cannot resolve $destination"
                return 1
            }
            backup_path "$target" false
        fi
        backup_path "$destination" false
        mkdir -p -- "${destination%/*}"
        [[ ! -L $destination ]] || rm -- "$destination"
        cp -p -- "$source" "$destination"
    fi
}

write_file() {
    local destination=$1 content=$2 privileged=$3
    new_temp
    printf '%s' "$content" >"$TEMP_DIR/content"
    install_file "$TEMP_DIR/content" "$destination" "$privileged"
}

download() {
    curl --fail --location --show-error --silent --proto '=https' --proto-redir '=https' --output "$2" "$1"
}

download_verified() {
    local url=$1 checksum=$2 destination=$3
    if [[ -n ${DOTFILES_DOWNLOAD_CACHE:-} && -f $DOTFILES_DOWNLOAD_CACHE/$checksum ]]; then
        cp -- "$DOTFILES_DOWNLOAD_CACHE/$checksum" "$destination"
    else download "$url" "$destination"; fi
    [[ $(sha256sum -- "$destination") == "$checksum "* ]] || {
        fail "SHA-256 mismatch for $url"; return 1;
    }
}

safe_archive_path() {
    [[ -n $1 && $1 != /* && $1 != *\\* && $1 != *:* && /$1/ != *'/../'* ]]
}

extract_archive() {
    local file=$1 destination=$2 strip=$3 format=$4 line path
    local listing=$TEMP_DIR/listing
    if [[ $format == zip ]]; then
        unzip -Z -1 "$file" >"$listing"
        while IFS= read -r path; do safe_archive_path "$path" || {
            fail "Unsafe archive path: $path"
            return 1
        }; done <"$listing"
        unzip -Z -l "$file" >"$listing"
        while IFS= read -r line; do
            # ZIP metadata lines start with mode fields; reject links/devices.
            if [[ $line =~ ^[bcdlps-][rwxstST?-]{9}[[:space:]] ]]; then
                [[ $line == [-d]* ]] || {
                    fail 'Archive contains a link or special file.'
                    return 1
                }
            fi
        done <"$listing"
        if ((strip > 0)); then
            # ZIP archives used here have a single enclosing directory per
            # stripped level. Reject ambiguous layouts instead of flattening.
            new_temp
            local zip_source=$TEMP_DIR/unpacked level
            local -a zip_entries=()
            unzip -q "$file" -d "$zip_source"
            for ((level=0; level<strip; level++)); do
                mapfile -d '' -t zip_entries < <(find "$zip_source" -mindepth 1 -maxdepth 1 -print0)
                if ((${#zip_entries[@]} != 1)) || [[ ! -d ${zip_entries[0]} ]]; then
                    fail 'ZIP archive does not have a single enclosing directory.'
                    return 1
                fi
                zip_source=${zip_entries[0]}
            done
            cp -a -- "$zip_source/." "$destination/"
        else unzip -q "$file" -d "$destination"; fi
    else
        # C locales octal-escape valid Unicode (including Go's test sources).
        # A fixed UTF-8 locale preserves printable names while still escaping
        # control characters, which safe_archive_path deliberately rejects.
        LC_ALL=C.UTF-8 tar --quoting-style=escape -tf "$file" >"$listing"
        while IFS= read -r path; do safe_archive_path "$path" || {
            fail "Unsafe archive path: $path"
            return 1
        }; done <"$listing"
        LC_ALL=C.UTF-8 tar --quoting-style=escape -tvf "$file" >"$listing"
        while IFS= read -r line; do [[ $line == [-d]* ]] || {
            fail 'Archive contains a link or special file.'
            return 1
        }; done <"$listing"
        tar -xf "$file" --no-same-owner --no-same-permissions --strip-components="$strip" -C "$destination"
    fi
}

install_archive() {
    local id=$1 url=$2 destination=$3 strip=$4 expected=$5 checksum=${6:-} format=tar staging scratch
    if [[ -f $destination/$expected && ! -L $destination ]]; then
        printf 'Keeping existing %s\n' "$destination"
        return 0
    fi
    [[ ! -e $destination && ! -L $destination ]] || {
        fail "Incomplete existing directory; inspect it before retrying: $destination"
        return 1
    }
    new_temp
    scratch=$TEMP_DIR
    if [[ -n $checksum ]]; then download_verified "$url" "$checksum" "$scratch/archive"
    else download "$url" "$scratch/archive"; fi
    [[ $url != *.zip ]] || format=zip
    mkdir "$scratch/extracted"
    extract_archive "$scratch/archive" "$scratch/extracted" "$strip" "$format"
    [[ -f $scratch/extracted/$expected ]] || {
        fail "Archive does not contain $expected"
        return 1
    }
    [[ $id == nerd-font ]] || chmod u+x "$scratch/extracted/$expected"
    mkdir -p -- "${destination%/*}"
    # Move from a staging directory on the destination filesystem.
    staging=$(mktemp -d "${destination%/*}/.install.XXXXXXXX")
    TEMP_DIRS+=("$staging")
    # Rename on a shared filesystem; mv copies across filesystems when needed.
    # Large SDK/IDE archives otherwise retain a second full extracted copy.
    mv -T -- "$scratch/extracted" "$staging"
    mv -- "$staging" "$destination"
    claim_path "$id" "$destination"
}

install_link() {
    local id=$1 source=$2 destination=$3
    [[ -e $source ]] || {
        fail "Link source is missing: $source"
        return 1
    }
    if [[ -L $destination && $(readlink -- "$destination") == "$source" ]]; then return 0; fi
    backup_path "$destination" false move
    mkdir -p -- "${destination%/*}"
    ln -s -- "$source" "$destination"
    claim_path "$id" "$destination"
}

install_clone() {
    local id=$1 url=$2 destination=$3
    if [[ -e $destination || -L $destination ]]; then
        [[ -d $destination/.git ]] || {
            fail "Existing path is not a Git checkout: $destination"
            return 1
        }
        printf 'Keeping existing checkout %s\n' "$destination"
        return 0
    fi
    mkdir -p -- "${destination%/*}"
    git clone --depth 1 -- "$url" "$destination"
    claim_path "$id" "$destination"
}

check_package_removal() {
    local output package selected found
    local -a packages=("$@")
    output=$(LC_ALL=C apt-get --simulate remove -- "${packages[@]}") || return
    while IFS= read -r package; do
        found=false
        for selected in "${packages[@]}"; do [[ ${package%%:*} != "$selected" ]] || found=true; done
        [[ $found == true ]] || {
            fail "APT would also remove $package. Keep the software that needs it selected, or turn off removal of unchecked software."
            return 1
        }
    done < <(awk '$1=="Remv" {print $2}' <<<"$output")
}

apply_service() {
    local state=$1 units_csv=$2 unit
    local -a units=()
    IFS=',' read -r -a units <<<"$units_csv"
    for unit in "${units[@]}"; do
        if run_privileged systemctl cat "$unit" >/dev/null 2>&1; then
            run_privileged systemctl "$state" --now "$unit"
        elif [[ $state == enable ]]; then
            fail "Service unit not found: $unit"
            return 1
        else printf 'Absent service left alone: %s\n' "$unit"; fi
    done
}

apply_plan() {
    local i kind destination url scratch
    [[ $DRY_RUN == false ]] || {
        fail 'Refusing to apply a dry-run plan.'
        return 1
    }
    preflight_managed_removal
    for ((i = 0; i < ${#ACTION_KIND[@]}; i++)); do
        if [[ ${ACTION_KIND[$i]} == remove_packages ]]; then
            local -n removal_arguments="ACTION_ARGS_$i"
            check_package_removal "${removal_arguments[@]}"
        fi
    done
    RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
    BACKUP_DIR=$STATE_DIR/dotfiles/backups/$RUN_ID
    declare -gA BACKED_UP=() BACKUP_LOCATIONS=()
    declare -ga CLAIM_IDS=() CLAIM_PATHS=()
    for ((i = 0; i < ${#ACTION_KIND[@]}; i++)); do
        kind=${ACTION_KIND[$i]}
        local -n arguments="ACTION_ARGS_$i"
        printf '\n[%s/%s] %s\n' "$((i + 1))" "${#ACTION_KIND[@]}" "${ACTION_LABEL[$i]}"
        case $kind in
            root_command) run_privileged "${arguments[@]}" ;;
            command) "${arguments[@]}" ;;
            copy) install_file "${arguments[@]}" false ;;
            write) write_file "${arguments[@]}" false ;;
            write_root) write_file "${arguments[@]}" true ;;
            download_key)
                new_temp
                download "${arguments[0]}" "$TEMP_DIR/key"
                [[ -s $TEMP_DIR/key ]] || {
                    fail 'Empty repository key download.'
                    return 1
                }
                install_file "$TEMP_DIR/key" "${arguments[1]}" true
                ;;
            archive) install_archive "${arguments[@]}" ;;
            link) install_link "${arguments[@]}" ;;
            clone) install_clone "${arguments[@]}" ;;
            receipt) record_receipt "${arguments[@]}" ;;
            claim) claim_path "${arguments[@]}" ;;
            android_sdk) install_android_packages "${arguments[@]}" ;;
            android_env) install_android_environment "${arguments[@]}" ;;
            android_launcher) install_android_launcher "${arguments[@]}" ;;
            remove_packages)
                check_package_removal "${arguments[@]}"
                run_privileged env DEBIAN_FRONTEND=noninteractive apt-get --yes remove -- "${arguments[@]}"
                ;;
            remove_managed) remove_managed "${arguments[@]}" ;;
            deb)
                new_temp
                scratch=$TEMP_DIR
                chmod 755 "$scratch"
                download "${arguments[0]}" "$scratch/package.deb"
                chmod 644 "$scratch/package.deb"
                run_privileged env DEBIAN_FRONTEND=noninteractive apt-get --yes --no-remove install -- "$scratch/package.deb"
                ;;
            service) apply_service "${arguments[@]}" ;;
            git_config)
                destination=${arguments[0]}
                if [[ -L $destination ]]; then backup_path "$(readlink -f -- "$destination")" false; fi
                backup_path "$destination" false
                mkdir -p -- "${destination%/*}"
                git config --file "$destination" "${arguments[1]}" "${arguments[2]}"
                ;;
            merge_json)
                destination=${arguments[0]}
                new_temp
                if [[ -e $destination ]]; then
                    jq -e 'if type == "object" then . + {SKIP_HOST_UPDATE:true, skipHostUpdate:true} else error("Expected JSON object") end' "$destination" >"$TEMP_DIR/settings"
                else printf '%s\n' '{"SKIP_HOST_UPDATE":true,"skipHostUpdate":true}' >"$TEMP_DIR/settings"; fi
                install_file "$TEMP_DIR/settings" "$destination" false
                ;;
            *)
                fail "Unknown action: $kind"
                return 1
                ;;
        esac
    done
    printf '\nCompleted. Open a new shell/session for environment and group changes.\n'
    [[ ! -d $BACKUP_DIR ]] || printf 'Backups: %s\n' "$BACKUP_DIR"
}
