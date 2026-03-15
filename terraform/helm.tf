# ─── ArgoCD ────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.7.0"

  depends_on = [module.eks]
}

# ─── Crossplane ────────────────────────────────────────
resource "helm_release" "crossplane" {
  name             = "crossplane"
  repository       = "https://charts.crossplane.io/stable"
  chart            = "crossplane"
  namespace        = "crossplane-system"
  create_namespace = true

  depends_on = [module.eks]
}

# ─── Prometheus + Grafana ──────────────────────────────
resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  values = [
    <<-EOT
    grafana:
      adminPassword: shipyard123
      service:
        type: LoadBalancer
    EOT
  ]

  depends_on = [module.eks]
}

# ─── ArgoCD LoadBalancer ───────────────────────────────
resource "kubernetes_service" "argocd_lb" {
  metadata {
    name      = "argocd-server-lb"
    namespace = "argocd"
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "argocd-server"
    }

    port {
      port        = 443
      target_port = 8080
    }

    type = "LoadBalancer"
  }

  depends_on = [helm_release.argocd]
}