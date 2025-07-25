#!/usr/bin/env bash
set -euo pipefail

# Variable set
timezone="Asia/Kolkata"
username="piyush"

# Load variables from install.conf
source /root/install.conf
uuid=$(blkid -s UUID -o value "$part2")

# --- Set hostname ---
echo "$hostname" >/etc/hostname
echo "127.0.0.1  localhost" >/etc/hosts
echo "::1        localhost" >>/etc/hosts
echo "127.0.1.1  $hostname.localdomain  $hostname" >>/etc/hosts

# --- Set root password ---
echo "root:$root_password" | chpasswd

# --- Create user and set password ---
if ! id "$username" &>/dev/null; then
  if [[ "$howMuch" == "max" && "$hardware" == "hardware" ]]; then
    useradd -m -G wheel,storage,video,audio,lp,scanner,sys,kvm,libvirt,docker -s /bin/bash "$username"
  else
    useradd -m -G wheel,storage,video,audio,lp,sys -s /bin/bash "$username"
  fi
  echo "$username:$user_password" | chpasswd
else
  echo "User $username already exists, skipping creation."
fi

# Local Setup
ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/g' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf

# Sudo Configuration
echo "%wheel ALL=(ALL) ALL" >/etc/sudoers.d/wheel
echo "Defaults timestamp_timeout=-1" >/etc/sudoers.d/timestamp
chmod 440 /etc/sudoers.d/wheel /etc/sudoers.d/timestamp

# Boot Manager setup
if [[ "$microcode_pkg" == "intel-ucode" ]]; then
  microcode_img="initrd /intel-ucode.img"
elif [[ "$microcode_pkg" == "amd-ucode" ]]; then
  microcode_img="initrd /amd-ucode.img"
else
  microcode_img=""
fi
bootctl install

cat >/boot/loader/loader.conf <<EOF
default arch
timeout 3
editor no
EOF

cat >/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
$microcode_img
initrd  /initramfs-linux.img
options root=UUID=$uuid rw zswap.enabled=0 rootfstype=ext4
EOF

if [[ "$howMuch" == "max" ]]; then
  cat >/boot/loader/entries/arch-lts.conf <<EOF
  title   Arch Linux (LTS)
  linux   /vmlinuz-linux-lts
  $microcode_img
  initrd  /initramfs-linux-lts.img
  options root=UUID=$uuid rw zswap.enabled=0 rootfstype=ext4
EOF
fi

# Reflector and pacman Setup
sed -i '/^#Color$/c\Color' /etc/pacman.conf
mkdir -p /etc/xdg/reflector
cat >/etc/xdg/reflector/reflector.conf <<REFCONF
--save /etc/pacman.d/mirrorlist
--protocol https
--country India
--latest 10
--age 24
--sort rate
REFCONF

reflector --country 'India' --latest 10 --age 24 --sort rate --save /etc/pacman.d/mirrorlist
systemctl enable reflector.timer

