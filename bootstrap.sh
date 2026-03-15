#!/bin/bash
set -e

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║         Shipyard IDP Bootstrap        ║"
echo "║   Self-service Internal Developer     ║"
echo "║          Platform Setup               ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# ─── Deployment target ────────────────────────────────
echo "Where do you want to deploy Shipyard IDP?"
echo ""
echo "  1. Local  (Kind cluster — free, instant, good for testing)"
echo "  2. Cloud  (AWS EKS — production grade, costs ~$5/day)"
echo ""
read -p "Enter choice [1 or 2]: " DEPLOY_TARGET

# ─── Common inputs ────────────────────────────────────
echo ""
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -sp "Enter your GitHub token (repo + workflow permissions): " GITHUB_TOKEN
echo ""

# ─── Cloud inputs ─────────────────────────────────────
if [ "$DEPLOY_TARGET" = "2" ]; then
  echo ""
  read -p "Enter AWS region (default: us-east-1): " AWS_REGION
  AWS_REGION=${AWS_REGION:-us-east-1}
  read -p "Enter EKS cluster name (default: shipyard-idp): " CLUSTER_NAME
  CLUSTER_NAME=${CLUSTER_NAME:-shipyard-idp}
  read -p "Enter node instance type (default: t3.medium): " INSTANCE_TYPE
  INSTANCE_TYPE=${INSTANCE_TYPE:-t3.medium}
fi

# ─── Local deployment ─────────────────────────────────
if [ "$DEPLOY_TARGET" = "1" ]; then
  echo ""
  echo "🚀 Deploying Shipyard IDP locally..."
  echo ""

  # Create Kind cluster
  echo "📦 Creating Kind cluster..."
  kind create cluster --name shipyard --config kind-config.yaml
  echo "✅ Cluster ready"

  # Install ArgoCD
  echo "🔄 Installing ArgoCD..."
  kubectl create namespace argocd
  kubectl apply -n argocd -f \
    https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server \
    -n argocd --timeout=180s
  echo "✅ ArgoCD ready"

  # Install Crossplane
  echo "⚙️  Installing Crossplane..."
  helm repo add crossplane-stable \
    https://charts.crossplane.io/stable --force-update
  helm repo update
  helm install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system \
    --create-namespace
  kubectl wait --for=condition=ready pod \
    -l app=crossplane \
    -n crossplane-system --timeout=120s
  echo "✅ Crossplane ready"

  # Install Prometheus + Grafana
  echo "📊 Installing monitoring stack..."
  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts --force-update
  helm repo update
  helm install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.adminPassword=shipyard123
  kubectl apply -f monitoring/argocd-servicemonitor.yaml
  echo "✅ Monitoring ready"

  # Configure Crossplane AWS providers
  echo "☁️  Configuring Crossplane AWS providers..."
  kubectl apply -f crossplane/provider-aws.yaml
  echo "Waiting for providers (2-3 minutes)..."
  sleep 30
  kubectl wait --for=condition=healthy provider/provider-aws-ec2 \
    --timeout=180s
  kubectl wait --for=condition=healthy provider/provider-aws-rds \
    --timeout=180s

  # AWS credentials for Crossplane
  echo ""
  read -p "Enter AWS Access Key ID (for Crossplane RDS provisioning): " AWS_KEY
  read -sp "Enter AWS Secret Access Key: " AWS_SECRET
  echo ""

  cat > /tmp/aws-creds.txt <<CREDS
[default]
aws_access_key_id=${AWS_KEY}
aws_secret_access_key=${AWS_SECRET}
CREDS

  kubectl create secret generic aws-secret \
    -n crossplane-system \
    --from-file=creds=/tmp/aws-creds.txt
  rm /tmp/aws-creds.txt
  kubectl apply -f crossplane/provider-config.yaml
  echo "✅ AWS connected"

  # Apply ArgoCD App of Apps
  echo "🔁 Configuring GitOps..."
  kubectl apply -f argocd/root-app.yaml
  echo "✅ GitOps configured"

  # Configure Backstage
  export GITHUB_TOKEN=$GITHUB_TOKEN
  export GITHUB_USERNAME=$GITHUB_USERNAME

  # Get ArgoCD password
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret \
    argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

  echo ""
  echo "╔═══════════════════════════════════════════╗"
  echo "║       ✅ Shipyard IDP is ready!           ║"
  echo "╚═══════════════════════════════════════════╝"
  echo ""
  echo "Start Backstage (in a new terminal):"
  echo "  cd shipyard && GITHUB_TOKEN=$GITHUB_TOKEN yarn start"
  echo ""
  echo "Then open these URLs:"
  echo ""
  echo "  Backstage (Developer Portal):"
  echo "  → http://localhost:3000"
  echo ""
  echo "  ArgoCD (run in new terminal first):"
  echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "  → https://localhost:8080"
  echo "  Username: admin"
  echo "  Password: $ARGOCD_PASSWORD"
  echo ""
  echo "  Grafana (run in new terminal first):"
  echo "  kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80"
  echo "  → http://localhost:3001"
  echo "  Username: admin | Password: shipyard123"
  echo ""
