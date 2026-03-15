# ${{ values.serviceName }}

 ${{ values.description }}

## Getting Started

This service was provisioned by the Shipyard IDP platform.

## CI/CD

This repository includes a GitHub Actions pipeline that automatically:
- Runs tests on every pull request
- Builds and pushes Docker image on merge to main
- Deploys to Kubernetes via ArgoCD