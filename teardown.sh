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

# ─── Auto-detect what's running ───────────────────────
LOCAL_RUNNING=false
CLOUD_RUNNING=false

if kind get clusters 2>/dev/null | grep -q "^shipyard$"; then
  LOCAL_RUNNING=true
fi

if [ -f "terraform/terraform.tfstate" ] && \
   grep -q "aws_eks_cluster" terraform/terraform.tfstate 2>/dev/null; then
  CLOUD_RUNNING=true
fi

# ─── Show what was detected ───────────────────────────
echo -e "  ${BOLD}Detected running environments:${NC}"
echo ""
if [ "$LOCAL_RUNNING" = true ]; then
  echo -e "  ${GREEN}✓${NC}  Local Kind cluster — shipyard"
else
  echo -e "  ${CYAN}–${NC}  Local Kind cluster — not running"
fi
if [ "$CLOUD_RUNNING" = true ]; then
  echo -e "  ${GREEN}✓${NC}  AWS EKS cluster — terraform state found"
else
  echo -e "  ${CYAN}–${NC}  AWS EKS cluster — not running"
fi
echo ""

# ─── If nothing running ───────────────────────────────
if [ "$LOCAL_RUNNING" = false ] && [ "$CLOUD_RUNNING" = false ]; then
  echo -e "  ${CYAN}→${NC}  Nothing to tear down."
  echo ""
  exit 0
fi

# ─── If only local running — skip the question ────────
if [ "$LOCAL_RUNNING" = true ] && [ "$CLOUD_RUNNING" = false ]; then
  echo -e "  ${CYAN}→${NC}  Only local cluster detected."
  read -p "  Destroy local Kind cluster? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo -e "  ${CYAN}→${NC}  Aborted."
    exit 0
  fi
  pkill -f "kubectl port-forward" 2>/dev/null || true
  kind delete cluster --name shipyard
  echo ""
  echo -e "  ${GREEN}✓${NC}  Local cluster deleted. No costs incurred."
  echo ""
  exit 0
fi

# ─── If only cloud running — skip the question ────────
if [ "$LOCAL_RUNNING" = false ] && [ "$CLOUD_RUNNING" = true ]; then
  echo -e "  ${CYAN}→${NC}  Only AWS deployment detected."
  echo ""
  echo -e "  ${RED}${BOLD}⚠️   WARNING${NC}"
  echo -e "  This destroys ALL AWS infrastructure."
  echo -e "  VPC, EKS, RDS, ECR — everything."
  echo ""
  read -p "  Type 'destroy' to confirm: " CONFIRM
  if [ "$CONFIRM" != "destroy" ]; then
    echo -e "  ${CYAN}→${NC}  Aborted. Nothing was deleted."
    exit 0
  fi
  pkill -f "kubectl port-forward" 2>/dev/null || true
  cd terraform
  terraform destroy -auto-approve
  echo ""
  echo -e "  ${GREEN}✓${NC}  All AWS resources destroyed. Billing stopped."
  echo ""
  exit 0
fi

# ─── Both running — ask which one ─────────────────────
echo -e "  Both environments detected. What do you want to destroy?"
echo ""
echo -e "  ${GREEN}1${NC}  Local only  ${CYAN}(Kind cluster)${NC}"
echo -e "  ${YELLOW}2${NC}  Cloud only  ${CYAN}(AWS EKS)${NC}"
echo -e "  ${RED}3${NC}  Both"
echo ""
read -p "  Enter choice [1, 2, or 3]: " TARGET
echo ""

if [ "$TARGET" = "1" ] || [ "$TARGET" = "3" ]; then
  pkill -f "kubectl port-forward" 2>/dev/null || true
  echo -e "  ${CYAN}→${NC}  Deleting Kind cluster..."
  kind delete cluster --name shipyard
  echo -e "  ${GREEN}✓${NC}  Local cluster deleted"
fi

if [ "$TARGET" = "2" ] || [ "$TARGET" = "3" ]; then
  echo ""
  echo -e "  ${RED}${BOLD}⚠️   WARNING — destroying AWS infrastructure${NC}"
  read -p "  Type 'destroy' to confirm: " CONFIRM
  if [ "$CONFIRM" != "destroy" ]; then
    echo -e "  ${CYAN}→${NC}  Cloud teardown aborted."
    exit 0
  fi
  pkill -f "kubectl port-forward" 2>/dev/null || true
  cd terraform
  terraform destroy -auto-approve
  echo -e "  ${GREEN}✓${NC}  All AWS resources destroyed. Billing stopped."
fi

echo ""
echo -e "  ${GREEN}✓${NC}  Teardown complete."
echo ""
