#!/bin/bash
WALLPAPER_DIR="$HOME/tori/pictures/wallpapers/"
RANDOM_WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \) | shuf -n 1)

if [ -z "$RANDOM_WALLPAPER" ]; then
    notify-send "Error" "No wallpapers found in $WALLPAPER_DIR"
    exit 1
fi

feh --bg-fill "$RANDOM_WALLPAPER"
notify-send "Wallpaper Changed" "$RANDOM_WALLPAPER"
