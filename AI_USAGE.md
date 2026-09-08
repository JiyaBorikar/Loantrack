# AI Usage

AI assistance was used during the development of LoanTrack for planning,
implementation support, debugging, documentation, and verification.

| Task | AI assistance | Accepted as-is? | Changes / verification |
|---|---|---|---|
| Application structure and API design | Used for initial implementation guidance | No | Reviewed the API requirements and tested `/loans`, `/healthz`, and `/readyz` manually |
| PostgreSQL schema and seed data | Used for SQL structure guidance | Partly | Verified the schema and seed records directly using `psql` |
| Backend Dockerfile | Used for multi-stage Dockerfile guidance | No | Adjusted ownership so only application files are changed, reducing the final image below 300 MB |
| Frontend Dockerfile and Nginx | Used for containerization guidance | Partly | Tested Nginx configuration and verified the frontend runs as the non-root `nginx` user |
| Docker Compose | Used for Compose structure and health-check guidance | Partly | Verified service-name networking, health checks, dependency ordering, named PostgreSQL volume, and frontend access |
| Kubernetes manifests | Used for initial manifest guidance | No | Tested probes, resources, Services, StatefulSet, PVC, ConfigMap, Secret, scaling, rolling updates, and pod replacement |
| Kubernetes deployment script | Used for automation guidance | No | Implemented and tested `scripts/deploy.sh`, including image builds, resource application, rollout waits, and idempotent redeployment |
| Documentation | Used for drafting and organization | No | Reviewed the documentation against the actual implementation and testing results |
| Evidence collection | Used for deciding useful verification commands | No | Executed the commands manually and captured Docker/Kubernetes application evidence |

## Examples of AI mistakes or misleading suggestions

AI-generated suggestions were treated as starting points rather than automatically
correct solutions. Several issues were discovered through actual testing.

1. The backend Docker image initially exceeded the required 300 MB limit because
   ownership changes were applied too broadly. The Dockerfile was changed so that
   ownership is applied only to the application directory. The resulting backend
   image was verified at approximately 289 MB.

2. The frontend initially had networking problems when tested outside the intended
   Compose network. The configuration was corrected to use the Compose user-defined
   network and Docker service-name DNS rather than relying on localhost or container
   IP addresses.

3. During Kubernetes testing, the frontend temporarily entered `CrashLoopBackOff`
   after Minikube/Docker restarted. Logs and pod events showed startup-probe
   connection-refused errors while the container was starting. The pod subsequently
   recovered and became Ready, demonstrating why actual Kubernetes logs and events
   were used instead of assuming a configuration problem.

All generated configuration was therefore validated by running the application,
checking container/pod status, inspecting logs, testing endpoints, and verifying
database persistence.