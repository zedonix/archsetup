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

# Setting up mkinitcpio cuz of lvm
sed -i '/^HOOKS=/ s/\(block\)/\1 lvm2/' /etc/mkinitcpio.conf
mkinitcpio -P

# Boot Manager setup
if [[ "$microcode_pkg" == "intel-ucode" ]]; then
  microcode_img="initrd /intel-ucode.img"
elif [[ "$microcode_pkg" == "amd-ucode" ]]; then
  microcode_img="initrd /amd-ucode.img"
fi
bootctl install

cat >/boot/loader/loader.conf <<EOF
default arch
timeout 3
editor no
EOF

{
  echo "title   Arch Linux"
  echo "linux   /vmlinuz-linux"
  echo "$microcode_img"
  echo "initrd  /initramfs-linux.img"
  echo "options root=UUID=$uuid rw zswap.enabled=0 rootfstype=ext4"
} >/boot/loader/entries/arch.conf

if [[ "$howMuch" == "max" ]]; then
  {
    echo "title   Arch Linux (LTS)"
    echo "linux   /vmlinuz-linux-lts"
    [[ -n "$microcode_img" ]] && echo "$microcode_img"
    echo "initrd  /initramfs-linux-lts.img"
    echo "options root=UUID=$uuid rw zswap.enabled=0 rootfstype=ext4"
  } >/boot/loader/entries/arch-lts.conf
fi

# Reflector and pacman Setup
sed -i '/^#Color$/c\Color' /etc/pacman.conf
mkdir -p /etc/xdg/reflector
{
  echo "--save /etc/pacman.d/mirrorlist"
  echo "--protocol https"
  echo "--country India"
  echo "--latest 10"
  echo "--age 24"
  echo "--sort rate"
} >/etc/xdg/reflector/reflector.conf

reflector --country 'India' --latest 10 --age 24 --sort rate --save /etc/pacman.d/mirrorlist
systemctl enable reflector.timer

# Copy config and dotfiles as the user
if [[ "$howMuch" == "max" ]]; then
  su - "$username" -c '
    mkdir -p ~/Documents/default
    # Clone scripts
    git clone https://github.com/zedonix/scripts.git ~/Documents/default/scripts
    git clone https://github.com/zedonix/dotfiles.git ~/Documents/default/dotfiles
    git clone https://github.com/zedonix/archsetup.git ~/Documents/default/archsetup
    git clone https://github.com/zedonix/notes.git ~/Documents/default/notes
    git clone https://github.com/zedonix/GruvboxGtk.git ~/Documents/default/GruvboxGtk
    git clone https://github.com/zedonix/GruvboxQT.git ~/Documents/default/GruvboxQT
  '
  # Root .config
  mkdir -p ~/.config ~/.local/state/bash ~/.local/state/zsh
  echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >~/.bash_profile
  touch ~/.local/state/zsh/history ~/.local/state/bash/history
  ln -sf /home/$username/Documents/default/dotfiles/.bashrc ~/.bashrc 2>/dev/null || true
  ln -sf /home/$username/Documents/default/dotfiles/.zshrc ~/.zshrc 2>/dev/null || true
  ln -sf /home/$username/Documents/default/dotfiles/.config/nvim/ ~/.config

  # Setup QT theme
  THEME_SRC="/home/$username/Documents/default/GruvboxQT/"
  THEME_DEST="/usr/share/Kvantum/Gruvbox"
  mkdir -p "$THEME_DEST"
  cp "$THEME_SRC/gruvbox-kvantum.kvconfig" "$THEME_DEST/Gruvbox.kvconfig" 2>/dev/null || true
  cp "$THEME_SRC/gruvbox-kvantum.svg" "$THEME_DEST/Gruvbox.svg" 2>/dev/null || true

  # Firefox policy
  mkdir -p /etc/firefox/policies
  ln -sf "/home/$username/Documents/default/dotfiles/policies.json" /etc/firefox/policies/policies.json 2>/dev/null || true
fi
if [[ "$recon" == "no" ]]; then
  su - "$username" -c '
  mkdir -p ~/Downloads ~/Documents/projects ~/Public ~/Templates/wiki ~/Videos ~/Pictures/Screenshots ~/.config ~/.local/state/bash ~/.local/state/zsh
  mkdir -p ~/.local/bin ~/.cache/cargo-target
  touch ~/.local/state/bash/history ~/.local/state/zsh/history ~/Templates/wiki/index.md

  # Copy and link files (only if dotfiles exists)
  if [[ -d ~/Documents/default/dotfiles ]]; then
    cp ~/Documents/default/dotfiles/.config/sway/archLogo.png ~/Pictures/ 2>/dev/null || true
    cp ~/Documents/default/dotfiles/pics/* ~/Pictures/ 2>/dev/null || true
    cp -r ~/Documents/default/dotfiles/.local/share/themes/Gruvbox-Dark ~/.local/share/themes/ 2>/dev/null || true
    ln -sf ~/Documents/default/dotfiles/.bashrc ~/.bashrc 2>/dev/null || true
    ln -sf ~/Documents/default/dotfiles/.zshrc ~/.zshrc 2>/dev/null || true

    for link in ~/Documents/default/dotfiles/.config/*; do
      ln -sf "$link" ~/.config/ 2>/dev/null || true
    done
    for link in ~/Documents/default/scripts/bin/*; do
      ln -sf "$link" ~/.local/bin 2>/dev/null || true
    done
  fi

  # Clone tpm
  git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
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
{
  echo "[zram0]"
  echo "zram-size = ${ZRAM_SIZE}"
  echo "compression-algorithm = zstd #lzo-rle"
  echo "swap-priority = 100"
  echo "fs-type = swap"
} >/etc/systemd/zram-generator.conf.d/00-zram.conf

# Services
# rfkill unblock bluetooth
# modprobe btusb || true
systemctl enable NetworkManager NetworkManager-dispatcher
if [[ "$howMuch" == "max" ]]; then
  if [[ "$hardware" == "hardware" ]]; then
    systemctl enable ly fstrim.timer acpid cronie libvirtd.socket cups ipp-usb docker.socket sshd
  else
    systemctl enable ly cronie sshd cronie
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

# Clean up package cache and Wrapping up
pacman -Scc --noconfirm
