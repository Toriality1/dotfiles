# Fedora (DNF) and Arch (pacman). Shared application recipes require glibc.
declare -gA NATIVE_PACKAGES=()
while IFS='|' read -r component fedora arch; do
    [[ -n $component && $component != \#* ]] || continue
    if [[ $BACKEND == fedora ]]; then NATIVE_PACKAGES["$component"]=$fedora
    else NATIVE_PACKAGES["$component"]=$arch; fi
done <"$REPO_DIR/installer/backends/native.conf"
unset component fedora arch
if [[ $BACKEND == fedora && ${VERSION_ID:-} =~ ^[0-9]+$ ]] && ((10#$VERSION_ID < 44)); then
    NATIVE_PACKAGES[tigervnc-standalone-server]=tigervnc-server
    NATIVE_PACKAGES[lsb-release]=redhat-lsb-core
fi
SERVICE_UNITS[printing]=cups.service,cups-browsed.service
SERVICE_UNITS[iscsi]=iscsi.service
if [[ $BACKEND == fedora ]]; then
    SERVICE_UNITS[libvirt]=virtqemud.socket,virtnetworkd.socket,virtstoraged.socket,virtnodedevd.socket,virtsecretd.socket,virtnwfilterd.socket,virtlogd.socket,virtlockd.socket
fi

backend_feature_available() {
    local id=$1
    case $id in
        spotify | vscodium | antigravity | mongodb-compass | google-chrome) return 1 ;;
        discord) [[ $BACKEND == arch ]] ;;
        *) [[ ${KIND[$id]} != package || -n ${NATIVE_PACKAGES[$id]:-} ]] ;;
    esac
}
backend_package_name() { printf '%s' "${NATIVE_PACKAGES[$1]:-$1}"; }
backend_bootstrap_ui() {
    printf '%s\n' 'Installing dialog for the terminal checklist...'
    if [[ $BACKEND == fedora ]]; then run_privileged dnf --assumeyes install dialog
    else run_privileged pacman --sync --refresh --sysupgrade --needed --noconfirm dialog; fi
}
backend_update() {
    if [[ $BACKEND == fedora ]]; then add_action root_command 'Refresh Fedora package metadata' dnf --assumeyes makecache --refresh
    else PLAN_NOTES+=('Arch installs use a full system upgrade (-Syu) to avoid unsupported partial upgrades.'); fi
}
backend_upgrade() {
    if [[ $BACKEND == fedora ]]; then add_action root_command 'Upgrade Fedora packages' dnf --assumeyes upgrade --refresh
    else add_action root_command 'Upgrade Arch packages' pacman --sync --refresh --sysupgrade --noconfirm; fi
}
backend_install() {
    (($#)) || return 0
    if [[ $BACKEND == fedora ]]; then add_action root_command 'Install selected Fedora packages' dnf --assumeyes install -- "$@"
    else add_action root_command 'Install selected Arch packages and upgrade the system' pacman --sync --refresh --sysupgrade --needed --noconfirm -- "$@"; fi
}
backend_remove() {
    (($# == 0)) || { plan_error 'Automatic package removal is supported only on Debian/Ubuntu.'; return 1; }
}
backend_repository() {
    [[ $BACKEND != arch ]] || return 0 # Official Arch repos supply Docker/Tailscale.
    local url
    case $1 in
        docker) url=https://download.docker.com/linux/fedora/docker-ce.repo ;;
        tailscale) url=https://pkgs.tailscale.com/stable/fedora/tailscale.repo ;;
        *) plan_error "No Fedora repository recipe: $1"; return 1 ;;
    esac
    # DNF reads the upstream repository definition (including GPG verification).
    add_action download_key "Configure $1 Fedora repository" "$url" "/etc/yum.repos.d/dotfiles-$1.repo"
}
backend_scan_installed() {
    declare -gA INSTALLED_PACKAGES=() INSTALLED_RELATIONS=()
    [[ $PREVIEW_TARGET == false ]] || return 0
    local output package
    if [[ $BACKEND == fedora ]]; then output=$(rpm -qa --queryformat '%{NAME}\n') || return
    else output=$(pacman -Qq) || return; fi
    while IFS= read -r package; do [[ -z $package ]] || INSTALLED_PACKAGES["$package"]=1; done <<<"$output"
}
backend_installed_component_packages() {
    local package
    local -a packages=()
    read -r -a packages <<<"$(backend_package_name "$1")"
    for package in "${packages[@]}"; do [[ ! ${INSTALLED_PACKAGES[$package]+present} ]] || printf '%s\n' "$package"; done
    return 0
}
backend_protect_dependencies() { declare -gA PROTECTED_PACKAGES=(); }
