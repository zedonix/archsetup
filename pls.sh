#!/bin/bash

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
    pkg="${driver_to_pkg[$driver]}"
    [[ -n "$pkg" ]] && required_pkgs+=("$pkg")
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
