# LoanTrack

LoanTrack is a three-tier application consisting of:

- Frontend
- Backend API
- PostgreSQL database

The application is packaged with Docker Compose and deployed to a local
Kubernetes cluster using Minikube.

## Tools and Versions

| Tool | Version |
|---|---|
| Docker | 28.4.0 |
| Docker Compose | v2.39.2-desktop.1 |
| Minikube | v1.37.0 |
| kubectl | v1.32.2 |
| Kubernetes | v1.34.0 |
| Python | 3.10.0 |

The backend container uses Python 3.12.

## Architecture

```text
                         Browser
                            |
                            | HTTP
                            v
                  +-------------------+
                  |     Frontend      |
                  |   Nginx :80       |
                  | NodePort :30080   |
                  +---------+---------+
                            |
                            | HTTP /loans
                            v
                  +-------------------+
                  |      Backend      |
                  | FastAPI :8000     |
                  |   3 replicas      |
                  +---------+---------+
                            |
                            | PostgreSQL :5432
                            v
                  +-------------------+
                  |    PostgreSQL     |
                  |    StatefulSet    |
                  |    Persistent PVC |
                  +-------------------+
```

The frontend communicates with the backend over HTTP. The frontend never
connects directly to PostgreSQL.

In Kubernetes, the frontend is exposed through a NodePort. The backend and
PostgreSQL use ClusterIP services.

## Docker Compose

### Prerequisites

- Docker
- Docker Compose

### Run

Create the local environment file from the example:

```bash
cp .env.example .env
```

Start the application:

```bash
docker compose up -d
```

Open the frontend:

```text
http://localhost:8081
```

The backend is available at:

```text
http://localhost:8000
```

PostgreSQL is not exposed to the host. Services communicate using Docker
service names on the user-defined Compose network.

Stop the application:

```bash
docker compose down
```

The PostgreSQL named volume is preserved.

To remove the database data as well:

```bash
docker compose down -v
```

## Kubernetes

### Prerequisites

- Docker
- Minikube
- kubectl

### Start Minikube

```bash
minikube start --driver=docker --cpus=2 --memory=4096
```

### Build Images

```bash
minikube image build -t loantrack-backend:v2 ./backend
minikube image build -t loantrack-frontend:v1 ./frontend
```

### Create the Database Secret

The real Kubernetes Secret is created locally and is not committed to Git.

Create the namespace:

```bash
kubectl create namespace loantrack
```

Create the Secret using your local database values:

```bash
kubectl create secret generic loantrack-db-secret \
  --namespace=loantrack \
  --from-literal=POSTGRES_DB=<database> \
  --from-literal=POSTGRES_USER=<username> \
  --from-literal=POSTGRES_PASSWORD=<password>
```

A dummy example is provided in:

```text
k8s/secret.example.yaml
```

### Deploy

Apply the manifests in dependency order:

```bash
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/db-init-configmap.yaml

kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/postgres-statefulset.yaml

kubectl rollout status statefulset/postgres -n loantrack

kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/backend-deployment.yaml

kubectl rollout status deployment/backend -n loantrack

kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml

kubectl rollout status deployment/frontend -n loantrack
```

Open the application:

```bash
minikube service frontend -n loantrack --url
```

Alternatively, the complete deployment can be performed using:

```bash
./scripts/deploy.sh
```

The deployment script builds the images into Minikube, applies the manifests
in order, waits for rollouts, and can be run repeatedly without duplicating
database data.

## Design Decisions

- **Backend base image:** `python:3.12-slim` provides the required Python runtime while keeping the image smaller than a full Python image.
- **Layer-cache boundary:** `requirements.txt` is copied and dependencies are installed before the application source, so source changes reuse the dependency layer.
- **PostgreSQL workload:** PostgreSQL uses a StatefulSet with a `volumeClaimTemplate` because it is a stateful workload that requires persistent storage.
- **Liveness vs readiness:** `/healthz` checks whether the backend process is alive, while `/readyz` checks database connectivity so an unhealthy dependency prevents traffic without causing an unnecessary restart.
- **Memory vs CPU limits:** Exceeding a container's memory limit can cause it to be killed, while exceeding its CPU limit results in CPU throttling rather than an immediate kill.
- **Kubernetes Secret security:** Secret values are base64-encoded for representation, not encrypted; in production I would use a managed secret-management solution such as a cloud secret manager or Vault with appropriate access controls and encryption.

### Probe Timing Justification

The backend startup probe uses `periodSeconds: 5`, `timeoutSeconds: 3`, and
`failureThreshold: 18`, giving approximately 90 seconds for startup. This is
intentional because the backend retries its PostgreSQL connection with
exponential backoff during startup.

The backend readiness probe uses `/readyz` with `periodSeconds: 5`,
`timeoutSeconds: 3`, and `failureThreshold: 3`. This prevents a backend that
cannot reach PostgreSQL from receiving application traffic while allowing the
process to remain running and continue recovering.

The backend liveness probe uses `/healthz` with `periodSeconds: 10`,
`timeoutSeconds: 3`, and `failureThreshold: 3`. It checks process health
independently of PostgreSQL so a database outage does not unnecessarily restart
the backend.

The frontend startup probe uses `periodSeconds: 5`, `timeoutSeconds: 3`, and
`failureThreshold: 12`, giving approximately 60 seconds for Nginx to start.
Its readiness probe uses `/healthz` with `periodSeconds: 5`, `timeoutSeconds: 3`,
and `failureThreshold: 3`. Its liveness probe uses `/healthz` with
`periodSeconds: 10`, `timeoutSeconds: 3`, and `failureThreshold: 3`.

## Security

Real credentials are stored only in the local git-ignored `.env` file for
Docker Compose and in a Kubernetes Secret for the cluster.

No real credentials are stored in source code, Docker images, or committed
Kubernetes manifests.

## Project Structure

```text
loantrack/
├── backend/
├── frontend/
├── db/
│   └── migrations/
├── k8s/
├── scripts/
├── .env.example
├── .gitignore
├── docker-compose.yml
├── BRANCHING.md
├── EVIDENCE.md
└── AI_USAGE.md
```

## Additional Documentation

- `BRANCHING.md` — Git branching strategy.
- `EVIDENCE.md` — Commands, outputs, and screenshots demonstrating the Docker and Kubernetes requirements.
- `AI_USAGE.md` — AI tools used during the assignment and changes made to AI-generated work.
