## Docker

### Dockerfile Overview

Multi-stage build with two stages:

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| `builder` | `python:3.11-slim` | Installs pip dependencies (incl. bcrypt C extension) into `/opt/venv` |
| `runtime` | `python:3.11-slim` | Copies the virtualenv + application code; runs as `appuser` |

**Key design decisions:**

- **Non-root user** — `appuser` (UID `1001`) in group `appgroup` (GID `1001`). The UID/GID is a deployed contract — do not change it without updating K8s SecurityContext and volume ownership.
- **Alembic included** — unlike some services, IAM bundles `alembic.ini` and the `alembic/` directory into the image. The K8s initContainer runs `alembic upgrade head` against this image before the main container starts.
- **No home directory** — `--no-create-home` and `--shell /bin/false` reduce the user's footprint. The app writes nothing to `$HOME`.

### Build

```bash
docker build -t minibank-iam .
```

### Run

```bash
docker run --rm -p 8001:8001 \
  -e DATABASE_URL=postgresql+asyncpg://iam_user:iam_pass@host.docker.internal:5432/iam_db \
  -e JWT_SECRET_KEY=replace-me-in-production \
  minibank-iam
```

> [!CAUTION]
> Never use the default `JWT_SECRET_KEY` in a deployed environment. Pass a strong, randomly generated secret via a K8s Secret or vault integration.

### Exposed Port

| Port | Protocol | Description |
|------|----------|-------------|
| `8001` | HTTP | Uvicorn ASGI server |

### Runtime Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | **Yes** (prod) | `postgresql+asyncpg://iam_user:iam_pass@localhost:5432/iam_db` | Async PostgreSQL connection string |
| `JWT_SECRET_KEY` | **Yes** (prod) | `changeme-in-production` | HMAC signing key for HS256 JWTs |
| `JWT_ALGORITHM` | No | `HS256` | JWT signing algorithm |
| `JWT_EXPIRY_MINUTES` | No | `60` | Token lifetime in minutes |
| `BCRYPT_ROUNDS` | No | `12` | bcrypt work factor (OWASP minimum: 12) |

### Health & Readiness Checks

| Endpoint | K8s Probe | What It Checks |
|----------|-----------|----------------|
| `GET /health` | Liveness | Process is up (no DB call) |
| `GET /ready` | Readiness | `SELECT 1` against PostgreSQL succeeds |

### Database Migrations

The image includes Alembic. In Kubernetes, run migrations as an **initContainer** before the main pod starts:

```yaml
initContainers:
  - name: migrate
    image: minibank-iam:latest
    command: ["alembic", "upgrade", "head"]
    env:
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: iam-secrets
            key: database-url
```

### Security Notes

- Runs as non-root (`appuser`, UID `1001`).
- Passwords are hashed with bcrypt (configurable rounds).
- `JWT_SECRET_KEY` must be injected at runtime — the default is deliberately insecure to force replacement.
- Tests excluded from the image via `.dockerignore`.