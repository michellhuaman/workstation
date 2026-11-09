#!/usr/bin/env bash
# Set up a fresh Ubuntu (stock GNOME desktop) install.
#
#   1. System:    vendor repos (Brave, VS Code, mise, Claude Desktop; keys in
#                 lists/apt-keys/); the packages in lists/apt.txt; your groups
#                 from lists/groups.txt; polkit action for Bitwarden's unlock
#                 with system authentication (sudo). Nothing that came with
#                 Ubuntu is removed.
#   2. chezmoi:   the latest release, run through mise; and GitHub's SSH
#                 host keys
#   3. Dotfiles:  chezmoi clones this repo (public, over HTTPS) into
#                 ~/.local/share/chezmoi and applies home/, with pushes
#                 going over SSH (Bitwarden's agent); its scripts install
#                 the flatpaks, CLI tools, GNOME settings and user services
#                 (no sudo). That clone is where you change and push this
#                 repo later.
#
# Run it from a terminal in your GNOME session, as your normal user:
#   bash /path/to/workstation/setup.sh
#
# Nothing waits on Bitwarden: it's only needed later, to push.
#
# Safe to run again: only what's missing gets installed, and if the dotfiles
# are already cloned it runs `chezmoi update` (pull and apply) instead. A
# package dropped from lists/apt.txt stays until you remove it by hand.
#
# Options:
#   --branch NAME   branch to clone on the first run (default: main); use the
#                   one you downloaded setup.sh from
#   --no-system     skip step 1, e.g. when re-running after a dotfiles fix

set -euo pipefail

repo_url="https://github.com/michellhuaman/workstation.git"   # pulls: public, no key
push_url="git@github.com:michellhuaman/workstation.git"       # pushes: Bitwarden's agent
branch=""
# chezmoi's clone of this repo (its working tree; the dotfiles are in home/).
clone_dir="${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi"
do_system=true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo; echo "==> $*"; }
warn() { echo "!! $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)    branch="${2:?--branch needs a name}"; shift 2 ;;
    --no-system) do_system=false; shift ;;
    -h|--help)   awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)           die "unknown option: $1 (try --help)" ;;
  esac
done

# Prints the entries of a list file: comments, blank lines and trailing
# spaces removed, one entry per line.
read_list() {
  [[ -f "$1" ]] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' -e '/^$/d' "$1"
}

# curl for downloads. Right after boot (or a VM resume) the network can take a
# moment, so failures, including name resolution, are retried for about 30
# seconds before giving up.
fetch() {
  curl -fsSL --connect-timeout 10 --retry 6 --retry-delay 5 --retry-all-errors "$@"
}

# ---- checks ---------------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "run this as your normal user; it uses sudo when needed"
[[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] \
  || die "run this from a terminal inside your desktop session; the dotfiles change its settings"

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] \
  || die "this script sets up Ubuntu; this is ${PRETTY_NAME:-${ID:-an unknown system}}"
lists="$script_dir/lists"
[[ -f "$lists/apt.txt" ]] || die "lists/apt.txt not found next to setup.sh"

info "Setting up ${PRETTY_NAME:-$ID} for $(id -un)"

# ---- 1. system ------------------------------------------------------------------

