export XDG_DATA_HOME="$HOME/.local/share"
export ZSH="${XDG_DATA_HOME}/.oh-my-zsh"
export ZDOTDIR="$HOME/.config/zsh"
export HISTFILE="${ZDOTDIR}/.zsh_history"

alias vim="nvim"
alias sudoku="sudo apt update && sudo apt upgrade && sudo apt autoremove"
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'

ZSH_THEME="robbyrussell"

plugins=(
    web-search
    zsh-autosuggestions
    zsh-syntax-highlighting
    fzf
)

ZSH_WEB_SEARCH_ENGINES=(
    deepseek "https://chat.deepseek.com/"
    gemini "https://gemini.google.com/app"
    claude "https://claude.ai/new?q="
    copilot "https://copilot.microsoft.com/?q="
    phind "https://phind.com/"
    grok "https://grok.com/?q="
    aistudio "https://aistudio.google.com/prompts/new_chat"
    meta "https://meta.ai/"
)

source $ZSH/oh-my-zsh.sh

# fnm
FNM_PATH="/home/pedro/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="/home/pedro/.local/share/fnm:$PATH"
  eval "`fnm env`"
fi

export PATH="/home/pedro/.config/herd-lite/bin:$PATH"

