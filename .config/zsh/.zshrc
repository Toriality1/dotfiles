export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export ZSH="${ZSH:-$XDG_DATA_HOME/.oh-my-zsh}"
export HISTFILE="${ZDOTDIR:-$XDG_CONFIG_HOME/zsh}/.zsh_history"

alias vim="nvim"
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'

# Keep the first occurrence when this file or a tool adds an existing PATH entry.
typeset -U path PATH
export FNM_PATH="${FNM_PATH:-$XDG_DATA_HOME/fnm}"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PNPM_HOME="${PNPM_HOME:-$XDG_DATA_HOME/pnpm}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
if [[ -z "$JAVA_HOME" && -d "$HOME/android-studio/jbr" ]]; then
  export JAVA_HOME="$HOME/android-studio/jbr"
fi

typeset -a tool_paths
tool_paths=()
for tool_dir in \
  "$HOME/.local/bin" \
  "$XDG_CONFIG_HOME/herd-lite/bin" \
  "$HOME/.opencode/bin" \
  "$BUN_INSTALL/bin" \
  "$PNPM_HOME" \
  "$FNM_PATH" \
  "$ANDROID_HOME/cmdline-tools/latest/bin" \
  "$ANDROID_HOME/platform-tools" \
  "$ANDROID_HOME/emulator" \
  "$HOME/android-studio/bin" \
  "${JAVA_HOME:+$JAVA_HOME/bin}" \
  "$HOME/.maestro/bin" \
  /usr/local/go/bin; do
  [[ -d "$tool_dir" ]] && tool_paths+=("$tool_dir")
done
path=("${tool_paths[@]}" "${path[@]}")
export PATH
unset tool_dir tool_paths

ZSH_THEME="robbyrussell"
plugins=()
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  if [[ -d "${ZSH_CUSTOM:-$ZSH/custom}/plugins/$plugin" || -d "$ZSH/plugins/$plugin" ]]; then
    plugins+=("$plugin")
  fi
done
unset plugin

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

if (( $+commands[fnm] )); then
  eval "$(fnm env --shell zsh)"
fi

if (( $+functions[compdef] )) && [[ -r "$BUN_INSTALL/_bun" ]]; then
  source "$BUN_INSTALL/_bun"
fi

# SDKMAN adjusts Java's PATH, so initialize it after the other tools.
export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
if [[ -r "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi
