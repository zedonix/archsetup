#!/usr/bin/env bash
set -e

gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Material-Dark'
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
declare -A gsettings_keys=(
  ["org.virt-manager.virt-manager.new-vm firmware"]="uefi"
  ["org.virt-manager.virt-manager.new-vm cpu-default"]="host-passthrough"
  ["org.virt-manager.virt-manager.new-vm graphics-type"]="spice"
)

for key in "${!gsettings_keys[@]}"; do
  schema="${key% *}"
  subkey="${key#* }"
  value="${gsettings_keys[$key]}"

  if gsettings describe "$schema" "$subkey" &>/dev/null; then
    gsettings set "$schema" "$subkey" "$value"
  fi
done

# Firefox user.js linking
echo "/home/$USER/Documents/projects/default/dotfiles/ublock.txt" | wl-copy
gh auth login
dir=$(echo ~/.mozilla/firefox/*.default-release)
ln -sf ~/Documents/projects/default/dotfiles/user.js "$dir/user.js"
cp -f ~/Documents/projects/default/dotfiles/book* "$dir/bookmarkbackups/"

# UFW setup
# sudo ufw limit 22/tcp              # ssh
sudo ufw allow 80/tcp              # http
sudo ufw allow 443/tcp             # https
sudo ufw allow from 192.168.0.0/24 #lan
sudo ufw deny 631/tcp              # cups stuff
sudo ufw allow in on virbr0 to any port 67 proto udp
sudo ufw allow out on virbr0 to any port 68 proto udp
sudo ufw allow in on virbr0 to any port 53
sudo ufw allow out on virbr0 to any port 53
sudo ufw default allow routed
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
sudo ufw logging on
sudo systemctl enable ufw

# Flatpak setup
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Libvirt setup
if pacman -Qq libvirt &>/dev/null; then
  sudo virsh net-autostart default
  sudo virsh net-start default
fi

# Configure static IP, gateway, and custom DNS
# sudo tee /etc/systemd/resolved.conf >/dev/null <<EOF
# [Resolve]
# DNS=8.8.8.8 8.8.4.4
# EOF
# sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null <<EOF
# [main]
# dns=none
# systemd-resolved=false
# EOF
# sudo tee /etc/resolv.conf >/dev/null <<EOF
# nameserver 1.1.1.1
# nameserver 1.0.0.1
# EOF
# sudo systemctl restart NetworkManager

# A cron job
(
  crontab -l 2>/dev/null
  echo "@daily $(which trash-empty) 30"
) | crontab -

# Nvim tools install
foot -e nvim +MasonToolsInstall &
foot -e sudo nvim +MasonToolsInstall &

# Running aur.sh
bash ~/Documents/projects/default/archsetup/aur.sh
