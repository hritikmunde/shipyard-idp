#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo ""
echo -e "  ${RED}${BOLD}⚓  Shipyard IDP — Teardown${NC}"
echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  What do you want to destroy?"
echo ""
echo -e "  ${GREEN}1${NC}  Local  ${CYAN}(Kind cluster)${NC}"
echo -e "  ${YELLOW}2${NC}  Cloud  ${CYAN}(AWS EKS via Terraform)${NC}"
echo ""
read -p "  Enter choice [1 or 2]: " TARGET
echo ""

if [ "$TARGET" = "1" ]; then
  echo -e "  ${CYAN}→${NC}  Stopping port-forwards..."
  pkill -f "kubectl port-forward" 2>/dev/null || true

  echo -e "  ${CYAN}→${NC}  Deleting Kind cluster..."
  kind delete cluster --name shipyard

  echo ""
  echo -e "  ${GREEN}✓${NC}  Local cluster deleted"
  echo -e "  ${CYAN}→${NC}  All data removed. No costs incurred."
  echo ""
fi

if [ "$TARGET" = "2" ]; then
  echo -e "  ${RED}${BOLD}⚠️   WARNING${NC}"
  echo -e "  This destroys ALL AWS infrastructure:"
  echo -e "  VPC, EKS cluster, RDS instances, ECR — everything."
  echo -e "  Billing stops immediately after completion."
  echo ""
  read -p "  Type 'destroy' to confirm: " CONFIRM
  echo ""

  if [ "$CONFIRM" != "destroy" ]; then
    echo -e "  ${CYAN}→${NC}  Aborted. Nothing was deleted."
    exit 0
  fi

  echo -e "  ${CYAN}→${NC}  Stopping port-forwards..."
  pkill -f "kubectl port-forward" 2>/dev/null || true

  echo -e "  ${CYAN}→${NC}  Running terraform destroy..."
  echo -e "  ${YELLOW}!${NC}   This takes 10-15 minutes..."
  echo ""
  cd terraform
  terraform destroy -auto-approve

  echo ""
  echo -e "  ${GREEN}✓${NC}  All AWS resources destroyed"
  echo -e "  ${GREEN}✓${NC}  Billing stopped"
  echo ""
fi
