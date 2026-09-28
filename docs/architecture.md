# System Architecture — MiniBank Platform

This document describes the end-to-end technical architecture of the MiniBank platform across infrastructure provisioning, system configuration, container orchestration, and application networking.

---

## 1. High-Level Architecture Overview

The MiniBank platform deploys a 4-tier microservice financial application on AWS using modern Infrastructure as Code (IaC), configuration management, and Kubernetes container orchestration.

```
                     ┌───────────────────────────────────────────────────────────┐
                     │                         Internet                          │
                     └─────────────────────────────┬─────────────────────────────┘
                                                   │
                                                   ▼
                     ┌───────────────────────────────────────────────────────────┐
                     │            AWS Application Load Balancer (ALB)            │
                     │          (Auto-generated AWS DNS: *.elb.amazonaws.com)    │
                     └─────────────────────────────┬─────────────────────────────┘
                                                   │ HTTP :80
                                                   ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│ AWS VPC (3 Availability Zones: us-east-1a, us-east-1b, us-east-1c)                              │
│                                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ Public Subnets (10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24)                              │  │
│  │                                                                                           │  │
│  │   [ NAT Gateway(s) ]      [ Bastion Host (EC2) ]      [ ALB Ingress Controller Nodes ]    │  │
│  │    (Single in Dev,          (SSH Admin Jump Box)                                          │  │
│  │     Multi-AZ in Prod)                                                                     │  │
│  └───────────────────────────────────────────┬───────────────────────────────────────────────┘  │
│                                              │                                                  │
│  ┌───────────────────────────────────────────┼───────────────────────────────────────────────┐  │
│  │ Private Subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24)                                  │  │
│  │                                           │                                               │  │
│  │   Kubernetes Cluster (`minibank` namespace)                                               │  │
│  │                                                                                           │  │
│  │   ┌───────────────────────────────────────────────────────────────────────────────────┐   │  │
│  │   │ Ingress: minibank-ingress (ALB target-type: ip)                                    │   │  │
│  │   └───────────────────────────────────────┬───────────────────────────────────────────┘   │  │
│  │                                           │ ClusterIP :8000                               │  │
│  │                                           ▼                                               │  │
│  │   ┌───────────────────────────────────────────────────────────────────────────────────┐   │  │
│  │   │ API Gateway Service & Pods (Replicas: 3, Topology Spread across 3 AZs)            │   │  │
│  │   └───────┬───────────────────────────────┼───────────────────────────────────────────┘   │  │
│  │           │ Internal HTTP                 │ Internal HTTP                                 │  │
│  │           ▼                               ▼                                               │  │
│  │   ┌───────────────────────────────┐ ┌─────────────────────────────────────────────────┐   │  │
│  │   │ IAM Service                   │ │ Wallet / Ledger Service                         │   │  │
│  │   │ - Auth & JWT issuance         │ │ - Double-entry ledger & balance                 │   │  │
│  │   │ - Alembic migration init      │ │ - Alembic migration init                        │   │  │
│  │   └───────────────┬───────────────┘ └───────┬─────────────────────────┬───────────────┘   │  │
│  │                   │                         │                         │ Event Publish     │  │
│  │                   │ PostgreSQL :5432        │ PostgreSQL :5432        ▼                   │  │
│  │                   │                         │               ┌─────────────────────────┐   │  │
│  │                   ▼                         ▼               │ RabbitMQ Broker :5672   │   │  │
│  │           ┌─────────────────────────────────────────┐       │ Exchange:               │   │  │
│  │           │ PostgreSQL Database (Helm: bitnami)     │       │   minibank.transfers    │   │  │
│  │           │ - Databases: iam_db, wallet_db          │       └─────────┬───────────────┘   │  │
│  │           └─────────────────────────────────────────┘                 │ Event Consume     │  │
│  │                                                                       ▼                   │  │
│  │                                                             ┌─────────────────────────┐   │  │
│  │                                                             │ Notification Service    │   │  │
│  │                                                             │ - Async event logger    │   │  │
│  │                                                             │ - Mock email / SMS      │   │  │
│  │                                                             └─────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Infrastructure Layer (Terraform)

The infrastructure foundation is provisioned declaratively with Terraform, organized into reusable modules under `terraform/modules/` and called by environment definitions in `terraform/environments/{dev,staging,prod}`.

### 2.1 Networking & Multi-AZ Design (`modules/vpc`)
- **VPC CIDR:** Partitioned by environment to prevent collision:
  - `dev`: `10.0.0.0/16`
  - `staging`: `10.1.0.0/16`
  - `prod`: `10.2.0.0/16`
- **Availability Zones:** Spanned across 3 AZs (`us-east-1a`, `us-east-1b`, `us-east-1c`) with 3 private subnets and 3 public subnets.
- **NAT Gateway Strategy:**
  - `dev` and `staging`: Single shared NAT Gateway (`single_nat_gateway = true`) to minimize monthly idle costs.
  - `prod`: Dedicated NAT Gateway per AZ (`single_nat_gateway = false`, `one_nat_gateway_per_az = true`) ensuring complete AZ fault isolation.

### 2.2 Defense-in-Depth Security (`modules/security`)
Security is implemented in two concentric rings:
1. **Security Groups (Layer 1 — Stateful, Instance-Level):**
   - `bastion-sg`: Inbound port 22 restricted to specific operator CIDRs; full outbound.
   - `app-node-sg`: Inbound port 22 from `bastion-sg` only (for Ansible configuration); inbound port 8000 from the VPC CIDR (ALB traffic); outbound HTTPS/HTTP via NAT and internal VPC.
   - `db-sg`: Inbound PostgreSQL port 5432 strictly restricted to `app-node-sg` (application queries) and `bastion-sg` (administrative psql access).
2. **Network ACLs (Layer 2 — Stateless, Subnet-Level):**
   - `public-nacl`: Permits HTTP/HTTPS/SSH inbound and explicitly permits ephemeral return traffic (ports 1024–65535) required by stateless packet inspection.
   - `private-nacl`: Denies direct inbound internet traffic; permits all intra-VPC TCP traffic and ephemeral response packets for NAT-initiated outbound requests.

### 2.3 Centralized Logging & Audit (`modules/logging`)
- Dedicated S3 bucket per environment (`${project}-${environment}-logs`) with AES-256 server-side encryption and public access blocks.
- Lifecycle rules transitioning logs to `STANDARD_IA` after 30 days and expiring after 90 days.
- AWS VPC Flow Logs capturing all network interface traffic in Parquet format.

---

## 3. Configuration Management Layer (Ansible)

Ansible orchestrates the OS-level configuration and provisioning of the Kubernetes nodes:
- **Role Separation:**
  - `common`: OS updates, base tooling (curl, git, pip), UTC timezone, hostname configuration, and permanently disabling swap.
  - `docker`: Installation of Docker CE and `containerd`, configuring `containerd` with `SystemdCgroup = true` to align with Kubernetes cgroup v2 standards.
  - `k8s-prereqs`: Loading kernel modules (`overlay`, `br_netfilter`), configuring sysctl bridging/IP forwarding, adding Kubernetes package repositories, and installing `kubelet`, `kubeadm`, and `kubectl` pinned via `dpkg_selections`.
  - `monitoring-agent`: Installing and enabling `prometheus-node-exporter` for bare-metal/node-level observability.

---

## 4. Container Orchestration Layer (Kubernetes)

All workloads run in the `minibank` namespace to ensure isolation from cluster management components.

### 4.1 Microservices Architecture
The application consists of four Python (FastAPI / SQLAlchemy / Alembic) services:
1. **API Gateway:** Single external entry point. Routes incoming client requests, verifies tokens against IAM, and applies in-memory rate limiting.
2. **IAM Service:** User registration, authentication, RBAC, and JWT token issuance backed by PostgreSQL (`iam_db`).
3. **Wallet/Ledger Service:** Double-entry ledger supporting `check_balance` and `transfer_funds`. Backed by PostgreSQL (`wallet_db`) and publishes `transfer.completed` events to RabbitMQ.
4. **Notification Service:** Asynchronous event consumer listening on RabbitMQ queue `notifications.events` and logging mock SMS/email notifications.

### 4.2 Pod Lifecycle & Reliability
- **Zero-Downtime Multi-AZ Placement:** Pods utilize `topologySpreadConstraints` across `topology.kubernetes.io/zone` to prevent replica concentration in a single failure domain.
- **Database Migrations:** IAM and Wallet/Ledger run Alembic schema migrations (`alembic upgrade head`) via `initContainers`. Main app containers never execute DDL statements.
- **Security Context:** Containers run as non-root (`runAsUser: 10001`), with read-only root filesystems and all Linux capabilities dropped (`drop: ["ALL"]`).
- **Configuration Delivery:** ConfigMaps and Secrets are mounted exclusively as volume files under `/etc/minibank/config` and `/etc/minibank/secrets`, avoiding environment variable leakage via process dumps or `/proc`.

### 4.3 External Access & Networking
- **Ingress:** AWS Load Balancer Controller manages an internet-facing Application Load Balancer.
- **Direct Pod Routing:** Ingress uses `alb.ingress.kubernetes.io/target-type: ip`, routing traffic directly to pod IPs without extra NodePort hops.
- **DNS:** Application routes externally via the ALB's auto-generated DNS name; Route53 custom domain management was deliberately omitted to maintain platform focus.
