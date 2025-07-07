#!/bin/bash
set -euo pipefail

# Variable set
timezone="Asia/Kolkata"
username="piyush"
git_name="piyush"
git_email="zedonix@proton.me"

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
    if [[ "$second" == "max" && "$first" == "hardware" ]]; then
        useradd -m -G wheel,storage,video,audio,lp,sys,kvm,libvirt,docker -s /bin/bash "$username"
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

# Bootloader
# grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot
# sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
#sed -i 's/^#GRUB_DISABLE_SUBMENU=y/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
# grub-mkconfig -o /boot/grub/grub.cfg

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

if [[ "$second" == "max" ]]; then
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
if [[ "$second" == "max" && "$recon" != "yes" ]]; then
    su - "$username" -c '
        xdg-user-dirs-update
        mkdir -p ~/Pictures/Screenshots ~/Documents/projects ~/.config ~/.local/state/bash ~/.wiki
        touch ~/.wiki/index.md

        # Clone scripts
        if ! git clone https://github.com/zedonix/scripts.git ~/.scripts; then
            echo "Failed to clone scripts. Continuing..."
        fi

        # Clone dotfiles
        if ! git clone https://github.com/zedonix/dotfiles.git ~/.dotfiles; then
            echo "Failed to clone dotfiles. Continuing..."
        fi

        # Clone archsetup
        if ! git clone https://github.com/zedonix/archsetup.git ~/.archsetup; then
            echo "Failed to clone archsetup. Continuing..."
        fi

        # Clone ananicy-rules
        if ! git clone https://github.com/CachyOS/ananicy-rules.git ~/Downloads/ananicy-rules; then
            echo "Failed to clone ananicy-rules. Continuing..."
        fi

        # Clone GruvboxGtk
        if ! git clone https://github.com/zedonix/GruvboxGtk.git ~/Downloads/GruvboxGtk; then
            echo "Failed to clone GruvboxGtk. Continuing..."
        fi

        # Clone GruvboxQT
        if ! git clone https://github.com/zedonix/GruvboxQT.git ~/Downloads/GruvboxQT; then
            echo "Failed to clone GruvboxQT. Continuing..."
        fi

        # Copy and link files (only if dotfiles exists)
        if [[ -d ~/.dotfiles ]]; then
            cp ~/.dotfiles/.config/sway/archLogo.png ~/Pictures/ 2>/dev/null || true
            cp ~/.dotfiles/pics/* ~/Pictures/ 2>/dev/null || true
            cp -r ~/.dotfiles/.local/share/themes/Gruvbox-Dark ~/.local/share/themes/ 2>/dev/null || true
            ln -sf ~/.dotfiles/.bashrc ~/.bashrc 2>/dev/null || true

            for link in ~/.dotfiles/.config/*; do
                ln -sf "$link" ~/.config/ 2>/dev/null || true
            done
        fi

        # Clone tpm
        if ! git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm; then
            echo "Failed to clone tpm. Continuing..."
        fi

        git config --global user.name "'"$git_name"'"
        git config --global user.email "'"$git_email"'"
        git config --global init.defaultBranch main
    '
    # Root .config
    mkdir -p ~/.config ~/.local/state/bash
    ln -sf /home/$username/.dotfiles/.bashrc ~/.bashrc
    ln -sf /home/$username/.dotfiles/.config/nvim/ ~/.config

    # ly sway setup
    sed -i "s|^Exec=.*|Exec=/home/$username/.scripts/sway.sh|" /usr/share/wayland-sessions/sway.desktop

    # Setup QT theme
    THEME_SRC="/home/$username/Downloads/GruvboxQT/"
    THEME_DEST="/usr/share/Kvantum/Gruvbox"
    mkdir -p "$THEME_DEST"
    cp "$THEME_SRC/gruvbox-kvantum.kvconfig" "$THEME_DEST/Gruvbox.kvconfig" 2>/dev/null || true
    cp "$THEME_SRC/gruvbox-kvantum.svg" "$THEME_DEST/Gruvbox.svg" 2>/dev/null || true

    # Install CachyOS Ananicy Rules
    ANANICY_RULES_SRC="/home/$username/Downloads/ananicy-rules"
    mkdir -p /etc/ananicy.d

    cp -r "$ANANICY_RULES_SRC/00-default" /etc/ananicy.d/ 2>/dev/null || true
    cp "$ANANICY_RULES_SRC/"*.rules /etc/ananicy.d/ 2>/dev/null || true
    cp "$ANANICY_RULES_SRC/00-cgroups.cgroups" /etc/ananicy.d/ 2>/dev/null || true
    cp "$ANANICY_RULES_SRC/00-types.types" /etc/ananicy.d/ 2>/dev/null || true
    cp "$ANANICY_RULES_SRC/ananicy.conf" /etc/ananicy.d/ 2>/dev/null || true

    chmod -R 644 /etc/ananicy.d/*
    chmod 755 /etc/ananicy.d/00-default

    # tldr wiki setup
    curl -L "https://raw.githubusercontent.com/filiparag/wikiman/master/Makefile" -o "wikiman-makefile"
    make -f ./wikiman-makefile source-tldr
    make -f ./wikiman-makefile source-install
    make -f ./wikiman-makefile clean

    # Firefox policy
    mkdir -p /etc/firefox/policies
    ln -sf "/home/$username/.dotfiles/policies.json" /etc/firefox/policies/policies.json 2>/dev/null || true
elif [[ "$second" == "max" && "$recon" == "yes" ]]; then

    # Root .config
    mkdir -p ~/.config ~/.local/state/bash
    ln -sf /home/$username/.dotfiles/.bashrc ~/.bashrc
    ln -sf /home/$username/.dotfiles/.config/nvim/ ~/.config

    # ly sway setup
    sed -i "s|^Exec=.*|Exec=/home/$username/.scripts/sway.sh|" /usr/share/wayland-sessions/sway.desktop

    # Setup QT theme
    THEME_SRC="/home/$username/Downloads/GruvboxQT/"
    THEME_DEST="/usr/share/Kvantum/Gruvbox"
    mkdir -p "$THEME_DEST"
    cp "$THEME_SRC/gruvbox-kvantum.kvconfig" "$THEME_DEST/Gruvbox.kvconfig" 2>/dev/null || true
    cp "$THEME_SRC/gruvbox-kvantum.svg" "$THEME_DEST/Gruvbox.svg" 2>/dev/null || true

    # Install CachyOS Ananicy Rules
    ANANICY_RULES_SRC="/home/$username/Downloads/ananicy-rules"
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
    ln -sf "/home/$username/.dotfiles/policies.json" /etc/firefox/policies/policies.json 2>/dev/null || true
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
if [[ "$second" == "max" ]]; then
    if [[ "$first" == "hardware" ]]; then
        systemctl enable ly fstrim.timer acpid cronie ananicy-cpp libvirtd.socket cups docker sshd
    else
        systemctl enable ly cronie ananicy-cpp sshd cronie
    fi
    if [[ "$third" == "laptop" || "$third" == "bluetooth" ]]; then
        systemctl enable bluetooth
    fi
    if [[ "$third" == "laptop" ]]; then
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
