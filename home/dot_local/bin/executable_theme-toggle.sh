#!/usr/bin/env bash
#
# theme-toggle.sh
# Switches GNOME's color scheme, GTK theme and icon theme (Ubuntu's Yaru), and
# Alacritty's Catppuccin flavor (Latte for light, Mocha for dark). starship and
# bat use the terminal's ANSI colors, so they follow.
#
#   theme-toggle.sh              toggle light/dark (Super+Shift+T)
#   theme-toggle.sh light|dark   switch to that mode

set -uo pipefail

schema=org.gnome.desktop.interface
themes="$HOME/.config/alacritty/themes"

case "${1:-toggle}" in
  light|dark) mode="$1" ;;
  toggle)
    if [[ "$(gsettings get "$schema" color-scheme)" == "'prefer-dark'" ]]; then
      mode=light
    else
      mode=dark
    fi
    ;;
  *) echo "usage: ${0##*/} [light|dark]" >&2; exit 2 ;;
esac

if [[ "$mode" == light ]]; then
  scheme=default theme=Yaru flavor=latte
else
  scheme=prefer-dark theme=Yaru-dark flavor=mocha
fi

gsettings set "$schema" color-scheme "$scheme"
gsettings set "$schema" gtk-theme "$theme"
gsettings set "$schema" icon-theme "$theme"

# chezmoi tracks the theme files but not this link, so toggling never shows up
# as a change.
ln -sfn "catppuccin-$flavor.toml" "$themes/catppuccin-current.toml"
# Open Alacritty windows don't always notice the imported link changing.
# Touching alacritty.toml makes them reload; its contents don't change, so
# chezmoi sees no difference.
touch "$HOME/.config/alacritty/alacritty.toml"

notify-send "Theme" "Switched to $mode" 2>/dev/null || true
