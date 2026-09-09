**# LoanTrack — Evidence**

This document records the verification evidence for the LoanTrack SRE/DevOps assignment.

Terminal output is preferred where possible; UI screenshots are included as supporting evidence.

---

**## 1. Docker Compose Evidence**

**### 1.1 Three-tier stack**

Command:

```powershell

docker compose ps

```

Observed result:

```text

NAME                    IMAGE                   SERVICE    STATUS

loantrack-backend-1     loantrack-backend\:v1   backend    Up (healthy)

loantrack-frontend-1    loantrack-frontend\:v1   frontend   Up

loantrack-postgres-1    postgres:16             postgres   Up (healthy)

```

Ports observed:

- Frontend: `8081 -> 80`

- Backend: `8000 -> 8000`

- PostgreSQL: `5432` is internal to the Compose network

This verifies that the three tiers run together and PostgreSQL is not published to the host.

**### 1.2 Image size and non-root execution**

Command:

```powershell

docker images

```

Relevant images:

```text

loantrack-backend\:v1    289MB

loantrack-frontend\:v1   73.7MB

postgres:16             636MB

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

**### 1.3 Docker UI to database verification**

The Docker Compose application was opened at:

```text

http\://localhost:8081

```

A loan named `Docker Evidence` was added through the UI.

Direct PostgreSQL verification:

```powershell

docker compose exec postgres psql -U loantrack\_user -d loantrack -c "SELECT id, borrower\_name, loan\_amount, property\_city, status FROM loans ORDER BY id;"

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

---

**## 2.6 Backend database retry and recovery**

The backend retry behavior was tested by temporarily scaling PostgreSQL to zero and starting a fresh backend pod while the database was unavailable.

Commands:

```bash
kubectl scale statefulset postgres -n loantrack --replicas=0
kubectl scale deployment backend -n loantrack --replicas=1
```

The fresh backend pod logged repeated connection failures and exponential backoff:

```text
Attempt 1 failed connection refused ... retry 1s
Attempt 2 failed connection refused ... retry 2s
Attempt 3 failed connection refused ... retry 4s
Attempt 4 failed connection refused ... retry 8s
Attempt 5 failed connection refused ... retry 10s
Attempt 6 failed connection refused ... retry 10s
Attempt 7 failed connection refused ... retry 10s
Attempt 8 failed connection refused ... retry 10s
```

PostgreSQL was restored:

```bash
kubectl scale statefulset postgres -n loantrack --replicas=1
```

The backend recovered automatically. Its subsequent logs included:

```text
Application startup complete.
Uvicorn running on http://0.0.0.0:8000
```

Health/readiness requests subsequently returned HTTP 200. The backend was restored to 3 replicas after the test.

---

**## 2. Kubernetes Evidence**

**### 2.1 Cluster status**

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

**### 2.2 Application pods**

Command:

```powershell

kubectl get pods -n loantrack -o wide

```

Observed:

```text

backend     3/3 Running

frontend    1/1 Running

postgres-0  1/1 Running

```

All application workloads are deployed in the `loantrack` namespace.

**### 2.3 Services and workloads**

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

**### 2.4 Storage and configuration**

Command:

```powershell

kubectl get pvc,configmap,secret -n loantrack

```

Verified:

- PostgreSQL PVC: `Bound`, `1Gi`, `RWO`

- `loantrack-config` ConfigMap

- `loantrack-db-init` ConfigMap

- `loantrack-db-secret` Secret containing 3 data entries

Sensitive database values are supplied through the Kubernetes Secret rather than written as literals in the Deployment.

**### 2.5 Kubernetes database verification**

Schema inspection:

```powershell

kubectl exec -n loantrack postgres-0 -- psql -U loantrack\_user -d loantrack -c "\d loans"

```

The `loans` table contains:

- `id`

- `borrower\_name`

- `loan\_amount`

- `property\_city`

- `status`

- `created\_at`

Direct query:

