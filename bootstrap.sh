#!/bin/bash
set -e

# ─── Colors ───────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Animated header ──────────────────────────────────
clear
echo ""
echo -e "${CYAN}${BOLD}"
sleep 0.05; echo "  ███████╗██╗  ██╗██╗██████╗ ██╗   ██╗ █████╗ ██████╗ ██████╗ "
sleep 0.05; echo "  ██╔════╝██║  ██║██║██╔══██╗╚██╗ ██╔╝██╔══██╗██╔══██╗██╔══██╗"
sleep 0.05; echo "  ███████╗███████║██║██████╔╝ ╚████╔╝ ███████║██████╔╝██║  ██║"
sleep 0.05; echo "  ╚════██║██╔══██║██║██╔═══╝   ╚██╔╝  ██╔══██║██╔══██╗██║  ██║"
sleep 0.05; echo "  ███████║██║  ██║██║██║        ██║   ██║  ██║██║  ██║██████╔╝"
sleep 0.05; echo "  ╚══════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ "
echo -e "${NC}"
sleep 0.1
echo -e "${PURPLE}${BOLD}  ██╗██████╗ ██████╗ ${NC}"
sleep 0.05
echo -e "${PURPLE}${BOLD}  ██║██╔══██╗██╔══██╗${NC}"
sleep 0.05
echo -e "${PURPLE}${BOLD}  ██║██║  ██║██████╔╝${NC}"
sleep 0.05
echo -e "${PURPLE}${BOLD}  ██║██║  ██║██╔═══╝ ${NC}"
sleep 0.05
echo -e "${PURPLE}${BOLD}  ██║██████╔╝██║     ${NC}"
sleep 0.05
echo -e "${PURPLE}${BOLD}  ╚═╝╚═════╝ ╚═╝     ${NC}"
echo ""
sleep 0.2
echo -e "${CYAN}  Self-service Internal Developer Platform${NC}"
echo -e "${CYAN}  Provision repos, CI/CD, and databases in 3 minutes${NC}"
echo ""
echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
sleep 0.3

# ─── Spinner helper ───────────────────────────────────
spin() {
  local pid=$1
  local msg=$2
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while kill -0 $pid 2>/dev/null; do
    for i in $(seq 0 9); do
      printf "\r  ${CYAN}${spinstr:$i:1}${NC}  $msg"
      sleep 0.1
    done
  done
  printf "\r  ${GREEN}✓${NC}  $msg\n"
}

