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
# Wait for migration to complete
kubectl -n ticket-master wait --for=condition=complete job/db-migrate --timeout=60s
kubectl apply -f service/k8s/event-service/
kubectl apply -f service/k8s/booking-service/
```

Services are reachable via Traefik at `http://localhost/events/...` and `http://localhost/bookings/...`.

## CI/CD

Pushing to `main` triggers `.github/workflows/ci.yml`:

1. **test** — runs `go test -race ./...` for both modules against a real Postgres (GitHub Actions service container). The concurrent double-booking test is included here.
2. **build-push** — builds and pushes both images to GHCR tagged `latest` and `sha-<SHA>`.
3. **deploy** — creates/syncs k8s secrets and the migrations ConfigMap, deploys Postgres, runs the migration Job, then rolls out both services.

### Required GitHub secrets

| Secret | Value |
|--------|-------|
| `KUBECONFIG` | Contents of `/etc/rancher/k3s/k3s.yaml` on the EC2 node, with `127.0.0.1` replaced by the server's public hostname |
| `DB_PASSWORD` | Postgres password for the cluster |
| `GHCR_PAT` | GitHub PAT with `read:packages` scope (so k3s can pull images from GHCR) |

Extract the kubeconfig after the server is provisioned:

```bash
ssh ubuntu@ticket-master.onlydevelop.net \
  "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed 's/127.0.0.1/ticket-master.onlydevelop.net/'
```

The EC2 instance is provisioned by `terraform/`. Run `terraform apply` once; subsequent deploys are fully automated by CI.

## Out of scope (below the line)

The following are explicitly not built. They are valid v2 additions but would increase complexity without demonstrating new correctness properties at this scale:

- **Virtual waiting queue** — for high-demand events; adds a Redis queue + SSE fan-out
- **Elasticsearch** — replaced here by Postgres full-text search (tsvector/GIN), which is sufficient at this scale
- **Redis distributed lock** — `SELECT … FOR UPDATE` is simpler and correct for a single-DB setup
- **CDC pipeline / Debezium** — not needed without event sourcing or a separate read model
- **SSE real-time seat map updates** — would require a pub/sub layer
- **Real payment gateway** — `POST /bookings/pay` is a stub; integrate Stripe/Razorpay in v2
- **Dynamic pricing** — simple fixed `price_cents` per ticket
