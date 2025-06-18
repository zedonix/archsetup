#!/bin/bash
set -euo pipefail

# --- Prompt Section (collect all user input here) ---

# Disk Selection
disks=($(lsblk -dno NAME))
echo "Available disks:"
for i in "${!disks[@]}"; do
    info=$(lsblk -dno NAME,SIZE,MODEL "/dev/${disks[$i]}")
    printf "%2d) %s\n" "$((i + 1))" "$info"
done
while true; do
    read -p "Select disk [1-${#disks[@]}]: " idx
    if [[ "$idx" =~ ^[1-9][0-9]*$ ]] && ((idx >= 1 && idx <= ${#disks[@]})); then
        disk="/dev/${disks[$((idx - 1))]}"
        break
    else
        echo "Invalid selection. Try again."
    fi
done

# Hostname
while true; do
    read -p "Hostname: " hostname
    # RFC 1123: 1-63 chars, letters, digits, hyphens, not start/end with hyphen
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        echo "Invalid hostname. Use 1-63 letters, digits, or hyphens (not starting or ending with hyphen)."
        continue
    fi
    break
done

# Root Password
while true; do
    read -s -p "Root password: " root_password
    echo
    read -s -p "Confirm root password: " root_password2
    echo
    [[ "$root_password" != "$root_password2" ]] && echo "Passwords do not match." && continue
    [[ -z "$root_password" ]] && echo "Password cannot be empty." && continue
    break
done

# Username
while true; do
    read -p "Username: " user
    # Linux username: 1-32 chars, start with letter, then letters/digits/_/-
    if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "Invalid username. Use 1-32 lowercase letters, digits, underscores, or hyphens, starting with a letter or underscore."
        continue
    fi
    break
done

# User Password
while true; do
    read -s -p "User password: " user_password
    echo
    read -s -p "Confirm user password: " user_password2
    echo
    [[ "$user_password" != "$user_password2" ]] && echo "Passwords do not match." && continue
    [[ -z "$user_password" ]] && echo "Password cannot be empty." && continue
    break
done

# Git Username
while true; do
    read -p "Git username: " git_username
    [[ -z "$git_username" ]] && echo "Git username cannot be empty." && continue
    break
done

# Git Email with regex validation and double confirmation
email_regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
while true; do
    read -p "Git email: " git_email
    [[ ! "$git_email" =~ $email_regex ]] && echo "Invalid email format." && continue
    read -p "Confirm git email: " git_email2
    [[ "$git_email" != "$git_email2" ]] && echo "Emails do not match." && continue
    break
done

# Export variables for later use
export disk hostname root_password user user_password git_username git_email

# Partition Naming
if [[ "$disk" == *nvme* ]]; then
    part_prefix="${disk}p"
else
    part_prefix="${disk}"
fi

part1="${part_prefix}1"
part2="${part_prefix}2"

# Partitioning --
parted -s "$disk" mklabel gpt
parted -s "$disk" mkpart ESP fat32 1MiB 1025MiB
parted -s "$disk" set 1 esp on
parted -s "$disk" mkpart primary btrfs 1025MiB 100%

# Formatting
mkfs.vfat -F 32 -n EFI "$part1"
mkfs.btrfs -f -L ROOT "$part2"

mount "$part2" /mnt
# --

# mount -o subvolid=5 "$part2" /mnt
# btrfs subvolume delete /mnt/@ || true
btrfs subvolume create /mnt/@
[ ! -d /mnt/@home ] && btrfs subvolume create /mnt/@home
[ ! -d /mnt/@var ] && btrfs subvolume create /mnt/@var
[ ! -d /mnt/@snapshots ] && btrfs subvolume create /mnt/@snapshots

umount /mnt

mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@ "$part2" /mnt
mkdir -p /mnt/{boot/efi,home,var,.snapshots}
mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@home "$part2" /mnt/home
mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@var "$part2" /mnt/var
mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@snapshots "$part2" /mnt/.snapshots
mount "$part1" /mnt/boot/efi/

# Detect CPU vendor and set microcode package
cpu_vendor=$(lscpu | awk -F: '/Vendor ID:/ {print $2}' | xargs)
if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
    microcode_pkg="intel-ucode"
elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
    microcode_pkg="amd-ucode"
else
    microcode_pkg=""
    echo "Warning: Unknown CPU vendor. No microcode package will be installed."
fi

# Pacstrap stuff
install_pkgs=(
    base base-devel linux-lts linux-lts-headers linux-zen linux-zen-headers linux-firmware sudo btrfs-progs bash-completion
    ananicy-cpp zram-generator acpid acpi tlp tlp-rdw
    networkmanager network-manager-applet bluez bluez-utils
    ntfs-3g exfat-utils mtools dosfstools inotify-tools
    "$microcode_pkg"
    # cups cups-pdf ghostscript gsfonts gutenprint foomatic-db foomatic-db-engine foomatic-db-nonfree foomatic-db-ppds system-config-printer
    # hplip
    grub grub-btrfs efibootmgr os-prober snapper snap-pac
    qemu-desktop virt-manager libvirt dnsmasq vde2 bridge-utils openbsd-netcat dmidecode
    openssh ncdu bat bat-extras eza fzf git github-cli ripgrep ripgrep-all fd sqlite cronie ufw trash-cli curl wget playerctl bc ffmpegthumbnailer
    sassc udisks2 udisks2-btrfs gvfs gvfs-mtp gvfs-gphoto2 unrar 7zip unzip rsync jq reflector polkit polkit-gnome file-roller flatpak imagemagick
    man-db man-pages wikiman tldr arch-wiki-docs
    pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-audio pipewire-jack brightnessctl
    xorg-xwayland xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    ly sway swaybg swaylock swayidle swayimg waybar kanshi
    discord firefox zathura pcmanfm-gtk3 gimp blueman mission-center deluge-gtk mpv fuzzel rofimoji
    easyeffects audacity lsp-plugins-lv2 mda.lv2 zam-plugins-lv2 calf
    foot nvtop htop powertop lshw fastfetch onefetch newsboat neovim tmux asciinema yt-dlp vifm caligula
    papirus-icon-theme noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-font-awesome ttc-iosevka ttf-iosevkaterm-nerd gnu-free-fonts
    qt6ct qt6-wayland kvantum
    wl-clip-persist wl-clipboard cliphist libnotify swaync grim slurp satty hyprpicker
    texlive-latex pandoc zathura-pdf-mupdf #texlive-mathscience
    docker docker-compose
    lua lua-language-server stylua
    python uv ruff pyright
    typescript-language-server prettier nodejs npm #pnpm
    bash-language-server shfmt
    ollama
)

# Pacstrap with error handling
reflector --country 'India' --latest 10 --age 24 --sort rate --save /etc/pacman.d/mirrorlist
if ! pacstrap /mnt "${install_pkgs[@]}"; then
    echo "pacstrap failed. Please check the package list and network connection."
    exit 1
fi

# System Configuration
genfstab -U /mnt >/mnt/etc/fstab

# Exporting variables for chroot
cat >/mnt/root/install.conf <<EOF
hostname=$hostname
root_password=$root_password
user=$user
user_password=$user_password
EOF

cat >/mnt/root/git.conf <<EOF
git_username=$git_username
git_email=$git_email
EOF

chmod 600 /mnt/root/install.conf
chmod 666 /mnt/root/git.conf

# Run chroot.sh
cp "$(dirname "$0")/chroot.sh" /mnt/root/chroot.sh
chmod +x /mnt/root/chroot.sh
arch-chroot /mnt /root/chroot.sh

# Unmount and finalize
if mountpoint -q /mnt; then
    umount -R /mnt
fi
echo "Installation completed. Please reboot your system."