```powershell

kubectl exec -n loantrack postgres-0 -- psql -U loantrack\_user -d loantrack -c "SELECT id, borrower\_name, loan\_amount, property\_city, status FROM loans ORDER BY id;"

```

At the time of evidence collection, 8 loans were present, including application-created records.

**### 2.6 Backend to PostgreSQL DNS/FQDN verification**

The backend was tested from inside the Kubernetes cluster using the PostgreSQL Service DNS name.

Command:

```bash
kubectl exec deployment/backend -n loantrack -- python -c "import socket; print(socket.gethostbyname('postgres.loantrack.svc.cluster.local'))"
```

Observed output:

```text
10.97.133.9
```

TCP connectivity was also verified:

```bash
kubectl exec deployment/backend -n loantrack -- python -c "import socket; s=socket.create_connection(('postgres.loantrack.svc.cluster.local', 5432), 5); print('TCP connection successful'); s.close()"
```

Observed output:

```text
TCP connection successful
```

Fully-qualified Kubernetes Service DNS name:

```text
postgres.loantrack.svc.cluster.local
```

The PostgreSQL Service is a ClusterIP and is therefore reachable by backend pods inside the cluster, but is not exposed outside the cluster.

**### 2.7 Kubernetes UI and HTTP verification**

The application was accessed using:

```powershell
minikube service frontend -n loantrack --url
```

One observed run returned:

```text
http://127.0.0.1:62439
```

The Minikube service tunnel must remain open when using the Windows Docker driver.

HTTP verification through the tunnel:

```bash
curl -i http://127.0.0.1:62439/healthz
```

Observed:

```text
HTTP/1.1 200 OK
Server: nginx/1.27.5
Content-Type: text/plain

ok
```

The loans endpoint was also verified:

```bash
curl -i http://127.0.0.1:62439/loans
```

Observed:

```text
HTTP/1.1 200 OK
Content-Type: application/json
x-pod-name: backend-87f46c7c9-wtzd7
```

The response contained the seeded/application-created loan records. The UI displayed the LoanTrack dashboard and loan records, and a loan was added successfully.

---

**## 3. Kubernetes Operations Evidence**

**### 3.1 Backend scaling**

The backend was scaled to 3 replicas.

Command:

```powershell
kubectl scale deployment backend -n loantrack --replicas=3
kubectl get deployment backend -n loantrack
kubectl get pods -n loantrack -l app=backend -o wide
```

Observed:

```text
backend   3/3   3   3

backend-87f46c7c9-nf4df   1/1   Running
backend-87f46c7c9-t72fs   1/1   Running
backend-87f46c7c9-wtzd7   1/1   Running
```

A request through the frontend returned:

```text
x-pod-name: backend-87f46c7c9-wtzd7
```

This confirms that the API response identifies the backend pod serving the request. Multiple backend pods were Running and the application was tested through the Service after scaling.

**### 3.2 Rolling update and rollback**

A `v2` backend image was built and deployed.

Command:

```powershell
kubectl rollout status deployment/backend -n loantrack
```

Observed:

```text
deployment "backend" successfully rolled out
```

Rollback was tested with:

```powershell
kubectl rollout undo deployment/backend -n loantrack
kubectl rollout status deployment/backend -n loantrack
```

The rollback completed successfully and the backend was subsequently restored to 3 replicas.

The Deployment uses:

```yaml
maxUnavailable: 0
maxSurge: 1
```

During a rolling update, users continue to have available backend capacity while replacement pods are brought up. `maxUnavailable: 0` prevents the Deployment from voluntarily reducing the number of available replicas during the rollout, while `maxSurge: 1` permits one additional replacement pod.

**### 3.3 Backend pod replacement**

A backend pod was deleted manually:

```powershell
kubectl delete pod backend-87f46c7c9-spfmg -n loantrack
kubectl get pods -n loantrack -l app=backend
```

The deleted pod was replaced by:

```text
backend-87f46c7c9-wtzd7   1/1   Running
```

