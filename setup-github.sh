#!/bin/bash
set -e

# === Setup GitHub Repo for Corrupted SMP Wiki ===
# Usage: bash setup-github.sh YOUR_GITHUB_TOKEN
# Creates a private repo and pushes everything

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

if [ -z "$1" ]; then
  echo -e "${RED}Usage: bash setup-github.sh YOUR_GITHUB_TOKEN${NC}"
  echo "  Get a token at: https://github.com/settings/tokens (scopes: repo)"
  exit 1
fi

TOKEN="$1"
USERNAME=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/user | python3 -c "import json,sys; print(json.load(sys.stdin)['login'])" 2>/dev/null || true)

if [ -z "$USERNAME" ]; then
  echo -e "${RED}Invalid token or API error. Check your token.${NC}"
  exit 1
fi

REPO_NAME="corrupted-smp-wiki"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Setting up GitHub repo for $USERNAME   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# Create repo on GitHub (private)
echo ">> Creating private repo $REPO_NAME..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  https://api.github.com/user/repos \
  -d "{\"name\":\"$REPO_NAME\",\"private\":true,\"auto_init\":false}" 2>/dev/null)

if [ "$HTTP_CODE" = "422" ]; then
  echo "  Repo already exists, will push to it."
elif [ "$HTTP_CODE" = "201" ]; then
  echo "  Repo created!"
else
  echo -e "${RED}  Failed to create repo (HTTP $HTTP_CODE). Will try to push anyway.${NC}"
fi

# Initialize git and push
cd "$DIR"
echo ">> Initializing git..."
git init
git config user.email "deploy@corrupted-smp"
git config user.name "Deploy Bot"
git add -A
git commit -m "Initial commit — Corrupted SMP Wiki + CMS"

echo ">> Pushing to GitHub..."
git remote add origin "https://$USERNAME:$TOKEN@github.com/$USERNAME/$REPO_NAME.git"
git branch -M main
git push -u origin main

# Update deploy.sh with the correct repo URL
REPO_URL="https://github.com/$USERNAME/$REPO_NAME.git"
sed -i "s|^REPO_URL=.*|REPO_URL=\"$REPO_URL\"|" deploy.sh
git add -A && git commit -m "Update REPO_URL in deploy.sh" && git push

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ DONE! Repo pushed to GitHub         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Repo URL:  ${CYAN}https://github.com/$USERNAME/$REPO_NAME${NC}"
echo ""
echo -e "  ${GREEN}One-command deploy on any VPS:${NC}"
echo -e "  ${CYAN}curl -sL https://raw.githubusercontent.com/$USERNAME/$REPO_NAME/main/deploy.sh | bash${NC}"
