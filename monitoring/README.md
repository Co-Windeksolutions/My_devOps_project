# Monitoring & Observability Stack

This directory contains the declarative infrastructure configuration for the MiniBank monitoring stack, powered by Prometheus, Grafana, Alertmanager, and the Prometheus Operator via the community `kube-prometheus-stack` Helm chart.

---

## 1. Architecture Overview

The monitoring architecture uses the **Prometheus Operator** pattern:
- **`kube-prometheus-stack` (Helm):** Deploys the Prometheus Operator, Prometheus, Alertmanager, Grafana, `kube-state-metrics`, and `node-exporter`.
- **`ServiceMonitor` CRDs (`prometheus/servicemonitors/`):** Declaratively tells Prometheus how to discover and scrape each of the 4 MiniBank microservices in the `minibank` namespace.
- **`PrometheusRule` CRDs (`prometheus/alerts/`):** Defines alerting rules for platform stability, HTTP golden signals, business ledger operations, and message queue backlogs.
- **Grafana Dashboards (`grafana/dashboards/`):** Visualizations for platform health, resource usage, topology spread, and financial ledger throughput.

---

## 2. Deployment Instructions (Helm Naming Contract)

Following the established pattern for PostgreSQL and RabbitMQ, monitoring uses a strict release name contract.

### Step 1: Add Helm Repository
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Step 2: Install `kube-prometheus-stack`
```bash
# Release name MUST be 'kube-prometheus-stack' in the 'monitoring' namespace
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring/prometheus/values.yaml
```

### Step 3: Apply Custom ServiceMonitors & Alert Rules
Once the Prometheus Operator CRDs are installed by Helm, apply the custom monitors and alerting rules:

```bash
# 1. Apply ServiceMonitors for the 4 microservices
kubectl apply -f monitoring/prometheus/servicemonitors/

# 2. Apply custom PrometheusRule alerting manifests
kubectl apply -f monitoring/prometheus/alerts/
```

### Step 4: Load Grafana Dashboards
The Grafana instance has its dashboard sidecar enabled (`sidecar.dashboards.enabled = true`). You can load dashboards into Grafana automatically by creating a ConfigMap with the label `grafana_dashboard: "1"`:

```bash
# Platform Overview Dashboard
kubectl create configmap minibank-overview-dashboard \
  --from-file=minibank-overview.json=monitoring/grafana/dashboards/minibank-overview.json \
  -n monitoring
kubectl label configmap minibank-overview-dashboard grafana_dashboard=1 -n monitoring

# Wallet/Ledger Business Metrics Dashboard
kubectl create configmap wallet-ledger-dashboard \
  --from-file=wallet-ledger-metrics.json=monitoring/grafana/dashboards/wallet-ledger-metrics.json \
  -n monitoring
kubectl label configmap wallet-ledger-dashboard grafana_dashboard=1 -n monitoring
```

---

## 3. Current Status: Live vs. Scaffolded Components

Because application-level `/metrics` instrumentation in `app-repo` is separate work, the monitoring components are currently divided into **Live/Working** and **Scaffolded/Waiting**:

### 3.1 Fully Live & Working Today (Infra-Level)
These components require **zero app-code changes** and work immediately upon Helm installation:

| Component | Source | What Works |
|---|---|---|
| **Pod Stability Alerts** | `kube-state-metrics` | `PodCrashLooping` (>3 restarts in 15m), `OOMKilled` (memory limit exceeded) |
| **Topology Spread Alert** | `kube-state-metrics` + Node Labels | `TopologySpreadViolation` (detects if all replicas of a service land on a single AZ) |
| **RabbitMQ Queue Lag Alert** | RabbitMQ Prometheus Plugin (:15692) | `NotificationQueueLag` (>500 pending messages or 0 consumers) |
| **Resource Metrics** | cAdvisor / kubelet | CPU usage and Memory working set per pod |
| **Platform Health Dashboard** | `kube-state-metrics` + cAdvisor | Running pod counts, restart rates, node distribution, CPU/Memory charts |

