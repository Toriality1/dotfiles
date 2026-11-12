# Debian/Ubuntu package names and scoped APT repositories.

backend_bootstrap_ui() {
    printf '%s\n' 'Installing whiptail for the terminal checklist...'
    run_privileged apt-get update
    run_privileged env DEBIAN_FRONTEND=noninteractive apt-get --yes --no-remove --no-install-recommends install whiptail
}

backend_package_name() {
    case $1 in
        spotify) printf '%s' spotify-client ;;
        vscodium) printf '%s' codium ;;
        google-chrome) printf '%s' google-chrome-stable ;;
        dmenu) printf '%s' suckless-tools ;;
        android-runtime)
            local alsa=libasound2t64
            [[ $CODENAME != bookworm && $CODENAME != jammy ]] || alsa=libasound2
            printf '%s' "libx11-6 libxext6 libxi6 libxrender1 libxtst6 libfreetype6 libfontconfig1 $alsa libgl1 libnss3 libxkbcommon0 libpulse0 libxkbfile1 libdrm2 libsm6 libice6"
            ;;
        default-jdk)
            if [[ $DISTRO == ubuntu && $CODENAME == jammy ]]; then printf '%s' openjdk-17-jdk-headless
            else printf '%s' default-jdk; fi
            ;;
        chromium)
            if [[ $DISTRO == ubuntu ]]; then printf '%s' chromium-browser
            else printf '%s' chromium; fi
            ;;
        *) printf '%s' "$1" ;;
    esac
}

