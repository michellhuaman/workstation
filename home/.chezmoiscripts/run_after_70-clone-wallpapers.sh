#!/bin/bash
# Clones the private wallpapers repo into ~/Pictures/wallpapers on a machine
# that doesn't have them yet.
# The repo needs an SSH key, and on a new machine the first apply runs before
# Bitwarden is set up, so without access this skips (it mustn't fail the
# apply). That's why this is run_after_ and not run_once_: a skipped run has
# to try again on the next `chezmoi apply`. Once the folder has anything in
# it, this does nothing.
set -euo pipefail

repo=git@github.com:michellhuaman/wallpapers.git
dir="$HOME/Pictures/wallpapers"

if [[ -d "$dir" && -n "$(ls -A "$dir")" ]]; then
  exit 0
fi

# Never stop to ask for anything; a locked Bitwarden gets 30 seconds to unlock.
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"
if ! timeout 30 git ls-remote "$repo" HEAD >/dev/null 2>&1; then
  echo "Wallpapers not cloned: no SSH access to GitHub yet. Unlock Bitwarden, then run chezmoi apply."
  exit 0
fi

mkdir -p "${dir%/*}"
git clone "$repo" "$dir"
