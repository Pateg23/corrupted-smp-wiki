#!/bin/bash
set -e

# === Corrupted SMP Wiki + CMS — One-Command Deploy ===
# Usage (with credentials):
#   CMS_PASSWORD=Acegotaura CLOUDFLARE_API_TOKEN=cfat_xxx CLOUDFLARE_ACCOUNT_ID=67c74... \
#     curl -sL https://raw.githubusercontent.com/Pateg23/corrupted-smp-wiki/main/deploy.sh | bash
#
# Usage (prompts for credentials):
#   curl -sL https://raw.githubusercontent.com/Pateg23/corrupted-smp-wiki/main/deploy.sh | bash

REPO_URL="https://github.com/Pateg23/corrupted-smp-wiki.git"
INSTALL_DIR="/root/wiki-server"
SERVER_SERVICE="wiki-server"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Corrupted SMP Wiki + CMS Installer     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Must run as root. Use: sudo bash deploy.sh${NC}"
  exit 1
fi

# --- Install dependencies ---
if ! command -v node &>/dev/null; then
  echo ">> Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
if ! command -v python3 &>/dev/null; then
  echo ">> Installing Python3..."
  apt-get update -qq && apt-get install -y python3
fi
if ! command -v wrangler &>/dev/null; then
  echo ">> Installing wrangler..."
  npm install -g wrangler
fi

# --- Clone repo ---
if [ -d "$INSTALL_DIR" ]; then
  echo ">> Updating existing installation..."
  cd "$INSTALL_DIR" && git pull
else
  echo ">> Cloning repo..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

mkdir -p public/images backups
npm install --production

# --- Create .env from env vars or prompt ---
CMS_PASSWORD="${CMS_PASSWORD:-}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"

if [ -z "$CMS_PASSWORD" ] && [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  # If .env already exists from a previous install, keep it
  if [ -f .env ]; then
    echo ">> Using existing .env"
  else
    echo ""
    echo -e "${CYAN}Enter your credentials (press Enter to skip Cloudflare):${NC}"
    read -r -s -p "  CMS Password: " CMS_PASSWORD
    echo
    read -r -p "  Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    read -r -p "  Cloudflare Account ID: " CLOUDFLARE_ACCOUNT_ID
  fi
fi

if [ -n "$CMS_PASSWORD" ] || [ -n "$CLOUDFLARE_API_TOKEN" ]; then
  cat > .env << ENVEOF
CMS_PASSWORD=${CMS_PASSWORD}
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}
CLOUDFLARE_PROJECT_NAME=corrupted-smp
PORT=8420
ENVEOF
  echo ">> .env created"
fi

# --- Setup systemd service ---
echo ">> Setting up systemd service..."
cat > /etc/systemd/system/$SERVER_SERVICE.service << SERVICEEOF
[Unit]
Description=Corrupted SMP Wiki Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node $INSTALL_DIR/server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable $SERVER_SERVICE
systemctl restart $SERVER_SERVICE

# --- Show info ---
SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
PORT=$(grep -oP '^PORT=\K.*' .env 2>/dev/null || echo "8420")
CF_PROJECT=$(grep -oP '^CLOUDFLARE_PROJECT_NAME=\K.*' .env 2>/dev/null || echo "corrupted-smp")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ INSTALLATION COMPLETE!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}CMS Editor:${NC}    http://$SERVER_IP:$PORT/admin/"
echo -e "  ${CYAN}Wiki Page:${NC}     http://$SERVER_IP:$PORT/"
echo -e "  ${CYAN}API Content:${NC}  http://$SERVER_IP:$PORT/api/content"
echo ""
echo -e "  ${CYAN}Cloudflare:${NC}    https://${CF_PROJECT}.pages.dev"
echo ""

sleep 2
if curl -sf "http://localhost:$PORT/api/content" > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Server is running and responding.${NC}"
else
  echo -e "${RED}✗ Server may not be running. Check: systemctl status $SERVER_SERVICE${NC}"
fi
