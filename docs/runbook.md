# MiniBank Platform Runbook

This runbook provides operational guidelines, incident triage steps, maintenance procedures, and deployment workflows for the MiniBank platform.

---

## 1. Deployment Workflow & Architectural Scoping

### 1.1 Current Deployment Procedure (Manual Handoff)

Application deployments currently follow a deliberate **manual image bump workflow**:

1. New images are built and pushed to GitHub Container Registry (GHCR) by the `app-repo` CI pipeline on merge to `main` (e.g. `ghcr.io/your-org/wallet-ledger-service:v1.4.2`).
2. The platform operator updates the image tag in the target deployment manifest:
   ```yaml
   # k8s/deployments/wallet-ledger-deployment.yaml
   spec:
     template:
       spec:
         containers:
           - name: wallet-ledger
             image: ghcr.io/your-org/wallet-ledger-service:v1.4.2
   ```
3. Apply the updated manifest to the cluster:
   ```bash
   kubectl apply -f k8s/deployments/wallet-ledger-deployment.yaml
   ```
4. Monitor the rollout until completion:
   ```bash
   kubectl rollout status deployment/wallet-ledger -n minibank
   ```

### 1.2 Deliberately Deferred: Automated CI-to-Cluster Handoff

> **Scoping Decision Notice:**
> Fully automated CI-to-cluster deployment handoff (such as `repository_dispatch` triggering a CD pipeline in this repo, or GitOps reconciliation via ArgoCD / Flux) has been **deliberately deferred** to a subsequent project phase.
>
> **Rationale:**
> - **Separation of Concerns:** In production environments, application repositories (`app-repo`) never have direct administrative access to the Kubernetes control plane or infrastructure repository (`devops-repo`).
> - **Auditability & Gatekeeping:** Manual tag updates in manifests ensure that all changes deployed to the cluster pass through an explicit git commit and review boundary in the infrastructure repository.
> - **Phased Complexity:** Establishing rock-solid manual rollouts, Alembic migration initContainers, and health probe validation is the foundation upon which GitOps automation is introduced in Phase 6 / Project 2.

---

## 2. Infrastructure Provisioning & Teardown

### 2.1 Provisioning an Environment (`dev`, `staging`, `prod`)

Before provisioning, verify that the remote S3 state bucket exists and that `terraform.tfvars` contains your admin IP and SSH key name:

```bash
cd terraform/environments/dev

# Initialize backend and providers
terraform init

# Validate configuration syntax and references
terraform validate

# Review proposed changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan
```

### 2.2 Teardown Procedure

For non-production environments (`dev`), `log_bucket_force_destroy` is set to `true`, allowing automated teardown:
```bash
cd terraform/environments/dev
terraform destroy
```

For production (`prod`), `log_bucket_force_destroy` is `false`. You must explicitly empty the S3 log bucket before teardown can succeed:
```bash
aws s3 rm s3://minibank-prod-logs --recursive
terraform destroy
```

---

## 3. Node Configuration Runbook (Ansible)

To configure the EC2 instances created by Terraform to act as Kubernetes nodes:

1. Update `ansible/inventory/hosts.ini` with the private IPs of the EC2 instances and the path to your SSH private key:
   ```ini
   [k8s_nodes]
   10.0.1.10  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/minibank-dev-key.pem
   10.0.2.11  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/minibank-dev-key.pem
   ```
2. Verify SSH connectivity via the bastion jump box:
   ```bash
   ansible -i ansible/inventory/hosts.ini k8s_nodes -m ping
   ```
3. Execute the playbook:
   ```bash
   cd ansible
   ansible-playbook -i inventory/hosts.ini playbook.yml
   ```
4. Verify that Docker, containerd, and kubelet are active:
   ```bash
   ansible -i inventory/hosts.ini k8s_nodes -m command -a "systemctl status kubelet" --become
   ```

---

## 4. Common Incident Triage & Troubleshooting

### 4.1 Pod in `CrashLoopBackOff` or `Init:CrashLoopBackOff`

**Symptoms:** Microservice pod fails to start; restart count increases.

