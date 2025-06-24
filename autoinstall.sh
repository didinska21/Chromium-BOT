#!/bin/bash

# Berhenti jika ada error
set -e

echo "=== [1/6] Update sistem dan hapus Docker versi lama ==="
sudo apt update -y && sudo apt upgrade -y

# Hapus paket docker lama jika ada
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  sudo apt-get remove -y $pkg || true
done

echo "=== [2/6] Instalasi Docker versi terbaru ==="
# Install dependensi untuk Docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Tambahkan GPG key resmi Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Tambahkan repository Docker ke sistem
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update ulang setelah tambahkan repo Docker
sudo apt update -y && sudo apt upgrade -y

# Install Docker dan komponennya
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Cek versi Docker untuk memastikan sudah terpasang
docker --version

echo "=== [3/6] Cek timezone server ==="
TIMEZONE=$(realpath --relative-to /usr/share/zoneinfo /etc/localtime)
echo "Timezone saat ini: $TIMEZONE"

echo "=== [4/6] Masukkan konfigurasi container Chromium ==="
# Interaktif: minta input dari pengguna
read -p "Masukkan username untuk login Chromium: " CUSTOM_USER
read -p "Masukkan password untuk login Chromium: " PASSWORD
read -p "Port untuk HTTP (default 3010): " PORT1
read -p "Port untuk HTTPS (default 3011): " PORT2
read -p "Timezone [$TIMEZONE]: " USER_TZ
read -p "Halaman awal saat membuka Chromium [default: https://github.com/didinska21]: " START_PAGE

# Gunakan nilai default jika kosong
PORT1=${PORT1:-3010}
PORT2=${PORT2:-3011}
USER_TZ=${USER_TZ:-$TIMEZONE}
START_PAGE=${START_PAGE:-https://github.com/didinska21}

echo "=== [5/6] Setup dan buat file docker-compose.yaml ==="
mkdir -p ~/chromium
cd ~/chromium

# Tulis file docker-compose.yaml berdasarkan input user
cat <<EOF > docker-compose.yaml
services:
  chromium:
    image: lscr.io/linuxserver/chromium:latest
    container_name: chromium
    security_opt:
      - seccomp:unconfined # opsional, untuk akses penuh
    environment:
      - CUSTOM_USER=$CUSTOM_USER
      - PASSWORD=$PASSWORD
      - PUID=1000
      - PGID=1000
      - TZ=$USER_TZ
      - CHROME_CLI=$START_PAGE
    volumes:
      - /root/chromium/config:/config
    ports:
      - ${PORT1}:3000
      - ${PORT2}:3001
    shm_size: "1gb"
    restart: unless-stopped
EOF

echo "=== [6/6] Menjalankan container Chromium ==="
docker compose up -d

# Ambil IP lokal dari server
SERVER_IP=$(hostname -I | awk '{print $1}')

# Tampilkan URL akses di akhir
echo -e "\n✅ Chromium berhasil dijalankan!"
echo "➡ Buka browser kamu dan akses:"
echo "   🔹 http://$SERVER_IP:$PORT1/"
echo "   🔹 https://$SERVER_IP:$PORT2/"