# Copy config and dotfiles as the user
if [[ "$howMuch" == "max" ]]; then
  su - "$username" -c '
    mkdir -p ~/Documents
    # Clone scripts
    if ! git clone https://github.com/zedonix/scripts.git ~/Documents/scripts; then
      echo "Failed to clone scripts. Continuing..."
    fi
    # Clone dotfiles
    if ! git clone https://github.com/zedonix/dotfiles.git ~/Documents/dotfiles; then
      echo "Failed to clone dotfiles. Continuing..."
    fi

    # Clone archsetup
    if ! git clone https://github.com/zedonix/archsetup.git ~/Documents/archsetup; then
      echo "Failed to clone archsetup. Continuing..."
    fi

    # Clone Notes
    if ! git clone https://github.com/zedonix/notes.git ~/Documents/notes; then
      echo "Failed to clone ananicy-rules. Continuing..."
    fi

    # Clone ananicy-rules
    if ! git clone https://github.com/CachyOS/ananicy-rules.git ~/Documents/ananicy-rules; then
      echo "Failed to clone ananicy-rules. Continuing..."
    fi

    # Clone GruvboxGtk
    if ! git clone https://github.com/zedonix/GruvboxGtk.git ~/Documents/GruvboxGtk; then
      echo "Failed to clone GruvboxGtk. Continuing..."
    fi

    # Clone GruvboxQT
    if ! git clone https://github.com/zedonix/GruvboxQT.git ~/Documents/GruvboxQT; then
      echo "Failed to clone GruvboxQT. Continuing..."
    fi
  '
  # Root .config
  mkdir -p ~/.config ~/.local/state/bash ~/.local/state/zsh
  echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >~/.bash_profile
  touch ~/.local/state/zsh/history ~/.local/state/bash/history
  ln -sf /home/$username/Documents/dotfiles/.bashrc ~/.bashrc 2>/dev/null || true
  ln -sf /home/$username/Documents/dotfiles/.zshrc ~/.zshrc 2>/dev/null || true
  ln -sf /home/$username/Documents/dotfiles/.config/nvim/ ~/.config

  # Setup QT theme
  THEME_SRC="/home/$username/Documents/GruvboxQT/"
  THEME_DEST="/usr/share/Kvantum/Gruvbox"
  mkdir -p "$THEME_DEST"
  cp "$THEME_SRC/gruvbox-kvantum.kvconfig" "$THEME_DEST/Gruvbox.kvconfig" 2>/dev/null || true
  cp "$THEME_SRC/gruvbox-kvantum.svg" "$THEME_DEST/Gruvbox.svg" 2>/dev/null || true

  # Install CachyOS Ananicy Rules
  ANANICY_RULES_SRC="/home/$username/Documents/ananicy-rules"
  mkdir -p /etc/ananicy.d

  cp -r "$ANANICY_RULES_SRC/00-default" /etc/ananicy.d/ 2>/dev/null || true
  cp "$ANANICY_RULES_SRC/"*.rules /etc/ananicy.d/ 2>/dev/null || true
  cp "$ANANICY_RULES_SRC/00-cgroups.cgroups" /etc/ananicy.d/ 2>/dev/null || true
  cp "$ANANICY_RULES_SRC/00-types.types" /etc/ananicy.d/ 2>/dev/null || true
  cp "$ANANICY_RULES_SRC/ananicy.conf" /etc/ananicy.d/ 2>/dev/null || true

  chmod -R 644 /etc/ananicy.d/*
  chmod 755 /etc/ananicy.d/00-default

  # Firefox policy
  mkdir -p /etc/firefox/policies
  ln -sf "/home/$username/Documents/dotfiles/policies.json" /etc/firefox/policies/policies.json 2>/dev/null || true
fi
if [[ "$recon" == "no" ]]; then
  su - "$username" -c '
  mkdir -p ~/Downloads ~/Documents/projects ~/Public ~/Templates/projects ~/Videos ~/Pictures/Screenshots ~/.config ~/.local/state/bash ~/.local/state/zsh ~/.wiki
  mkdir -p ~/.local/share/npm ~/.cache/npm ~/.config/npm/config ~/.local/bin
  touch ~/.wiki/index ~/.local/state/bash/history ~/.local/state/zsh/history

  # Copy and link files (only if dotfiles exists)
  if [[ -d ~/Documents/dotfiles ]]; then
    cp ~/Documents/dotfiles/.config/sway/archLogo.png ~/Pictures/ 2>/dev/null || true
    cp ~/Documents/dotfiles/pics/* ~/Pictures/ 2>/dev/null || true
    cp -r ~/Documents/dotfiles/.local/share/themes/Gruvbox-Dark ~/.local/share/themes/ 2>/dev/null || true
    ln -sf ~/Documents/dotfiles/.bashrc ~/.bashrc 2>/dev/null || true
    ln -sf ~/Documents/dotfiles/.zshrc ~/.zshrc 2>/dev/null || true
    ln -sf ~/Documents/dotfiles/.gtk-bookmarks ~/.git-bookmarks || true

    for link in ~/Documents/dotfiles/.config/*; do
      ln -sf "$link" ~/.config/ 2>/dev/null || true
    done
    for link in ~/Documents/scripts/bin/*; do
      ln -sf "$link" ~/.local/bin 2>/dev/null || true
    done
  fi

  # Clone tpm
  if ! git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm; then
    echo "Failed to clone tpm. Continuing..."
  fi
  '
  # tldr wiki setup
  curl -L "https://raw.githubusercontent.com/filiparag/wikiman/master/Makefile" -o "wikiman-makefile"
  make -f ./wikiman-makefile source-tldr
  make -f ./wikiman-makefile source-install
  make -f ./wikiman-makefile clean
fi

# Delete variables
shred -u /root/install.conf

# zram config
# Get total memory in MiB
TOTAL_MEM=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
ZRAM_SIZE=$((TOTAL_MEM / 2))

# Create zram config
mkdir -p /etc/systemd/zram-generator.conf.d

cat >/etc/systemd/zram-generator.conf.d/00-zram.conf <<EOF
[zram0]
zram-size = ${ZRAM_SIZE}
compression-algorithm = zstd #lzo-rle
swap-priority = 100
fs-type = swap
EOF

# Services
# rfkill unblock bluetooth
# modprobe btusb || true
systemctl enable NetworkManager NetworkManager-dispatcher
if [[ "$howMuch" == "max" ]]; then
  if [[ "$hardware" == "hardware" ]]; then
    systemctl enable ly fstrim.timer acpid cronie ananicy-cpp libvirtd.socket cups ipp-usb docker.socket sshd
  else
    systemctl enable ly cronie ananicy-cpp sshd cronie
  fi
  if [[ "$extra" == "laptop" || "$extra" == "bluetooth" ]]; then
    systemctl enable bluetooth
  fi
  if [[ "$extra" == "laptop" ]]; then
    systemctl enable tlp
  fi
fi
systemctl mask systemd-rfkill systemd-rfkill.socket
systemctl disable NetworkManager-wait-online.service systemd-networkd.service systemd-resolved

# Prevent NetworkManager from using systemd-resolved
mkdir -p /etc/NetworkManager/conf.d
echo -e "[main]\nsystemd-resolved=false" | tee /etc/NetworkManager/conf.d/no-systemd-resolved.conf >/dev/null

# Set DNS handling to 'default'
echo -e "[main]\ndns=default" | tee /etc/NetworkManager/conf.d/dns.conf >/dev/null

# Clean up package cache and Wrapping up
pacman -Scc --noconfirm
