# nuga homelab

A self-hosted homelab stack managed with Terraform and deployed automatically via GitHub Actions. Services run as Kubernetes workloads on a small k3s cluster and are exposed securely through Cloudflare Tunnel — no port forwarding required.

## Stack

| Layer | Tool |
|---|---|
| Infrastructure as code | Terraform |
| Container orchestration | Kubernetes (k3s) |
| Ingress | Traefik (bundled with k3s), fronted by Cloudflare Zero Trust Tunnel |
| Auth | Cloudflare Access (OTP + passkey) |
| CI/CD | GitHub Actions (self-hosted runner) |

## Services

| Service | URL | Auth |
|---|---|---|
| Homepage | [homepage.nuga.dev](https://homepage.nuga.dev) | Public |
| IT Tools | [tools.nuga.dev](https://tools.nuga.dev) | Cloudflare Access |
| Grafana | [grafana.nuga.dev](https://grafana.nuga.dev) | Cloudflare Access |
| [Kcal](services/kcal/) | [kcal.nuga.dev](https://kcal.nuga.dev) | Cloudflare Access |

Monitoring (Prometheus + cAdvisor) runs internally and feeds into Grafana.

## Cluster

Two AWS Lightsail instances (Ubuntu 24.04, 2GB plan) in the same AZ, private networking enabled between them:

- **node-1** — k3s server (control-plane, embedded SQLite datastore, bundled Traefik ingress controller). Also hosts the GitHub Actions self-hosted runner.
- **node-2** — k3s agent, labeled to run all app workloads so the control-plane node stays lightly loaded.

**Provisioning:**

```bash
# node-1
curl -sfL https://get.k3s.io | sh -
cat /var/lib/rancher/k3s/server/node-token   # copy this

# node-2 (use node-1's private IP)
curl -sfL https://get.k3s.io | K3S_URL=https://<node-1-private-ip>:6443 K3S_TOKEN=<token> sh -

# from node-1, label node-2 so app Deployments schedule there
kubectl label node <node-2-hostname> homelab/role=apps
```

Copy `/etc/rancher/k3s/k3s.yaml` from node-1 if you want `kubectl`/Terraform access from elsewhere — swap `127.0.0.1` for node-1's IP. Every service module's `provider "kubernetes"` block defaults `config_path` to `/etc/rancher/k3s/k3s.yaml`, which is why Terraform runs directly on node-1.

## Setup

**Prerequisites:** [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0, a running k3s cluster (see above), a Cloudflare account with a domain.

**1. Configure secrets**

```bash
chmod +x deploy.sh
```

Create `services/cloudflared/terraform.tfvars`:

```hcl
cloudflare_api_token = "your-api-token"
cloudflare_zone_id   = "your-zone-id"
tunnel_secret        = "$(openssl rand -base64 32)"
```

Create `services/grafana/terraform.tfvars`:

```hcl
grafana_admin_password = "your-password"
```

Create `services/kcal/terraform.tfvars` (generate the secret with `openssl rand -base64 32`):

```hcl
kcal_session_secret = "your-generated-secret"
```

**2. Deploy**

```bash
./deploy.sh          # deploy all services
./deploy.sh plan     # preview changes
./deploy.sh destroy  # tear everything down
```

## CI/CD

Every push to `main` automatically deploys via a self-hosted GitHub Actions runner. Pull requests trigger a `terraform plan` so changes can be reviewed before merging.

The runner lives on node-1, alongside the k3s server — it talks to the cluster the same way Terraform does, via the local `/etc/rancher/k3s/k3s.yaml` kubeconfig, with no cluster-external access needed. Terraform state is persisted to `~/.homelab-state/` and secrets are stored in `~/.homelab-secrets/` — both outside the repo and never committed.

To set up the runner: **GitHub repo → Settings → Actions → Runners → New self-hosted runner**, follow the Linux steps, then install it as a service:

```bash
cd ~/actions-runner
./svc.sh install && ./svc.sh start
```

## Adding a Service

1. Create a directory under `services/`
2. Add a `main.tf` with a `kubernetes_deployment`, `kubernetes_service`, and (if it needs to be reachable from outside the cluster) a `kubernetes_ingress_v1` pointed at `<name>.nuga.dev` — copy `services/it-tools/main.tf` as a minimal template. Alternatively, if the service ships as (or has) a Helm chart, use a `helm_release` resource instead — see `services/kcal/` for that pattern.
3. Add the service's directory to `DIRS` in `deploy.sh`, before `cloudflared`
4. Add a DNS record (and optionally a Cloudflare Access policy) in `services/cloudflared/main.tf` — cloudflared itself doesn't need any changes, since it routes every hostname to Traefik and Traefik dispatches by the Ingress rules already in the cluster
5. Run `./deploy.sh`
