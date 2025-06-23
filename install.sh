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

# third choice: laptop or bluetooth or none
if [[ "$second" == "max" && "$first" == "hardware" ]]; then
    echo "Choose one:"
    select third in "laptop" "bluetooth" "none"; do
        [[ -n $third ]] && break
        echo "Invalid choice."
    done
else
    third="none"
fi

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
#
# Get total disk size in MiB
total_mib=$(parted -s "$disk" unit MiB print | grep "Disk $disk" | awk '{print $3}' | tr -d 'MiB')
# Convert MiB to GB (1GB ≈ 1024MiB)
total_gb=$(echo "$total_mib / 1024" | bc)

parted -s "$disk" mklabel gpt
parted -s "$disk" mkpart ESP fat32 1MiB 2049MiB
parted -s "$disk" set 1 esp on
if [ "$total_gb" -lt 70 ]; then
    # Root and home 50% each
    parted -s "$disk" mkpart primary ext4 2049MiB 50% # root
    parted -s "$disk" mkpart primary ext4 50% 100%    #home
elif [ "$total_gb" -lt 120 ]; then
    # Root 40GB, home the rest (convert 40GB to MiB)
    root_end=$((2049 + 40 * 1024))
    parted -s "$disk" mkpart primary ext4 2049MiB "${root_end}MiB" # root
    parted -s "$disk" mkpart primary ext4 "${root_end}MiB" 100%    #home
else
    # Root 50GB, home the rest (convert 50GB to MiB)
    root_end=$((2049 + 50 * 1024))
    parted -s "$disk" mkpart primary ext4 2049MiB "${root_end}MiB" # root
    parted -s "$disk" mkpart primary ext4 "${root_end}MiB" 100%    #home
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
sed -i "s|microcode|$microcode_pkg|g" pkgs.txt

# Extracting exact firmware packages
mapfile -t drivers < <(lspci -k 2>/dev/null | grep -A1 "Kernel driver in use:" | awk -F': ' '/Kernel driver in use:/ {print $2}' | awk '{print $1}')
declare -A driver_to_pkg=(
    ["amdgpu"]="linux-firmware-amdgpu"
    ["radeon"]="linux-firmware-radeon"
    ["ath"]="linux-firmware-atheros"
    ["bnx2x"]="linux-firmware-broadcom" # Broadcom NetXtreme II
    ["tg3"]="linux-firmware-broadcom"   # Broadcom Tigon3
    ["i915"]="linux-firmware-intel"     # Intel graphics
    ["iwlwifi"]="linux-firmware-intel"  # Intel WiFi
    ["liquidio"]="linux-firmware-liquidio"
    ["mwl8k"]="linux-firmware-marvell" # Marvell WiFi
    ["mt76"]="linux-firmware-mediatek" # MediaTek WiFi
    ["mlx"]="linux-firmware-mellanox"  # Mellanox ConnectX
    ["nfp"]="linux-firmware-nfp"       # Netronome Flow Processor
    ["nvidia"]="linux-firmware-nvidia"
    ["qcom"]="linux-firmware-qcom"     # Qualcomm Atheros
    ["qede"]="linux-firmware-qlogic"   # QLogic FastLinQ
    ["r8169"]="linux-firmware-realtek" # Realtek Ethernet
    ["rtw"]="linux-firmware-realtek"   # Realtek WiFi
)

# Identify required packages
required_pkgs=()
for driver in "${drivers[@]}"; do
    if [[ -n "${driver_to_pkg[$driver]:-}" ]]; then
        required_pkgs+=("${driver_to_pkg[$driver]}")
    fi
done

# Deduplication
required_pkgs=($(printf "%s\n" "${required_pkgs[@]}" | sort -u))

# Converting in a single string to replace firmware
firmware_string=""
for pkg in "${required_pkgs[@]}"; do
    firmware_string+="$pkg "
done
firmware_string="${firmware_string% }"
if [[ -z "$firmware_string" ]]; then
    firmware_string="linux-firmware"
fi
sed -i "s|linux-firmware|$firmware_string|g" pkgs.txt

# Which type of packages?
# Main package selection
case "$first:$second" in
vm:min)
    sed -n '1p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
vm:max)
    sed -n '1p;3p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
hardware:min)
    sed -n '1,2p' pkgs.txt | head -n 2 | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
hardware:max)
    # For hardware:max, we will add lines 5 and/or 6 later based on $third
    sed -n '1,4p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >pkglist.txt
    ;;
esac

# For hardware:max, add lines 5 and/or 6 based on $third
if [[ "$first" == "hardware" && "$second" == "max" ]]; then
    case "$third" in
    laptop)
        # Add both line 5 and 6
        sed -n '5,6p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
        ;;
    bluetooth)
        # Add only line 5
        sed -n '5p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >>pkglist.txt
        ;;
    none)
        # Do not add line 5 or 6
        ;;
    esac
fi

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
third=$third
microcode_pkg=$microcode_pkg
part2=$part2
EOF

chmod 600 /mnt/root/install.conf

# Run chroot.sh
# hackaround for systemd not working - github.com/systemd/systemd/issues/36174
# bootctl --esp-path=/mnt/boot install
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