ubuntu_system() {
  local g me want=()
  mapfile -t want < <(read_list "$lists/apt.txt")

  # Vendor repos: the signing keys and .sources files go where apt reads them.
  echo "Adding the vendor repos"
  sudo install -D -m 644 -o root -g root -t /etc/apt/keyrings "$lists"/apt-keys/*.gpg
  sudo install -m 644 -o root -g root "$lists"/apt-sources/*.sources /etc/apt/sources.list.d/
  # VS Code's package offers to add Microsoft's repo itself; it's already
  # here (vscode.sources), so tell it not to.
  echo "code code/add-microsoft-repo boolean false" | sudo debconf-set-selections

  echo "Updating the package lists"
  sudo apt-get update -q

  # --no-upgrade: only what's missing. Listed packages are marked as manually
  # installed, so autoremove never takes one away.
  echo "Installing the packages in apt.txt"
  sudo apt-get install -y -q --no-upgrade "${want[@]}"
  sudo apt-mark manual "${want[@]}" >/dev/null

  # Groups from groups.txt, joined once (effective after a reboot). A
  # group whose package isn't installed doesn't exist yet: skipped, with a
  # warning.
  me="$(id -un)"
  while read -r g; do
    if ! getent group "$g" >/dev/null; then
      warn "group $g doesn't exist (is its package installed?); not joining it"
    elif ! id -nG "$me" | tr ' ' '\n' | grep -qxF "$g"; then
      echo "Adding $me to the $g group (effective after a reboot)"
      sudo usermod -aG "$g" "$me"
    fi
  done < <(read_list "$lists/groups.txt")

  # Bitwarden "unlock with system authentication" (its Linux biometrics): the
  # Flatpak asks polkit, which needs Bitwarden's action. Bitwarden's guide
  # puts it in /usr/share/polkit-1/actions, which belongs to the packages;
  # polkit reads /etc/polkit-1/actions too, so it goes there. The file is a
  # copy of Bitwarden's apps/desktop/resources/com.bitwarden.desktop.policy
  # (bitwarden/clients, unchanged since 92a620dd9c06), kept here so nothing
  # unpinned is installed as root. polkitd only watches action folders that
  # existed when it started, and /etc/polkit-1/actions usually didn't; a
  # reload makes it read the file now without dropping the running
  # authentication agent (a restart could).
  echo "Installing Bitwarden's polkit action (unlock with system authentication)"
  sudo install -D -m 644 -o root -g root "$script_dir/system/com.bitwarden.Bitwarden.policy" \
    /etc/polkit-1/actions/com.bitwarden.Bitwarden.policy
  sudo systemctl reload polkit
}

if $do_system; then
  info "Step 1/3: system packages (sudo)"
  # `sudo true` rather than `sudo -v`: Ubuntu's sudo-rs always asks for a
  # password on -v, even where sudoers says NOPASSWD.
  sudo true || die "your user needs sudo rights"
  # Package installs can outlast sudo's timeout; keep it fresh so you're only
  # asked once.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
  sudo_keepalive=$!
  trap 'kill "$sudo_keepalive" 2>/dev/null || true' EXIT

  ubuntu_system

  kill "$sudo_keepalive" 2>/dev/null || true
  trap - EXIT
  sudo -k   # nothing below needs root
else
  info "Step 1/3: skipped (--no-system)"
fi

for cmd in git ssh-keygen curl flatpak mise; do
  command -v "$cmd" >/dev/null || die "$cmd is missing; run setup.sh without --no-system"
done
fetch -I --max-time 10 https://github.com >/dev/null \
  || die "can't reach github.com; connect to the network and run this again"

# ---- 2. chezmoi -----------------------------------------------------------------
# Bitwarden is one of the dotfiles' Flatpaks: nothing here needs it, since
# the dotfiles are cloned over HTTPS.
info "Step 2/3: chezmoi"
# chezmoi is one of the dotfiles' CLI tools (mise). Until their own `mise
# install` has run, mise downloads it here, checking the release's checksums
# and their cosign signature.
chezmoi() { (cd "$HOME" && mise exec chezmoi@latest -- chezmoi "$@"); }
chezmoi --version

# Trust GitHub's published host keys (fetched over HTTPS) instead of
# whatever answers the first time, for the first push.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
known_hosts="$HOME/.ssh/known_hosts"
if ! ssh-keygen -F github.com -f "$known_hosts" >/dev/null 2>&1; then
  keys="$(fetch --max-time 10 https://api.github.com/meta | tr -d '\n' \
          | sed -n 's/.*"ssh_keys": *\[\([^]]*\)\].*/\1/p' | tr ',' '\n' \
          | sed -n 's/^[[:space:]]*"\(.*\)"[[:space:]]*$/github.com \1/p' || true)"
  if [[ -n "$keys" ]]; then
    printf '%s\n' "$keys" >>"$known_hosts"
    chmod 644 "$known_hosts"
    echo "Added GitHub's host keys to ~/.ssh/known_hosts"
  else
    warn "Couldn't fetch GitHub's host keys; ssh will trust the first one it sees"
  fi
fi

# ---- 3. dotfiles ----------------------------------------------------------------
info "Step 3/3: dotfiles"
if [[ -d "$clone_dir/.git" ]]; then
  echo "Already cloned in $clone_dir; pulling and applying"
  chezmoi git -- remote set-url origin "$repo_url"
  chezmoi git -- remote set-url --push origin "$push_url"
  chezmoi update --verbose
else
  init_args=(init --apply --verbose)
  [[ -n "$branch" ]] && init_args+=(--branch "$branch")
  chezmoi "${init_args[@]}" "$repo_url"
  chezmoi git -- remote set-url --push origin "$push_url"
fi

# ---- done -----------------------------------------------------------------------
info "Done."
cat <<EOF
Next: reboot (systemctl reboot) and log in again. Flatpak apps only show up
in the app grid after a fresh login, new groups (libvirt) only reach the
desktop after a reboot (logging out keeps the old ones: GNOME's apps run
under your systemd user manager, which outlives a logout), and ddcutil's
i2c module loads at boot.

  In Bitwarden, after logging in (master password and two-step login):
  - File > Settings > App settings (all accounts): turn on "Enable SSH
    agent", so git push works (check with: ssh -T git@github.com);
  - File > Settings > Security: "Unlock with system authentication", to
    unlock with your login password (or a fingerprint, if the machine has
    a reader) instead of the master password.
EOF
if [[ -f /var/run/reboot-required ]]; then
  echo "  Ubuntu also says an update needs a reboot."
fi
cat <<EOF

If anything failed, fix it in the repo, push, and run this again:
  bash $clone_dir/setup.sh          (add --no-system if only the dotfiles failed)
EOF
if [[ "$script_dir" != "$clone_dir" ]]; then
  echo
  echo "$script_dir was only a download; the clone is $clone_dir, so it can go."
fi
