#!/usr/bin/env bash
# Moves the pinned Nerd Fonts in home/.chezmoidata/packages.yaml to the latest
# stable release (version and checksums, edited in place), and shows any
# upstream change to Bitwarden's polkit action in system/ (never copied in).
# Nothing is committed: check `git diff`, then `chezmoi apply`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

pins=home/.chezmoidata/packages.yaml
policy=system/com.bitwarden.Bitwarden.policy
fonts=https://github.com/ryanoasis/nerd-fonts/releases
policy_url=https://raw.githubusercontent.com/bitwarden/clients/main/apps/desktop/resources/com.bitwarden.desktop.policy

fetch() { curl -fsSL --connect-timeout 10 --retry 4 --retry-delay 5 --retry-all-errors "$@"; }

cur="$(sed -n 's/^ *nerd_fonts: *\(v[^ #]*\).*/\1/p' "$pins")"
# "latest" redirects to the newest stable release's tag.
new="$(fetch -I -o /dev/null -w '%{url_effective}' "$fonts/latest")"
new="${new##*/}"

if [[ "$cur" == "$new" ]]; then
  echo "Nerd Fonts: $cur is the latest"
else
  sums="$(fetch "$fonts/download/$new/SHA-256.txt")"
  edits=(-e "s/^\( *nerd_fonts: *\)v[^ #]*/\1$new/")
  for name in $(sed -n 's/^ *\([A-Za-z0-9_-]*\): *[0-9a-f]\{64\}.*/\1/p' "$pins"); do
    sha="$(awk -v file="$name.tar.xz" '$2 == file { print $1 }' <<<"$sums")"
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "error: no checksum for $name.tar.xz in $new" >&2; exit 1; }
    edits+=(-e "s/^\( *$name: *\)[0-9a-f]\{64\}/\1$sha/")
  done
  sed -i "${edits[@]}" "$pins"   # all at once, so a failure above changes nothing
  echo "Nerd Fonts: $cur -> $new"
fi

upstream="$(mktemp)"
trap 'rm -f "$upstream"' EXIT
fetch -o "$upstream" "$policy_url"
if cmp -s "$policy" "$upstream"; then
  echo "Bitwarden polkit action: same as upstream"
else
  echo "Bitwarden polkit action: CHANGED upstream. Review it, and copy it over $policy if it's fine:"
  diff -u --label "$policy" --label upstream "$policy" "$upstream" || true
fi
