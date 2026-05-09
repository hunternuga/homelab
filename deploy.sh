#!/bin/bash

set -e

HOMELAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIRS=(
  "$HOMELAB_DIR/network"
  "$HOMELAB_DIR/services/homepage"
  "$HOMELAB_DIR/services/it-tools"
  "$HOMELAB_DIR/services/cadvisor"
  "$HOMELAB_DIR/services/prometheus"
  "$HOMELAB_DIR/services/grafana"
  "$HOMELAB_DIR/services/cloudflared"
)

# Container names to clean up before apply (avoids Podman netavark conflicts)
CONTAINERS=(
  "homepage"
  "it-tools"
  "cadvisor"
  "prometheus"
  "grafana"
  "cloudflared"
)

run_terraform() {
  local dir=$1
  local name=$(basename "$dir")

  echo ""
  echo "========================================="
  echo " $name"
  echo "========================================="

  cd "$dir"
  terraform init -upgrade -input=false
  terraform apply -auto-approve -input=false
}

destroy_terraform() {
  local dir=$1
  local name=$(basename "$dir")

  echo ""
  echo "========================================="
  echo " Destroying: $name"
  echo "========================================="

  cd "$dir"
  terraform init -upgrade -input=false
  terraform destroy -auto-approve -input=false
}

network_in_state() {
  cd "$HOMELAB_DIR/network"
  terraform init -upgrade -input=false -no-color 2>/dev/null
  terraform state list 2>/dev/null | grep -q "docker_network.homelab"
}

ensure_network() {
  echo ""
  echo "========================================="
  echo " Checking homelab network"
  echo "========================================="

  local dns_enabled
  dns_enabled=$(podman network inspect homelab --format '{{.DNSEnabled}}' 2>/dev/null || echo "missing")

  if [[ "$dns_enabled" == "missing" ]]; then
    echo "Network not found — creating with DNS disabled..."
    podman network create --disable-dns homelab
  elif [[ "$dns_enabled" == "true" ]]; then
    echo "Network has DNS enabled — recreating with DNS disabled..."
    for container in "${CONTAINERS[@]}"; do
      podman rm -f "$container" 2>/dev/null || true
    done
    podman network rm -f homelab 2>/dev/null || true
    podman network create --disable-dns homelab
  else
    echo "Network OK (DNS disabled)."
  fi

  # Always ensure network is in Terraform state
  cd "$HOMELAB_DIR/network"
  terraform init -upgrade -input=false
  if ! terraform state list 2>/dev/null | grep -q "docker_network.homelab"; then
    echo "Importing network into Terraform state..."
    terraform import docker_network.homelab homelab
  else
    echo "Network already in Terraform state."
  fi
}

ensure_homepage_config() {
  echo ""
  echo "========================================="
  echo " Checking homepage config"
  echo "========================================="

  local config_dir="$HOMELAB_DIR/services/homepage/config"

  if [[ ! -d "$config_dir" ]]; then
    echo "Config directory missing — creating..."
    mkdir -p "$config_dir"
  fi

  if [[ ! -f "$config_dir/services.yaml" ]]; then
    echo "services.yaml missing — creating default..."
    cat > "$config_dir/services.yaml" << EOF
- Infrastructure:
    - Homepage:
        href: https://homepage.nuga.dev
        description: Homelab dashboard

- Tools:
    - IT Tools:
        href: https://tools.nuga.dev
        description: Developer utilities toolkit

- Monitoring:
    - Grafana:
        href: https://grafana.nuga.dev
        description: Metrics and dashboards
EOF
  fi

  if [[ ! -f "$config_dir/settings.yaml" ]]; then
    echo "settings.yaml missing — creating default..."
    cat > "$config_dir/settings.yaml" << EOF
title: nuga homelab
allowedHosts:
  - homepage.nuga.dev
EOF
  fi

  if [[ ! -f "$config_dir/widgets.yaml" ]]; then
    echo "widgets.yaml missing — creating default..."
    cat > "$config_dir/widgets.yaml" << EOF
- resources:
    cpu: true
    memory: true
    disk: /

- search:
    provider: duckduckgo
    target: _blank
EOF
  fi

  if [[ ! -f "$config_dir/bookmarks.yaml" ]]; then
    echo "bookmarks.yaml missing — creating empty..."
    touch "$config_dir/bookmarks.yaml"
  fi

  echo "Homepage config OK."
}

case "${1:-apply}" in
  apply)
    echo "Deploying homelab..."

    ensure_network
    ensure_homepage_config

    for dir in "${DIRS[@]}"; do
      # Skip network dir since we handle it in ensure_network
      if [[ "$dir" == *"network"* ]]; then
        run_terraform "$dir"
        continue
      fi

      # Clean up containers to avoid Podman netavark conflicts
      for container in "${CONTAINERS[@]}"; do
        if [[ "$dir" == *"$container"* ]]; then
          echo ""
          echo "Cleaning up existing $container container if present..."
          podman rm -f "$container" 2>/dev/null || true
        fi
      done

      run_terraform "$dir"
    done

    echo ""
    echo "Deploy complete!"
    echo "  homepage  -> https://homepage.nuga.dev"
    echo "  it-tools  -> https://tools.nuga.dev"
    echo "  grafana   -> https://grafana.nuga.dev"
    ;;

  destroy)
    echo "Destroying homelab..."
    for dir in "${!DIRS[@]}"; do
      destroy_terraform "${DIRS[$(( ${#DIRS[@]} - 1 - $dir ))]}"
    done
    echo ""
    echo "Cleaning up homelab network..."
    podman network rm -f homelab 2>/dev/null || true
    echo ""
    echo "All resources destroyed."
    ;;

  plan)
    echo "Planning homelab..."
    for dir in "${DIRS[@]}"; do
      name=$(basename "$dir")
      echo ""
      echo "========================================="
      echo " Plan: $name"
      echo "========================================="
      cd "$dir"
      terraform init -upgrade -input=false
      terraform plan -input=false
    done
    ;;

  *)
    echo "Usage: ./deploy.sh [apply|destroy|plan]"
    echo ""
    echo "  apply    - Init and apply all services in order (default)"
    echo "  destroy  - Destroy all services in reverse order"
    echo "  plan     - Plan all services in order"
    exit 1
    ;;
esac