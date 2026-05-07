# 🏠 nuga homelab

A self-hosted homelab stack managed with Terraform, running containerized services exposed securely via Cloudflare Tunnel — no port forwarding required.

## Stack

- **Container runtime** — Podman (Docker-compatible)
- **Infrastructure as code** — Terraform with the [kreuzwerker Docker provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest)
- **Tunnel** — Cloudflare Zero Trust Tunnel (`cloudflared`)
- **Services** — Homepage dashboard (more coming soon)

---

## Prerequisites

Before you begin, make sure you have the following installed:

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.0`
- [Podman](https://podman.io/docs/installation) with a running machine (`podman machine start`)
- A [Cloudflare](https://cloudflare.com) account with a domain configured
- A Cloudflare API token with the following permissions:
  - **Account → Cloudflare Tunnel → Edit**
  - **Zone → DNS → Edit** (scoped to your domain)

---

## Project Structure

```
homelab/
├── deploy.sh                   # One-command deploy/destroy/plan script
├── scripts/
│   └── get_homepage_ip.sh      # Dynamic container IP resolver
├── network/
│   ├── main.tf                 # Shared Docker network
│   └── versions.tf
└── services/
    ├── homepage/
    │   ├── main.tf             # Homepage dashboard container
    │   ├── versions.tf
    │   └── outputs.tf
    └── cloudflared/
        ├── main.tf             # Cloudflare Tunnel + ingress config
        ├── versions.tf
        ├── variables.tf
        ├── outputs.tf
        └── terraform.tfvars    # Your secrets (never commit this)
```

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/youruser/homelab.git
cd homelab
```

### 2. Configure Podman socket

Find your Podman socket path and note it down — you'll need it for the provider config:

```bash
podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}'
```

Update the `host` field in `network/versions.tf` and `services/homepage/versions.tf` with this path.

### 3. Create the shared network

The homelab network must be created manually with DNS disabled to allow cloudflared to use external DNS resolvers:

```bash
podman network create --disable-dns homelab
```

Then import it into Terraform state:

```bash
cd network
terraform init
terraform import docker_network.homelab homelab
cd ..
```

### 4. Configure secrets

Copy the example vars file and fill in your values:

```bash
cp services/cloudflared/terraform.tfvars.example services/cloudflared/terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
cloudflare_api_token = "your-api-token-here"
cloudflare_zone_id   = "your-zone-id-here"
tunnel_secret        = "$(openssl rand -base64 32)"
```

> **Never commit `terraform.tfvars` to version control.** It is listed in `.gitignore`.

### 5. Make scripts executable

```bash
chmod +x deploy.sh
chmod +x scripts/get_homepage_ip.sh
```

### 6. Deploy

```bash
./deploy.sh
```

This will:
1. Apply the shared network (if not already imported)
2. Build and start the homepage container
3. Create the Cloudflare Tunnel, push ingress rules, create DNS records, and start cloudflared

Once complete, your homepage will be live at `https://homepage.nuga.dev` (or your configured domain).

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

2. Add the service to the deploy order in `deploy.sh`:

```bash
DIRS=(
  "$HOMELAB_DIR/network"
  "$HOMELAB_DIR/services/homepage"
  "$HOMELAB_DIR/services/myservice"   # <- add here
  "$HOMELAB_DIR/services/cloudflared"
)
```

3. Add a new ingress rule to `services/cloudflared/main.tf`:

```hcl
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  ...
  config {
    ingress_rule {
      hostname = "homepage.nuga.dev"
      service  = "http://homepage:3000"
    }
    ingress_rule {
      hostname = "myservice.nuga.dev"   # <- add here
      service  = "http://myservice:PORT"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}
```

4. Add a DNS record for the new service:

```hcl
resource "cloudflare_record" "myservice" {
  zone_id = var.cloudflare_zone_id
  name    = "myservice"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
```

5. Add a `host` entry in the cloudflared container for the new service's IP.

6. Run `./deploy.sh` to apply everything.

---

## Services

| Service | URL | Description |
|---|---|---|
| Homepage | [homepage.nuga.dev](https://homepage.nuga.dev) | Homelab dashboard |

---

## Notes

- **Mac users** — Closing the laptop lid will suspend Podman and drop the tunnel. Use [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704) to keep the Mac awake with the lid closed, and enable **System Settings → Battery → Options → Prevent automatic sleeping when the display is off**.
- **Linux users** — No special configuration needed. Services will run 24/7 as long as the machine is on.
- Cloudflare Tunnel handles all external HTTPS — no port forwarding or firewall rules needed.
- All container data is stored in named Podman volumes.

---

## Troubleshooting

**502 Bad Gateway** — The homepage container's IP may have changed. Re-run `./deploy.sh` to let Terraform pick up the new IP dynamically.

**Tunnel shows as inactive** — Check cloudflared logs: `podman logs cloudflared`. Ensure the credentials file exists in the volume and DNS is resolving correctly.

**Container networking issues after redeploy** — Run `podman rm -f <container>` before re-applying if you hit Podman netavark errors.
