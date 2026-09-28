resource "aws_security_group" "bastion" {
  name        = "bastion-sg-${var.environment}"
  description = "Allow SSH from specific IPs"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed office/admin IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "bastion-sg-${var.environment}"
    Environment = var.environment
    Project     = "minibank-devops"
  }
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.project}-${var.environment}-secrets-read"
  description = "Allow reading application secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = [
        "arn:aws:secretsmanager:*:*:secret:${var.project}-${var.environment}/*"
      ]
    }]
  })
}

# ---------------------------------------------------------------------------
# App-Node Security Group
# Attached to every EC2/K8s node running MiniBank microservices.
#
# Ingress:
#   - SSH (22)    from the bastion SG only — Ansible and manual debug access
#   - App port    from within the VPC (ALB/Ingress path in later phases will
#                 tighten this to the ALB SG specifically; using vpc_cidr now
#                 keeps the security group self-contained and avoids a circular
#                 dependency with a not-yet-created ALB SG)
#
# Egress:
#   - DB port     to the db SG only — defined as a standalone
#                 aws_security_group_rule below, after both SGs exist, to
#                 avoid a Terraform dependency cycle (app_node needs db.id,
#                 db needs app_node.id — mutually exclusive if inline)
#   - HTTPS (443) to 0.0.0.0/0 — package updates (apt), AWS API calls
#                 (Secrets Manager, SSM, ECR), and registry pulls
#   - RabbitMQ    5672/15672 within the VPC (Wallet-Ledger → Notification)
# ---------------------------------------------------------------------------
resource "aws_security_group" "app_node" {
  name        = "app-node-sg-${var.environment}"
  description = "Security group for MiniBank app-node EC2/K8s instances"
  vpc_id      = var.vpc_id

  # SSH from bastion only — not from 0.0.0.0/0
  ingress {
    description     = "SSH from bastion SG"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # App port from within the VPC (ALB/Ingress source tightened in a later phase)
  ingress {
    description = "App port from VPC (ALB/Ingress path)"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

    # Kubernetes node-to-node: API server 6443, kubelet 10250, etcd, Calico VXLAN 4789/udp, BGP 179
  ingress {
    description = "Node-to-node (kubeadm and Calico)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Node-to-node (kubeadm and Calico)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Outbound: HTTPS for AWS APIs, package updates, registry pulls
  egress {
    description = "HTTPS to internet (AWS APIs, apt, GHCR)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: HTTP — required for apt package lists (Ubuntu repos use plain HTTP)
  # archive.ubuntu.com and security.ubuntu.com are served over HTTP port 80.
  # Without this, "apt update" silently fails even though HTTPS is open.
  egress {
    description = "HTTP to internet (apt package lists from Ubuntu repos)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: RabbitMQ AMQP + management port within VPC
  egress {
    description = "RabbitMQ AMQP within VPC"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "RabbitMQ management UI within VPC"
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "app-node-sg-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

# ---------------------------------------------------------------------------
# Database Security Group
# Attached to PostgreSQL instances (EC2-hosted or future RDS).
#
# Ingress and egress rules that reference app_node SG are declared separately
# as aws_security_group_rule resources below — same cycle-avoidance reason.
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "db-sg-${var.environment}"
  description = "Security group for PostgreSQL database instances"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "db-sg-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

# ---------------------------------------------------------------------------
# Cross-SG rules — declared after both SGs exist to avoid a dependency cycle.
#
# Putting app_node's DB egress *inside* the app_node block AND db's ingress
# *inside* the db block creates a cycle: each resource's .id is needed by the
# other before it has been created. The fix: standalone aws_security_group_rule
# resources that reference both SG IDs after both SGs are in the graph.
# ---------------------------------------------------------------------------

# app_node → db: outbound PostgreSQL
resource "aws_security_group_rule" "app_node_to_db_egress" {
  type                     = "egress"
  description              = "PostgreSQL egress from app-node to DB SG"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app_node.id
  source_security_group_id = aws_security_group.db.id
}

# db ← app_node: inbound PostgreSQL (least-privilege — SG source, not VPC CIDR)
resource "aws_security_group_rule" "db_from_app_node_ingress" {
  type                     = "ingress"
  description              = "PostgreSQL ingress from app-node SG only"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app_node.id
}

# db → app_node: ephemeral response ports (TCP return traffic for DB connections)
resource "aws_security_group_rule" "db_to_app_node_egress" {
  type                     = "egress"
  description              = "Ephemeral response ports from DB to app-node SG"
  from_port                = 1024
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app_node.id
}

# ---------------------------------------------------------------------------
# Public Subnet NACL
# Stateless subnet-level rules applied to all public subnets (bastion, ALB).
# Defense-in-depth layer behind Security Groups: SGs are stateful/instance-level,
# NACLs are stateless/subnet-level — both are needed for a complete perimeter.
#
# Because NACLs are stateless, both inbound AND outbound rules must explicitly
# permit the return-traffic ephemeral port range (1024–65535).
# ---------------------------------------------------------------------------
resource "aws_network_acl" "public" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  # Allow inbound SSH from the internet (bastion SG then further restricts to allowed CIDRs)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

    ingress {
    rule_no    = 105
    protocol   = "udp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 4789
    to_port    = 4789
  }

  # Allow inbound HTTPS (ALB/Ingress traffic in Phase 4)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow inbound HTTP (redirect to HTTPS handled at ALB level)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow inbound ephemeral ports — return traffic for outbound connections
  # initiated from public-subnet instances (e.g. NAT health checks, apt, AWS APIs)
  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound — Security Groups on individual instances enforce tighter rules
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name        = "public-nacl-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

# ---------------------------------------------------------------------------
# Private Subnet NACL
# Stateless subnet-level rules applied to all private subnets (app nodes, DB).
# More restrictive than the public NACL — private subnets should never receive
# unsolicited inbound traffic from the internet.
# ---------------------------------------------------------------------------
resource "aws_network_acl" "private" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Allow inbound traffic from within the VPC only (from bastion, ALB, other nodes)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  # Allow inbound VXLAN (UDP 4789) — Calico overlay traffic between nodes in private subnets
  ingress {
    rule_no    = 105
    protocol   = "udp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 4789
    to_port    = 4789
  }

  # Allow inbound ephemeral ports — return traffic for outbound connections
  # initiated by private-subnet instances (apt updates, AWS API calls via NAT)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound — Security Groups on individual instances enforce tighter rules
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name        = "private-nacl-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}