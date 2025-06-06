#!/bin/bash

aur_pkgs=(
    sway-audio-idle-inhibit-git
    tlpui
    texpresso-git
)

aur_dir="$HOME/.aur"
mkdir -p "$aur_dir"
cd "$aur_dir"

for pkg in "${aur_pkgs[@]}"; do
    git clone "https://aur.archlinux.org/$pkg.git"
    cd "$pkg"
    makepkg -si --noconfirm --needed
    cd ..
done

kvantummanager

#ollama pull gemma3:1b
