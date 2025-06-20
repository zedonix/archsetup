#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR"

# --- Prompt Section (collect all user input here) ---
#
# Which type of install?
#
# First choice: vm or hardware
echo "Choose one:"
select first in "vm" "hardware"; do
    [[ -n $first ]] && break
    echo "Invalid choice. Please select 1 for vm or 2 for hardware."
done

# Second choice: min or max
echo "Choose one:"
select second in "min" "max"; do
    [[ -n $second ]] && break
    echo "Invalid choice. Please select 1 for min or 2 for max."
done

# Disk Selection
disks=($(lsblk -dno NAME,TYPE,RM | awk '$2 == "disk" && $3 == "0" {print $1}'))
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

# Partition Naming
if [[ "$disk" == *nvme* ]]; then
    part_prefix="${disk}p"
else
    part_prefix="${disk}"
fi

part1="${part_prefix}1"
part2="${part_prefix}2"
part3="${part_prefix}3"

# Partitioning
parted -s "$disk" mklabel gpt
parted -s "$disk" mkpart ESP fat32 1MiB 2049MiB
parted -s "$disk" set 1 esp on
if [[ "$first" == "vm" ]]; then
    parted -s "$disk" mkpart primary ext4 2049MiB 50%
    parted -s "$disk" mkpart primary ext4 50% 100%
else
    parted -s "$disk" mkpart primary ext4 2049MiB 102449MiB
    parted -s "$disk" mkpart primary ext4 102449MiB 100%
fi

# Formatting
mkfs.fat -F 32 -n EFI "$part1"
mkfs.ext4 -L ROOT "$part2"
mkfs.ext4 -L HOME "$part3"

# Mounting
mount "$part2" /mnt
mkdir /mnt/boot /mnt/home
mount "$part1" /mnt/boot
mount "$part3" /mnt/home

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
#
#texlive-mathscience
sed -i "s|\"\$microcode_pkg\"|$microcode_pkg|g" pkgs.txt

# Which type of packages?
case "$first:$second" in
vm:min)
    # Install only line 1
    sed -n '1p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
vm:max)
    # Install lines 1 and 3
    # sed -n '1,3p' pkgs.txt | head -n 3 | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    # Or, if you only want lines 1 and 3 (not 2), use:
    sed -n '1p;3p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
hardware:min)
    # Install lines 1 and 2
    sed -n '1,2p' pkgs.txt | head -n 2 | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
hardware:max)
    # Install all lines
    cat pkgs.txt | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
esac

# Pacstrap with error handling
reflector --country 'India' --latest 10 --age 24 --sort rate --save /etc/pacman.d/mirrorlist
if ! pacstrap /mnt - <pkglist.txt; then
    echo "pacstrap failed. Please check the package list and network connection."
    exit 1
fi

# System Configuration
genfstab -U /mnt >/mnt/etc/fstab

# Exporting variables for chroot
cat >/mnt/root/install.conf <<EOF
hostname=$hostname
root_password=$root_password
user_password=$user_password
first=$first
second=$second
microcode_pkg=$microcode_pkg
EOF

chmod 600 /mnt/root/install.conf

# Run chroot.sh
# hackaround for systemd not working - github.com/systemd/systemd/issues/36174
bootctl --esp-path=/mnt/boot install
cp chroot.sh /mnt/root/chroot.sh
chmod +x /mnt/root/chroot.sh
arch-chroot /mnt /root/chroot.sh

# Unmount and finalize
if mountpoint -q /mnt; then
    umount -R /mnt || {
        echo "Failed to unmount /mnt. Please check."
        exit 1
    }
fi
echo "Installation completed. Please reboot your system."
