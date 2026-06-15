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
export DEBIAN_FRONTEND=noninteractive
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

# --- Configure git remote with token so publish can push ---
GITHUB_TOKEN=$(grep -oP '^GITHUB_TOKEN=\K.*' .env 2>/dev/null || true)
if [ -n "$GITHUB_TOKEN" ]; then
  git remote set-url origin "https://Pateg23:$GITHUB_TOKEN@github.com/Pateg23/corrupted-smp-wiki.git"
  git config user.email "cms@corrupted-smp"
  git config user.name "CMS Bot"
  echo ">> Git remote configured for auto-push"
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

# --- Generate wiki HTML and deploy to Cloudflare ---
echo ">> Generating wiki HTML..."
cd "$INSTALL_DIR"
python3 generate.py public/content.json wiki-template.html public/index.html 2>/dev/null || true

echo ">> Deploying to Cloudflare Pages..."
CF_PROJECT=$(grep -oP '^CLOUDFLARE_PROJECT_NAME=\K.*' .env 2>/dev/null || echo "corrupted-smp")
if command -v wrangler &>/dev/null && [ -f .env ]; then
  export CLOUDFLARE_API_TOKEN=$(grep -oP '^CLOUDFLARE_API_TOKEN=\K.*' .env 2>/dev/null || true)
  export CLOUDFLARE_ACCOUNT_ID=$(grep -oP '^CLOUDFLARE_ACCOUNT_ID=\K.*' .env 2>/dev/null || true)
  if [ -n "$CLOUDFLARE_API_TOKEN" ] && [ -n "$CLOUDFLARE_ACCOUNT_ID" ]; then
    wrangler pages deploy public --project-name="$CF_PROJECT" --branch=main 2>&1 | tail -3 || echo "  (Cloudflare deploy skipped — will work from CMS)"
  fi
fi

# --- Get IPs and URLs ---
SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
PORT=$(grep -oP '^PORT=\K.*' .env 2>/dev/null || echo "8420")
CF_URL="https://${CF_PROJECT}.pages.dev"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ INSTALLATION COMPLETE!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}CMS Editor:${NC}     http://$SERVER_IP:$PORT/admin/"
echo -e "  ${CYAN}Wiki Page (VPS):${NC} http://$SERVER_IP:$PORT/"
echo -e "  ${CYAN}Wiki Page (CDN):${NC} ${CF_URL}"
echo ""
echo -e "  ${CYAN}In the CMS, click:${NC}"
echo -e "    💾 Save     → saves content locally"
echo -e "    📢 Publish  → saves, generates, deploys to Cloudflare & pushes to GitHub"
echo ""

sleep 2
if curl -sf "http://localhost:$PORT/api/content" > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Server is running and responding.${NC}"
else
  echo -e "${RED}✗ Server may not be running. Check: systemctl status $SERVER_SERVICE${NC}"
fi