**Diagnosis:**
```bash
# Check pod status and events
kubectl describe pod <pod-name> -n minibank

# Check logs of the failed container
kubectl logs <pod-name> -n minibank

# If failure is in initContainer (Alembic migration):
kubectl logs <pod-name> -c run-migrations -n minibank
```

**Common Causes & Remediation:**
- **Alembic migration failure:** Verify PostgreSQL is running and accepting connections from the private subnet. Check whether `db-credentials.json` in the mounted secret has valid credentials.
- **ConfigMap/Secret missing:** Pods cannot start if a referenced volume mount does not exist. Verify with:
  ```bash
  kubectl get configmaps,secrets -n minibank
  ```
- **Permission denied:** Containers run with `readOnlyRootFilesystem: true` and `runAsUser: 10001`. The app must only write temporary files to `/tmp` (which must be mounted as an `emptyDir` volume).

### 4.2 Database Connectivity Failures (`psycopg2.OperationalError`)

**Symptoms:** API Gateway returns 500; IAM or Wallet/Ledger logs show connection refused or timeout to `postgresql.minibank.svc.cluster.local:5432`.

**Diagnosis:**
```bash
# Verify PostgreSQL pod status
kubectl get pods -l app.kubernetes.io/name=postgresql -n minibank

# Check PostgreSQL logs
kubectl logs -l app.kubernetes.io/name=postgresql -n minibank

# Test DNS resolution from within the cluster
kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -n minibank -- nslookup postgresql
```

**Remediation:**
- Ensure the Helm release was named `postgresql` so CoreDNS creates `postgresql.minibank.svc.cluster.local`.
- If the pod IP changed, verify that `kube-dns` / `CoreDNS` pods in `kube-system` are healthy.

### 4.3 RabbitMQ Queue Backlog & Notification Lag

**Symptoms:** Money transfers complete, but users do not receive notifications. Queue depth grows.

**Diagnosis:**
```bash
# Exec into RabbitMQ pod and inspect queues
kubectl exec -it rabbitmq-0 -n minibank -- rabbitmqctl list_queues name messages consumers

# Check notification-service logs
kubectl logs -l app=notification-service -n minibank -f
```

**Remediation:**
- If consumers count is 0: Check `notification-service` deployment status. Ensure the consumer loop hasn't crashed.
- If messages are unacknowledged: Check whether the mock notification handler is hanging on network calls or timeout exceptions.
- Restart notification consumer pods if necessary:
  ```bash
  kubectl rollout restart deployment/notification-service -n minibank
  ```

### 4.4 Ingress / ALB 502 Bad Gateway

**Symptoms:** External clients receive HTTP 502 when connecting via the ALB DNS name.

**Diagnosis:**
```bash
# Check AWS Load Balancer Controller logs in kube-system
kubectl logs -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system

# Verify API Gateway endpoints are healthy and registered
kubectl get endpoints api-gateway-service -n minibank

# Check API Gateway pod readiness probes
kubectl describe pod -l app=api-gateway -n minibank | grep -A 5 Readiness
```

**Remediation:**
- The Ingress uses `alb.ingress.kubernetes.io/target-type: ip`. Verify that the AWS security group on the ALB allows egress to pod IPs in the private subnets on port 8000.
- Verify that `api-gateway` pods are passing the `/health/readiness` probe. If readiness fails, the ALB removes the pod from the target group.

---

## 5. Rollback Procedures

### 5.1 Rolling Back a Failed Application Deployment

If a newly deployed version exhibits regressions or elevated error rates:

```bash
# Check rollout history
kubectl rollout history deployment/<service-name> -n minibank

# Roll back to the immediately preceding revision
kubectl rollout undo deployment/<service-name> -n minibank

# Verify rollback success
kubectl rollout status deployment/<service-name> -n minibank
```

### 5.2 Rolling Back Database Migrations

If a schema migration introduces breaking database changes:
```bash
# Access the pod or run a dedicated one-off migration job
kubectl exec -it <pod-name> -c <service-name> -n minibank -- alembic downgrade -1
```
*(Note: Ensure downgrade migrations are written defensively and tested prior to rollout).*
