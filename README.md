# 🏠 nuga homelab

A self-hosted homelab stack managed with Terraform, running containerized services exposed securely via Cloudflare Tunnel — no port forwarding required.

## Stack

- **Container runtime** — Podman (Docker-compatible)
- **Infrastructure as code** — Terraform with the [kreuzwerker Docker provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest)
- **Tunnel** — Cloudflare Zero Trust Tunnel (`cloudflared`)
- **Auth** — Cloudflare Access (email-based OTP + passkey support)
- **Monitoring** — Prometheus + cAdvisor + Grafana

---

## Services

| Service | URL | Description | Auth |
|---|---|---|---|
| Homepage | [homepage.nuga.dev](https://homepage.nuga.dev) | Homelab dashboard | Public |
| IT Tools | [tools.nuga.dev](https://tools.nuga.dev) | Developer utilities toolkit | Cloudflare Access |
| Grafana | [grafana.nuga.dev](https://grafana.nuga.dev) | Metrics and dashboards | Cloudflare Access |
| Prometheus | Internal only | Metrics scraping | None |
| cAdvisor | Internal only | Container metrics collection | None |

---

## Prerequisites

Before you begin, make sure you have the following installed:

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.0`
- [Podman](https://podman.io/docs/installation) with a running machine (`podman machine start`)
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
│   ├── get_homepage_ip.sh             # Dynamic container IP resolver
│   ├── get_it_tools_ip.sh
│   ├── get_grafana_ip.sh
│   ├── get_prometheus_ip.sh
│   ├── get_cadvisor_ip.sh
│   └── write_cloudflared_config.sh   # Writes tunnel credentials + ingress config
├── network/
│   ├── main.tf                        # Shared Docker network
│   └── versions.tf
└── services/
    ├── homepage/
    │   ├── config/                    # Homepage config files (persisted, not in volume)
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
    │   │   │   ├── dashboards.yaml    # Dashboard provisioning config
    │   │   │   └── cadvisor.json      # Exported dashboard JSON
    │   │   └── datasources/
    │   │       └── prometheus.yaml    # Prometheus data source config
    │   ├── main.tf
    │   ├── versions.tf
    │   └── outputs.tf
    └── cloudflared/
        ├── main.tf                    # Cloudflare Tunnel + ingress + Access policies
        ├── versions.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars          # Your secrets (never commit this)
```

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/youruser/homelab.git
cd homelab
```

### 2. Configure Podman socket

Find your Podman socket path:

```bash
podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}'
```

Update the `host` field in each service's `versions.tf` with this path.

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

> **Never commit `terraform.tfvars` to version control.** It is listed in `.gitignore`.

### 5. Deploy

```bash
./deploy.sh
```

This will:
1. Create the shared Podman network with DNS disabled
2. Deploy homepage, IT Tools, cAdvisor, Prometheus, and Grafana
3. Create the Cloudflare Tunnel, push ingress rules, create DNS records, and start cloudflared
4. Set up Cloudflare Access policies for protected services

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

1. Create a new directory under `services/`:

```
services/
└── myservice/
    ├── main.tf
    ├── versions.tf
    └── outputs.tf
```

2. Add an IP script under `scripts/`:

```bash
#!/bin/bash
ip=$(podman inspect myservice --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"
```

3. Add the service to the deploy order in `deploy.sh` before cloudflared.

4. Add a new ingress rule to `write_cloudflared_config.sh` and a new argument for the IP.

5. Add DNS record and optionally a Cloudflare Access policy in `services/cloudflared/main.tf`.

6. Update `null_resource.cloudflared_credentials` triggers and provisioner command in `cloudflared/main.tf` to pass the new IP.

7. Run `./deploy.sh`.

---

## Monitoring

Grafana is pre-provisioned with a cAdvisor dashboard showing:

- CPU usage per container
- Memory usage per container
- Network traffic (sent/received) per container
- Container info and uptime

Access it at [grafana.nuga.dev](https://grafana.nuga.dev) — login with the admin credentials set in `services/grafana/main.tf`.

> **Note:** After a redeploy, update the Prometheus data source URL in Grafana with the new container IP. This is a known limitation of running Podman rootless on macOS and will be resolved on the Linux migration.

---

## Notes

- **Mac users** — Closing the laptop lid will suspend Podman and drop the tunnel. Use [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704) to keep the Mac awake with the lid closed, and enable **System Settings → Battery → Options → Prevent automatic sleeping when the display is off**.
- **Linux users** — No special configuration needed. Services will run 24/7 as long as the machine is on. Container name DNS resolution will also work natively, eliminating the IP-based routing workarounds.
- Cloudflare Tunnel handles all external HTTPS — no port forwarding or firewall rules needed.
- Homepage config files are stored as bind mounts and persist across deploys.
- Grafana dashboards are provisioned from JSON files in the repo and persist across deploys.

---

## Troubleshooting

**502 Bad Gateway** — A container's IP changed after a restart. Run `./deploy.sh` to pick up the new IPs automatically.

**Tunnel shows as inactive** — Check cloudflared logs: `podman logs cloudflared`. Ensure the credentials file exists in the volume.

**Grafana shows no data** — Update the Prometheus data source URL with the current Prometheus container IP: `podman inspect prometheus --format '{{.NetworkSettings.Networks.homelab.IPAddress}}'`

**Container networking issues after redeploy** — The deploy script handles this automatically by removing containers before applying. If issues persist, run `podman network rm -f homelab` and re-run `./deploy.sh`.

**Network already exists error** — Run `cd network && terraform import docker_network.homelab homelab && cd .. && ./deploy.sh`.