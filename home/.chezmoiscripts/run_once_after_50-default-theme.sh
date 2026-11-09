#!/bin/bash
# Starts a new machine on the dark theme (Catppuccin Mocha) instead of GNOME's
# default light one. A machine that already has Alacritty's theme link is
# already set up, so it keeps the theme you picked with theme-toggle.sh.
set -euo pipefail

[[ -L "$HOME/.config/alacritty/themes/catppuccin-current.toml" ]] \
  || "$HOME/.local/bin/theme-toggle.sh" dark
