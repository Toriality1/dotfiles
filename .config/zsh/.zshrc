export XDG_DATA_HOME="$HOME/.local/share"
export ZSH="${XDG_DATA_HOME}/.oh-my-zsh"
export ZDOTDIR="$HOME/.config/zsh"
export HISTFILE="${ZDOTDIR}/.zsh_history"

alias vim="nvim"
alias sudoku="sudo apt update && sudo apt upgrade && sudo apt autoremove"
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
alias blog="cd ~/documents/projects/blog"

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

export PATH="/home/pedro/.config/herd-lite/bin:$PATH"


# Created by `pipx` on 2025-09-11 16:12:26
export PATH="$PATH:/home/pedro/.local/bin"
