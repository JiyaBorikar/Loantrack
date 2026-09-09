# AI Usage

AI tools were used during the development of LoanTrack for planning,
implementation support, debugging, documentation, and verification.

| Task | Tool | What you accepted as-is | What you changed and why |
|---|---|---|---|
| Application structure and API design | ChatGPT | Initial implementation guidance | Reviewed the assignment requirements and manually tested `/loans`, `/healthz`, and `/readyz`. |
| PostgreSQL schema and seed data | ChatGPT | SQL structure guidance | Verified the schema and seed records directly using `psql`. |
| Backend Dockerfile | ChatGPT | Multi-stage Dockerfile structure | Changed ownership handling so only `/app` is recursively owned by the non-root user. This reduced the final image from approximately 390 MB to approximately 289 MB. |
| Frontend Dockerfile and Nginx | ChatGPT | Initial containerization guidance | Tested the Nginx configuration and verified that the frontend runs as the non-root `nginx` user. |
| Docker Compose | ChatGPT | Compose structure and health-check guidance | Verified service-name networking, health checks, dependency ordering, named PostgreSQL volume, and frontend access. |
| Kubernetes manifests | ChatGPT | Initial manifest structure | Tested probes, resources, Services, StatefulSet, PVC, ConfigMap, Secret, scaling, rolling updates, pod replacement, and database persistence. |
| Kubernetes deployment script | ChatGPT | Initial automation guidance | Implemented and tested `scripts/deploy.sh`, including image builds, manifest application, rollout waits, and repeated deployment. The frontend URL behavior was adjusted based on the actual Windows + Minikube Docker-driver behavior. |
| Documentation | ChatGPT | Initial documentation structure | Reviewed the documentation against the actual implementation and testing results. |
| Evidence collection | ChatGPT | Suggestions for useful verification commands | Executed the commands manually and captured the actual Docker and Kubernetes outputs. |

## Examples of AI mistakes or misleading suggestions

AI-generated suggestions were treated as starting points rather than automatically
correct solutions. Several issues were discovered through actual testing.

1. The backend Docker image initially exceeded the required 300 MB limit because
ownership changes were applied too broadly. Reviewing the built image showed the
problem, so the Dockerfile was changed to apply ownership only to `/app`. The
resulting backend image was verified at approximately 289 MB.

2. The frontend initially had networking problems when tested outside the
intended Compose network. The configuration was corrected to use the
user-defined Compose network and Docker service-name DNS instead of relying on
localhost or container IP addresses.

3. During Kubernetes frontend troubleshooting, a restart was initially
suspected to be related to probe behavior. `kubectl describe`, pod events, and
`kubectl logs --previous` were used to verify the actual cause. The previous
container logs showed Nginx failing with `host not found in upstream "backend"`,
while the pod events did not show a probe failure. This demonstrated why actual
Kubernetes logs and events were necessary instead of assuming that the probe
configuration was the root cause.

All generated configuration was therefore validated by running the application,
checking container and pod status, inspecting logs and events, testing endpoints,
and verifying database persistence.