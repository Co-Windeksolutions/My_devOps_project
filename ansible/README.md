# Ansible — Configuration Management (Phase 2)

This directory contains the Ansible playbooks, roles, and inventory used to configure bare EC2 instances provisioned by Terraform into production-ready Kubernetes worker nodes and platform infrastructure.

---

## 1. Role Breakdown

Configuration is structured into modular roles under `roles/`, following the single-responsibility principle:

### 1.1 `common` (`roles/common/`)
Configures baseline operating system settings, security hardening, and required system tools:
- **Package Management:** Updates `apt` cache and installs essential utilities (`curl`, `wget`, `git`, `unzip`, `python3-pip`, `net-tools`).
- **System Identity:** Sets the system hostname to `inventory_hostname`.
- **Swap Disabling (Mandatory for Kubernetes):**
  - Runs `swapoff -a` conditionally when swap memory is active (`ansible_swaptotal_mb > 0`).
  - Permanently comments out swap entries in `/etc/fstab` using regular expression matching.
  - *Why:* The `kubelet` requires swap to be completely disabled to enforce memory limits and predictable pod scheduling.
- **Time Synchronization:** Sets system timezone to `UTC`.

### 1.2 `docker` (`roles/docker/`)
Installs and configures the container runtime ecosystem:
- **Repository Setup:** Adds the official Docker GPG key and apt repository for the host's Ubuntu distribution.
- **Engine Installation:** Installs `docker-ce`, `docker-ce-cli`, and `containerd.io`.
- **Service Management:** Starts and enables the `docker` and `containerd` systemd services.
- **User Group:** Adds the `ubuntu` system user to the `docker` group for non-root CLI execution.
- **Cgroup Driver Alignment:**
  - Generates `/etc/containerd/config.toml` from defaults.
  - Patches `SystemdCgroup = true` to align containerd with the systemd cgroup driver.
  - *Why:* Kubernetes v1.28+ requires the container runtime and kubelet to use the `systemd` cgroup driver to prevent resource contention under load.

### 1.3 `k8s-prereqs` (`roles/k8s-prereqs/`)
Prepares the kernel and OS for Kubernetes networking and installs the core Kubernetes binaries:
- **Kernel Modules:** Configures `/etc/modules-load.d/k8s.conf` and loads `overlay` and `br_netfilter`.
- **Sysctl Parameters:** Persists and reloads network parameters:
  - `net.bridge.bridge-nf-call-iptables = 1`
  - `net.bridge.bridge-nf-call-ip6tables = 1`
  - `net.ipv4.ip_forward = 1`
  - *Why:* Enables iptables to inspect bridged traffic across container network interfaces (CNI).
- **Package Installation:** Adds the official Kubernetes v1.29 repository (`pkgs.k8s.io`) and installs `kubelet`, `kubeadm`, and `kubectl`.
- **Version Pinning:** Puts `kubelet`, `kubeadm`, and `kubectl` on `hold` via `dpkg_selections` to prevent unattended upgrades from causing version skew.

### 1.4 `monitoring-agent` (`roles/monitoring-agent/`)
Sets up host-level telemetry:
- Installs `prometheus-node-exporter`.
- Starts and enables the service on port 9100.
- *Why:* Exposes hardware and OS metrics (CPU, memory, disk I/O, network) to be scraped by Prometheus in Phase 6.

---

## 2. Inventory Configuration (`inventory/hosts.ini`)

The inventory defines the target instances created by Terraform. For multi-AZ deployments, instances are grouped logically:

```ini
[k8s_nodes]
# Instance IP                SSH User        SSH Private Key Path
10.0.1.10  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/minibank-dev-key.pem
10.0.2.11  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/minibank-dev-key.pem
10.0.3.12  ansible_user=ubuntu  ansible_ssh_private_key_file=~/.ssh/minibank-dev-key.pem

[k8s_nodes:vars]
ansible_python_interpreter=/usr/bin/python3
```

> **Security Note:** Never commit private SSH keys (`.pem`) or passwords to this repository. Store keys securely in `~/.ssh/` on your management machine or use an SSH agent (`ssh-add`).

---

## 3. Running the Playbook

All tasks are executed with `become: true` (sudo) across the `k8s_nodes` group.

### Step 1: Syntax & Dry Run Verification
```bash
# Check syntax
ansible-playbook -i inventory/hosts.ini playbook.yml --syntax-check

# Test connectivity
ansible -i inventory/hosts.ini k8s_nodes -m ping

# Dry run (check mode)
ansible-playbook -i inventory/hosts.ini playbook.yml --check
```

### Step 2: Apply Configuration
```bash
ansible-playbook -i inventory/hosts.ini playbook.yml
```

### Step 3: Verify Node Health
```bash
# Verify containerd and kubelet status
ansible -i inventory/hosts.ini k8s_nodes -m shell -a "systemctl is-active containerd kubelet" --become

# Check node exporter endpoint
ansible -i inventory/hosts.ini k8s_nodes -m shell -a "curl -s http://localhost:9100/metrics | head -n 10"
```

---

## 4. Idempotency & Operational Guarantees

Every task in this playbook is designed to be **idempotent** — running the playbook multiple times produces the exact same end state without breaking running services:
- Package installations declare `state: present`.
- Configuration files use `creates:` guards or targeted line replacements (`replace` module).
- Kernel modules and sysctl parameters declare explicit state.
- Package holding (`dpkg_selections`) prevents unintentional version drift.