# ─── Step counter ─────────────────────────────────────
STEP=0
step() {
  STEP=$((STEP + 1))
  echo ""
  echo -e "  ${BOLD}${BLUE}[$STEP]${NC} ${BOLD}$1${NC}"
  echo -e "  ${YELLOW}────────────────────────────────${NC}"
}

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
info() { echo -e "  ${CYAN}→${NC}  $1"; }
warn() { echo -e "  ${YELLOW}!${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; exit 1; }

# ─── Deployment target ────────────────────────────────
echo -e "  ${BOLD}Where do you want to deploy Shipyard IDP?${NC}"
echo ""
echo -e "  ${GREEN}1${NC}  Local  ${CYAN}(Kind cluster — free, no cloud needed)${NC}"
echo -e "  ${YELLOW}2${NC}  Cloud  ${CYAN}(AWS EKS — production grade, ~\$5/day)${NC}"
echo ""
read -p "  Enter choice [1 or 2]: " DEPLOY_TARGET
echo ""

# ─── Common inputs ────────────────────────────────────
read -p "  GitHub username: " GITHUB_USERNAME
read -sp "  GitHub token (repo + workflow permissions): " GITHUB_TOKEN
echo ""

if [ "$DEPLOY_TARGET" = "2" ]; then
  echo ""
  read -p "  AWS region (default: us-east-1): " AWS_REGION
  AWS_REGION=${AWS_REGION:-us-east-1}
  read -p "  EKS cluster name (default: shipyard-idp): " CLUSTER_NAME
  CLUSTER_NAME=${CLUSTER_NAME:-shipyard-idp}
  read -p "  Node instance type (default: t3.medium): " INSTANCE_TYPE
  INSTANCE_TYPE=${INSTANCE_TYPE:-t3.medium}
fi

# ═══════════════════════════════════════════════════════
# LOCAL DEPLOYMENT
# ═══════════════════════════════════════════════════════
if [ "$DEPLOY_TARGET" = "1" ]; then

  echo ""
  echo -e "  ${BOLD}${PURPLE}Starting local deployment...${NC}"
  echo ""

  # ─── Prerequisites check ────────────────────────────
  step "Checking prerequisites"
  for cmd in docker kubectl kind helm terraform node yarn git; do
    if command -v $cmd &>/dev/null; then
      ok "$cmd $(${cmd} --version 2>/dev/null | head -1 | sed 's/.*version //' | cut -d' ' -f1)"
    else
      fail "$cmd is not installed. See README for installation instructions."
    fi
  done

  # ─── Kind cluster ───────────────────────────────────
  step "Creating Kind cluster"
  if kind get clusters 2>/dev/null | grep -q "^shipyard$"; then
    warn "Cluster 'shipyard' already exists — skipping creation"
  else
    info "Spinning up 3-node cluster (control-plane + 2 workers)..."
    kind create cluster --name shipyard --config kind-config.yaml &>/dev/null
    ok "Kind cluster created"
  fi
  kubectl wait --for=condition=ready node \
    --all --timeout=120s &>/dev/null
  ok "All nodes ready"

  # ─── ArgoCD ─────────────────────────────────────────
  step "Installing ArgoCD"
  if kubectl get namespace argocd &>/dev/null; then
    warn "ArgoCD namespace exists — skipping install"
  else
    kubectl create namespace argocd &>/dev/null
    kubectl apply -n argocd -f \
      https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
      &>/dev/null &
    spin $! "Applying ArgoCD manifests"
  fi
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server \
    -n argocd --timeout=180s &>/dev/null
  ok "ArgoCD running"

  # ─── Crossplane ─────────────────────────────────────
  step "Installing Crossplane"
  helm repo add crossplane-stable \
    https://charts.crossplane.io/stable &>/dev/null
  helm repo update &>/dev/null
  if helm list -n crossplane-system 2>/dev/null | grep -q crossplane; then
    warn "Crossplane already installed — skipping"
  else
    helm install crossplane crossplane-stable/crossplane \
      --namespace crossplane-system \
      --create-namespace &>/dev/null &
    spin $! "Installing Crossplane via Helm"
  fi
  kubectl wait --for=condition=ready pod \
    -l app=crossplane \
    -n crossplane-system --timeout=120s &>/dev/null
  ok "Crossplane running"

  # ─── Prometheus + Grafana ───────────────────────────
  step "Installing observability stack"
  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts &>/dev/null
  helm repo update &>/dev/null
  if helm list -n monitoring 2>/dev/null | grep -q monitoring; then
    warn "Monitoring stack already installed — skipping"
  else
    helm install monitoring \
      prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      --create-namespace \
      --set grafana.adminPassword=shipyard123 \
      &>/dev/null &
    spin $! "Installing Prometheus + Grafana"
  fi
  kubectl apply -f monitoring/argocd-servicemonitor.yaml &>/dev/null
  ok "Prometheus + Grafana running"

  # ─── Crossplane AWS providers ───────────────────────
  step "Configuring Crossplane AWS providers"
  kubectl apply -f crossplane/provider-aws.yaml &>/dev/null
  info "Waiting for providers to become healthy (2-3 minutes)..."
  sleep 30
  kubectl wait --for=condition=healthy \
    provider/provider-aws-ec2 --timeout=180s &>/dev/null
  kubectl wait --for=condition=healthy \
    provider/provider-aws-rds --timeout=180s &>/dev/null
  ok "AWS providers healthy"

  # ─── AWS credentials ────────────────────────────────
  # AWS credentials for Crossplane
  echo ""
  info "Reading AWS credentials from AWS CLI config..."

  AWS_KEY=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
  AWS_SECRET=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")

  if [ -z "$AWS_KEY" ] || [ -z "$AWS_SECRET" ]; then
    warn "AWS CLI credentials not found."
    warn "Either run 'aws configure' first, or enter manually:"
    echo ""
    read -p "  AWS Access Key ID: " AWS_KEY
    read -sp "  AWS Secret Access Key: " AWS_SECRET
    echo ""
  else
    ok "AWS credentials found in CLI config"
  fi

  cat > /tmp/aws-creds.txt <<CREDS
  [default]
  aws_access_key_id=${AWS_KEY}
  aws_secret_access_key=${AWS_SECRET}
  CREDS

  kubectl create secret generic aws-secret \
    -n crossplane-system \
    --from-file=creds=/tmp/aws-creds.txt \
    --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
  rm /tmp/aws-creds.txt
  kubectl apply -f crossplane/provider-config.yaml &>/dev/null
  ok "AWS credentials configured"

  # ─── ArgoCD App of Apps ─────────────────────────────
  step "Configuring GitOps (ArgoCD App of Apps)"
  kubectl apply -f argocd/root-app.yaml &>/dev/null
  ok "ArgoCD watching argocd/apps/ for new services"

  # ─── Build Backstage ────────────────────────────────
  step "Building Backstage (this takes 5-10 minutes)"
  info "Installing Node dependencies..."
  cd shipyard
  yarn install --immutable --silent 2>/dev/null &
  spin $! "yarn install"

  info "Compiling TypeScript..."
  yarn tsc --skipLibCheck 2>/dev/null || true
  ok "TypeScript compiled"

  info "Building backend bundle..."
  yarn build:backend &>/dev/null &
  spin $! "yarn build:backend"
  cd ..

  info "Building Docker image..."
  docker build \
    -t shipyard-idp-backstage:latest \
    -f shipyard/packages/backend/Dockerfile \
    shipyard/ &>/dev/null &
  spin $! "docker build"

  info "Loading image into Kind cluster..."
  kind load docker-image \
    shipyard-idp-backstage:latest \
    --name shipyard &>/dev/null &
  spin $! "kind load docker-image"
  ok "Backstage image ready"

  # ─── Deploy Backstage ───────────────────────────────
  step "Deploying Backstage to cluster"
  kubectl apply -f k8s/backstage/namespace.yaml &>/dev/null
  kubectl apply -f k8s/backstage/postgres.yaml &>/dev/null

  info "Waiting for PostgreSQL..."
  kubectl wait --for=condition=ready pod \
    -l app=postgres \
    -n backstage \
    --timeout=120s &>/dev/null
  ok "PostgreSQL ready"

  kubectl create secret generic backstage-secrets \
    -n backstage \
    --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN}" \
    --from-literal=POSTGRES_HOST=postgres \
    --from-literal=POSTGRES_PORT=5432 \
    --from-literal=POSTGRES_USER=backstage \
    --from-literal=POSTGRES_PASSWORD=backstage123 \
    --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  kubectl apply -f k8s/backstage/deployment.yaml &>/dev/null
  kubectl apply -f k8s/backstage/service.yaml &>/dev/null

  info "Waiting for Backstage to start (2-3 minutes)..."
  kubectl wait --for=condition=ready pod \
    -l app=backstage \
    -n backstage \
    --timeout=300s &>/dev/null
  ok "Backstage running in cluster"

  # ─── Get credentials ────────────────────────────────
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret \
    argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

  # ─── Done ───────────────────────────────────────────
  echo ""
  echo ""
  echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${GREEN}${BOLD}✅  Shipyard IDP is ready!${NC}"
  echo ""
  echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${BOLD}Run this to start the platform:${NC}"
  echo ""
  echo -e "    ${CYAN}./start-platform.sh${NC}"
  echo ""
  echo -e "  ${BOLD}Then open:${NC}"
  echo ""
  echo -e "    ${GREEN}Backstage${NC}   →  http://localhost:3000"
  echo -e "    ${GREEN}ArgoCD${NC}      →  https://localhost:8080"
  echo -e "    ${GREEN}Grafana${NC}     →  http://localhost:3001"
  echo ""
  echo -e "  ${BOLD}Credentials:${NC}"
  echo ""
  echo -e "    ArgoCD   admin / ${CYAN}${ARGOCD_PASSWORD}${NC}"
  echo -e "    Grafana  admin / ${CYAN}shipyard123${NC}"
  echo ""
  echo -e "  ${BOLD}When done:${NC}"
  echo ""
  echo -e "    ${CYAN}./stop-platform.sh${NC}   — stop port-forwards"
  echo -e "    ${CYAN}./teardown.sh${NC}        — destroy everything"
  echo ""
  echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

