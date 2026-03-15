#!/bin/bash
set -e

echo ""
echo "🚀 Shipyard IDP Bootstrap"
echo "========================="
echo ""

# Collect required inputs
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -p "Enter your GitHub token (needs repo + workflow permissions): " GITHUB_TOKEN
read -p "Enter your AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -p "Enter your AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
read -p "Enter your AWS region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

echo ""
echo "📦 Creating Kind cluster..."
kind create cluster --name shipyard --config kind-config.yaml
echo "✅ Cluster ready"

echo ""
echo "🔄 Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=180s
echo "✅ ArgoCD ready"

echo ""
echo "⚙️  Installing Crossplane..."
helm repo add crossplane-stable https://charts.crossplane.io/stable --force-update
helm repo update
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace
kubectl wait --for=condition=ready pod \
  -l app=crossplane \
  -n crossplane-system --timeout=120s
echo "✅ Crossplane ready"

echo ""
echo "📊 Installing Prometheus + Grafana..."
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts --force-update
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=shipyard123
kubectl apply -f monitoring/argocd-servicemonitor.yaml
echo "✅ Monitoring ready"

echo ""
echo "☁️  Configuring AWS + Crossplane providers..."
kubectl apply -f crossplane/provider-aws.yaml
echo "Waiting for providers to be healthy (this takes 2-3 minutes)..."
kubectl wait --for=condition=healthy provider/provider-aws-ec2 \
  --timeout=180s
kubectl wait --for=condition=healthy provider/provider-aws-rds \
  --timeout=180s

# Create AWS credentials secret
cat > /tmp/aws-creds.txt <<CREDS
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
CREDS

kubectl create secret generic aws-secret \
  -n crossplane-system \
  --from-file=creds=/tmp/aws-creds.txt
rm /tmp/aws-creds.txt

kubectl apply -f crossplane/provider-config.yaml
echo "✅ AWS connected"

echo ""
echo "🔁 Applying ArgoCD App of Apps..."
kubectl apply -f argocd/root-app.yaml
echo "✅ GitOps configured"

echo ""
echo "🎨 Configuring Backstage..."
export GITHUB_TOKEN=$GITHUB_TOKEN
export GITHUB_USERNAME=$GITHUB_USERNAME
echo "✅ Backstage configured"

echo ""
echo "========================================"
echo "✅ Shipyard IDP is ready!"
echo "========================================"
echo ""
echo "Access your platform:"
echo ""
echo "Backstage (Developer Portal):"
echo "  cd shipyard && yarn start"
echo "  → http://localhost:3000"
echo ""
echo "ArgoCD (GitOps Dashboard):"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  → https://localhost:8080"
echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret \\"
echo "            -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Grafana (Observability):"
echo "  kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80"
echo "  → http://localhost:3001"
echo "  Username: admin | Password: shipyard123"
echo ""