fi

# ─── Cloud deployment ─────────────────────────────────
if [ "$DEPLOY_TARGET" = "2" ]; then
  echo ""
  echo "🚀 Deploying Shipyard IDP on AWS EKS..."
  echo ""

  # Create tfvars file
  cat > terraform/terraform.tfvars <<TFVARS
region             = "${AWS_REGION}"
cluster_name       = "${CLUSTER_NAME}"
node_instance_type = "${INSTANCE_TYPE}"
node_count         = 2
github_username    = "${GITHUB_USERNAME}"
TFVARS

  export TF_VAR_github_token=$GITHUB_TOKEN

  # Run Terraform
  cd terraform
  echo "📦 Initializing Terraform..."
  terraform init

  echo ""
  echo "📋 Planning infrastructure..."
  terraform plan -out=tfplan

  echo ""
  echo "⚠️  About to provision AWS infrastructure."
  echo "   Estimated cost: ~$5/day while running."
  echo "   Run ./teardown.sh to destroy everything."
  echo ""
  read -p "Proceed? (yes/no): " CONFIRM

  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  echo ""
  echo "⏳ Provisioning infrastructure (15-20 minutes)..."
  terraform apply tfplan

  # Configure kubectl
  echo ""
  echo "🔧 Configuring kubectl..."
  aws eks update-kubeconfig \
    --region $AWS_REGION \
    --name $CLUSTER_NAME

  # Apply Crossplane providers and config
  cd ..
  kubectl apply -f crossplane/provider-aws.yaml
  echo "Waiting for Crossplane providers..."
  sleep 60
  kubectl wait --for=condition=healthy provider/provider-aws-ec2 \
    --timeout=180s
  kubectl wait --for=condition=healthy provider/provider-aws-rds \
    --timeout=180s

  # AWS credentials for Crossplane
  AWS_KEY=$(aws configure get aws_access_key_id)
  AWS_SECRET=$(aws configure get aws_secret_access_key)

  cat > /tmp/aws-creds.txt <<CREDS
[default]
aws_access_key_id=${AWS_KEY}
aws_secret_access_key=${AWS_SECRET}
CREDS

  kubectl create secret generic aws-secret \
    -n crossplane-system \
    --from-file=creds=/tmp/aws-creds.txt
  rm /tmp/aws-creds.txt
  kubectl apply -f crossplane/provider-config.yaml

  # Apply ArgoCD App of Apps
  kubectl apply -f argocd/root-app.yaml

  # Apply monitoring ServiceMonitors
  kubectl apply -f monitoring/argocd-servicemonitor.yaml

  # Get LoadBalancer URLs
  echo ""
  echo "⏳ Waiting for LoadBalancers to provision..."
  sleep 60

  BACKSTAGE_URL=$(kubectl get svc backstage -n backstage \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
    echo "pending - run: kubectl get svc -n backstage")

  ARGOCD_URL=$(kubectl get svc argocd-server-lb -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
    echo "pending - run: kubectl get svc -n argocd")

  GRAFANA_URL=$(kubectl get svc monitoring-grafana -n monitoring \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
    echo "pending - run: kubectl get svc -n monitoring")

  ARGOCD_PASSWORD=$(kubectl -n argocd get secret \
    argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

  echo ""
  echo "╔═══════════════════════════════════════════════╗"
  echo "║       ✅ Shipyard IDP is ready on AWS!        ║"
  echo "╚═══════════════════════════════════════════════╝"
  echo ""
  echo "  Backstage (Developer Portal):"
  echo "  → http://${BACKSTAGE_URL}:3000"
  echo ""
  echo "  ArgoCD (GitOps Dashboard):"
  echo "  → https://${ARGOCD_URL}"
  echo "  Username: admin | Password: $ARGOCD_PASSWORD"
  echo ""
  echo "  Grafana (Observability):"
  echo "  → http://${GRAFANA_URL}:3001"
  echo "  Username: admin | Password: shipyard123"
  echo ""
  echo "⚠️  Remember to run ./teardown.sh when done"
  echo "   to avoid unnecessary AWS charges."
  echo ""
fi