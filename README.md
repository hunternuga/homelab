# nuga homelab

A self-hosted homelab stack managed with Terraform and deployed automatically via GitHub Actions. Services run as Docker containers and are exposed securely through Cloudflare Tunnel — no port forwarding required.

## Stack

| Layer | Tool |
|---|---|
| Infrastructure as code | Terraform |
| Container runtime | Docker |
| Networking | Cloudflare Zero Trust Tunnel |
| Auth | Cloudflare Access (OTP + passkey) |
| CI/CD | GitHub Actions (self-hosted runner) |

## Services

| Service | URL | Auth |
|---|---|---|
| Homepage | [homepage.nuga.dev](https://homepage.nuga.dev) | Public |
| IT Tools | [tools.nuga.dev](https://tools.nuga.dev) | Cloudflare Access |
| Grafana | [grafana.nuga.dev](https://grafana.nuga.dev) | Cloudflare Access |
| MinePanel | [minepanel.nuga.dev](https://minepanel.nuga.dev) | Cloudflare Access |

Monitoring (Prometheus + cAdvisor) runs internally and feeds into Grafana.

## Setup

**Prerequisites:** [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0, [Docker Desktop](https://www.docker.com/products/docker-desktop/), a Cloudflare account with a domain.

**1. Configure secrets**

```bash
chmod +x deploy.sh scripts/*.sh
```

Create `services/cloudflared/terraform.tfvars`:

```hcl
cloudflare_api_token = "your-api-token"
cloudflare_zone_id   = "your-zone-id"
tunnel_secret        = "$(openssl rand -base64 32)"
```

Create `services/minepanel/terraform.tfvars`:

```hcl
jwt_secret     = "$(openssl rand -base64 32)"
admin_username = "admin"
admin_password = "your-password"
```

**2. Deploy**

```bash
./deploy.sh          # deploy all services
./deploy.sh plan     # preview changes
./deploy.sh destroy  # tear everything down
```

## CI/CD

Every push to `main` automatically deploys via a self-hosted GitHub Actions runner. Pull requests trigger a `terraform plan` so changes can be reviewed before merging.

The runner runs on the same machine as Docker, so it has access to the Docker socket and local secrets without needing to expose anything to GitHub. Terraform state is persisted to `~/.homelab-state/` and secrets are stored in `~/.homelab-secrets/` — both outside the repo and never committed.

To set up the runner: **GitHub repo → Settings → Actions → Runners → New self-hosted runner**, follow the macOS steps, then install it as a service:

```bash
cd ~/actions-runner
./svc.sh install && ./svc.sh start
```

## Adding a Service

1. Create a directory under `services/`
2. Add a `scripts/get_<service>_ip.sh` IP resolver
3. Add the service to `DIRS` and `CONTAINERS` in `deploy.sh` before cloudflared
4. Add an ingress rule to `scripts/write_cloudflared_config.sh`
5. Add a DNS record (and optionally an Access policy) in `services/cloudflared/main.tf`
6. Run `./deploy.sh`
