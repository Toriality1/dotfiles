export XDG_DATA_HOME="$HOME/.local/share"
export ZSH="${XDG_DATA_HOME}/.oh-my-zsh"
export ZDOTDIR="$HOME/.config/zsh"
export HISTFILE="${ZDOTDIR}/.zsh_history"

alias vim="nvim"

ZSH_THEME="robbyrussell"

plugins=(
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# fnm
FNM_PATH="/home/pedro/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="/home/pedro/.local/share/fnm:$PATH"
  eval "`fnm env`"
fi

