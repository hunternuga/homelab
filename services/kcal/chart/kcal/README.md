# kcal Helm chart

Installs [kcal](../../README.md), a lightweight self-hosted calorie and
macro tracker, on any Kubernetes cluster. This chart works standalone —
you don't need the rest of this repo to use it.

## Install

```bash
helm install kcal ./chart/kcal \
  --set sessionSecret="$(openssl rand -base64 32)" \
  --set ingress.enabled=true \
  --set ingress.host=kcal.example.com
```

Without `ingress.enabled=true`, reach it via port-forward:

```bash
kubectl port-forward svc/kcal 8080:8080
```

Then open the app and register the first account at `/register`.

## Values

| Key | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/hunternuga/kcal` | Image to deploy |
| `image.tag` | `latest` | Image tag |
| `replicaCount` | `1` | Do not scale beyond 1 — SQLite is single-writer |
| `service.port` | `8080` | Service port |
| `ingress.enabled` | `false` | Create an Ingress |
| `ingress.className` | `traefik` | IngressClass name |
| `ingress.host` | `kcal.example.com` | Hostname to route |
| `persistence.enabled` | `true` | Create a PVC for the SQLite file |
| `persistence.size` | `1Gi` | PVC size |
| `persistence.storageClassName` | `""` | StorageClass (empty = cluster default) |
| `sessionSecret` | `""` | Plaintext secret used to sign session cookies; the chart creates a Secret from it |
| `existingSecret` | `""` | Name of a pre-existing Secret with a `session-secret` key, instead of `sessionSecret` |

Exactly one of `sessionSecret` / `existingSecret` must be set, or the chart
refuses to render.
