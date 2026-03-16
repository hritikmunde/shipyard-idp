#!/bin/bash
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "  ${CYAN}${BOLD}⚓  Rebuilding Backstage${NC}"
echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "  ${CYAN}→${NC}  Building backend bundle..."
cd shipyard
yarn build:backend &>/dev/null
cd ..

echo -e "  ${CYAN}→${NC}  Building Docker image..."
docker build \
  -t shipyard-idp-backstage:latest \
  -f shipyard/packages/backend/Dockerfile \
  shipyard/ &>/dev/null

echo -e "  ${CYAN}→${NC}  Loading into Kind cluster..."
kind load docker-image \
  shipyard-idp-backstage:latest \
  --name shipyard &>/dev/null

echo -e "  ${CYAN}→${NC}  Restarting Backstage pod..."
kubectl rollout restart \
  deployment/backstage -n backstage &>/dev/null

echo -e "  ${CYAN}→${NC}  Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod \
  -l app=backstage \
  -n backstage \
  --timeout=180s &>/dev/null

echo ""
echo -e "  ${GREEN}✓${NC}  Backstage rebuilt and restarted"
echo -e "  ${CYAN}→${NC}  Run ./start-platform.sh to access"
echo ""
