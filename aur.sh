#!/bin/bash

aur_pkgs=(
    sway-audio-idle-inhibit-git
    sdl-ball
    tlpui
    cachyos-ananicy-rules
    logseq-desktop
)

aur_dir="$HOME/.aur"
mkdir -p "$aur_dir"
cd "$aur_dir"

for pkg in "${aur_pkgs[@]}"; do
    read -p "Install $pkg? [Y/n] " -r
    if [[ $REPLY =~ ^[Yy]?$ ]]; then
        git clone "https://aur.archlinux.org/$pkg.git"
        cd "$pkg"
        less PKGBUILD
        read -p "Build $pkg? [Y/n] " -r
        if [[ $REPLY =~ ^[Yy]?$ ]]; then
            makepkg -si --noconfirm --needed
        fi
        cd ..
    fi
done

sudo systectl enable --now ananicy-cpp

#ollama pull gemma3:1b