backend_existing_repository() {
    [[ $PREVIEW_TARGET == false ]] || return 1
    local uri=$1 suite=$2 file
    local apt_root=${APT_ROOT:-/etc/apt}
    for file in "$apt_root/sources.list" "$apt_root"/sources.list.d/*.list "$apt_root"/sources.list.d/*.sources; do
        [[ -f $file ]] || continue
        if [[ $file == *.sources ]]; then
            if awk -v uri="$uri" -v suite="$suite" '
                function canonical(s) { sub(/^https?:\/\//,"",s); sub(/\/$/,"",s); return s }
                BEGIN { RS=""; FS="\n" }
                { enabled=1; types=""; uris=""; suites=""; key=""
                  for(i=1;i<=NF;i++) {
                    line=$i
                    if(line ~ /^[[:space:]]*#/) continue
                    if(line ~ /^[[:space:]]/ && key!="") { fields[key]=fields[key] " " line; continue }
                    pos=index(line,":"); if(!pos) continue
                    key=substr(line,1,pos-1); fields[key]=substr(line,pos+1)
                  }
                  if(fields["Enabled"] ~ /^[[:space:]]*no[[:space:]]*$/) enabled=0
                  n=split(fields["URIs"],u,/[[:space:]]+/); m=split(fields["Suites"],s,/[[:space:]]+/)
                  for(i=1;i<=n;i++) for(j=1;j<=m;j++)
                    if(enabled && fields["Types"] ~ /(^|[[:space:]])deb([[:space:]]|$)/ && canonical(u[i])==canonical(uri) && s[j]==suite) found=1
                  for(key in fields) delete fields[key]
                }
                END { exit !found }' "$file"; then return 0; fi
        elif awk -v uri="$uri" -v suite="$suite" '
            function canonical(s) { sub(/^https?:\/\//,"",s); sub(/\/$/,"",s); return s }
            $1=="deb" { for(i=2;i<NF;i++) if(canonical($i)==canonical(uri) && $(i+1)==suite) found=1 }
            END { exit !found }' "$file"; then return 0; fi
    done
    return 1
}

backend_repository() {
    local name=$1 key_url uri suite component key
    case $name in
        docker)
            key_url=https://download.docker.com/linux/$DISTRO/gpg
            uri=https://download.docker.com/linux/$DISTRO
            suite=$CODENAME
            component=stable
            ;;
        spotify)
            key_url=https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc
            uri=https://repository.spotify.com
            suite=stable
            component=non-free
            ;;
        vscodium)
            key_url=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
            uri=https://download.vscodium.com/debs
            suite=vscodium
            component=main
            ;;
        antigravity)
            key_url=https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg
            uri=https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/
            suite=antigravity-debian
            component=main
            ;;
        tailscale)
            key_url=https://pkgs.tailscale.com/stable/$DISTRO/$CODENAME.noarmor.gpg
            uri=https://pkgs.tailscale.com/stable/$DISTRO
            suite=$CODENAME
            component=main
            ;;
        google-chrome)
            key_url=https://dl.google.com/linux/linux_signing_key.pub
            uri=https://dl.google.com/linux/chrome/deb
            suite=stable
            component=main
            ;;
        *)
            plan_error "Unknown Debian repository: $name"
            return 1
            ;;
    esac
    if backend_existing_repository "$uri" "$suite"; then
        PLAN_NOTES+=("Reuse existing $name repository and signing-key configuration.")
        return 0
    fi
    key=/etc/apt/keyrings/dotfiles-$name.asc
    [[ $name != tailscale ]] || key=/etc/apt/keyrings/dotfiles-tailscale.gpg
    add_action download_key "Install scoped $name signing key" "$key_url" "$key"
    local content
    printf -v content 'Types: deb\nURIs: %s\nSuites: %s\nComponents: %s\nArchitectures: %s\nSigned-By: %s\n' "$uri" "$suite" "$component" "$ARCH" "$key"
    add_action write_root "Configure $name repository" "/etc/apt/sources.list.d/dotfiles-$name.sources" "$content"
}

backend_update() { add_action root_command 'Refresh APT package indexes' apt-get update; }
backend_upgrade() { add_action root_command 'Upgrade installed packages' env DEBIAN_FRONTEND=noninteractive apt-get --yes --no-remove upgrade; }
backend_install() {
    (($#)) || return 0
    add_action root_command 'Install selected APT packages' env DEBIAN_FRONTEND=noninteractive apt-get --yes --no-remove --no-install-recommends install -- "$@"
}
backend_remove() {
    (($#)) || return 0
    add_action remove_packages 'Remove selected packages; retain configuration; no autoremove' "$@"
}

backend_scan_installed() {
    declare -gA INSTALLED_PACKAGES=() INSTALLED_RELATIONS=()
    [[ $PREVIEW_TARGET == false ]] || return 0
    local output package status dependencies pre_dependencies
    output=$(dpkg-query -W -f='${binary:Package}|${db:Status-Status}|${Pre-Depends}|${Depends}\n') || {
        fail 'Cannot read installed package state; refusing to guess what to remove.'
        return 1
    }
    while IFS='|' read -r package status pre_dependencies dependencies; do
        [[ $status == installed ]] || continue
        package=${package%%:*}
        INSTALLED_PACKAGES["$package"]=1
        INSTALLED_RELATIONS["$package"]=$pre_dependencies,$dependencies
    done <<<"$output"
}

# Recognize distro-packaged alternatives to tools we install from releases.
backend_installed_component_packages() {
    local id=$1 package
    local -a alternatives=() primary=()
    read -r -a primary <<<"$(backend_package_name "$id")"
    for package in "${primary[@]}"; do
        [[ ! ${INSTALLED_PACKAGES[$package]+present} ]] || printf '%s\n' "$package"
    done
    case $id in
        node) alternatives=(nodejs npm) ;;
        pnpm) alternatives=(node-pnpm) ;;
        neovim) alternatives=(neovim-runtime) ;;
        go)
            alternatives=(golang golang-go golang-src)
            for package in "${!INSTALLED_PACKAGES[@]}"; do
                case $package in golang-[0-9]*-go | golang-[0-9]*-src) alternatives+=("$package") ;; esac
            done
            ;;
    esac
    for package in "${alternatives[@]}"; do
        [[ ! ${INSTALLED_PACKAGES[$package]+present} ]] || printf '%s\n' "$package"
    done
    return 0
}

# Keep installed dependencies of wanted tools, including installed alternatives.
# Read dpkg relationships as data; no APT operations are needed during planning.
backend_protect_dependencies() {
    declare -gA PROTECTED_PACKAGES=()
    local id package relationship dependency unused index
    local -a queue=() relationships=()
    for id in "${ORDERED[@]}"; do
        while IFS= read -r package; do
            [[ -n $package && ! ${PROTECTED_PACKAGES[$package]+present} ]] || continue
            PROTECTED_PACKAGES["$package"]=1
            queue+=("$package")
        done < <(backend_installed_component_packages "$id")
    done
    for ((index = 0; index < ${#queue[@]}; index++)); do
        package=${queue[$index]}
        IFS=',|' read -r -a relationships <<<"${INSTALLED_RELATIONS[$package]:-}"
        for relationship in "${relationships[@]}"; do
            read -r dependency unused <<<"$relationship"
            dependency=${dependency%%:*}
            [[ $dependency =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || continue
            [[ ${INSTALLED_PACKAGES[$dependency]+present} && ! ${PROTECTED_PACKAGES[$dependency]+present} ]] || continue
            PROTECTED_PACKAGES["$dependency"]=1
            queue+=("$dependency")
        done
    done
}
