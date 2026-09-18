# nuga homelab

A self-hosted homelab stack managed with Terraform. Services run as
Kubernetes workloads on a single-node k3s cluster and are exposed securely
through Cloudflare Tunnel — no port forwarding required.

## Stack

| Layer | Tool |
|---|---|
| Infrastructure as code | Terraform |
| Container orchestration | Kubernetes (k3s) |
| Ingress | Traefik (bundled with k3s), fronted by Cloudflare Zero Trust Tunnel |
| Auth | Home Assistant's own login — see "Why no Cloudflare Access" below |

## Services

| Service | URL | Auth |
|---|---|---|
| [Home Assistant](services/home-assistant/) | [home.nuga.dev](https://home.nuga.dev) | Home Assistant login |

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

One AWS Lightsail instance (Ubuntu 24.04, `medium_3_0`, 4GB plan) running
k3s server, control-plane and app workloads together — this is a small
enough stack that splitting control-plane and app nodes isn't worth the
extra cost or complexity right now.

**Provisioning:**

```bash
curl -sfL https://get.k3s.io | sh -
```

Copy `/etc/rancher/k3s/k3s.yaml` from the node if you want `kubectl`/Terraform
access from elsewhere — swap `127.0.0.1` for the node's IP. Every service
module's `provider "kubernetes"` block defaults `config_path` to
`/etc/rancher/k3s/k3s.yaml`, which is why Terraform runs directly on the
node.

## Setup

**Prerequisites:** [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0, a running k3s cluster (see above), a Cloudflare account with a domain.

**1. Provision the node**

```bash
cd infra
terraform init
terraform apply
```

**2. Configure secrets**

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

**3. Deploy**

```bash
./deploy.sh          # deploy all services
./deploy.sh plan     # preview changes
./deploy.sh destroy  # tear everything down
```

Deploys are manual — run `./deploy.sh` from the k3s node (or anywhere with
`/etc/rancher/k3s/k3s.yaml` copied locally) whenever you want to apply
changes. There's no CI/CD wired up right now; this stack is small enough
that it isn't worth the setup.

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

## Adding a Service

1. Create a directory under `services/`
2. Add a `main.tf` with a `kubernetes_deployment`, `kubernetes_service`, and (if it needs to be reachable from outside the cluster) a `kubernetes_ingress_v1` pointed at `<name>.nuga.dev` — copy `services/home-assistant/main.tf` as a minimal template. Alternatively, if the service ships as (or has) a Helm chart, use a `helm_release` resource instead.
3. Add the service's directory to `DIRS` in `deploy.sh`, before `cloudflared`
4. Add a DNS record (and optionally a Cloudflare Access policy) in `services/cloudflared/main.tf` — cloudflared itself doesn't need any changes, since it routes every hostname to Traefik and Traefik dispatches by the Ingress rules already in the cluster
5. Run `./deploy.sh`
