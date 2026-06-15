#!/bin/bash
set -e

# === Corrupted SMP Wiki + CMS — One-Command Deploy ===
# Usage: curl -sL https://raw.githubusercontent.com/Pateg23/corrupted-smp-wiki/main/deploy.sh | bash
# Everything (including credentials) is baked into the repo.

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

# --- Create .env from encoded file (contains all credentials) ---
if [ ! -f .env ] && [ -f .env.b64 ]; then
  base64 -d .env.b64 > .env
  echo ">> .env restored with credentials"
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
