# Recipes describe actions; only executor.sh performs them.

plan_archive() {
    add_action archive "Install ${LABEL[$1]}" "$1" "$2" "$3" "$4" "$5" "${6:-}"
}
plan_link() { add_action link "Expose ${3##*/}" "$1" "$2" "$3"; }

npm_package_for() {
    case $1 in
        claude-code) printf '%s' '@anthropic-ai/claude-code' ;;
        codex) printf '%s' '@openai/codex' ;;
        opencode) printf '%s' opencode-ai ;;
        gemini-cli) printf '%s' '@google/gemini-cli' ;;
        bun) printf '%s' bun ;;
        *) return 1 ;;
    esac
}

plan_application() {
    local id=$1 version destination arch name
    local fnm=$DATA_DIR/fnm/fnm
    case $id in
        neovim)
            version=${VALUES[neovim_version]} arch=$ARCH
            [[ $arch != amd64 ]] || arch=x86_64
            destination=$APPS_DIR/neovim/$version
            plan_archive "$id" "https://github.com/neovim/neovim/releases/download/v$version/nvim-linux-$arch.tar.gz" "$destination" 1 bin/nvim
            plan_link "$id" "$destination/bin/nvim" "$LOCAL_BIN/nvim"
            ;;
        go)
            version=${VALUES[go_version]} destination=$APPS_DIR/go/${VALUES[go_version]}
            plan_archive "$id" "https://go.dev/dl/go$version.linux-$ARCH.tar.gz" "$destination" 1 bin/go
            for name in go gofmt; do plan_link "$id" "$destination/bin/$name" "$LOCAL_BIN/$name"; done
            ;;
        fnm)
            version=${VALUES[fnm_version]} destination=$APPS_DIR/fnm/${VALUES[fnm_version]} name=fnm-linux.zip
            [[ $ARCH != arm64 ]] || name='fnm-arm64.zip'
            plan_archive "$id" "https://github.com/Schniz/fnm/releases/download/v$version/$name" "$destination" 0 fnm
            plan_link "$id" "$destination/fnm" "$fnm"
            plan_link "$id" "$destination/fnm" "$LOCAL_BIN/fnm"
            ;;
        node)
            add_action command "Install Node ${VALUES[node_version]}" "$fnm" --fnm-dir "$DATA_DIR/fnm" install "${VALUES[node_version]}"
            ;;
        pnpm)
            add_action command 'Install pnpm in the selected Node runtime' "$fnm" --fnm-dir "$DATA_DIR/fnm" exec --using "${VALUES[node_version]}" npm install --global "pnpm@${VALUES[pnpm_version]}"
            ;;
        claude-code | codex | opencode | gemini-cli | bun)
            add_action command "Install ${LABEL[$id]} in the selected Node runtime" "$fnm" --fnm-dir "$DATA_DIR/fnm" exec --using "${VALUES[node_version]}" npm install --global "$(npm_package_for "$id")"
            ;;
        nerd-font)
            version=${VALUES[font_version]} destination=$DATA_DIR/fonts/JetBrainsMono/${VALUES[font_version]}
            plan_archive "$id" "https://github.com/ryanoasis/nerd-fonts/releases/download/v$version/JetBrainsMono.tar.xz" "$destination" 0 JetBrainsMonoNerdFont-Regular.ttf
            add_action command 'Refresh font cache' fc-cache -f "$destination"
            ;;
        oh-my-zsh)
            add_action clone 'Install Oh My Zsh' "$id" https://github.com/ohmyzsh/ohmyzsh.git "$DATA_DIR/.oh-my-zsh"
            ;;
        zsh-autosuggestions | zsh-syntax-highlighting)
            add_action clone "Install ${LABEL[$id]}" "$id" "https://github.com/zsh-users/$id.git" "$DATA_DIR/.oh-my-zsh/custom/plugins/$id"
            ;;
        *)
            plan_error "Missing application recipe: $id"
            return 1
            ;;
    esac
    add_action receipt "Record managed $id installation" "$id" "${VALUES[node_version]}"
}

