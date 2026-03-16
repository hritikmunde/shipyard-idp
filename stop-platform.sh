#!/bin/bash
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo -e "  ${CYAN}→${NC}  Stopping Shipyard IDP port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC}  Platform stopped"
echo -e "  ${CYAN}→${NC}  Cluster is still running"
echo -e "  ${CYAN}→${NC}  Run ./start-platform.sh to start again"
echo -e "  ${CYAN}→${NC}  Run ./teardown.sh to destroy everything"
echo ""
