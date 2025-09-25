#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  rc=$?
  # try to unmount /mnt if mounted
  if mountpoint -q /mnt; then
    umount -R /mnt >/dev/null 2>&1 || true
  fi
  if ((rc != 0)); then
    echo "Aborted. Cleaning up..."
  fi
  return $rc
}
trap cleanup EXIT

SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR"

# Variable set
timezone="Asia/Kolkata"
username="piyush"

# --- Prompt Section (collect all user input here) ---
# Ecryption
while true; do
  read -p "Encryption (yes/no)? " encryption
  case "$encryption" in
  yes | no) break ;;
  *) echo "Invalid input. Please enter 'yes' or 'no'." ;;
  esac
done

# Prompt for if ddos on arch
while true; do
  read -p "ddos attack ongoing (yes/no)? " ddos
  case "$ddos" in
  yes | no) break ;;
  *) echo "Invalid input. Please enter 'yes' or 'no'." ;;
  esac
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
mount | grep -q "$disk" && echo "Disk appears to be in use!" && exit 1

# Partition Naming
if [[ "$disk" == *nvme* ]] || [[ "$disk" == *mmcblk* ]]; then
  part_prefix="${disk}p"
else
  part_prefix="${disk}"
fi

part1="${part_prefix}1"
part2="${part_prefix}2"

# Which type of install?
#
# First choice: vm or hardware
echo "Choose one:"
select hardware in "vm" "hardware"; do
  [[ -n $hardware ]] && break
  echo "Invalid choice. Please select 1 for vm or 2 for hardware."
done

# Second choice: min or max
echo "Choose one:"
select howMuch in "min" "max"; do
  [[ -n $howMuch ]] && break
  echo "Invalid choice. Please select 1 for min or 2 for max."
done

# extra choice: laptop or bluetooth or none
if [[ "$howMuch" == "max" && "$hardware" == "hardware" ]]; then
  echo "Choose one:"
  select extra in "laptop" "bluetooth" "none"; do
    [[ -n $extra ]] && break
    echo "Invalid choice."
  done
else
  extra="none"
fi

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

# Partitioning
parted -s "$disk" mklabel gpt
parted -s "$disk" mkpart ESP fat32 1MiB 2049MiB
parted -s "$disk" set 1 esp on
parted -s "$disk" mkpart primary btrfs 2049MiB 100%

if [[ "$encryption" == "yes" ]]; then
  cryptsetup luksFormat "$part2"
  cryptsetup open "$part2" cryptroot
  rootdev="/dev/mapper/cryptroot"
else
  rootdev="$part2"
fi

# Format
mkfs.fat -F32 -n BOOT "$part1"
mkfs.btrfs -L ROOT "$rootdev"

# Mount to create subvolumes
mount "$rootdev" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Mount subvolumes
mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@ "$rootdev" /mnt
mkdir -p /mnt/{home,var,.snapshots}
mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@home "$rootdev" /mnt/home
mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@var "$rootdev" /mnt/var
mount -o noatime,compress=zstd,ssd,space_cache=v2,discard=async,subvol=@snapshots "$rootdev" /mnt/.snapshots

# Mount ESP
mkdir -p /mnt/boot
mount "$part1" /mnt/boot

# Detect CPU vendor and set microcode package
cpu_vendor=$(lscpu | awk -F: '/Vendor ID:/ {print $2}' | xargs)
if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
  microcode_pkg="intel-ucode"
elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
  microcode_pkg="amd-ucode"
fi

# Pacstrap stuff
#
cp pkgs.txt pkgss.txt
sed -i "s|microcode|$microcode_pkg|g" pkgss.txt

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
sed -i "s|linux-firmware|$firmware_string|g" pkgss.txt

# Which type of packages?
# Main package selection
case "$hardware:$howMuch" in
vm:min)
  sed -n '1p' pkgss.txt | tr ' ' '\n' | grep -v '^$' >pkglists.txt
  ;;
vm:max)
  sed -n '1p;3p' pkgss.txt | tr ' ' '\n' | grep -v '^$' >pkglists.txt
  ;;
hardware:min)
  sed -n '1,2p' pkgss.txt | head -n 2 | tr ' ' '\n' | grep -v '^$' >pkglists.txt
  ;;
hardware:max)
  # For hardware:max, we will add lines 5 and/or 6 later based on $extra
  sed -n '1,4p' pkgss.txt | tr ' ' '\n' | grep -v '^$' >pkglists.txt
  ;;
esac

# For hardware:max, add lines 5 and/or 6 based on $extra
if [[ "$hardware" == "hardware" && "$howMuch" == "max" ]]; then
  case "$extra" in
  laptop)
    # Add both line 5 and 6
    sed -n '5,6p' pkgss.txt | tr ' ' '\n' | grep -v '^$' >>pkglists.txt
    ;;
  bluetooth)
    # Add only line 5
    sed -n '5p' pkgss.txt | tr ' ' '\n' | grep -v '^$' >>pkglists.txt
    ;;
  none)
    # Do not add line 5 or 6
    ;;
  esac
fi

# Pacstrap with error handling
pacman-key --init
pacman-key --populate archlinux
pacman-key --refresh-keys
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
pacstrap /mnt - <pkglists.txt || {
  echo "pacstrap failed"
  exit 1
}

# System Configuration
genfstab -U /mnt >/mnt/etc/fstab

# Exporting variables for chroot
cat >/mnt/root/install.conf <<EOF
hostname=$hostname
hardware=$hardware
howMuch=$howMuch
extra=$extra
microcode_pkg=$microcode_pkg
ddos=$ddos
timezone=$timezone
username=$username
part2=$part2
encryption=$encryption
EOF
chmod 700 /mnt/root/install.conf

# Run chroot.sh
cp chroot.sh /mnt/root/chroot.sh
chmod 700 /mnt/root/chroot.sh
arch-chroot /mnt /bin/bash -s <<EOF
echo "root:$root_password" | chpasswd
if [[ "$howMuch" == "max" && "$hardware" == "hardware" ]]; then
  useradd -m -G wheel,storage,video,audio,lp,scanner,sys,kvm,libvirt,docker -s /bin/bash "$username"
else
  useradd -m -G wheel,storage,video,audio,lp,sys -s /bin/bash "$username"
fi
echo "$username:$user_password" | chpasswd
bash /root/chroot.sh
EOF

# Unmount and finalize
fuser -k /mnt || true
if mountpoint -q /mnt; then
  umount -R /mnt || {
    echo "Failed to unmount /mnt. Please check."
    exit 1
  }
fi