### 3.2 Scaffolded & Inactive (Waiting on App-Side `/metrics`)
These components are written, validated, and deployed, but will remain empty/inactive until the 4 microservices expose Prometheus metrics:

| Component | Metric Required | Expected Source |
|---|---|---|
| **`ServiceMonitor` targets (all 4)** | `GET /metrics` | HTTP 200 response on port 8000 |
| **`HighHttpErrorRate` Alert** | `http_requests_total{status=~"5.."}` | FastAPI Prometheus middleware |
| **`HighLatency` Alert** | `http_request_duration_seconds_bucket` | FastAPI Prometheus middleware |
| **`TransferFailureRateElevated` Alert** | `wallet_transfers_total{status="failed"}` | Custom counter in Wallet/Ledger |
| **HTTP RPS & Error Rate Panels** | `http_requests_total` | Overview Dashboard panels |
| **Transfer Throughput (TPS) Panels** | `wallet_transfers_total` | Wallet/Ledger Dashboard panels |

---

## 4. Architectural Overlap: Node Exporter vs. Ansible

### The Conflict:
- **Ansible Role (`ansible/roles/monitoring-agent`):** Installs `prometheus-node-exporter` directly onto the EC2 host via APT as a systemd service, listening on port 9100.
- **Helm Chart (`monitoring/prometheus/values.yaml`):** Deploys `nodeExporter` as a Kubernetes `DaemonSet` on every node, also binding host port 9100.

If both are executed on the same node, the second one will fail to start because **port 9100 is already in use**.

### The Source of Truth Recommendation:
**Use the Helm DaemonSet (`nodeExporter.enabled: true` in `values.yaml`) as the single source of truth.**

**Why:**
1. **Lifecycle Management:** In a Kubernetes environment, node agents should be managed declaratively by the Kubernetes control plane. Updates, resource limits, and scrape configurations are handled automatically by the Helm chart.
2. **Scrape Discovery:** The Helm chart automatically creates the `Service` and `ServiceMonitor` for the DaemonSet, so Prometheus starts scraping it with zero manual intervention.
3. **Ansible Alignment:** When configuring nodes via Ansible, **omit the `monitoring-agent` role** from `ansible/playbook.yml`, or keep it solely for non-Kubernetes standalone hosts (like a dedicated bastion jump box).

---

## 5. App-Side Instrumentation Guide (`app-repo` TODO)

When ready to implement Prometheus instrumentation in `app-repo`, follow this blueprint:

### 5.1 Recommended Library
Use [`prometheus-fastapi-instrumentator`](https://github.com/trallnag/prometheus-fastapi-instrumentator):
```bash
pip install prometheus-fastapi-instrumentator
```

### 5.2 Changes Required in Each Service (`main.py`)
Add 3 lines of middleware to each of the 4 FastAPI microservices (`api-gateway`, `iam-service`, `wallet-service`, `notification-service`):

```python
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()

# Instrument FastAPI and expose GET /metrics
Instrumentator().instrument(app).expose(app, endpoint="/metrics")
```
This automatically provides:
- `http_requests_total` (method, handler, status)
- `http_request_duration_seconds_bucket` (latency histogram)
- `http_request_size_bytes`, `http_response_size_bytes`

### 5.3 Custom Business Metrics (Wallet/Ledger Service Only)
In `wallet-service`, define a custom counter for double-entry ledger transactions:

```python
from prometheus_client import Counter

WALLET_TRANSFERS = Counter(
    "wallet_transfers_total",
    "Total financial transfer operations processed",
    ["status"] # "success" or "failed"
)

# In your transfer_funds endpoint:
try:
    ledger.execute_transfer(...)
    WALLET_TRANSFERS.labels(status="success").inc()
except Exception as e:
    WALLET_TRANSFERS.labels(status="failed").inc()
    raise
```

Once pushed and redeployed, Prometheus will automatically begin scraping via the existing `ServiceMonitor`s, activating the scaffolded alerts and dashboards immediately.
