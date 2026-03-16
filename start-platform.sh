#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo ""
echo -e "${CYAN}${BOLD}  ⚓  Shipyard IDP — Starting Platform${NC}"
echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Kill existing port-forwards
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1

# Check cluster is running
if ! kubectl get nodes &>/dev/null; then
  echo -e "  ${RED}✗${NC}  Cluster not running."
  echo -e "  ${CYAN}→${NC}  Run ./bootstrap.sh first"
  exit 1
fi

echo -e "  ${CYAN}→${NC}  Starting port-forwards..."

kubectl port-forward svc/backstage \
  -n backstage 3000:80 &>/dev/null &
kubectl port-forward svc/backstage \
  -n backstage 7007:80 &>/dev/null &
kubectl port-forward svc/argocd-server \
  -n argocd 8080:443 &>/dev/null &
kubectl port-forward svc/monitoring-grafana \
  -n monitoring 3001:80 &>/dev/null &

sleep 3

ARGOCD_PASSWORD=$(kubectl -n argocd get secret \
  argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | \
  base64 -d 2>/dev/null || echo "see kubectl output")

echo ""
echo -e "  ${GREEN}${BOLD}✅  Platform is running!${NC}"
echo ""
echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Backstage${NC} (Developer Portal)"
echo -e "  ${GREEN}→${NC}  http://localhost:3000"
echo -e "  ${CYAN}→${NC}  Sign in as Guest"
echo ""
echo -e "  ${BOLD}ArgoCD${NC} (GitOps Dashboard)"
echo -e "  ${GREEN}→${NC}  https://localhost:8080"
echo -e "  ${CYAN}→${NC}  admin / ${ARGOCD_PASSWORD}"
echo ""
echo -e "  ${BOLD}Grafana${NC} (Observability)"
echo -e "  ${GREEN}→${NC}  http://localhost:3001"
echo -e "  ${CYAN}→${NC}  admin / shipyard123"
echo ""
echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Run ${CYAN}./stop-platform.sh${NC} to stop"
echo ""