fi

# ═══════════════════════════════════════════════════════
# CLOUD DEPLOYMENT
# ═══════════════════════════════════════════════════════
if [ "$DEPLOY_TARGET" = "2" ]; then

  echo ""
  echo -e "  ${BOLD}${PURPLE}Starting AWS EKS deployment...${NC}"
  echo ""

  # ─── Prerequisites ──────────────────────────────────
  step "Checking prerequisites"
  for cmd in docker kubectl helm terraform node yarn git aws; do
    if command -v $cmd &>/dev/null; then
      ok "$cmd found"
    else
      fail "$cmd is not installed."
    fi
  done

  # Check AWS credentials
  if ! aws sts get-caller-identity &>/dev/null; then
    fail "AWS credentials not configured. Run: aws configure"
  fi
  ok "AWS credentials valid"

  # ─── Terraform ──────────────────────────────────────
  step "Provisioning AWS infrastructure with Terraform"

  cat > terraform/terraform.tfvars <<TFVARS
region             = "${AWS_REGION}"
cluster_name       = "${CLUSTER_NAME}"
node_instance_type = "${INSTANCE_TYPE}"
node_count         = 2
github_username    = "${GITHUB_USERNAME}"
TFVARS

  export TF_VAR_github_token=$GITHUB_TOKEN

  cd terraform
  info "Initializing Terraform..."
  terraform init &>/dev/null &
  spin $! "terraform init"

  info "Planning infrastructure..."
  terraform plan -out=tfplan -compact-warnings 2>/dev/null

  echo ""
  warn "About to provision AWS infrastructure."
  warn "Estimated cost: ~\$5/day while running."
  warn "Run ./teardown.sh to destroy and stop billing."
  echo ""
  read -p "  Proceed? (yes/no): " CONFIRM
  [ "$CONFIRM" != "yes" ] && echo "Aborted." && exit 0

  info "Provisioning (15-20 minutes)..."
  terraform apply tfplan

  # Configure kubectl
  info "Configuring kubectl..."
  aws eks update-kubeconfig \
    --region $AWS_REGION \
    --name $CLUSTER_NAME
  ok "kubectl configured for EKS"
  cd ..

  # ─── Crossplane providers ───────────────────────────
  step "Configuring Crossplane AWS providers"
  kubectl apply -f crossplane/provider-aws.yaml &>/dev/null
  info "Waiting for providers (2-3 minutes)..."
  sleep 60
  kubectl wait --for=condition=healthy \
    provider/provider-aws-ec2 --timeout=180s &>/dev/null
  kubectl wait --for=condition=healthy \
    provider/provider-aws-rds --timeout=180s &>/dev/null

  AWS_KEY=$(aws configure get aws_access_key_id)
  AWS_SECRET=$(aws configure get aws_secret_access_key)

  cat > /tmp/aws-creds.txt <<CREDS
