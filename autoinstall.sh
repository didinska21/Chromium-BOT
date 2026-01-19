#!/bin/bash
set -e

# Warna terminal
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
BLUE='\e[34m'
NC='\e[0m' # No Color

info()    { echo -e "${YELLOW}🌀 $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
fail()    { echo -e "${RED}❌ $1${NC}"; exit 1; }
warn()    { echo -e "${BLUE}⚠️  $1${NC}"; }

trap 'fail "Terjadi kesalahan. Proses dihentikan."' ERR

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════╗"
echo "║   CHROMIUM DOCKER INSTALLER                  ║"
echo "║   Remote Browser Access via Docker           ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# Cek apakah dijalankan sebagai root atau dengan sudo
if [ "$EUID" -ne 0 ]; then 
  warn "Script ini memerlukan sudo privileges"
  warn "Menjalankan ulang dengan sudo..."
  exec sudo bash "$0" "$@"
fi

info "[1/7] Update sistem dan hapus Docker lama"
apt update -y && apt upgrade -y
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  apt-get remove -y $pkg 2>/dev/null || true
done
success "Sistem diperbarui dan Docker lama dihapus"

info "[2/7] Instalasi Docker versi terbaru"
apt-get install -y ca-certificates curl gnupg lsb-release

# Deteksi OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  fail "Tidak dapat mendeteksi sistem operasi"
fi

# Setup Docker repository berdasarkan OS
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker service
systemctl enable docker
systemctl start docker

docker --version
success "Docker berhasil diinstal dan berjalan"

info "[3/7] Deteksi timezone server"
TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || echo "Etc/UTC")
echo -e "Timezone saat ini: ${GREEN}$TIMEZONE${NC}"

info "[4/7] Konfigurasi Chromium"
echo ""
read -p "Username Chromium [chromium]: " CUSTOM_USER
CUSTOM_USER=${CUSTOM_USER:-chromium}

read -sp "Password Chromium: " PASSWORD
echo ""
if [ -z "$PASSWORD" ]; then
  fail "Password tidak boleh kosong!"
fi

read -p "Port HTTP [3010]: " PORT1
PORT1=${PORT1:-3010}

read -p "Port HTTPS [3011]: " PORT2
PORT2=${PORT2:-3011}

read -p "Timezone [$TIMEZONE]: " USER_TZ
USER_TZ=${USER_TZ:-$TIMEZONE}

read -p "Start Page [https://www.google.com]: " START_PAGE
START_PAGE=${START_PAGE:-https://www.google.com}

# Validasi port
if ! [[ "$PORT1" =~ ^[0-9]+$ ]] || [ "$PORT1" -lt 1024 ] || [ "$PORT1" -gt 65535 ]; then
  fail "Port HTTP tidak valid (harus 1024-65535)"
fi

if ! [[ "$PORT2" =~ ^[0-9]+$ ]] || [ "$PORT2" -lt 1024 ] || [ "$PORT2" -gt 65535 ]; then
  fail "Port HTTPS tidak valid (harus 1024-65535)"
fi

info "[5/7] Membuat direktori dan file docker-compose.yaml"
INSTALL_DIR="/opt/chromium"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

cat <<EOF > docker-compose.yaml
services:
  chromium:
    image: lscr.io/linuxserver/chromium:latest
    container_name: chromium
    security_opt:
      - seccomp:unconfined
    environment:
      - CUSTOM_USER=$CUSTOM_USER
      - PASSWORD=$PASSWORD
      - PUID=1000
      - PGID=1000
      - TZ=$USER_TZ
      - CHROME_CLI=$START_PAGE
    volumes:
      - $INSTALL_DIR/config:/config
    ports:
      - $PORT1:3000
      - $PORT2:3001
    shm_size: "1gb"
    restart: unless-stopped
    networks:
      - chromium_network

networks:
  chromium_network:
    driver: bridge
EOF

success "File docker-compose.yaml berhasil dibuat di $INSTALL_DIR"

info "[6/7] Download Docker image dan jalankan container"
docker compose pull
docker compose up -d

# Tunggu container siap
echo -n "Menunggu container siap"
for i in {1..10}; do
  echo -n "."
  sleep 1
done
echo ""

# Cek status container
if docker ps | grep -q chromium; then
  success "Container Chromium berhasil berjalan"
else
  fail "Container gagal berjalan. Cek log: docker logs chromium"
fi

info "[7/7] Konfigurasi firewall (opsional)"
if command -v ufw &> /dev/null; then
  read -p "Buka port di firewall? (y/n) [y]: " OPEN_FIREWALL
  OPEN_FIREWALL=${OPEN_FIREWALL:-y}
  
  if [ "$OPEN_FIREWALL" = "y" ]; then
    ufw allow $PORT1/tcp
    ufw allow $PORT2/tcp
    success "Port $PORT1 dan $PORT2 dibuka di firewall"
  fi
fi

# Deteksi IP server
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
  SERVER_IP=$(curl -s ifconfig.me)
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          INSTALASI BERHASIL! 🎉              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📦 Lokasi instalasi:${NC} $INSTALL_DIR"
echo -e "${BLUE}🐳 Container name:${NC} chromium"
echo ""
echo -e "${GREEN}🔗 Akses Chromium di browser:${NC}"
echo -e "   ➡ HTTP  : ${GREEN}http://$SERVER_IP:$PORT1/${NC}"
echo -e "   ➡ HTTPS : ${GREEN}https://$SERVER_IP:$PORT2/${NC}"
echo ""
echo -e "${BLUE}👤 Login credentials:${NC}"
echo -e "   Username: ${GREEN}$CUSTOM_USER${NC}"
echo -e "   Password: ${GREEN}[yang kamu set tadi]${NC}"
echo ""
echo -e "${YELLOW}📝 Perintah berguna:${NC}"
echo -e "   Start   : ${GREEN}cd $INSTALL_DIR && docker compose start${NC}"
echo -e "   Stop    : ${GREEN}cd $INSTALL_DIR && docker compose stop${NC}"
echo -e "   Restart : ${GREEN}cd $INSTALL_DIR && docker compose restart${NC}"
echo -e "   Logs    : ${GREEN}docker logs chromium${NC}"
echo -e "   Remove  : ${GREEN}cd $INSTALL_DIR && docker compose down${NC}"
echo ""
success "Selesai! Browser Chromium siap digunakan 🚀"
