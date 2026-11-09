# workstation

Takes a fresh **Ubuntu** install (the stock GNOME desktop) to my working
desktop: the installer's answers, the system packages and settings, and my
dotfiles (managed with [chezmoi](https://www.chezmoi.io/), themed with
Catppuccin).

The dividing line inside the repo is **sudo**. `setup.sh` and `lists/`, at the
root, are the system half. `home/` is the dotfiles: chezmoi only reads that
folder (`.chezmoiroot`), and everything in it installs into the home folder,
so `chezmoi apply` never asks for a password. Anything that needs root goes in
`setup.sh`, never under `home/`.

Nothing secret lives here, so the repo is public: a new machine downloads it
and chezmoi clones it over HTTPS, with no key. Pushes go over SSH, through
Bitwarden's agent. The clone is `~/.local/share/chezmoi` (`chezmoi cd` goes
there).

The setup before Ubuntu, Fedora Sway Atomic, is kept as the tag
`fedora-sway-atomic`.

## Layout

```
autoinstall.yaml     answers for the Ubuntu installer ("Automated installation")
setup.sh             the one script to run, after the first login (sudo)
setup-virtualbox.sh  optional: installs VirtualBox (sudo)
update-pins.sh       bumps the pinned Nerd Fonts
lists/               apt packages, vendor repos and keys, user groups
system/              Bitwarden's polkit action, installed by setup.sh
home/                the dotfiles: chezmoi's source
  .chezmoidata/      flatpaks, Nerd Font version and checksums, systemd user units
  .chezmoiexternal.toml.tmpl   the Nerd Font downloads
  .chezmoiscripts/   run by `chezmoi apply`, in number order
  dot_local/bin/     theme-toggle.sh, ddc-brightness.sh, powermenu.sh, vm,
                     random-wallpaper.sh, wallpaper-reject.sh
```

Each script explains itself in its header. chezmoi turns source names into
real ones: `dot_` becomes `.`, `private_` means only you can read it,
`executable_` makes it executable, and `.tmpl` means it's a template.

## Setting up a new machine

1. **Install Ubuntu.** Connect to Wi-Fi or Ethernet when the installer
   asks, and at "Type of installation" pick **Automated installation** with
   this URL:

   ```
   https://raw.githubusercontent.com/michellhuaman/workstation/main/autoinstall.yaml
   ```

   The installer still asks for the disk (Erase disk, advanced: LVM with
   encryption, and a passphrase) and for your name, username, hostname and
   password.
2. **Log in, open a terminal (`Ctrl+Alt+T`) and run** (wget comes with
   Ubuntu; curl and git may not yet):

   ```bash
   wget -qO- https://github.com/michellhuaman/workstation/archive/refs/heads/main.tar.gz | tar -xz
   bash workstation-main/setup.sh
   ```

   It only asks for your **sudo password**, once. The downloaded
   `workstation-main` folder can be deleted afterwards.

3. **Reboot** (`systemctl reboot`) and log in. Flatpak apps are in the app
   grid, and `Super+Return` opens Alacritty.
4. **In Bitwarden**, log in (it starts at login), then:
   - File > Settings > App settings (all accounts) > turn on **Enable SSH
     agent**, so `git push` works. Check with `ssh -T git@github.com`
     (approve the request in Bitwarden).
   - File > Settings > Security > turn on **Unlock with system
     authentication**. This one can't be automated: Bitwarden keeps it in
     each account's own settings. After Bitwarden starts, the first unlock
     still needs the master password.

   Then run `chezmoi apply` once more to clone the private wallpapers repo,
   which the first apply skipped because it needs SSH access.

