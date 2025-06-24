#!/bin/bash
set -e

# Warna terminal
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
NC='\e[0m' # No Color

info()    { echo -e "${YELLOW}🌀 $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
fail()    { echo -e "${RED}❌ $1${NC}"; }

trap 'fail "Terjadi kesalahan. Proses dihentikan."' ERR

info "[1/6] Update sistem dan hapus Docker lama"
sudo apt update -y && sudo apt upgrade -y
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y $pkg || true
done
success "Sistem diperbarui dan Docker lama dihapus"

info "[2/6] Instalasi Docker versi terbaru"
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker --version
success "Docker berhasil diinstal"

info "[3/6] Deteksi timezone server"
TIMEZONE=$(realpath --relative-to /usr/share/zoneinfo /etc/localtime || echo "Etc/UTC")
echo -e "Timezone saat ini: ${GREEN}$TIMEZONE${NC}"

info "[4/6] Masukkan konfigurasi Chromium"
read -p "Username Chromium: " CUSTOM_USER
read -p "Password Chromium: " PASSWORD
read -p "Port HTTP [3010]: " PORT1
read -p "Port HTTPS [3011]: " PORT2
read -p "Timezone [$TIMEZONE]: " USER_TZ
read -p "Start Page [https://github.com/didinska21]: " START_PAGE

PORT1=${PORT1:-3010}
PORT2=${PORT2:-3011}
USER_TZ=${USER_TZ:-$TIMEZONE}
START_PAGE=${START_PAGE:-https://github.com/didinska21}

info "[5/6] Membuat file docker-compose.yaml"
mkdir -p ~/chromium && cd ~/chromium

cat <<EOF > docker-compose.yaml
services:
  chromium:
    image: lscr.io/linuxserver/chromium:latest
    container_name: chromium
    security_opt:
      - seccomp:unconfined
    environment:
      CUSTOM_USER: $CUSTOM_USER
      PASSWORD: $PASSWORD
      PUID: 1000
      PGID: 1000
      TZ: $USER_TZ
      CHROME_CLI: $START_PAGE
    volumes:
      - /root/chromium/config:/config
    ports:
      - ${PORT1}:3000
      - ${PORT2}:3001
    shm_size: "1gb"
    restart: unless-stopped
EOF

success "File docker-compose.yaml dibuat"

info "[6/6] Menjalankan container Chromium"
docker compose up -d

SERVER_IP=$(hostname -I | awk '{print $1}')
success "Chromium berhasil dijalankan"

echo -e "\n${GREEN}🔗 Akses Chromium di browser:${NC}"
echo -e "➡ ${GREEN}http://$SERVER_IP:$PORT1/${NC}"
echo -e "➡ ${GREEN}https://$SERVER_IP:$PORT2/${NC}"
