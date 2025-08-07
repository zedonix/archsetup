#!/usr/bin/env bash

aur_pkgs=(
  cachyos-ananicy-rules
  systemd-boot-pacman-hook
  sway-audio-idle-inhibit-git
  bashmount
  ventoy-bin
  bemoji
  newsraft
  networkmanager-dmenu-git
  cnijfilter2
)

aur_dir="$HOME/Templates/aur"
mkdir -p "$aur_dir"
cd "$aur_dir" || exit 1

for pkg in "${aur_pkgs[@]}"; do
  if [[ ! -d $pkg ]]; then
    git clone "https://aur.archlinux.org/$pkg.git"
  fi
done

for pkg in "${aur_pkgs[@]}"; do
  cd "$aur_dir/$pkg" || continue
  less PKGBUILD
  read -rp "Build and install '$pkg'? (y/n): " reply
  if [[ -z $reply || $reply =~ ^[Yy]$ ]]; then
    makepkg -si --noconfirm --needed
  else
    echo "Skipped $pkg"
  fi
done

kvantummanager

sudo systemctl enable ananicy-cpp

flatpak install -y --user org.gtk.Gtk3theme.Adwaita-dark
flatpak override --user --env=GTK_THEME=Adwaita-dark --env=QT_STYLE_OVERRIDE=Adwaita-Dark
flatpak install -y --user flathub org.gimp.GIMP
flatpak install -y --user flathub com.github.wwmm.easyeffects
flatpak install -y --user flathub com.github.d4nj1.tlpui

#ollama pull gemma3:1b
#ollama pull codellama:7b-instruct