The Deployment returned to 3 ready backend replicas.

**### 3.4 PostgreSQL pod replacement and persistence**

Before deletion, the database contained 8 loan records. The PostgreSQL pod was then deleted:

```powershell
kubectl delete pod postgres-0 -n loantrack
```

Kubernetes recreated `postgres-0`. After the replacement became Ready, the same 8 loan records were queried again and remained present. The PVC also remained Bound:

```text
postgres-data-postgres-0   Bound   1Gi   RWO
```

This verifies database persistence through PostgreSQL pod replacement.

**### 3.5 Required Kubernetes resource inventory**

Commands:

```powershell
kubectl get all -n loantrack
kubectl get pvc,configmap,secret -n loantrack
```

Final observed workload state:

```text
backend Deployment    3/3
frontend Deployment   1/1
postgres StatefulSet   1/1
backend Service       ClusterIP 10.109.228.181:8000
frontend Service      NodePort  80:30080
postgres Service      ClusterIP 10.97.133.9:5432
```

Storage/configuration included:

```text
postgres-data-postgres-0   Bound   1Gi   RWO
loantrack-config           ConfigMap
loantrack-db-init           ConfigMap
loantrack-db-secret         Secret (3 data entries)
```

---

**## 4. Docker Compose Persistence Evidence**

The Compose stack was stopped and started again.

The PostgreSQL named volume preserved the existing database state.

A separate:

```powershell

docker compose down -v

```

test was also performed. Removing the named volume removed the PostgreSQL state and caused the initialization SQL to run again with the seed records.

---

**## 5. Deployment Automation Evidence**

The project contains:

```text

scripts/deploy.sh

```

The script:

1\. Checks/starts Minikube.

2\. Loads local environment variables.

3\. Builds backend and frontend images inside Minikube.

4\. Applies the namespace and configuration.

5\. Creates/updates the Kubernetes Secret from environment variables.

6\. Applies PostgreSQL resources and waits for the StatefulSet rollout.

7\. Applies backend resources and waits for the Deployment rollout.

8\. Applies frontend resources and waits for the Deployment rollout.

9\. Prints pods, services, and the frontend URL.

Syntax check:

```bash

bash -n scripts/deploy.sh

```

The deployment script was run successfully more than once. Repeated execution completed successfully and the database records remained intact. A successful manual Minikube service tunnel was also verified at `http://127.0.0.1:62439`; the final script run that captures and prints the dynamically allocated tunnel URL should be retained as the E2 URL-printing evidence.

---

**## 6. Troubleshooting Evidence**

**### Problem 1 — Backend Docker image exceeded the size limit**

****Symptom****

The first backend image was approximately 390 MB, exceeding the required 300 MB limit.

****Diagnosis****

```powershell

docker images loantrack-backend

```

The Dockerfile was reviewed after confirming the oversized image.

****Root cause****

The original Dockerfile used a recursive ownership change that also affected the copied Python virtual environment.

****Fix****

The ownership command was changed to operate only on `/app`:

```dockerfile

RUN useradd --create-home appuser && \\

    chown -R appuser\:appuser /app

```

The image was rebuilt and verified at approximately 289 MB.

**### Problem 2 — Frontend could not resolve the backend container**

****Symptom****

During an early standalone Docker test, the frontend could not reach the backend using the backend service name.

****Diagnosis****

```powershell

docker network ls

docker network inspect <network-name>

docker exec <frontend-container> getent hosts backend

```

****Root cause****

The containers were initially tested on Docker's default bridge network, where the required service-name DNS behavior was not available.

****Fix****

A user-defined Compose network named `loantrack-network` was configured. The frontend communicates with the backend using the Compose service name instead of an IP address or `localhost`.

The final application worked through:

```text

http\://localhost:8081

```

**### Problem 3 — Frontend pod failed to start because Nginx could not resolve the backend Service**

**Symptom**

The frontend pod had previously restarted and showed:

```text
Last State: Terminated
Reason: Error
Exit Code: 1
Restart Count: 4
```

