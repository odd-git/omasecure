#!/bin/bash

set -euo pipefail
## DNF5 Speedup
sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf
dnf -y install libvirt virt-manager qemu-kvm flatpak-builder wlr-randr iotop sysstat lxqt-openssh-askpass lxpolkit parallel

# User apps
dnf -y install nautilus kitty mpv gnome-terminal gnome-system-monitor

# Nautilus open any terminal extension
curl -Lo /etc/yum.repos.d/nautilus-open-any-terminal.repo \
  https://copr.fedorainfracloud.org/coprs/monkeygold/nautilus-open-any-terminal/repo/fedora-$(rpm -E %fedora)/monkeygold-nautilus-open-any-terminal-fedora-$(rpm -E %fedora).repo
dnf install -y nautilus-open-any-terminal
glib-compile-schemas /usr/share/glib-2.0/schemas
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty

# Install Niri
dnf -y install niri

# Install Dank Linux shell
curl --output-dir "/etc/yum.repos.d/" \
  --remote-name "https://copr.fedorainfracloud.org/coprs/avengemedia/dms/repo/fedora-$(rpm -E %fedora)/avengemedia-dms-fedora-$(rpm -E %fedora).repo"
dnf -y install quickshell dms greetd dms-greeter --allowerasing
#
# Install greetd login manager with dank configuration (still needs some work)
mkdir -p /etc/greetd/
cat >/etc/greetd/config.toml <<EOF
[terminal]
vt = 1
[default_session]
user = "greeter"
command = "dms-greeter --command niri"
EOF
rm -f /etc/systemd/system/display-manager.service
ln -s /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable --force greetd.service

mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -s /usr/lib/systemd/user/dms.service /etc/skel/.config/systemd/user/graphical-session.target.wants/
mkdir -p /etc/skel/.config/niri/
cp -rf /tmp/files/dot_config/niri/config.kdl /etc/skel/.config/niri/

#### Enable podman
systemctl enable podman.socket

# Disable Origami tips
sudo mv /etc/profile.d/origami-aliases.sh /etc/profile.d/origami-aliases.sh.bak
# Remove COSMIC shell and waybar
dnf -y remove cosmic-comp cosmic-initial-setup cosmic-settings cosmic-settings-daemon cosmic-store waybar

## CLEAN UP
# Clean up dnf cache to reduce image size
dnf5 -y clean all
rm -rf /run/dnf /run/selinux-policy
rm -rf /var/lib/dnf
