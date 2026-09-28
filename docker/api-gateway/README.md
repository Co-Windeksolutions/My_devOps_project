## Docker

### Dockerfile Overview

The Dockerfile uses a **multi-stage build** to keep the runtime image small and secure:

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| `builder` | `python:3.11-slim` | Creates a virtualenv and installs all pip dependencies |
| `runtime` | `python:3.11-slim` | Copies only the built virtualenv — no pip, no build tools |

**Key design decisions:**

- **Virtualenv isolation** — dependencies are installed into `/opt/venv` in the builder stage and copied wholesale into the runtime stage. This avoids carrying pip, setuptools, and wheel in the final image.
- **Non-root user** — a dedicated `app` user (UID/GID `1001`) runs the process. The application files are `COPY --chown`'d so no extra `chmod` layer is needed.
- **No `.env` in the image** — the [`.dockerignore`](.dockerignore) excludes `.env` files. All configuration is injected via environment variables at runtime (K8s ConfigMaps / Secrets in the cluster).

### Build

```bash
docker build -t minibank-api-gateway .
```

### Run

```bash
docker run --rm -p 8000:8000 \
  -e IAM_SERVICE_URL=http://host.docker.internal:8001 \
  -e WALLET_SERVICE_URL=http://host.docker.internal:8002 \
  minibank-api-gateway
```

> [!IMPORTANT]
> Use `host.docker.internal` on Docker Desktop (macOS/Windows). On Linux, use `--network host` or the host's IP address to reach services running outside the container.

### Exposed Port

| Port | Protocol | Description |
|------|----------|-------------|
| `8000` | HTTP | Uvicorn ASGI server |

### Runtime Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `IAM_SERVICE_URL` | No | `http://localhost:8001` | Base URL for the IAM service |
| `WALLET_SERVICE_URL` | No | `http://localhost:8002` | Base URL for the Wallet service |
| `RATE_LIMIT_REGISTER` | No | `10/minute` | slowapi rate limit for `/auth/register` |
| `RATE_LIMIT_LOGIN` | No | `20/minute` | slowapi rate limit for `/auth/login` |
| `HTTP_TIMEOUT` | No | `10.0` | Timeout (seconds) for outbound requests to downstream services |

### Health Check

```bash
curl http://localhost:8000/health
# {"status": "ok"}
```

Suitable as a Kubernetes **liveness probe**. The gateway has no database, so liveness equals readiness.

### Security Notes

- Runs as non-root (`app`, UID `1001`).
- Tests are excluded from the image via `.dockerignore` to reduce attack surface.
- No secrets are baked into the image — `JWT_SECRET_KEY` is never needed here (token validation is delegated to IAM via HTTP).
- Rate limit counters are in-memory and **not shared across replicas**. Use Redis-backed storage for production multi-replica deployments.

### Image Size Optimisation

- Multi-stage build drops pip and build artifacts.
- `--no-cache-dir` prevents pip from writing a cache layer.
- `.dockerignore` excludes tests, venvs, git metadata, and IDE files.