**Diagnosis**

The pod was inspected with:

```powershell
kubectl describe pod frontend-5cbbd7cdb7-8lskn -n loantrack
kubectl logs frontend-5cbbd7cdb7-8lskn -n loantrack --previous
```

The previous container log showed:

```text
[emerg] host not found in upstream "backend" in /etc/nginx/nginx.conf:39
nginx: [emerg] host not found in upstream "backend" in /etc/nginx/nginx.conf:39
```

The pod events were also checked. No liveness/startup/readiness probe failure event was present, so the initial probe-related hypothesis was disproved.

**Root cause**

Nginx failed during container startup because the `backend` upstream name could not be resolved at that moment.

**Fix**

The backend Service and its endpoints were verified, and the frontend was allowed to restart once Kubernetes networking was available. The frontend subsequently returned to `1/1 Running` and `/healthz` returned HTTP 200 through the Minikube tunnel.

**### Problem 4 — Backend database connection was refused during startup**

**Symptom**

PostgreSQL was temporarily scaled to zero while a fresh backend pod was started. The backend could not connect to PostgreSQL on port 5432.

**Diagnosis**

Commands used:

```powershell
kubectl scale statefulset postgres -n loantrack --replicas=0
kubectl scale deployment backend -n loantrack --replicas=1
kubectl get pods -n loantrack
kubectl logs <fresh-backend-pod> -n loantrack
```

The logs showed connection-refused errors and retry delays of 1, 2, 4, 8 and then 10 seconds.

**Root cause**

No PostgreSQL pod was available to accept connections on the PostgreSQL Service while the StatefulSet had zero replicas.

**Fix**

PostgreSQL was restored with:

```powershell
kubectl scale statefulset postgres -n loantrack --replicas=1
```

The backend recovered automatically without a rebuild or code change. It subsequently logged `Application startup complete` and health/readiness requests returned HTTP 200.

**### Problem 5 — Minikube backend image build failed**

**Symptom**

An early Minikube backend image build failed because the Dockerfile was not available in the build context.

**Diagnosis**

```powershell
minikube image build -t loantrack-backend:v1 ./backend
```

The backend `.dockerignore` file was then inspected.

**Root cause**

The backend `.dockerignore` incorrectly excluded `Dockerfile`.

**Fix**

The `Dockerfile` entry was removed from `backend/.dockerignore`. The image was rebuilt successfully with Minikube and the Kubernetes deployment then completed successfully.


**E4 integrity note:** The assignment asks for three real problems, including a probe killing a healthy container. No genuine probe-kill incident was observed in the collected Kubernetes events; the frontend probe hypothesis was investigated and disproved. This evidence therefore does not fabricate a probe failure.

---

**## 7. Security Evidence**

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

The backend source requires PostgreSQL configuration through environment variables and does not contain hard-coded database credential defaults.

---

**## 8. Evidence Screenshots**

The following screenshots are included as supporting visual evidence:

\| Screenshot | Purpose |

\|---|---|

\| `evidence/docker-compose.png` | Docker Compose services and health status |

\| `evidence/docker-ui.png` | LoanTrack UI running through Docker Compose |

\| `evidence/kubernetes-ui.png` | LoanTrack UI running through Kubernetes |

Terminal commands and outputs remain the primary evidence where possible.

---

**## 9. Evidence Summary**

The implemented LoanTrack system was verified in both environments:

```text

Docker Compose

  Frontend -> Backend -> PostgreSQL       PASS

Kubernetes

  Frontend -> Backend -> PostgreSQL       PASS

  Backend replicas = 3                    PASS

  PostgreSQL persistent storage           PASS

  Health/readiness probes                 PASS

  Non-root application containers         PASS

  Backend image < 300 MB                  PASS

  Kubernetes Service DNS                  PASS

  Rolling update and rollback             PASS

  Pod replacement                         PASS

  Database persistence after pod deletion PASS

  Deployment automation                   PASS

```