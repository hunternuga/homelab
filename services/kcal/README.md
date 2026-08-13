# kcal

A lightweight, self-hosted calorie and macro tracker. Log meals, see daily
and weekly totals, done — no accounts with third parties, no ads, no
telemetry, one small container with a SQLite file.

Built as (and freely usable as) a standalone self-hosted project — see
[chart/kcal](chart/kcal/) if you just want to run it on your own cluster
without any of the surrounding homelab repo.

## Features

- Multi-user accounts (bcrypt-hashed passwords, signed session cookies)
- Log meals with calories, protein, carbs, and fat
- Today's dashboard with running totals
- 30-day history with per-day and weekly totals
- Single static Go binary + SQLite — one container, no external database

## Running it

**Standalone via Helm** (any Kubernetes cluster):

```bash
helm install kcal ./chart/kcal --set sessionSecret="$(openssl rand -base64 32)"
```

See [chart/kcal/README.md](chart/kcal/README.md) for all chart values.

**Via Docker:**

```bash
docker run -p 8080:8080 \
  -e SESSION_SECRET="$(openssl rand -base64 32)" \
  -v kcal-data:/data \
  ghcr.io/hunternuga/kcal:latest
```

**Locally, for development** (requires Go 1.23+):

```bash
cd app
SESSION_SECRET=dev-secret DB_PATH=./kcal.db go run ./cmd/kcal
```

Then visit `http://localhost:8080` and register the first account at
`/register`.

## Configuration

| Env var | Default | Description |
|---|---|---|
| `PORT` | `8080` | Port to listen on |
| `DB_PATH` | `/data/kcal.db` | Path to the SQLite database file |
| `SESSION_SECRET` | — | **Required.** Signs session cookies; rotating it logs everyone out |

## In this repo

`services/kcal/` is deployed alongside the rest of this homelab, but via its
Helm chart (`helm_release` in `main.tf`) rather than raw Terraform
`kubernetes_*` resources, since a Helm chart is what makes it independently
installable by anyone else self-hosting it. See the top-level
[README](../../README.md) for how it fits into the overall deploy.

## License

[MIT](LICENSE)
