#!/bin/bash

set -e

HOMELAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.homelab-state"

DIRS=(
  "$HOMELAB_DIR/network"
  "$HOMELAB_DIR/services/homepage"
  "$HOMELAB_DIR/services/it-tools"
  "$HOMELAB_DIR/services/cadvisor"
  "$HOMELAB_DIR/services/prometheus"
  "$HOMELAB_DIR/services/grafana"
  "$HOMELAB_DIR/services/cloudflared"
)

restore_state() {
  [[ ! -d "$STATE_DIR" ]] && return 0
  echo ""
  echo "========================================="
  echo " Restoring Terraform state"
  echo "========================================="
  for dir in "${DIRS[@]}"; do
    local name
    name=$(basename "$dir")
    if [[ -f "$STATE_DIR/$name.tfstate" ]]; then
      echo "  $name"
      cp "$STATE_DIR/$name.tfstate" "$dir/terraform.tfstate"
    fi
  done
}

backup_state() {
  mkdir -p "$STATE_DIR"
  echo ""
  echo "========================================="
  echo " Backing up Terraform state"
  echo "========================================="
  for dir in "${DIRS[@]}"; do
    local name
    name=$(basename "$dir")
    if [[ -f "$dir/terraform.tfstate" ]]; then
      echo "  $name"
      cp "$dir/terraform.tfstate" "$STATE_DIR/$name.tfstate"
    fi
  done
}

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

  # homepage's config-init step aborts entirely if any of these is missing
  # (it can't fall back to copying its own defaults into a read-only mount),
  # even though we never customize them.
  for f in kubernetes.yaml docker.yaml proxmox.yaml custom.css custom.js; do
    if [[ ! -f "$config_dir/$f" ]]; then
      echo "$f missing — creating empty..."
      touch "$config_dir/$f"
    fi
  done

  echo "Homepage config OK."
}

case "${1:-apply}" in
  apply)
    echo "Deploying homelab..."

    ensure_homepage_config

    restore_state

    for dir in "${DIRS[@]}"; do
      run_terraform "$dir"
    done

    backup_state

    echo ""
    echo "Deploy complete!"
    echo "  homepage   -> https://homepage.nuga.dev"
    echo "  it-tools   -> https://tools.nuga.dev"
    echo "  grafana    -> https://grafana.nuga.dev"
    ;;

  destroy)
    echo "Destroying homelab..."
    for dir in "${!DIRS[@]}"; do
      destroy_terraform "${DIRS[$(( ${#DIRS[@]} - 1 - $dir ))]}"
    done
    echo ""
    echo "All resources destroyed."
    ;;

  plan)
    restore_state
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