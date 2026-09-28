## Docker

### Dockerfile Overview

Multi-stage build with an **extra build-time validation step** unique to this service:

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| `builder` | `python:3.11-slim` | Installs pip dependencies into `/opt/venv` |
| `runtime` | `python:3.11-slim` | Copies virtualenv + code, **validates Alembic assets**, runs as `appuser` |

**Key design decisions:**

- **Alembic build-time check** — the Dockerfile includes a `RUN test -f alembic.ini && test -d alembic` guard that **fails the build** if the migration directory or config is missing. This catches `.dockerignore` misconfigurations early, since the K8s initContainer depends on these files being present at runtime.
- **Dual external dependencies** — this is the only service that connects to both PostgreSQL *and* RabbitMQ. Both connection URLs must be provided at runtime.
- **Non-root user** — `appuser` (UID `1001`), consistent with IAM and Notification services.

### Build

```bash
docker build -t minibank-wallet .
```

> [!WARNING]
> The build will **fail** if `alembic.ini` or the `alembic/` directory is missing from the build context. This is intentional — the K8s initContainer runs `alembic upgrade head` against this image.

### Run

```bash
docker run --rm -p 8002:8002 \
  -e DATABASE_URL=postgresql+asyncpg://wallet_user:wallet_pass@host.docker.internal:5432/wallet_db \
  -e RABBITMQ_URL=amqp://guest:guest@host.docker.internal:5672/ \
  minibank-wallet
```

### Exposed Port

| Port | Protocol | Description |
|------|----------|-------------|
| `8002` | HTTP | Uvicorn ASGI server |

### Runtime Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | **Yes** (prod) | `postgresql+asyncpg://wallet_user:wallet_pass@localhost:5432/wallet_db` | Async PostgreSQL connection string |
| `RABBITMQ_URL` | **Yes** (prod) | `amqp://guest:guest@localhost:5672/` | AMQP connection URL |
| `TRANSFER_EXCHANGE_NAME` | No | `transfers` | Must match the Notification service consumer |

### Health & Readiness Checks

| Endpoint | K8s Probe | What It Checks |
|----------|-----------|----------------|
| `GET /health` | Liveness | Process is up (no external calls) |
| `GET /ready` | Readiness | `SELECT 1` against PostgreSQL succeeds |

### Database Migrations

```yaml
initContainers:
  - name: migrate
    image: minibank-wallet:latest
    command: ["alembic", "upgrade", "head"]
    env:
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: wallet-secrets
            key: database-url
```

For local development, the app auto-creates tables on startup (`Base.metadata.create_all`). **Do not rely on this in production** — always run Alembic migrations.

### Security Notes

- Runs as non-root (`appuser`, UID `1001`).
- Financial transfers use `SELECT ... FOR UPDATE` row-level locking to prevent double-spend race conditions.
- RabbitMQ messages are published with `DeliveryMode.PERSISTENT` to survive broker restarts.
- Tests excluded from the image.
- No JWT handling — this service trusts `X-User-Id` / `X-User-Role` headers set by the API Gateway.

### Architecture Note

```
API Gateway ──HTTP──▶ Wallet Service ──AMQP──▶ RabbitMQ ──▶ Notification Service
                           │
                           ▼
                       PostgreSQL
                    (accounts + ledger)
```

Transfer flow inside the container:
1. Lock sender & receiver rows (`FOR UPDATE`)
2. Validate KYC + balance
3. Update balances + write ledger entries (single atomic commit)
4. Publish `transfer.completed` event to RabbitMQ (after commit)