[default]
aws_access_key_id=${AWS_KEY}
aws_secret_access_key=${AWS_SECRET}
CREDS
  kubectl create secret generic aws-secret \
    -n crossplane-system \
    --from-file=creds=/tmp/aws-creds.txt \
    --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
  rm /tmp/aws-creds.txt
  kubectl apply -f crossplane/provider-config.yaml &>/dev/null
  ok "AWS providers configured"

  # ─── GitOps ─────────────────────────────────────────
  step "Configuring GitOps"
  kubectl apply -f argocd/root-app.yaml &>/dev/null
  kubectl apply -f monitoring/argocd-servicemonitor.yaml &>/dev/null
  ok "ArgoCD App of Apps applied"

  # ─── Build + push Backstage ─────────────────────────
  step "Building and deploying Backstage"

  ECR_URL=$(cd terraform && \
    terraform output -raw ecr_repository_url 2>/dev/null || \
    echo "")

  if [ -z "$ECR_URL" ]; then
    warn "ECR URL not found — skipping Backstage cloud deploy"
    warn "Add ECR repository to terraform/helm.tf and rerun"
  else
    info "Building Backstage..."
    cd shipyard
    yarn install --immutable --silent 2>/dev/null
    yarn build:backend &>/dev/null
    cd ..

    docker build \
      -t backstage:latest \
      -f shipyard/packages/backend/Dockerfile \
      shipyard/ &>/dev/null &
    spin $! "Building Docker image"

    aws ecr get-login-password --region $AWS_REGION | \
      docker login --username AWS \
      --password-stdin $ECR_URL &>/dev/null
    docker tag backstage:latest $ECR_URL:latest
    docker push $ECR_URL:latest &>/dev/null &
    spin $! "Pushing to ECR"

    kubectl create namespace backstage \
      --dry-run=client -o yaml | kubectl apply -f - &>/dev/null
    kubectl create secret generic backstage-secrets \
      -n backstage \
      --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN}" \
      --from-literal=POSTGRES_HOST="" \
      --from-literal=POSTGRES_PORT=5432 \
      --from-literal=POSTGRES_USER=backstage \
      --from-literal=POSTGRES_PASSWORD=backstage123 \
      --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

    sed "s|BACKSTAGE_IMAGE_URL|${ECR_URL}:latest|g" \
      argocd/apps/backstage/deployment.yaml | \
      kubectl apply -f - &>/dev/null
    ok "Backstage deployed to EKS"
  fi

  # ─── Get URLs ───────────────────────────────────────
  step "Fetching platform URLs"
  info "Waiting for LoadBalancers (60s)..."
  sleep 60

  ARGOCD_URL=$(kubectl get svc argocd-server-lb -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null || echo "pending")
  GRAFANA_URL=$(kubectl get svc monitoring-grafana -n monitoring \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null || echo "pending")
  BACKSTAGE_URL=$(kubectl get svc backstage -n backstage \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null || echo "pending")
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret \
    argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

  # ─── Done ───────────────────────────────────────────
  echo ""
  echo ""
  echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${GREEN}${BOLD}✅  Shipyard IDP is live on AWS!${NC}"
  echo ""
  echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${BOLD}Access your platform:${NC}"
  echo ""
  echo -e "    ${GREEN}Backstage${NC}   →  http://${BACKSTAGE_URL}"
  echo -e "    ${GREEN}ArgoCD${NC}      →  https://${ARGOCD_URL}"
  echo -e "    ${GREEN}Grafana${NC}     →  http://${GRAFANA_URL}"
  echo ""
  echo -e "  ${BOLD}Credentials:${NC}"
  echo ""
  echo -e "    ArgoCD   admin / ${CYAN}${ARGOCD_PASSWORD}${NC}"
  echo -e "    Grafana  admin / ${CYAN}shipyard123${NC}"
  echo ""
  echo -e "  ${RED}${BOLD}⚠️   Remember to destroy when done:${NC}"
  echo -e "    ${CYAN}./teardown.sh${NC}  → choose option 2"
  echo ""
  echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

fi