#!/bin/bash
set -e

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║       Shipyard IDP Teardown           ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "What do you want to tear down?"
echo ""
echo "  1. Local (Kind cluster)"
echo "  2. Cloud (AWS EKS via Terraform)"
echo ""
read -p "Enter choice [1 or 2]: " TARGET

if [ "$TARGET" = "1" ]; then
  echo ""
  echo "🗑️  Deleting Kind cluster..."
  kind delete cluster --name shipyard
  echo "✅ Local cluster deleted"
fi

if [ "$TARGET" = "2" ]; then
  echo ""
  echo "⚠️  This will destroy ALL AWS infrastructure."
  echo "   VPC, EKS cluster, RDS instances, everything."
  echo ""
  read -p "Are you sure? Type 'destroy' to confirm: " CONFIRM

  if [ "$CONFIRM" != "destroy" ]; then
    echo "Aborted."
    exit 0
  fi

  echo ""
  echo "🗑️  Running terraform destroy..."
  cd terraform
  terraform destroy -auto-approve
  echo ""
  echo "✅ All AWS resources destroyed. Billing stopped."
fi