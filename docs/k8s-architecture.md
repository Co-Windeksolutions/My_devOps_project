# Kubernetes Architecture — MiniBank

This document explains how the four MiniBank microservices, the Ingress, ConfigMaps, Secrets, and Helm-deployed infrastructure dependencies are connected inside the `minibank` Kubernetes namespace.

---

## Traffic Flow Diagram

```
                        [ Internet / Users ]
                                 │
                    HTTP :80 via AWS ALB
                                 │
                                 ▼
              ┌──────────────────────────────────┐
              │   Ingress: minibank-ingress       │
              │   ingressClassName: alb           │
              │   path: / → api-gateway-service   │
              └──────────────┬───────────────────┘
                             │ ClusterIP :8000
                             ▼
              ┌──────────────────────────────────┐
              │   Service: api-gateway-service    │
              │   type: ClusterIP                 │
              └──────────────┬───────────────────┘
                             │
              ┌──────────────▼───────────────────┐
              │   Deployment: api-gateway         │
              │   replicas: 3, SA: api-gateway-sa │
              │   ConfigMap: api-gateway-config   │
              └──────┬───────────────────────────┘
                     │ HTTP (internal CoreDNS)
       ┌─────────────┼──────────────┐
       │             │              │
       ▼             ▼              ▼
  iam-service  wallet-ledger  notification-service
  :8000        -service :8000  :8000
       │             │              ▲
       │             │  RabbitMQ    │
       ▼             ▼   events     │
  Deployment:  Deployment:    Deployment:
  iam-service  wallet-ledger  notification-service
  SA: iam-sa   SA:wallet-     SA: notification-sa
               ledger-sa
       │             │              │
       ▼             ▼              ▼
  iam-config   wallet-ledger  notification-config
  iam-secret   -config        notification-secret
               wallet-ledger
               -secret
       │             │
       └──────┬──────┘
              ▼
   postgresql.minibank.svc.cluster.local:5432
   (Helm release: postgresql, bitnami/postgresql)
   Databases: iam_db, wallet_db
              │
              ▼
   rabbitmq.minibank.svc.cluster.local:5672
   (Helm release: rabbitmq, bitnami/rabbitmq)
   Queue: notifications.events
   Exchange: minibank.transfers
```

---

## Component Breakdown

### Namespace

All resources live in the `minibank` namespace, defined in `namespace.yaml`. This isolates platform workloads from `kube-system` and any other tenants on the cluster.

---

### Ingress

**File:** `ingress/ingress.yaml`

A single `Ingress` resource acts as the platform's single external entry point. It uses the AWS Application Load Balancer (ALB) controller (`ingressClassName: alb`) and is configured as `internet-facing` so the ALB gets public IPs in the VPC's public subnets.

All incoming HTTP traffic on port 80 is routed to `api-gateway-service:8000`. There is no Route53 or custom domain — the cluster is accessed via the ALB's auto-generated AWS DNS name (e.g. `k8s-minibank-xxxxx.us-east-1.elb.amazonaws.com`). This was a deliberate decision documented in the project roadmap.

The `alb.ingress.kubernetes.io/target-type: ip` annotation instructs the ALB to route directly to pod IPs across AZs rather than bouncing through NodePort, which reduces latency and hop count.

---

### Services

**Files:** `services/`

All four microservices use `ClusterIP` Services — they are only reachable inside the cluster. No service exposes a `NodePort` or `LoadBalancer` type directly. Only the API Gateway is reachable externally, and only via the Ingress above.

| Service | DNS name (inside cluster) | Port | Consumers |
|---|---|---|---|
| `api-gateway-service` | `api-gateway-service.minibank.svc.cluster.local` | 8000 | Ingress |
| `iam-service` | `iam-service.minibank.svc.cluster.local` | 8000 | API Gateway |
| `wallet-ledger-service` | `wallet-ledger-service.minibank.svc.cluster.local` | 8000 | API Gateway |
| `notification-service` | `notification-service.minibank.svc.cluster.local` | 8000 | Health/metrics only |

The Notification service is an async queue consumer and does not serve traffic from the API Gateway. Its Service exists solely to expose the health check endpoint (`/health/liveness`, `/health/readiness`) for Kubernetes probes, and the `/metrics` endpoint for Prometheus scraping in Phase 6.

---

### Deployments

**Files:** `deployments/`

One `Deployment` per microservice. All deployments share these properties:

- **Namespace:** `minibank`
- **Replicas:** 2–3, spread across AZs via `topologySpreadConstraints` with `topologyKey: topology.kubernetes.io/zone`
- **ServiceAccount:** a dedicated, scoped ServiceAccount per service (not the `default` SA)
- **Security context:** `runAsNonRoot: true`, `runAsUser: 10001`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ALL`
- **Probes:** both `livenessProbe` and `readinessProbe` on `/health/liveness` and `/health/readiness`
- **Config delivery:** all configuration mounted as volume files, not environment variables (see ConfigMaps/Secrets below)

**IAM and Wallet/Ledger** also have an `initContainer` that runs Alembic database migrations (`alembic upgrade head`) before the main application container starts. This means the running application never needs DDL permissions on the database. If migrations fail, the pod does not start.

**Notification** has no `initContainer` because it has no database schema to manage.

---

### ConfigMaps

**Files:** `configmaps/`

Each service has a dedicated ConfigMap containing a `config.yaml` key, mounted as a file at `/etc/minibank/config/config.yaml` inside the container. Services read their configuration from this file path — no environment variables are used for configuration.

| ConfigMap | Mounted in | Contains |
|---|---|---|
| `api-gateway-config` | API Gateway | Downstream service URLs, rate limiting, timeouts |
| `iam-config` | IAM | DB host/port/name, server settings |
| `wallet-ledger-config` | Wallet/Ledger | DB host/port/name, RabbitMQ broker host/exchange |
| `notification-config` | Notification | RabbitMQ broker host/queue, mock notification settings |
| `postgres-initdb-scripts` | Postgres Helm (initdb) | SQL script that creates `wallet_db` on first boot |

**Why files instead of environment variables:** Environment variables in Kubernetes are readable via `/proc/<pid>/environ` by any process with access to the pod, and are often captured in crash dumps and logs. Mounted files can be read on-demand by the application and are not broadcast to the process environment. This matches the roadmap's explicit requirement.

---

### Secrets

**Files:** `secrets/`

Secrets follow the same volume-mount pattern as ConfigMaps. Each is mounted at `/etc/minibank/secrets/` and contains JSON-formatted credential files the application reads at startup.

| Secret | Mounted in | Contains |
|---|---|---|
| `iam-secret` | IAM | `db-credentials.json`, `jwt-secret-key` |
| `wallet-ledger-secret` | Wallet/Ledger | `db-credentials.json`, `broker-credentials.json` |
| `notification-secret` | Notification | `broker-credentials.json` |
| `postgres-credentials` | Postgres Helm | `password`, `postgres-password` (Bitnami chart keys) |
| `rabbitmq-credentials` | RabbitMQ Helm | `rabbitmq-password`, `rabbitmq-erlang-cookie` (Bitnami chart keys) |

> **Important:** The Secret manifests in this repo use `stringData` with placeholder values (`CHANGE_ME_...`). In production (Phase 6), these are replaced with Sealed Secrets or AWS Secrets Manager references — plaintext credentials must never be committed to Git.

---

### Helm-Deployed Dependencies

**Files:** `helm-values/`

PostgreSQL and RabbitMQ are deployed as Bitnami Helm charts, not as custom manifests. The application services connect to them using Kubernetes internal CoreDNS names that are derived from the Helm release name.

**Release names are fixed contracts.** The ConfigMaps hard-code:
- `postgresql.minibank.svc.cluster.local:5432` — requires `helm install postgresql ...`
- `rabbitmq.minibank.svc.cluster.local:5672` — requires `helm install rabbitmq ...`

See `README.md` for the exact install commands.

**PostgreSQL:** A single release serves two databases. `iam_db` is created by the chart automatically. `wallet_db` is created by the SQL init script in `postgres-initdb-configmap.yaml`, which the chart runs once on first boot via `primary.initdb.scriptsConfigMap`.

**RabbitMQ:** A single release serves both Wallet/Ledger (publisher) and Notification (consumer). Wallet/Ledger publishes transfer events to the `minibank.transfers` exchange with routing key `transfer.completed`. Notification consumes from the `notifications.events` queue.

---

### RBAC

**Files:** `rbac/`

Four ServiceAccounts, one per microservice, all with `automountServiceAccountToken: false`. This means no Kubernetes API token is mounted into any pod — the microservices are FastAPI applications that do not need to call the Kubernetes API.

Each ServiceAccount has an explicit Role and RoleBinding with empty rules, making the zero-permission grant an auditable declaration rather than an implicit gap. A separate `minibank-operator-role` gives the `devops-engineers` group read-only visibility into pods, services, configmaps, deployments, and replicasets in the `minibank` namespace.
