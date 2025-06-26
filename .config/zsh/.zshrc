if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export XDG_DATA_HOME="$HOME/.local/share"
export ZSH="${XDG_DATA_HOME}/.oh-my-zsh"
export ZDOTDIR="$HOME/.config/zsh"
export HISTFILE="${ZDOTDIR}/.zsh_history"

alias vim="nvim"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
    fzf
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# fnm
FNM_PATH="/home/pedro/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="/home/pedro/.local/share/fnm:$PATH"
  eval "`fnm env`"
fi

