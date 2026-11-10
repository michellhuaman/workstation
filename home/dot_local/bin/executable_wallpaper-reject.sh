#!/usr/bin/env bash
# Asks, in a zenity dialog, whether to move the wallpaper on screen to the
# Trash; if so, trashes it and shows another one (random-wallpaper.sh).
# Only touches files under ~/Pictures/wallpapers, never a system background.
#
# The dotfiles' GNOME settings bind it to Super+Shift+W. A file trashed by
# mistake can be put back from the Trash in Files (Restore).
set -euo pipefail

DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
SCHEMA=org.gnome.desktop.background

notify() { notify-send -i preferences-desktop-wallpaper "Wallpaper" "$1" 2>/dev/null || true; }
fail() { notify "$1"; echo "$1" >&2; exit 1; }

command -v zenity &>/dev/null || fail "zenity is not installed."

# The dark one is what's on screen (the dotfiles keep GNOME dark).
uri=$(gsettings get "$SCHEMA" picture-uri-dark | tr -d "'")
file=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$uri")

dir_real=$(realpath -- "$DIR")
file_real=$(realpath -m -- "$file")
name=${file_real##*/}
if [[ ! -f "$file_real" || "$file_real" != "$dir_real"/* ]]; then
  notify "The wallpaper on screen isn't in $DIR, so there's nothing to trash: $file"
  exit 0
fi

# zenity's --text is Pango markup.
esc() { local s=${1//&/&amp;}; s=${s//</&lt;}; printf '%s' "${s//>/&gt;}"; }
zenity --question --title="Wallpaper" \
  --text="Move $(esc "$name") to the Trash?" \
  --ok-label="Move to Trash" --cancel-label="Cancel" || exit 0

err=$(gio trash -- "$file_real" 2>&1) || fail "Couldn't move $name to the Trash: $err"
"$HOME/.local/bin/random-wallpaper.sh" >/dev/null
notify "Moved $name to the Trash"
