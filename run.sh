#!/usr/bin/env bash
set -e

SRC_DIR="$HOME/Documents/default/GruvboxGtk"
DEST_DIR="$HOME/.local/share/themes"
THEME_NAME="Gruvbox-Dark"
THEME_DIR="${DEST_DIR}/${THEME_NAME}"
rm -rf "${THEME_DIR}"
mkdir -p "${THEME_DIR}"
# --- GTK2 ---
mkdir -p "${THEME_DIR}/gtk-2.0"
cp -r "${SRC_DIR}/main/gtk-2.0/common/"*'.rc' "${THEME_DIR}/gtk-2.0" 2>/dev/null || true
cp -r "${SRC_DIR}/assets/gtk-2.0/assets-common-Dark" "${THEME_DIR}/gtk-2.0/assets" 2>/dev/null || true
cp -r "${SRC_DIR}/assets/gtk-2.0/assets-Dark/"*.png "${THEME_DIR}/gtk-2.0/assets" 2>/dev/null || true
# --- GTK3 ---
mkdir -p "${THEME_DIR}/gtk-3.0"
cp -r "${SRC_DIR}/assets/gtk/scalable" "${THEME_DIR}/gtk-3.0/assets" 2>/dev/null || true
if [ -f "${SRC_DIR}/main/gtk-3.0/gtk-Dark.scss" ]; then
    sassc -M -t expanded "${SRC_DIR}/main/gtk-3.0/gtk-Dark.scss" "${THEME_DIR}/gtk-3.0/gtk.css"
    cp "${THEME_DIR}/gtk-3.0/gtk.css" "${THEME_DIR}/gtk-3.0/gtk-dark.css"
fi
# --- GTK4 ---
mkdir -p "${THEME_DIR}/gtk-4.0"
cp -r "${SRC_DIR}/assets/gtk/scalable" "${THEME_DIR}/gtk-4.0/assets" 2>/dev/null || true
if [ -f "${SRC_DIR}/main/gtk-4.0/gtk-Dark.scss" ]; then
    sassc -M -t expanded "${SRC_DIR}/main/gtk-4.0/gtk-Dark.scss" "${THEME_DIR}/gtk-4.0/gtk.css"
    cp "${THEME_DIR}/gtk-4.0/gtk.css" "${THEME_DIR}/gtk-4.0/gtk-dark.css"
fi
# --- index.theme ---
cat >"${THEME_DIR}/index.theme" <<EOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=${THEME_NAME}
Comment=Gruvbox Dark GTK Theme
EOF

gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Dark'
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.virt-manager.virt-manager.new-vm firmware 'uefi'
gsettings set org.virt-manager.virt-manager.new-vm.cpu-default 'host-passthrough'
gsettings set org.virt-manager.virt-manager.new-vm.graphics-type 'spice'

# Firefox user.js linking
echo "/home/$USER/Documents/default/dotfiles/ublock.txt" | wl-copy
gh auth login
for dir in ~/.mozilla/firefox/*.default-release/; do
    [ -d "$dir" ] || continue
    ln -sf ~/Documents/default/dotfiles/user.js "$dir/user.js"
    break
done

# UFW setup
# sudo ufw limit 22/tcp              # ssh
sudo ufw allow 80/tcp              # http
sudo ufw allow 443/tcp             # https
sudo ufw allow from 192.168.0.0/24 #lan
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
sudo virsh net-autostart default
sudo virsh net-start default

# Configure static IP, gateway, and custom DNS
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null <<EOF
[main]
dns=none
systemd-resolved=false
EOF
sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
sudo systemctl restart NetworkManager

# A cron job
(
    crontab -l
    echo "*/5 * * * * battery-alert.sh"
    echo "@daily $(which trash-empty) 30"
) | crontab -

# Nvim tools install
foot -e nvim +MasonToolsInstall &

# Running aur.sh
bash ~/Documents/default/archsetup/aur.sh
