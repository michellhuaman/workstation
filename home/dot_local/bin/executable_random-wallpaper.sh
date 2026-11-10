#!/usr/bin/env bash
# Sets a random GNOME wallpaper from ~/Pictures/wallpapers (and its
# subfolders). GNOME keeps one wallpaper per color scheme (picture-uri for
# light, picture-uri-dark for dark); both get the same image, so it shows
# whichever scheme is on. Never picks the one already set, when there's
# another choice.
#
#   random-wallpaper.sh
set -euo pipefail

DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
SCHEMA=org.gnome.desktop.background

images=()
if [[ -d "$DIR" ]]; then
  mapfile -d '' images < <(find "$DIR" -path "$DIR/.git" -prune -o -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
fi
if (( ${#images[@]} == 0 )); then
  echo "No images found in $DIR" >&2
  exit 1
fi

# The dark one is what's on screen (the dotfiles keep GNOME dark).
current=$(gsettings get "$SCHEMA" picture-uri-dark | tr -d "'")
choice="${images[RANDOM % ${#images[@]}]}"
if (( ${#images[@]} > 1 )); then
  while [[ "file://$choice" == "$current" ]]; do
    choice="${images[RANDOM % ${#images[@]}]}"
  done
fi

gsettings set "$SCHEMA" picture-uri      "file://$choice"
gsettings set "$SCHEMA" picture-uri-dark "file://$choice"
gsettings set "$SCHEMA" picture-options 'zoom'
echo "Wallpaper set to $choice"
