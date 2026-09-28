 # Kubernetes

This directory defines the platform namespace, service deployments, internal services, ingress, RBAC, configuration, and Helm values for PostgreSQL and RabbitMQ.

Secrets are reserved for sealed or Vault-referenced manifests and must never contain committed plaintext credentials. Network policies and admission policies are reserved for Phase 6.

---

## Apply Order

Apply base resources in this order — sequence matters because Secrets must exist before Deployments try to mount them, and the namespace must exist before anything else:

```bash
# 1. Namespace first — everything else scopes to minibank
kubectl apply -f namespace.yaml

# 2. Secrets before Deployments (pods refuse to schedule if a referenced Secret is missing)
kubectl apply -f secrets/

# 3. RBAC — ServiceAccounts, Roles, RoleBindings
kubectl apply -f rbac/

# 4. ConfigMaps
kubectl apply -f configmaps/

# 5. Workloads and networking
kubectl apply -f deployments/
kubectl apply -f services/
kubectl apply -f ingress/
```

---

## Helm-Deployed Dependencies (PostgreSQL + RabbitMQ)

The ConfigMaps for IAM, Wallet/Ledger, and Notification use Kubernetes internal DNS names to reach the database and message broker. **Those DNS names are derived directly from the Helm release name and the namespace** — they will only resolve correctly if the Helm releases are installed with exactly the names below.

Install both before applying Deployments:

```bash
# Add the Bitnami chart repository if not already added
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# PostgreSQL — release name MUST be 'postgresql' so that the DNS name
# postgresql.minibank.svc.cluster.local resolves inside the cluster.
# The postgres-credentials Secret and postgres-initdb-scripts ConfigMap
# must exist in the minibank namespace before running this command.
kubectl apply -f secrets/postgres-credentials.yaml
kubectl apply -f configmaps/postgres-initdb-configmap.yaml
helm install postgresql bitnami/postgresql \
  --namespace minibank \
  --values helm-values/postgres-values.yaml

# RabbitMQ — release name MUST be 'rabbitmq' so that the DNS name
# rabbitmq.minibank.svc.cluster.local resolves inside the cluster.
# The rabbitmq-credentials Secret must exist before running this command.
kubectl apply -f secrets/rabbitmq-credentials.yaml
helm install rabbitmq bitnami/rabbitmq \
  --namespace minibank \
  --values helm-values/rabbitmq-values.yaml
```

> **Why the release name matters:** Bitnami charts name their Service after the Helm release. A release named `postgresql` produces a Service named `postgresql`, which CoreDNS resolves as `postgresql.minibank.svc.cluster.local`. If you use a different release name (e.g. `postgres` or `pg`), update the `host` field in `configmaps/iam-configmap.yaml` and `configmaps/wallet-ledger-configmap.yaml` to match, or pods will fail DNS lookups at runtime.

---

## DNS Names Reference

| ConfigMap reference | Helm release name | Resolved by |
|---|---|---|
| `postgresql.minibank.svc.cluster.local:5432` | `helm install postgresql ...` | IAM, Wallet/Ledger configmaps |
| `rabbitmq.minibank.svc.cluster.local:5672` | `helm install rabbitmq ...` | Wallet/Ledger, Notification configmaps |

---

## Databases

A single PostgreSQL release serves both IAM and Wallet/Ledger. The chart creates `iam_db` automatically (from `global.postgresql.auth.database`). The `wallet_db` database is created on first boot via the SQL init script in `configmaps/postgres-initdb-configmap.yaml`, which the chart mounts under `primary.initdb.scriptsConfigMap`.
