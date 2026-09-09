#!/usr/bin/env bash

set -euo pipefail

echo "=== LoanTrack Kubernetes Deployment ==="

# --------------------------------------------------
# 1. Check required tools
# --------------------------------------------------

command -v minikube >/dev/null 2>&1 || {
    echo "ERROR: minikube is not installed."
    exit 1
}

command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl is not installed."
    exit 1
}

# --------------------------------------------------
# 2. Load local environment variables
# --------------------------------------------------

if [[ ! -f .env ]]; then
    echo "ERROR: .env file not found."
    echo "Create it from .env.example before deploying."
    exit 1
fi

set -a
source .env
set +a

: "${POSTGRES_DB:?POSTGRES_DB is not set}"
: "${POSTGRES_USER:?POSTGRES_USER is not set}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is not set}"

# --------------------------------------------------
# 3. Start Minikube if necessary
# --------------------------------------------------

if ! minikube status --profile minikube >/dev/null 2>&1; then
    echo "Starting Minikube..."
    minikube start \
        --profile minikube \
        --driver=docker \
        --cpus=2 \
        --memory=4096
else
    echo "Minikube is already running."
fi

# --------------------------------------------------
# 4. Build application images inside Minikube
# --------------------------------------------------

echo "Building backend image..."
minikube image build \
    --profile minikube \
    -t loantrack-backend:v2 \
    ./backend

echo "Building frontend image..."
minikube image build \
    --profile minikube \
    -t loantrack-frontend:v1 \
    ./frontend

# --------------------------------------------------
# 5. Create/update namespace
# --------------------------------------------------

echo "Applying namespace..."

kubectl create namespace loantrack \
    --dry-run=client \
    -o yaml | kubectl apply -f -

# --------------------------------------------------
# 6. Create/update Kubernetes Secret
# --------------------------------------------------

echo "Applying database Secret..."

kubectl create secret generic loantrack-db-secret \
    --namespace=loantrack \
    --from-literal="POSTGRES_DB=${POSTGRES_DB}" \
    --from-literal="POSTGRES_USER=${POSTGRES_USER}" \
    --from-literal="POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

# --------------------------------------------------
# 7. Apply configuration
# --------------------------------------------------

echo "Applying ConfigMaps..."

kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/db-init-configmap.yaml

# --------------------------------------------------
# 8. Deploy PostgreSQL
# --------------------------------------------------

echo "Deploying PostgreSQL..."

kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/postgres-statefulset.yaml

echo "Waiting for PostgreSQL..."

kubectl rollout status \
    statefulset/postgres \
    -n loantrack \
    --timeout=180s

# --------------------------------------------------
# 9. Deploy backend
# --------------------------------------------------

echo "Deploying backend..."

kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/backend-deployment.yaml

echo "Waiting for backend..."

kubectl rollout status \
    deployment/backend \
    -n loantrack \
    --timeout=180s

# --------------------------------------------------
# 10. Deploy frontend
# --------------------------------------------------

echo "Deploying frontend..."

kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml

echo "Waiting for frontend..."

kubectl rollout status \
    deployment/frontend \
    -n loantrack \
    --timeout=180s

# --------------------------------------------------
# 11. Final status
# --------------------------------------------------

echo
echo "=== Deployment successful ==="
echo
kubectl get pods -n loantrack
echo
kubectl get services -n loantrack

echo
echo "Starting frontend access tunnel..."

URL_FILE="$(mktemp)"
minikube service frontend -n loantrack --url > "$URL_FILE" 2>/dev/null &
TUNNEL_PID=$!

for i in {1..15}; do
    if grep -q '^http://' "$URL_FILE"; then
        break
    fi
    sleep 1
done

FRONTEND_URL="$(grep '^http://' "$URL_FILE" | head -n 1)"

if [[ -z "$FRONTEND_URL" ]]; then
    echo "ERROR: Could not determine frontend URL."
    kill "$TUNNEL_PID" 2>/dev/null || true
    rm -f "$URL_FILE"
    exit 1
fi

echo "LoanTrack URL: $FRONTEND_URL"
echo
echo "Deployment is complete."
echo "Keep this terminal open while using the URL."

wait "$TUNNEL_PID"
rm -f "$URL_FILE"