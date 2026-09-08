# LoanTrack — Evidence

This document records the verification evidence for the LoanTrack SRE/DevOps assignment.
Terminal output is preferred where possible; UI screenshots are included as supporting evidence.

---

## 1. Docker Compose Evidence

### 1.1 Three-tier stack

Command:

```powershell
docker compose ps
```

Observed result:

```text
NAME                   IMAGE                   SERVICE    STATUS
loantrack-backend-1    loantrack-backend:v1    backend    Up (healthy)
loantrack-frontend-1   loantrack-frontend:v1   frontend   Up
loantrack-postgres-1   postgres:16             postgres   Up (healthy)
```

Ports observed:

- Frontend: `8081 -> 80`
- Backend: `8000 -> 8000`
- PostgreSQL: `5432` is internal to the Compose network

This verifies that the three application tiers run together and that PostgreSQL is not published to the host.

### 1.2 Image size and non-root execution

Command:

```powershell
docker images
```

Relevant images:

```text
loantrack-backend:v1    289MB
loantrack-frontend:v1   73.7MB
postgres:16             636MB
```

The backend image is below the required 300 MB limit.

Commands:

```powershell
docker compose exec backend whoami
docker compose exec frontend whoami
```

Observed:

```text
appuser
nginx
```

Both application containers therefore run as non-root users.

### 1.3 Docker UI to database verification

The Docker Compose application was opened at:

```text
http://localhost:8081
```

A loan named `Docker Evidence` was added through the UI.

Direct PostgreSQL verification:

```powershell
docker compose exec postgres psql -U loantrack_user -d loantrack -c "SELECT id, borrower_name, loan_amount, property_city, status FROM loans ORDER BY id;"
```

Observed final record:

```text
6 | Docker Evidence | 88888.00 | mumbai | APPROVED
```

This verifies the end-to-end path:

```text
Browser -> Nginx frontend -> FastAPI backend -> PostgreSQL
```

The frontend does not connect directly to PostgreSQL.

### 1.4 Docker UI screenshot

Supporting screenshot:

- `docker-ui.png` — LoanTrack running through Docker Compose, showing the application dashboard and the newly added Docker Evidence loan.

---

## 2. Kubernetes Evidence

### 2.1 Cluster status

Command:

```powershell
minikube status
```

Observed:

