# Terraform — Stage 1

Terraform provisions the AWS foundation that MiniBank's application and Kubernetes cluster run on: VPC networking across multiple Availability Zones, two layers of security controls, centralised logging, and EC2 compute. Everything is parameterised into reusable modules so the same configuration deploys dev, staging, and prod by passing different inputs.

> **Note — deliberately excluded from this stage:**
> - **DNS / Route53** — skipped. Using the ALB/Ingress auto-generated DNS name directly instead of provisioning a hosted zone and records. No DevOps signal is lost; all VPC, EC2, Ingress, and K8s routing is still fully demonstrated.
> - **Vault** — dropped in favour of AWS Secrets Manager, which is simpler to provision via Terraform, integrates cleanly with EC2 IAM roles, and is what AWS shops actually use at this scale. Secrets Manager is provisioned in a later pass (`modules/secrets/` — currently a stub).

## What this provisions

| Module | What it builds |
|---|---|
| `modules/vpc` | VPC with public and private subnets across 3 AZs, Internet Gateway, NAT Gateway(s), route tables |
| `modules/security` | Security Groups (bastion, app-node, DB) + Network ACLs for public and private subnets |
| `modules/logging` | S3 log bucket (encrypted, public-access blocked, lifecycle policy) + VPC Flow Logs |
| `modules/ec2` | Bastion host in a public subnet; reusable for worker nodes in later phases |
| `modules/secrets` | AWS Secrets Manager secrets — stub, to be completed in the next pass |

## Key decisions

**Multi-AZ networking:** Subnets span three Availability Zones (`us-east-1a/b/c`). This means a single AZ failure doesn't take down the entire application — the core talking point for "I understand high availability."

**NAT Gateway strategy (cost vs. resilience tradeoff, documented deliberately):**
- Dev / Staging: one shared NAT Gateway. Saves ~$32/month per AZ. If that AZ fails, all private subnets lose outbound internet access — acceptable for non-production.
- Prod: one NAT Gateway per AZ (`one_nat_gateway_per_az = true`). Each AZ's private subnets retain outbound access independently.

**Two-layer security (defense-in-depth):**
- Security Groups (Layer 1) — stateful, per-instance. Return traffic is automatically allowed; rules only need to describe initiated traffic. Three SGs: bastion (SSH from approved IPs only), app-node (SSH from bastion + app port from VPC), DB (PostgreSQL from app-node and bastion only).
- Network ACLs (Layer 2) — stateless, per-subnet. Both directions must be explicitly allowed, including ephemeral/return ports (1024-65535). Public subnets allow HTTPS/HTTP/SSH inbound plus ephemeral return. Private subnets allow all intra-VPC TCP plus ephemeral return for NAT-initiated traffic; no direct internet inbound.
- If an SG rule is ever misconfigured, the NACL acts as a subnet-level safety net before traffic reaches any instance.

**State isolation:** Each environment (`dev`, `staging`, `prod`) has its own S3 state file key and its own backend configuration. Running `terraform apply` in `environments/dev` cannot touch prod state.

**Sensitive values:** Never committed to version control. `bastion_allowed_cidrs` and `key_name` are set locally in `terraform.tfvars` (gitignored). Secrets (DB credentials, JWT keys) will be pulled from AWS Secrets Manager at runtime via EC2 IAM role — never in `.tf` files or CI variables in plain text.

## Running it

```bash
cd terraform/environments/dev   # or staging / prod
terraform init                  # downloads providers and modules, connects to S3 backend
terraform validate              # catches syntax/reference errors before hitting AWS
terraform plan                  # shows exactly what will be created — review before applying
terraform apply
```

Make sure the S3 state bucket exists and is versioned before running `terraform init`. See the main project README for bootstrap instructions.
