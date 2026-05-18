# 🏠 nuga homelab

A self-hosted homelab stack managed with Terraform, running containerized services exposed securely via Cloudflare Tunnel — no port forwarding required.

## Stack

- **Container runtime** — Docker Desktop (Mac) / Docker Engine (Linux)
- **Infrastructure as code** — Terraform with the [kreuzwerker Docker provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest)
- **Tunnel** — Cloudflare Zero Trust Tunnel (`cloudflared`)
- **Auth** — Cloudflare Access (email-based OTP + passkey support)
- **Monitoring** — Prometheus + cAdvisor + Grafana
- **Gaming** — MinePanel (Minecraft server management)

---

## Services

| Service | URL | Description | Auth |
|---|---|---|---|
| Homepage | [homepage.nuga.dev](https://homepage.nuga.dev) | Homelab dashboard | Public |
| IT Tools | [tools.nuga.dev](https://tools.nuga.dev) | Developer utilities toolkit | Cloudflare Access |
| Grafana | [grafana.nuga.dev](https://grafana.nuga.dev) | Metrics and dashboards | Cloudflare Access |
| MinePanel | [minepanel.nuga.dev](https://minepanel.nuga.dev) | Minecraft server management | Cloudflare Access |
| MinePanel API | [minepanel-api.nuga.dev](https://minepanel-api.nuga.dev) | MinePanel backend API | JWT (bypass) |
| Prometheus | Internal only | Metrics scraping | None |
| cAdvisor | Internal only | Container metrics collection | None |

---

## Prerequisites

Before you begin, make sure you have the following installed:

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.0`
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Mac/Windows) or Docker Engine (Linux)
- A [Cloudflare](https://cloudflare.com) account with a domain configured
- A Cloudflare API token with the following permissions:
  - **Account → Cloudflare Tunnel → Edit**
  - **Account → Access: Apps and Policies → Edit**
  - **Zone → DNS → Edit** (scoped to your domain)

---

## Project Structure

```
homelab/
├── deploy.sh                          # One-command deploy/destroy/plan script
├── scripts/
│   ├── get_homepage_ip.sh             # Dynamic container IP resolvers
│   ├── get_it_tools_ip.sh
│   ├── get_grafana_ip.sh
│   ├── get_prometheus_ip.sh
│   ├── get_cadvisor_ip.sh
│   ├── get_minepanel_ip.sh
│   └── write_cloudflared_config.sh   # Writes tunnel credentials + ingress config
├── network/
│   ├── main.tf                        # Shared Docker network
│   └── versions.tf
└── services/
    ├── homepage/
    │   ├── config/                    # Homepage config files (persisted via bind mount)
    │   │   ├── services.yaml
    │   │   ├── settings.yaml
    │   │   ├── widgets.yaml
    │   │   └── bookmarks.yaml
    │   ├── main.tf
    │   ├── versions.tf
    │   └── outputs.tf
    ├── it-tools/
    │   ├── main.tf
    │   └── versions.tf
    ├── cadvisor/
    │   ├── main.tf
    │   └── versions.tf
    ├── prometheus/
    │   ├── config/
    │   │   └── prometheus.yml         # Prometheus scrape config
    │   ├── main.tf
    │   ├── versions.tf
    │   └── outputs.tf
    ├── grafana/
    │   ├── provisioning/
    │   │   ├── dashboards/
    │   │   │   ├── dashboards.yaml
    │   │   │   └── cadvisor.json      # Exported dashboard JSON
    │   │   └── datasources/
    │   │       └── prometheus.yaml
    │   ├── main.tf
    │   ├── versions.tf
    │   └── outputs.tf
    ├── minepanel/
    │   ├── data/                      # MinePanel data (persisted via bind mount)
    │   │   └── servers/               # Minecraft server data
    │   ├── main.tf
    │   ├── versions.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── terraform.tfvars          # MinePanel secrets (never commit)
    └── cloudflared/
        ├── main.tf                    # Cloudflare Tunnel + ingress + Access policies
        ├── versions.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars          # Cloudflare secrets (never commit)
```

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/hunternuga/homelab.git
cd homelab
```

### 2. Install Docker Desktop

Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and make sure it's running before deploying.

### 3. Make scripts executable

```bash
chmod +x deploy.sh
chmod +x scripts/*.sh
```

### 4. Configure secrets

Edit `services/cloudflared/terraform.tfvars`:

```hcl
cloudflare_api_token = "your-api-token-here"
cloudflare_zone_id   = "your-zone-id-here"
tunnel_secret        = "$(openssl rand -base64 32)"
```

Edit `services/minepanel/terraform.tfvars`:

```hcl
jwt_secret     = "$(openssl rand -base64 32)"
admin_username = "admin"
admin_password = "your-password-here"
```

> **Never commit `terraform.tfvars` files to version control.** They are listed in `.gitignore`.

### 5. Deploy

```bash
./deploy.sh
```

This will:
1. Create the shared Docker network
2. Deploy all services in order
3. Create the Cloudflare Tunnel, DNS records, and Access policies
4. Write the cloudflared config with all ingress rules

---

## Usage

```bash
# Deploy all services
./deploy.sh

# Preview changes without applying
./deploy.sh plan

# Tear down all services
./deploy.sh destroy
```

---

## Adding a New Service

1. Create a new directory under `services/`
2. Add an IP script under `scripts/get_<service>_ip.sh`
3. Add the service to `DIRS` and `CONTAINERS` in `deploy.sh` before cloudflared
4. Add a new ingress rule to `write_cloudflared_config.sh`
5. Add DNS record and optionally a Cloudflare Access policy in `services/cloudflared/main.tf`
6. Update `null_resource.cloudflared_credentials` triggers and provisioner command in `cloudflared/main.tf`
7. Run `./deploy.sh`

---

## Monitoring

Grafana is pre-provisioned with a cAdvisor dashboard showing CPU, memory, network traffic, and container uptime. Access it at [grafana.nuga.dev](https://grafana.nuga.dev).

> **Note:** After a redeploy, update the Prometheus data source URL in Grafana with the new container IP:
> ```bash
> docker inspect prometheus --format '{{.NetworkSettings.Networks.homelab.IPAddress}}'
> ```

Also update `services/prometheus/config/prometheus.yml` with the new cAdvisor IP after each redeploy, then restart Prometheus:
```bash
docker restart prometheus
```

---

## Gaming

MinePanel is accessible at [minepanel.nuga.dev](https://minepanel.nuga.dev) behind Cloudflare Access. It supports:

- Java and Bedrock Minecraft servers
- Modpack installation via CurseForge and Modrinth (API key required)
- Real-time server metrics and logs
- Automatic backups

Server data is persisted in `services/minepanel/data/servers/` on the host.

---

## Notes

- **Docker Desktop required on Mac** — Docker Desktop handles all networking natively, unlike Podman which has rootless limitations on Mac.
- **Linux users** — Docker Engine works natively with no special configuration needed.
- Cloudflare Tunnel handles all external HTTPS — no port forwarding or firewall rules needed.
- Homepage config files are stored as bind mounts and persist across deploys.
- Grafana dashboards are provisioned from JSON files in the repo and persist across deploys.
- MinePanel server data is stored as a bind mount and persists across deploys.

---

## Troubleshooting

**502 Bad Gateway** — A container's IP changed after a restart. Run `./deploy.sh` to pick up the new IPs automatically.

**Tunnel shows as inactive** — Check cloudflared logs: `docker logs cloudflared`. Ensure the credentials file exists in the volume:
```bash
docker run --rm -v cloudflared_config:/etc/cloudflared alpine cat /etc/cloudflared/config.yml
```

**Grafana shows no data** — Update the Prometheus data source URL with the current IP:
```bash
docker inspect prometheus --format '{{.NetworkSettings.Networks.homelab.IPAddress}}'
```

**Network already exists error** — Run:
```bash
docker network rm homelab
cd network && terraform state rm docker_network.homelab && cd ..
./deploy.sh
```

**MinePanel can't create servers** — Ensure Docker socket is mounted correctly and `BASE_DIR` points to a valid host path that Docker Desktop can access.