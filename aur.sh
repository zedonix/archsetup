#!/usr/bin/env bash

aur_pkgs=(
  systemd-boot-pacman-hook
  nohang
  wayland-pipewire-idle-inhibit
  newsraft
  bemoji
  ventoy-bin
  networkmanager-dmenu-git
  cnijfilter2
  onlyoffice-bin
  # poweralertd
  archiso-systemd-boot
)

aur_dir="$HOME/Documents/aur"
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

systemctl --user enable wayland-pipewire-idle-inhibit.service --now
go install github.com/savedra1/clipse@v1.1.0
bemoji --download all

flatpak install -y org.gtk.Gtk3theme.Adwaita-dark
flatpak override --user --env=GTK_THEME=Adwaita-dark --env=QT_STYLE_OVERRIDE=Adwaita-Dark
# flatpak install -y flathub org.gimp.GIMP
# flatpak install -y flathub io.gitlab.theevilskeleton.Upscaler
# flatpak install -y flathub com.github.wwmm.easyeffects
# flatpak install -y flathub com.github.d4nj1.tlpui

#ollama pull gemma3:1b
#ollama pull codellama:7b-instruct
