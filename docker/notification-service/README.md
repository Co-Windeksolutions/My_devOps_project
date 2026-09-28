## Docker

### Dockerfile Overview

Multi-stage build, identical structure to the other services:

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| `builder` | `python:3.11-slim` | Installs pip dependencies into `/opt/venv` |
| `runtime` | `python:3.11-slim` | Copies virtualenv + code; runs as `appuser` |

**Key design decisions:**

- **No database** — this is the only service with no PostgreSQL dependency. The image is smaller and has no migration step.
- **RabbitMQ consumer + HTTP server** — the container runs a single process that hosts both the FastAPI HTTP server (health check) and a background asyncio task consuming from RabbitMQ. There is no separate consumer process or sidecar.
- **Durable queue** — the consumer declares a durable, named queue (`notification.transfers`). Messages published while this pod is down are retained by RabbitMQ and delivered when it restarts.

### Build

```bash
docker build -t minibank-notifications .
```

### Run

```bash
docker run --rm -p 8003:8003 \
  -e RABBITMQ_URL=amqp://guest:guest@host.docker.internal:5672/ \
  minibank-notifications
```

### Exposed Port

| Port | Protocol | Description |
|------|----------|-------------|
| `8003` | HTTP | Uvicorn ASGI server (health endpoint only) |

### Runtime Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RABBITMQ_URL` | **Yes** (prod) | `amqp://guest:guest@localhost:5672/` | AMQP connection URL |
| `TRANSFER_EXCHANGE_NAME` | No | `transfers` | Must match the Wallet service publisher |
| `NOTIFICATION_QUEUE_NAME` | No | `notification.transfers` | Durable consumer queue name |

### Health Check

```bash
curl http://localhost:8003/health
# {"status": "ok"}
```

> [!NOTE]
> The health endpoint confirms the HTTP process is alive. It does **not** verify that the background RabbitMQ consumer task is running. If the consumer crashes, the pod stays up but stops processing events. A production enhancement would expose consumer liveness in this endpoint.

### How It Works Inside the Container

```
┌─────────────────────────────────────────────┐
│  Container (port 8003)                      │
│                                             │
│  ┌──────────────┐   ┌────────────────────┐  │
│  │ FastAPI HTTP  │   │ RabbitMQ Consumer  │  │
│  │  /health      │   │ (asyncio task)     │  │
│  └──────────────┘   └────────────────────┘  │
│         ▲                     ▲              │
│         │                     │              │
│    K8s probe            aio_pika robust     │
│                         connection          │
└─────────────────────────────────────────────┘
```

### Security Notes

- Runs as non-root (`appuser`, UID `1001`).
- No secrets beyond the RabbitMQ URL.
- No database — no migration step, no SQL injection surface.
- Tests excluded from the image.
- `prefetch_count=10` prevents the consumer from being overwhelmed by a burst of messages.