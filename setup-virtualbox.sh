#!/usr/bin/env bash
# Installs VirtualBox, from Ubuntu's multiverse. Optional: setup.sh leaves it
# out, so run this only on a machine that needs VirtualBox VMs (`vm` needs it).
# Safe to run again.
#
# With Secure Boot on, the kernel modules are signed with the machine's MOK
# key, which must be enrolled once: the install asks for a one-time password,
# and the next boot shows the screen where you enroll it (see "VirtualBox" in
# the README).
#
# virtualbox-dkms also sets `options kvm enable_virt_at_load=0`
# (/usr/lib/modprobe.d/virtualbox-dkms.conf): since kernel 6.12 KVM takes
# AMD-V/VT-x at boot and VirtualBox VMs won't start. With it, KVM only takes it
# while a KVM VM runs, so a VirtualBox VM and a KVM one (virt-manager, Claude
# Desktop's Cowork) can't run at the same time. Effective after a reboot.
set -euo pipefail

[[ $EUID -ne 0 ]] || { echo "error: run this as your normal user; it uses sudo when needed" >&2; exit 1; }

sudo apt-get update -q
# gcc builds the kernel modules; removing it later would remove VirtualBox too.
sudo apt-get install -y -q --no-upgrade gcc virtualbox virtualbox-qt
# vboxusers: passing host USB devices through to VMs.
sudo usermod -aG vboxusers "$(id -un)"

cat <<EOF

Done. Reboot (systemctl reboot). If a blue MOK Manager screen appears, choose
"Enroll MOK", not "Continue boot", then Continue, Yes, the password you just
set, and Reboot.
EOF
