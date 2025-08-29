#!/usr/bin/env bash
set -euo pipefail

# Load variables from install.conf
source /root/install.conf
uuid=$(blkid -s UUID -o value "$part2")

# --- Set hostname ---
echo "$hostname" >/etc/hostname
echo "127.0.0.1  localhost" >/etc/hosts
echo "::1        localhost" >>/etc/hosts
echo "127.0.1.1  $hostname.localdomain  $hostname" >>/etc/hosts

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

if [[ "$ddos" == "no" ]]; then
  reflector --country 'India' --latest 10 --age 24 --sort rate --save /etc/pacman.d/mirrorlist
else
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
  cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://in.arch.niranjan.co/$repo/os/$arch
Server = https://mirrors.saswata.cc/archlinux/$repo/os/$arch
Server = https://mirror.del2.albony.in/archlinux/$repo/os/$arch
Server = https://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
EOF
fi
systemctl enable reflector.timer

# Copy config and dotfiles as the user
if [[ "$howMuch" == "max" ]]; then
  su - "$username" -c '
    mkdir -p ~/Documents/projects/default
    # Clone scripts
    git clone https://github.com/zedonix/scripts.git ~/Documents/projects/default/scripts
    git clone https://github.com/zedonix/dotfiles.git ~/Documents/projects/default/dotfiles
    git clone https://github.com/zedonix/archsetup.git ~/Documents/projects/default/archsetup
    git clone https://github.com/zedonix/notes.git ~/Documents/projects/default/notes
    git clone https://github.com/zedonix/GruvboxGtk.git ~/Documents/projects/default/GruvboxGtk
    git clone https://github.com/zedonix/GruvboxQT.git ~/Documents/projects/default/GruvboxQT
  '
  # Root .config
  mkdir -p ~/.config ~/.local/state/bash ~/.local/state/zsh
  echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >~/.bash_profile
  touch ~/.local/state/zsh/history ~/.local/state/bash/history
  ln -sf /home/$username/Documents/projects/default/dotfiles/.bashrc ~/.bashrc 2>/dev/null || true
  ln -sf /home/$username/Documents/projects/default/dotfiles/.zshrc ~/.zshrc 2>/dev/null || true
  ln -sf /home/$username/Documents/projects/default/dotfiles/.config/nvim/ ~/.config

  # ly config
  # -e 's/^bigclock *= *.*/bigclock = en/' \
  # sed -i \
  #   -e 's/^allow_empty_password *= *.*/allow_empty_password = false/' \
  #   -e 's/^clear_password *= *.*/clear_password = true/' \
  #   -e 's/^clock *= *.*/clock = %a %d\/%m %H:%M/' \
  #   /etc/ly/config.ini

  # Greetd setup for tuigreet
  cp -f /home/$username/Documents/projects/default/dotfiles/config.toml /etc/greetd/

  # Setup QT theme
  THEME_SRC="/home/$username/projects/default/GruvboxQT/"
  THEME_DEST="/usr/share/Kvantum/Gruvbox"
  mkdir -p "$THEME_DEST"
  cp "$THEME_SRC/gruvbox-kvantum.kvconfig" "$THEME_DEST/Gruvbox.kvconfig" 2>/dev/null || true
  cp "$THEME_SRC/gruvbox-kvantum.svg" "$THEME_DEST/Gruvbox.svg" 2>/dev/null || true

  # Anancy-cpp rules
  git clone --depth=1 https://github.com/RogueScholar/ananicy.git
  git clone --depth=1 https://github.com/CachyOS/ananicy-rules.git
  mkdir -p /etc/ananicy.d/roguescholar /etc/ananicy.d/zz-cachyos
  cp -r ananicy/ananicy.d/* /etc/ananicy.d/roguescholar/
  cp -r ananicy-rules/00-default/* /etc/ananicy.d/zz-cachyos/
  cp -r ananicy-rules/00-types.types /etc/ananicy.d/zz-cachyos/
  cp -r ananicy-rules/00-cgroups.cgroups /etc/ananicy.d/zz-cachyos/

  # Firefox policy
  mkdir -p /etc/firefox/policies
  ln -sf "/home/$username/Documents/projects/default/dotfiles/policies.json" /etc/firefox/policies/policies.json 2>/dev/null || true
fi
if [[ "$recovery" == "no" ]]; then
  su - "$username" -c '
  mkdir -p ~/Downloads ~/Desktop ~/Public ~/Templates ~/Videos ~/Pictures/Screenshots/temp ~/.config
  mkdir -p ~/Documents/projects/work ~/Documents/projects/sandbox ~/Documents/personal/wiki
  mkdir -p ~/.local/bin ~/.cache/cargo-target ~/.local/state/bash ~/.local/state/zsh
  touch ~/.local/state/bash/history ~/.local/state/zsh/history ~/Documents/personal/wiki/index.txt

  # Copy and link files (only if dotfiles exists)
  if [[ -d ~/Documents/projects/default/dotfiles ]]; then
    cp ~/Documents/projects/default/dotfiles/.config/sway/archLogo.png ~/Pictures/ 2>/dev/null || true
    cp ~/Documents/projects/default/dotfiles/pics/* ~/Pictures/ 2>/dev/null || true
    cp -r ~/Documents/projects/default/dotfiles/.local/share/themes/Gruvbox-Dark ~/.local/share/themes/ 2>/dev/null || true
    ln -sf ~/Documents/projects/default/dotfiles/.bashrc ~/.bashrc 2>/dev/null || true
    ln -sf ~/Documents/projects/default/dotfiles/.zshrc ~/.zshrc 2>/dev/null || true

    for link in ~/Documents/projects/default/dotfiles/.config/*; do
      ln -sf "$link" ~/.config/ 2>/dev/null || true
    done
    for link in ~/Documents/projects/default/scripts/bin/*; do
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
if [[ "$howMuch" == "max" ]]; then
  systemctl enable ananicy-cpp greetd cronie sshd
  if [[ "$hardware" == "hardware" ]]; then
    systemctl enable fstrim.timer acpid libvirtd.socket cups ipp-usb docker.socket
  fi
  if [[ "$extra" == "laptop" || "$extra" == "bluetooth" ]]; then
    systemctl enable bluetooth
  fi
  if [[ "$extra" == "laptop" ]]; then
    systemctl enable tlp
    cpupower frequency-set -g schedutil
    # setup schedutil and tlp together
  fi
fi
systemctl enable NetworkManager NetworkManager-dispatcher
systemctl mask systemd-rfkill systemd-rfkill.socket
systemctl disable NetworkManager-wait-online.service

# Clean up package cache and Wrapping up
pacman -Scc --noconfirm
