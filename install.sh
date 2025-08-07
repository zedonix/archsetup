#!/usr/bin/env bash
set -euo pipefail

# Redirect all output (stdout & stderr) into the user’s home directory log
LOGFILE="${HOME}/log"
# ensure log exists and is owned by the user
: >"${LOGFILE}"
exec > >(tee -a "$LOGFILE") 2>&1

trap 'echo "Aborted. Cleaning up..."; umount -R /mnt >/dev/null 2>&1 || true' EXIT
SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR"

# --- Prompt Section (collect all user input here) ---
# Prompt for home recovery Installation
while true; do
  read -p "Recovery Install (yes/no)? " recon
  case "$recon" in
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
if [[ "$disk" == *nvme* ]]; then
  part_prefix="${disk}p"
else
  part_prefix="${disk}"
fi

part1="${part_prefix}1"
part2="${part_prefix}2"

if [[ "$recon" == "yes" ]]; then
  for p in "$part1" "$part2"; do
    [[ ! -b "$p" ]] && echo "Missing partition $p. Recovery mode expects disk to be pre-partitioned." && exit 1
  done
  vgscan           # detect any VG on $part2
  vgchange -ay vg0 # activate vg0 so /dev/vg0/{root,home} appear
  # verify expected LVs
  for lv in root home; do
    if [[ ! -e /dev/vg0/$lv ]]; then
      echo "ERROR: /dev/vg0/$lv not found. Cannot continue recovery." >&2
      exit 1
    fi
  done
  echo "LVM recovery: vg0 and its LVs are active."
else
  # --- Disk Size Calculation ---
  total_mib=$(($(blockdev --getsize64 "$disk") / 1024 / 1024))
  total_gb=$(echo "$total_mib / 1024" | bc)
  half_gb=$(echo "$total_gb / 2" | bc)

  # --- Root Partition Size Selection ---
  while true; do
    echo "Choose root partition size (total gb: $total_gb):"
    echo "1) 40GB"
    echo "2) 50GB"
    echo "3) 50% of disk ($half_gb GB)"
    echo "4) Custom"

    read -p "Enter choice [1-4]: " choice
    case "$choice" in
    1) rootSize=40 ;;
    2) rootSize=50 ;;
    3) rootSize=$half_gb ;;
    4)
      read -p "Enter custom size in GB (max: $half_gb GB): " rootSize
      if ! [[ "$rootSize" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "Invalid number. Enter a positive number (e.g., 45 or 45.5)."
        continue
      fi
      if (($(echo "$rootSize > $half_gb" | bc -l))); then
        echo "Root size exceeds 50% of total disk size ($half_gb GB). Try again."
        continue
      fi
      ;;
    *)
      echo "Invalid option. Try again."
      continue
      ;;
    esac

    if ((rootSize > half_gb)); then
      echo "Root size exceeds 50% of total disk size ($total_gb GB). Try again."
    else
      break
    fi
  done
fi

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

if [[ "$recon" == "no" ]]; then
  # Partitioning
  parted -s "$disk" mklabel gpt
  parted -s "$disk" mkpart ESP fat32 1MiB 2049MiB
  parted -s "$disk" set 1 esp on
  parted -s "$disk" mkpart primary ext4 2049MiB 100%
  # pv, vg
  pvcreate "${disk}2"
  vgcreate vg0 "${disk}2"
  # Activate the VG
  vgchange -ay vg0
  # Creating the Thin-Pool
  # Get total free extents from vg
  free_extents=$(vgdisplay vg0 | awk '/Free  PE/ {print $5}')
  # Reserve 512 extents for safety (~2 GiB)
  pool_extents=$((free_extents - 512))
  if ((pool_extents <= 0)); then
    echo "ERROR: Not enough space for thin pool after reserving metadata."
    exit 1
  fi
  # Create thin pool with extents instead of GB
  lvcreate --type thin-pool -l "$pool_extents" --poolmetadatasize 2G -n thinpool vg0
  # Make thin volumes
  lvcreate --thin -V "${rootSize}G" -n root vg0/thinpool
  # Compute how big 'home' can be:
  # Calculate free extents in pool
  extent_size=$(vgdisplay vg0 | awk '/PE Size/ {print int($3)}') # in MiB
  meta_extents=$((2048 / extent_size))                           # 2048 MiB = 2 GiB
  free_extents=$(vgdisplay vg0 | awk '/Free  PE/ {print $5}')
  pool_extents=$((free_extents - meta_extents))
  # Ensure it's enough
  if ((free_extents > 0)); then
    home_gib=$(echo "$free_extents * 4 / 1024" | bc)
    lvcreate --thin -V "${home_gib}G" -n home vg0/thinpool
  else
    echo "WARNING: Not enough space to create home LV. You can manually create it later."
  fi
fi

# Formatting
mkfs.fat -F 32 -n EFI "$part1"
mkfs.ext4 /dev/vg0/root
if [[ "$recon" == "no" ]]; then
  mkfs.ext4 /dev/vg0/home
fi

# Mounting
udevadm settle
mkdir -p /mnt/boot /mnt/home
mount /dev/vg0/root /mnt
mount /dev/vg0/home /mnt/home
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
case "$hardware:$howMuch" in
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
  # For hardware:max, we will add lines 5 and/or 6 later based on $extra
  sed -n '1,4p' pkgs.txt | tr ' ' '\n' | grep -v '^$' >pkglist.txt
  ;;
esac

# For hardware:max, add lines 5 and/or 6 based on $extra
if [[ "$hardware" == "hardware" && "$howMuch" == "max" ]]; then
  case "$extra" in
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
hardware=$hardware
howMuch=$howMuch
extra=$extra
microcode_pkg=$microcode_pkg
part2=$part2
recon=$recon
EOF

chmod 600 /mnt/root/install.conf

# Run chroot.sh
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