5. **Google Drive** (backs up `~/drive`, by `drive-backup.timer`): the
   first apply wrote `~/.config/rclone/rclone.conf` only if Bitwarden's CLI
   was unlocked. If it wasn't, unlock it and apply again:

   ```bash
   bw login                                   # first time on this machine
   export BW_SESSION="$(bw unlock --raw)"
   chezmoi apply
   ```

   Then sign rclone in (a browser opens; answer `y`, then `n` to "Shared
   Drive") and restore your files:

   ```bash
   rclone config reconnect gdrive:
   rclone copy gdrive:backup ~/drive --drive-skip-gdocs
   ```

   Backups are skipped while `~/drive` is empty. If the copy is interrupted,
   run it again right away: the next backup treats what's missing as deleted.

## VirtualBox (optional)

`setup.sh` leaves VirtualBox out. On a machine that needs it (`vm` does), run:

```bash
bash ~/.local/share/chezmoi/setup-virtualbox.sh
```

With Secure Boot on, the install asks for a one-time password you make up.
Reboot, and on the blue MOK Manager screen pick **Enroll MOK** (not "Continue
boot"), then **Continue**, **Yes**, type that password and **Reboot**.

To check it, or if the screen went by:

```bash
mokutil --test-key /var/lib/shim-signed/mok/MOK.der
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der   # if it's "not enrolled", then reboot
```

Once VirtualBox is installed, it and KVM (virt-manager, Claude Desktop's
Cowork) can't run VMs at the same time: only one can hold AMD-V/VT-x.

## Daily workflow

Files in `~` are output: chezmoi overwrites them on apply, so change the source
in `home/`.

```bash
edot ~/.config/alacritty/alacritty.toml          # edit a dotfile by its real path, apply on quit
chezmoi git -- add -A && chezmoi git -- commit -m "What changed" && chezmoi git -- push
chezmoi update                                   # on the other machines: pull + apply
```

For a change that started in `~` (a setting saved from inside an app),
`chezmoi diff` shows it and `chezmoi re-add` copies it into the repo. `re-add`
skips templates; for those, use `edot`. `chezmoi apply` throws a change away.
To track a new file: `chezmoi add ~/.config/newapp/config`.

| Change | Where | Then |
| --- | --- | --- |
| a Flatpak app | `packages.flatpak` in `.chezmoidata/packages.yaml` (the whole set: per-user apps not listed are uninstalled, their data kept) | `chezmoi apply` |
| a keyboard shortcut | `.chezmoiscripts/run_onchange_after_60-gnome-settings.sh.tmpl` | `chezmoi apply` |
| a CLI tool | `edot ~/.config/mise/config.toml` (as `"latest"`; the whole set, unlisted tools are pruned) | applied on save |
| another Nerd Font | its archive's name and checksum under `fonts.nerd_fonts_sha256` (the `SHA-256.txt` of the release in `fonts.nerd_fonts`) | `chezmoi apply` |
| a systemd user unit | the unit in `dot_config/systemd/user/`, its name in `services.user` | `chezmoi apply` |
| anything else in `home/` | `chezmoi cd`, then edit the file | `chezmoi apply`, `exit` |
| a system (apt) package | `lists/apt.txt` | re-run `setup.sh` |
| a vendor apt repo | its `.sources` file in `lists/apt-sources/` and its binary key in `lists/apt-keys/` (check it first: `gpg --show-keys`) | re-run `setup.sh` |

`chezmoi update` doesn't run `setup.sh`. Nothing removes system changes for
you: when dropping a package, group or repo from `lists/`, also run
`sudo apt remove <pkg>`, `sudo gpasswd -d "$USER" <group>`, or delete its file
in `/etc/apt/sources.list.d/`.

Updates are by hand: `update` (in `.bashrc`) upgrades apt, Flatpak, Snap and
the mise tools.

## If something goes wrong

- **A package name is wrong, or a step fails**: fix it in the repo, push,
  and run `bash ~/.local/share/chezmoi/setup.sh` again. If only the dotfiles
  part failed, add `--no-system`.
- **"Could not get lock /var/lib/dpkg/lock-frontend"**: the automatic
  updater (or the App Center) is busy; wait a minute and run `setup.sh`
  again.
- **"can't reach github.com"**: right after boot the network can take a
  moment; connect and run `setup.sh` again.
- **`git push` fails with "Permission denied (publickey)"**: Bitwarden is
  locked, its SSH agent switch is off, the vault has no SSH key items, or
  the key isn't added to your GitHub account.
- **`<your-user> is not in the sudoers file`**: the user isn't an
  administrator. From an administrator account, run
  `sudo usermod -aG sudo <your-user>`, then log out and back in.

## Good to know

**Themes.** `Super+Shift+T` runs `theme-toggle.sh`. A new machine starts dark.
The wallpaper follows on its own, since GNOME keeps one per mode.

**Wallpapers.** The images are in a private repo cloned to
`~/Pictures/wallpapers`, so they aren't here. `random-wallpaper.sh` picks new
ones daily from `light/` and `dark/`; `Super+Shift+W` trashes or sorts the one
on screen. Sorting only changes the working copy, so commit and push it
yourself: `git -C ~/Pictures/wallpapers add -A`, then `commit` and `push`.

**Bitwarden.** It holds the SSH keys and is the SSH agent, so it must be
unlocked for `git push` and `ssh`. Its autostart file has no comments because
it's exactly what the desktop portal writes. The Flatpak override in
`dot_local/private_share` lets it claim the D-Bus name its tray icon needs.
To run in the tray, turn on "Keep Bitwarden running in the background" in its
settings (stored with the vault data, so not tracked here).

**Google Drive.** `~/drive` is an ordinary local folder and the source of
truth. `drive-backup.timer` mirrors it hourly to the `backup` folder in Drive,
so edits made directly in that folder are overwritten by the next run. Deleted
files go to Drive's trash. If a run would delete more than 25 files, the backup
stops before deleting anything and the service shows as failed; after a
deliberate big cleanup, run `rclone sync ~/drive gdrive:backup
--drive-skip-gdocs` once. Native Google Docs, Sheets and Slides aren't backed
up: they stay in Drive, outside `backup`. The client ID and secret are custom
fields `client_id` and `client_secret` of the Bitwarden item `rclone-drive`.
They belong to the
Google Cloud project `rclone-smr`, a Desktop app OAuth client, published so
the sign-in doesn't expire after 7 days.

## Updating the pinned versions

The Nerd Fonts are pinned to an exact version and checksums. The CLI tools
aren't pinned (`update` upgrades them), and the Catppuccin theme files are
plain copies.

```bash
bash ~/.local/share/chezmoi/update-pins.sh
chezmoi git -- diff
chezmoi apply
```

Check the fonts look right, then commit and push. The script also shows any
upstream change to Bitwarden's polkit action; it never copies it in.

## Testing setup.sh in the VM

Worth doing for changes to `setup.sh` or the first apply. Push a branch, then
go back to the fresh install and start it:

```bash
virsh -c qemu:///system snapshot-revert ws-test fresh-install
virsh -c qemu:///system start ws-test
```

Open it in Virtual Machine Manager, unlock the disk, log in, and in a terminal
run this. Use the branch you downloaded `setup.sh` from, so both halves match:

```bash
b=my-branch
wget -qO- https://github.com/michellhuaman/workstation/archive/refs/heads/$b.tar.gz | tar -xz
bash workstation-$b/setup.sh --branch "$b"
```

Reboot the VM and check it, then shut it down:
`virsh -c qemu:///system shutdown ws-test`.

### Making the VM again

`ws-test` is a libvirt VM with a fresh Ubuntu installed from `autoinstall.yaml`
and the snapshot `fresh-install`, taken after the first login and before
`setup.sh`. Its disks live in `~/vms`. For a new Ubuntu release, set up `~/vms`
and put the ISO in libvirt's image folder, which the VM can read (USB drives
it can't):

```bash
mkdir -p ~/vms
setfacl -m u:libvirt-qemu:x ~ && setfacl -m u:libvirt-qemu:rwx ~/vms
virsh -c qemu:///system pool-define-as vms dir --target ~/vms
virsh -c qemu:///system pool-start vms && virsh -c qemu:///system pool-autostart vms
iso=ubuntu-26.04.1-desktop-amd64.iso
virsh -c qemu:///system vol-create-as default "$iso" "$(stat -c %s "/path/to/$iso")" --format raw
virsh -c qemu:///system vol-upload --pool default "$iso" "/path/to/$iso"
virt-install --connect qemu:///system --name ws-test --osinfo ubuntu25.10 \
  --memory 6144 --vcpus 4 --cpu host-passthrough --boot uefi \
  --disk pool=vms,size=40,format=qcow2,bus=virtio \
  --cdrom "/var/lib/libvirt/images/$iso" \
  --network network=default,model=virtio --graphics spice --video virtio \
  --noautoconsole
```

(`--osinfo` is the newest Ubuntu that `virt-install --osinfo list` knows.)
Install it like a real machine, log in once, shut it down, and snapshot it.
The snapshot is disk-only because libvirt can't take internal snapshots of a
VM with UEFI firmware:

```bash
virsh -c qemu:///system shutdown ws-test
virsh -c qemu:///system snapshot-create-as ws-test fresh-install --disk-only --atomic
```