plan_config() {
    local id=$1 source destination
    local -a files=()
    case $id in
        config-bash) files=("$REPO_DIR/.bashrc") ;;
        config-zsh) files=("$REPO_DIR/.zshenv" "$REPO_DIR/.config/zsh/.zshrc") ;;
        config-tmux) files=("$REPO_DIR/.config/tmux/tmux.conf" "$REPO_DIR/.config/tmux/clipboard.sh") ;;
        config-alacritty) files=("$REPO_DIR/.config/alacritty/alacritty.toml") ;;
        config-dunst) files=("$REPO_DIR/.config/dunst/dunstrc") ;;
        config-rofi) files=("$REPO_DIR/.config/rofi/config.rasi") ;;
        config-nvim) files=("$REPO_DIR/.config/nvim/init.lua" "$REPO_DIR/.config/nvim/lazy-lock.json" "$REPO_DIR/.config/nvim/stylua.toml" "$REPO_DIR"/.config/nvim/lua/toriality/*.lua "$REPO_DIR"/.config/nvim/lua/toriality/lazy/*.lua) ;;
        *)
            plan_error "Missing dotfile recipe: $id"
            return 1
            ;;
    esac
    for source in "${files[@]}"; do
        [[ -f $source ]] || {
            plan_error "Missing dotfile: $source"
            return 1
        }
        if [[ $source == "$REPO_DIR/.config/"* ]]; then
            destination=$CONFIG_DIR/${source#"$REPO_DIR/.config/"}
        else destination=$INSTALL_HOME/${source#"$REPO_DIR/"}; fi
        add_action copy "Deploy ${source#"$REPO_DIR/"}" "$source" "$destination"
    done
}

plan_i3() {
    local content startup id command
    [[ -f $REPO_DIR/.config/i3/config ]] || {
        plan_error 'Missing i3 config.'
        return 1
    }
    content=$(awk '!/^[[:space:]]*(exec |exec_always |include machine.conf|include installer.conf)/ && $0 != "# Machine-specific display setup is kept out of the shared bindings."' "$REPO_DIR/.config/i3/config")
    content+=$'\n\ninclude installer.conf\n'
    startup=$'# Generated from terminal installer choices.\n'
    for id in dex lock network dunst keyring polkit flameshot picom; do
        [[ ${RESOLVED["autostart-$id"]+present} ]] || continue
        case $id in
            dex) command='dex --autostart --environment i3' ;;
            lock) command='xss-lock --transfer-sleep-lock -- i3lock --nofork' ;;
            network) command=nm-applet ;;
            dunst) command=dunst ;;
            keyring) command='gnome-keyring-daemon --start --components=pkcs11,secrets,ssh' ;;
            polkit) command=lxpolkit ;;
            flameshot) command=flameshot ;;
            picom) command=picom ;;
        esac
        startup+="exec --no-startup-id $command"$'\n'
    done
    if [[ ${RESOLVED["i3-keyboard"]+present} ]]; then
        startup+="exec_always --no-startup-id setxkbmap -option '' -option '${VALUES[keyboard_options]}' -layout '${VALUES[keyboard_layouts]}' -variant '${VALUES[keyboard_variants]}'"$'\n'
    fi
    if [[ ${RESOLVED["i3-display"]+present} ]]; then
        startup+="exec --no-startup-id xrandr --output '${VALUES[display_output]}' --mode '${VALUES[display_mode]}'"$'\n'
    fi
    if [[ ${RESOLVED["i3-power"]+present} ]]; then
        command=-dpms
        [[ ${VALUES[display_power]} != on ]] || command=+dpms
        [[ ${VALUES[display_power]} == keep ]] || startup+="exec --no-startup-id xset $command"$'\n'
        command=off
        [[ ${VALUES[screen_blanking]} != on ]] || command=default
        [[ ${VALUES[screen_blanking]} == keep ]] || startup+="exec --no-startup-id xset s $command"$'\n'
    fi
    add_action write 'Deploy shared i3 bindings' "$CONFIG_DIR/i3/config" "$content"
    add_action write 'Configure selected i3 startup and devices' "$CONFIG_DIR/i3/installer.conf" "$startup"
}

plan_git() {
    local destination=$INSTALL_HOME/.gitconfig
    if [[ ! -e $destination && -f $CONFIG_DIR/git/config ]]; then destination=$CONFIG_DIR/git/config; fi
    if [[ -n ${GIT_CONFIG_GLOBAL:-} ]]; then
        [[ $GIT_CONFIG_GLOBAL == /* ]] || {
            plan_error 'GIT_CONFIG_GLOBAL must be absolute.'
            return 1
        }
        destination=$GIT_CONFIG_GLOBAL
    fi
    add_action git_config "$1" "$destination" "$2" "$3"
}

plan_setting() {
    case $1 in
        git-identity)
            plan_git 'Set Git author name' user.name "${VALUES[git_name]}" || return
            plan_git 'Set Git author email' user.email "${VALUES[git_email]}"
            ;;
        git-branch) plan_git 'Set Git default branch' init.defaultBranch "${VALUES[git_branch]}" ;;
        github-login) add_action command 'Log in with GitHub CLI' gh auth login ;;
        tailscale-login) add_action root_command 'Connect Tailscale' tailscale up ;;
        default-shell) add_action command 'Set default shell to Zsh' chsh -s /usr/bin/zsh "$INSTALL_USER" ;;
        node-default) add_action command 'Set default Node runtime' "$DATA_DIR/fnm/fnm" --fnm-dir "$DATA_DIR/fnm" default "${VALUES[node_version]}" ;;
        docker-group) add_action root_command 'Allow Docker without sudo' usermod -aG docker "$INSTALL_USER" ;;
        libvirt-group) add_action root_command 'Allow virtual machine management' usermod -aG libvirt "$INSTALL_USER" ;;
        kvm-group) add_action root_command 'Allow KVM acceleration' usermod -aG kvm "$INSTALL_USER" ;;
        timezone) add_action root_command 'Set timezone' timedatectl set-timezone "${VALUES[timezone]}" ;;
        hostname) add_action root_command 'Set hostname' hostnamectl set-hostname "${VALUES[hostname]}" ;;
        discord-updates) add_action merge_json 'Skip Discord host-update checks' "$CONFIG_DIR/discord/settings.json" ;;
    esac
    return 0
}
