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
NEW="$HOME/Documents/libvirt"
TMP="/tmp/default-pool.xml"
VIRSH="virsh --connect qemu:///system"

if pacman -Q libvirt >/dev/null 2>&1; then
  sudo systemctl start libvirtd.service || true
  sudo virsh net-autostart default >/dev/null 2>&1 || true
  sudo virsh net-start default >/dev/null 2>&1 || true

  mkdir -p "$NEW"
  sudo chown -R root:libvirt "$NEW"
  sudo chmod -R 2775 "$NEW"

  for p in $($VIRSH pool-list --all --name); do
    [ -z "$p" ] && continue
    if $VIRSH pool-dumpxml "$p" 2>/dev/null | grep -q "<path>${NEW}</path>"; then
      [ "$p" != "default" ] && sudo $VIRSH pool-destroy "$p" >/dev/null 2>&1 || true
      [ "$p" != "default" ] && sudo $VIRSH pool-undefine "$p" >/dev/null 2>&1 || true
    fi
  done

  if $VIRSH pool-list --all | awk 'NR>2{print $1}' | grep -qx default; then
    sudo $VIRSH pool-destroy default >/dev/null 2>&1 || true
    sudo $VIRSH pool-undefine default >/dev/null 2>&1 || true
  fi

  cat >"$TMP" <<EOF
<pool type='dir'>
  <name>default</name>
  <target><path>${NEW}</path></target>
</pool>
EOF

  sudo $VIRSH pool-define "$TMP"
  sudo $VIRSH pool-start default
  sudo $VIRSH pool-autostart default

  if [ -d /var/lib/libvirt/images ] && [ "$(ls -A /var/lib/libvirt/images 2>/dev/null || true)" != "" ]; then
    sudo rsync -aHAX --progress /var/lib/libvirt/images/ "$NEW/"
    sudo chown -R root:libvirt "$NEW"
    sudo find "$NEW" -type d -exec chmod 2775 {} +
    sudo find "$NEW" -type f -exec chmod 0644 {} +
  fi

  sudo $VIRSH pool-refresh default
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
echo "@daily $(which trash-empty) 30" | crontab -

# Nvim tools install
foot -e nvim +MasonToolsInstall &
foot -e sudo nvim +MasonToolsInstall &

# Running aur.sh
bash ~/Documents/projects/default/archsetup/aur.sh
