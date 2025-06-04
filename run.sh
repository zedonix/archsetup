#!/usr/bin/env bash
set -e

gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Dark'
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Firefox user.js linking
echo 'https://nsfw.oisd.nl/
https://raw.githubusercontent.com/iam-py-test/uBlock-combo/main/list.txt
https://raw.githubusercontent.com/yokoffing/filterlists/main/click2load.txt' | wl-copy
gh auth login
if [ -d ~/.mozilla/firefox ]; then
    dir=$(ls ~/.mozilla/firefox/ | grep ".default-release" | head -n1)
    if [ -n "$dir" ]; then
        ln -sf /home/$USER/.dotfiles/user.js /home/$USER/.mozilla/firefox/$dir/user.js
    fi
fi

# UFW setup
sudo ufw allow 20/tcp # ftp
sudo ufw allow 21/tcp # ftp (I am server)
# sudo ufw limit 22/tcp # ssh
sudo ufw allow 80/tcp # https (I am server)
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
sudo systemctl enable ufw

# Libvirt setup
# sudo virsh net-autostart default

# Flatpak setup
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Configure static IP, gateway, and custom DNS
nmcli con mod "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "1.1.1.1,1.0.0.1"
nmcli con mod "Wired connection 1" ipv4.ignore-auto-dns yes

# Apply changes
nmcli con down "Wired connection 1"
nmcli con up "Wired connection 1"

# Snapper setup
if mountpoint -q /.snapshots; then
    sudo umount /.snapshots/
fi
[[ -d /.snapshots ]] && sudo rm -rf /.snapshots/
sudo snapper -c root create-config /
sudo snapper -c home create-config /home
sudo mount -a

sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
sudo systemctl enable --now grub-btrfsd

sudo sed -i \
    -e 's/^TIMELINE_MIN_AGE="3600"/TIMELINE_MIN_AGE="1800"/' \
    -e 's/^TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"/' \
    -e 's/^TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"/' \
    -e 's/^TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="0"/' \
    -e 's/^TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"/' \
    "/etc/snapper/configs/root"

sudo sed -i \
    -e 's/^TIMELINE_MIN_AGE="3600"/TIMELINE_MIN_AGE="1800"/' \
    -e 's/^TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"/' \
    -e 's/^TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="0"/' \
    -e 's/^TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="0"/' \
    -e 's/^TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"/' \
    "/etc/snapper/configs/home"

# A cron job
(
    crontab -l
    echo "@daily $(which trash-empty) 30"
) | crontab -

# Running aur.sh
bash ~/.archsetup/aur.sh
