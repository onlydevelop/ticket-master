# ticket-master

A deliberately minimal Ticketmaster-style booking system. Two Go microservices, one shared Postgres database, no extra infrastructure.

## Services

| Service | Port | Endpoints |
|---------|------|-----------|
| event-service | 8080 | `GET /events/{id}`, `GET /events/{id}/tickets`, `GET /events/search?q=` |
| booking-service | 8081 | `POST /bookings/reserve`, `POST /bookings/confirm`, `POST /bookings/pay` |

## How the no-double-booking guarantee works

The `reserve` handler opens a Postgres transaction and immediately issues `SELECT … FOR UPDATE` on the target ticket row. This row-level lock serializes concurrent attempts at the database level — when two requests race, one acquires the lock and proceeds; the other blocks until the first transaction commits. It then reads the updated status (`reserved`) and returns 409. No Redis distributed lock, no cron sweep, no external coordinator — just a single atomic read-modify-write inside a transaction.

Ticket states: `available → reserved` (10-minute hold) `→ booked` (after confirm).

## Run locally with Docker Compose

```bash
cd service
docker compose up --build
```

Then:
```bash
# Search events
curl "http://localhost:8080/events/search?q=concert"

# Get tickets for an event
curl "http://localhost:8080/events/<uuid>/tickets"

# Reserve a ticket
curl -X POST http://localhost:8081/bookings/reserve \
  -H "Content-Type: application/json" \
  -d '{"ticket_id":"<uuid>","user_id":"<uuid>"}'

# Confirm a pending reservation
curl -X POST http://localhost:8081/bookings/confirm \
  -H "Content-Type: application/json" \
  -d '{"booking_id":"<uuid>","user_id":"<uuid>"}'
```

The frontend dev server runs at http://localhost:5173.

## Run on Rancher Desktop (local k3s)

### Prerequisites

1. Rancher Desktop running with the `rancher-desktop` kubectl context active
2. A GitHub PAT with `read:packages` scope (to pull private GHCR images)

### One-time setup

```bash
# Create namespace and secrets
kubectl apply -f service/k8s/shared/namespace.yaml

kubectl -n ticket-master create secret generic db-credentials \
  --from-literal=password=secret \
  --from-literal=dsn="postgresql://ticketmaster:secret@postgres:5432/ticketmaster?sslmode=disable"

kubectl -n ticket-master create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=<GITHUB_USER> \
  --docker-password=<PAT_WITH_READ_PACKAGES>

# Load migration SQL into a ConfigMap so the migrate Job can mount them
kubectl -n ticket-master create configmap db-migrations \
  --from-file=service/migrations/
```

### Apply manifests

```bash
kubectl apply -f service/k8s/postgres/
kubectl apply -f service/k8s/shared/migrate-job.yaml
kubectl -n ticket-master wait --for=condition=complete job/db-migrate --timeout=60s
kubectl apply -f service/k8s/event-service/
kubectl apply -f service/k8s/booking-service/
```

Services are reachable via NGINX ingress at `http://localhost/events/...` and `http://localhost/bookings/...`.

## CI/CD

Pushing to `main` triggers `.github/workflows/ci.yml`:

1. **test** — runs `go test -race ./...` for both modules against a real Postgres (GitHub Actions service container). The concurrent double-booking test is included here.
2. **build-push** — builds ARM64 images and pushes them to GHCR tagged `latest` and `sha-<SHA>`.
3. **deploy** — creates/syncs k8s secrets and the migrations ConfigMap, deploys Postgres, runs the migration Job, then rolls out both services.

### GitHub secrets — where to put them

All secrets must be added as **Repository secrets**, not Environment secrets or Organization secrets.

Navigate to: **GitHub repo → Settings → Secrets and variables → Actions → Repository secrets → New repository secret**

| Secret | How to get the value |
|--------|----------------------|
| `KUBECONFIG_B64` | See below |
| `DB_PASSWORD` | Any password you choose — used for the Postgres `ticketmaster` user |
| `GHCR_PAT` | GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → New token → scope: `read:packages` only |

#### Generating KUBECONFIG_B64

The k3s API server TLS certificate must include the public hostname as a SAN. On the EC2 node, confirm `/etc/rancher/k3s/config.yaml` contains:

```yaml
tls-san:
  - ticket-master.onlydevelop.net
```

If not, add it and regenerate the certs:

```bash
sudo systemctl stop k3s
sudo mkdir -p /etc/rancher/k3s
echo "tls-san:" | sudo tee /etc/rancher/k3s/config.yaml
echo "  - ticket-master.onlydevelop.net" | sudo tee -a /etc/rancher/k3s/config.yaml
sudo rm -rf /var/lib/rancher/k3s/server/tls
sudo systemctl start k3s
sudo k3s kubectl get nodes   # wait until Ready
```

Then extract and base64-encode the kubeconfig:

```bash
sudo cat /etc/rancher/k3s/k3s.yaml \
  | sed 's/127.0.0.1/ticket-master.onlydevelop.net/' \
  | base64 -w 0
```

Paste the single-line output as the value of `KUBECONFIG_B64`.

The EC2 instance is provisioned by `terraform/`. Run `terraform apply` once; subsequent deploys are fully automated by CI.

## Troubleshooting

### `kubectl` connecting to `localhost:8080` instead of the cluster

`KUBECONFIG_B64` secret is missing or empty. Check **Settings → Secrets and variables → Actions** and confirm it appears under **Repository secrets** (not Environment secrets). Delete and recreate it if needed.

### `x509: certificate is valid for … not ticket-master.onlydevelop.net`

The k3s TLS cert doesn't cover the public hostname. Follow the "Generating KUBECONFIG_B64" steps above to regenerate the cert with the correct SAN, then update the secret.

### `exec format error` in pod logs

The Docker image architecture doesn't match the node. The EC2 instance is ARM64 (Graviton `t4g`); images must be built for `linux/arm64`. The CI workflow handles this automatically via QEMU — if you built images manually, add `GOARCH=arm64` to the `go build` command.

### `pq: SSL is not enabled on the server` in migration job logs

The database DSN is missing `?sslmode=disable`. The `db-credentials` secret in k8s must use:
```
postgresql://ticketmaster:<password>@postgres:5432/ticketmaster?sslmode=disable
```
CI creates this automatically from `DB_PASSWORD`. If you created the secret manually, recreate it with the `sslmode=disable` suffix.

### Migration job times out

Check logs and pod status:
```bash
sudo k3s kubectl -n ticket-master logs job/db-migrate --all-containers
sudo k3s kubectl -n ticket-master describe job db-migrate
```

Common causes: Postgres not yet ready (check `get pods`), missing `db-migrations` ConfigMap, or a bad DSN in the `db-credentials` secret.

### Services in `CrashLoopBackOff`

```bash
sudo k3s kubectl -n ticket-master get pods
sudo k3s kubectl -n ticket-master logs deployment/event-service
sudo k3s kubectl -n ticket-master logs deployment/booking-service
```

Common causes:
- `ImagePullBackOff` — `ghcr-pull-secret` missing or `GHCR_PAT` wrong/expired
- `exec format error` — wrong image architecture (see above)
- Database connection error — check `db-credentials` secret DSN

### `ImagePullBackOff`

The cluster can't pull from GHCR. Verify the `ghcr-pull-secret` exists:
```bash
sudo k3s kubectl -n ticket-master get secret ghcr-pull-secret
```

If missing, CI will create it on the next push. If present but still failing, the `GHCR_PAT` token may have expired — generate a new one and re-run the workflow.
