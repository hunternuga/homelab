# nuga homelab

A self-hosted homelab stack managed with Terraform, running on a mini PC on
the home network. Most services run as Kubernetes workloads on a
single-node k3s cluster; MinePanel runs as plain Docker instead, since it
needs direct access to the Docker socket. Everything is exposed securely
through Cloudflare Tunnel — no port forwarding required.

## Stack

| Layer | Tool |
|---|---|
| Infrastructure as code | Terraform |
| Container orchestration | Kubernetes (k3s), plus plain Docker for MinePanel |
| Ingress | Traefik (bundled with k3s), fronted by Cloudflare Zero Trust Tunnel |
| Auth | Per-service — see the Services table and "Why no Cloudflare Access" below |

## Services

| Service | URL | Auth |
|---|---|---|
| [Home Assistant](services/home-assistant/) | [home.nuga.dev](https://home.nuga.dev) | Home Assistant login |
| [Collection Tracker](services/collection-tracker/) | [collection.nuga.dev](https://collection.nuga.dev) | Cloudflare Access |
| [MinePanel](services/minepanel/) | [minepanel.nuga.dev](https://minepanel.nuga.dev) | Cloudflare Access (frontend) + its own login |

`nuga.dev` itself (the apex domain) isn't part of this stack — it's routed
via Cloudflare DNS to a GitHub Pages-hosted portfolio site
(`hunternuga.github.io`), managed entirely outside this repo. Only
subdomains under it (like `home.nuga.dev`) belong to this Terraform.

### Why no Cloudflare Access

The Home Assistant iOS Companion App makes raw (non-browser) API calls that
choke on Cloudflare Access's HTML login challenge instead of the JSON they
expect, and Access has no native way to exempt just the app's traffic
(no User-Agent/header selector) short of enrolling every device in
Cloudflare WARP. Home Assistant's own login — which has IP-ban-after-
failed-attempts enabled by default — is the auth boundary instead.

## Cluster

One bare-metal mini PC on the home network (Debian 13, 8 threads, 16GB RAM)
running k3s server, control-plane and app workloads together, plus Docker
for MinePanel — this is a small enough stack that splitting any of this out
isn't worth the extra complexity right now. Previously ran on an AWS
Lightsail VM; moved here to avoid the monthly cost and because the hardware
is strong enough to also run MinePanel's Minecraft server containers.

**Provisioning** (there's no cloud API to drive for physical hardware, so
this is the manual, one-time setup after a fresh OS install):

```bash
curl -sfL https://get.k3s.io | sh -
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
```

Terraform itself isn't packaged for Debian — add HashiCorp's apt repo first:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```

Copy `/etc/rancher/k3s/k3s.yaml` from the node if you want `kubectl`/Terraform
access from elsewhere — swap `127.0.0.1` for the node's IP. Every
Kubernetes-based service module's `provider "kubernetes"` block defaults
`config_path` to `/etc/rancher/k3s/k3s.yaml`, which is why Terraform runs
directly on the node. `services/minepanel/`'s `provider "docker"` block
likewise defaults to the node's local Docker socket.

## Setup

**Prerequisites:** [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0, a running k3s cluster + Docker (see "Cluster" above for provisioning a fresh node), a Cloudflare account with a domain.

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

`services/home-assistant/terraform.tfvars` is optional — only needed if you
want to override the default `timezone` (`America/Denver`).

Create `services/collection-tracker/terraform.tfvars`:

```hcl
collection_postgres_password  = "generate-a-password"
collection_ebay_client_id     = "your-ebay-client-id"
collection_ebay_client_secret = "your-ebay-client-secret"
collection_ha_token           = "your-ha-long-lived-access-token"
collection_ha_notify_service  = "notify.mobile_app_your_device"
```

Create `services/minepanel/terraform.tfvars`:

```hcl
minepanel_jwt_secret = "$(openssl rand -base64 32)"
```

**2. Deploy**

```bash
./deploy.sh          # deploy all services
./deploy.sh plan     # preview changes
./deploy.sh destroy  # tear everything down
```

You can run `./deploy.sh` by hand from the k3s node (or anywhere with
`/etc/rancher/k3s/k3s.yaml` copied locally), or let CI/CD do it — see
below.

## CI/CD

> **Status:** the runner (`homelab-minipc`) is registered and running on
> the mini PC. One real limitation: `deploy.sh` runs with `set -e`, so a
> push-triggered deploy stops at the first service that fails — right now
> that's `collection-tracker` (no secrets yet, see above), which means
> `minepanel` and `cloudflared` (ordered after it in `DIRS`) won't pick up
> *new* changes via CI until collection-tracker is either deployed for
> real or moved later in `DIRS`. Apply those two manually in the meantime
> if you change them.

A self-hosted GitHub Actions runner on the k3s node builds and pushes the
`collection-tracker` container image to GHCR, then runs `./deploy.sh`
(pushes to `main`) or `./deploy.sh plan` (pull requests). Home Assistant
needs no build step since it uses the public upstream image directly, but
still gets applied along with everything else since `deploy.sh` loops over
every service.

**One-time runner setup**, on the k3s node:

```bash
sudo apt-get install -y podman

# The "latest/download/<fixed-filename>" URL only works while the asset
# filename has no version in it — GitHub's actual releases are versioned
# (e.g. actions-runner-linux-x64-2.338.2.tar.gz), so resolve it dynamically.
RUNNER_URL=$(gh api repos/actions/runner/releases/latest --jq '.assets[] | select(.name | test("linux-x64-.*\\.tar\\.gz$")) | .browser_download_url')
TOKEN=$(gh api repos/hunternuga/homelab/actions/runners/registration-token -X POST --jq .token)

curl -sS -o actions-runner.tar.gz -L "$RUNNER_URL"
mkdir actions-runner && tar xzf actions-runner.tar.gz -C actions-runner
cd actions-runner
sudo ./bin/installdependencies.sh   # .NET runtime deps config.sh needs
./config.sh --url https://github.com/hunternuga/homelab --token "$TOKEN" --name "$(hostname)" --unattended
sudo ./svc.sh install
sudo ./svc.sh start
```

Then create `~/.homelab-secrets/cloudflared.tfvars`,
`~/.homelab-secrets/collection-tracker.tfvars`, and
`~/.homelab-secrets/minepanel.tfvars` on the node with the same contents as
the `terraform.tfvars` files above — the workflow restores these before
every plan/apply so secrets never touch the repo.

## External Manual Setup

A few things aren't Terraform-managed and need to be done by hand, once,
after the first deploy:

1. **Nest integration** — requires a Google Cloud project and registering
   for [Google's Device Access program](https://developers.google.com/nest/device-access) (one-time $5 fee) before adding the
   Nest integration in the Home Assistant UI.
2. **Blink integration** — built into Home Assistant core. Add it via
   *Settings → Devices & Services* after first boot; your Blink
   email/password and 2FA code are entered there, not stored anywhere in
   this repo.
3. **Echo Show (best-effort)** — Amazon doesn't expose an official
   integration path. If you want to try it, install
   [HACS](https://hacs.xyz/) inside the running instance, then the
   community "Alexa Media Player" integration. This is fragile and breaks
   periodically when Amazon changes things — treat it as optional.
4. **Reverse proxy trust fix** — Home Assistant will reject logins behind
   a reverse proxy until you add this to its `configuration.yaml` (only
   generated after first boot, so this can't be pre-seeded by Terraform):

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 10.42.0.0/16   # k3s's default pod CIDR — confirm with:
                        # kubectl cluster-info dump | grep -m1 cluster-cidr
   ```

   Edit the file (`kubectl exec` into the pod, or Home Assistant's File
   Editor add-on), then restart it:

   ```bash
   kubectl rollout restart deployment/home-assistant -n homelab
   ```

5. **eBay Developer Program app** (for Collection Tracker) — register at
   [developer.ebay.com](https://developer.ebay.com), create a Production
   keyset, and use its Client ID/Secret for
   `collection_ebay_client_id`/`collection_ebay_client_secret`.
6. **Home Assistant long-lived access token** (for Collection Tracker's
   notifications) — generate one in the Home Assistant UI under your
   profile page → Long-Lived Access Tokens.
7. **Look up your notify service name** — in the running Home Assistant
   instance, check Developer Tools → Services (or Settings → Devices →
   your phone) for the exact `notify.mobile_app_<device>` service; it
   depends on your device's registered name so it can't be guessed ahead
   of time.
8. **Adding future wanted items** to Collection Tracker — there's no admin
   UI for this (rarely-used, single-user path); insert rows directly:

   ```bash
   kubectl exec -it deploy/collection-postgres -n homelab -- psql -U collection -d collection
   ```

## Adding a Service

1. Create a directory under `services/`
2. Add a `main.tf` with a `kubernetes_deployment`, `kubernetes_service`, and (if it needs to be reachable from outside the cluster) a `kubernetes_ingress_v1` pointed at `<name>.nuga.dev` — copy `services/home-assistant/main.tf` as a minimal template. Alternatively, if the service ships as (or has) a Helm chart, use a `helm_release` resource instead.
   - If the service genuinely can't run in Kubernetes (needs the host's Docker socket, like MinePanel), use the `kreuzwerker/docker` provider and `docker_container` resources instead — copy `services/minepanel/main.tf` as a template. In that case cloudflared's ingress config needs a rule pointing straight at the node's LAN IP and published port instead of at Traefik (see `local.cloudflared_config` in `services/cloudflared/main.tf`).
3. Add the service's directory to `DIRS` in `deploy.sh`, before `cloudflared`
4. Add a DNS record (and optionally a Cloudflare Access policy) in `services/cloudflared/main.tf` — for a Kubernetes-based service, cloudflared itself doesn't need any changes, since it routes every hostname to Traefik and Traefik dispatches by the Ingress rules already in the cluster
5. Run `./deploy.sh`
