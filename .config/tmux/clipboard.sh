#!/bin/sh
# Tmux also copies to the client terminal via OSC 52 (set-clipboard external).
# On SSH, let the client handle it rather than copying to the server's desktop.
if [ -n "$SSH_CONNECTION$SSH_TTY" ]; then
    cat > /dev/null
elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy > /dev/null 2>&1; then
    wl-copy
elif [ -n "$DISPLAY" ] && command -v xclip > /dev/null 2>&1; then
    xclip -in -selection clipboard
else
    cat > /dev/null
fi