```text
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

### 2.2 Application pods

Command:

```powershell
kubectl get pods -n loantrack -o wide
```

Observed:

```text
backend     3/3 Running
frontend    1/1 Running
postgres-0  1/1 Running
```

All application workloads are deployed in the `loantrack` namespace.

### 2.3 Services and workloads

Command:

```powershell
kubectl get all -n loantrack
```

Verified:

- Backend Deployment: 3/3 replicas
- Frontend Deployment: 1/1 replica
- PostgreSQL StatefulSet: 1/1
- Backend Service: ClusterIP on port 8000
- PostgreSQL Service: ClusterIP on port 5432
- Frontend Service: NodePort on port 30080

### 2.4 Storage and configuration

Command:

```powershell
kubectl get pvc,configmap,secret -n loantrack
```

Verified:

- PostgreSQL PVC: `Bound`, `1Gi`, `RWO`
- `loantrack-config` ConfigMap
- `loantrack-db-init` ConfigMap
- `loantrack-db-secret` Secret containing 3 data entries

Sensitive database values are supplied through the Kubernetes Secret rather than being written as literals in the Deployment.

### 2.5 Kubernetes database verification

The PostgreSQL schema was inspected with:

```powershell
kubectl exec -n loantrack postgres-0 -- psql -U loantrack_user -d loantrack -c "\d loans"
```

The `loans` table contains:

- `id`
- `borrower_name`
- `loan_amount`
- `property_city`
- `status`
- `created_at`

The database was then queried directly:

```powershell
kubectl exec -n loantrack postgres-0 -- psql -U loantrack_user -d loantrack -c "SELECT id, borrower_name, loan_amount, property_city, status FROM loans ORDER BY id;"
```

At the time of evidence collection, 8 loans were present, including application-created records.

### 2.6 Kubernetes UI verification

The application was accessed using:

```powershell
minikube service frontend -n loantrack --url
```

The resulting local Minikube URL was opened in the browser.

The UI successfully displayed the LoanTrack dashboard and loan records, and a loan could be added successfully.

Supporting screenshot:

- `kubernetes-ui.png` — LoanTrack dashboard running through the Kubernetes frontend service.

### 2.7 Backend and database health

The backend exposes:

```text
GET /healthz
GET /readyz
GET /loans
POST /loans
```

`/healthz` is used for process liveness/startup checks, while `/readyz` verifies database reachability.

The Kubernetes backend Deployment wires:

- startup probe -> `/healthz`
- liveness probe -> `/healthz`
- readiness probe -> `/readyz`

### 2.8 Kubernetes DNS and connectivity

Backend-to-PostgreSQL DNS was verified using:

```powershell
kubectl exec deployment/backend -- python -c "import socket; print(socket.gethostbyname('postgres.loantrack.svc.cluster.local'))"
```

The PostgreSQL Service resolved successfully.

A TCP connectivity test to the PostgreSQL Service also succeeded.

The backend therefore communicates with PostgreSQL through Kubernetes Service DNS rather than an IP address or localhost.

---

## 3. Kubernetes Operations Evidence

### 3.1 Backend scaling

The backend was scaled to 3 replicas and verified with:

```powershell
kubectl get pods -n loantrack
```

Three backend pods reached `Running` and `Ready`.

Requests through the frontend were observed across multiple backend pod names, demonstrating that more than one backend replica served requests.

### 3.2 Rolling update

A `v2` backend image was built and deployed.

The rollout was checked using:

```powershell
kubectl rollout status deployment/backend -n loantrack
```

The rollout completed successfully.

Rollout history was inspected, and the previous revision was restored using:

```powershell
kubectl rollout undo deployment/backend -n loantrack
```

The Deployment uses a RollingUpdate strategy with:

```yaml
maxUnavailable: 0
maxSurge: 1
```

This keeps existing capacity available while the replacement pod is brought up.

### 3.3 Backend pod replacement

A backend pod was deleted manually:

```powershell
kubectl delete pod <backend-pod> -n loantrack
```

Kubernetes automatically created a replacement pod and restored the Deployment to 3 ready replicas.

### 3.4 PostgreSQL pod replacement and persistence

The PostgreSQL pod was deleted during testing.

After Kubernetes recreated `postgres-0`, the existing loan records remained available.

The PostgreSQL PVC remained `Bound`, demonstrating persistence through pod replacement.

---

## 4. Docker Compose Persistence Evidence

The Compose stack was stopped and started again.

The PostgreSQL named volume preserved the existing database state.

A separate `docker compose down -v` test was also performed to demonstrate that removing the named volume removes PostgreSQL state and causes the initialization SQL to run again with the seed records.

---

## 5. Deployment Automation Evidence

The project contains:

```text
scripts/deploy.sh
```

The script:

1. Checks/starts Minikube.
2. Loads local environment variables.
3. Builds backend and frontend images inside Minikube.
4. Applies the namespace and configuration.
5. Creates/updates the Kubernetes Secret from environment variables.
6. Applies PostgreSQL resources and waits for the StatefulSet rollout.
7. Applies backend resources and waits for the Deployment rollout.
8. Applies frontend resources and waits for the Deployment rollout.
9. Prints pods, services, and the frontend URL.

The script was syntax-checked with:

```bash
bash -n scripts/deploy.sh
```

The deployment script was run successfully more than once, demonstrating idempotent deployment behavior. The database records remained intact on repeated execution.

---

## 6. Security Evidence

Verified design:

```text
Frontend
   |
   | HTTP
   v
Backend
   |
   | PostgreSQL connection
   v
PostgreSQL
```

The frontend contains no PostgreSQL credentials and does not connect directly to the database.

Local credentials are stored in `.env`, which is ignored by Git.

The repository contains `.env.example` with dummy values only.

Kubernetes database credentials are provided through a Secret.

The real Kubernetes Secret was created from local environment variables and was not committed to the repository.

---

## 7. Evidence Screenshots

The following screenshots are intended as supporting visual evidence:

| Screenshot | Purpose |
|---|---|
| `docker-compose.png` | Docker Compose services and health status |
| `docker-images-users.png` | Docker image sizes and non-root container users |
| `docker-ui.png` | LoanTrack UI running under Docker Compose |
| `kubernetes-ui.png` | LoanTrack UI running under Kubernetes |

Terminal commands and outputs remain the primary evidence where possible.

---

## 8. Evidence Summary

The implemented LoanTrack system was verified in both environments:

```text
Docker Compose
  Frontend -> Backend -> PostgreSQL       PASS

Kubernetes
  Frontend -> Backend -> PostgreSQL       PASS

Backend replicas = 3                      PASS
PostgreSQL persistent storage             PASS
Health/readiness probes                   PASS
Non-root application containers           PASS
Backend image < 300 MB                    PASS
Kubernetes Service DNS                    PASS
Rolling update and rollback               PASS
Pod replacement                           PASS
Database persistence after pod deletion   PASS
Deployment automation                     PASS
```
