#!/bin/bash

set -e

HOMELAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIRS=(
  "$HOMELAB_DIR/network"
  "$HOMELAB_DIR/services/homepage"
  "$HOMELAB_DIR/services/cloudflared"
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

case "${1:-apply}" in
  apply)
    echo "Deploying homelab..."
    for dir in "${DIRS[@]}"; do
      # Clean up any existing containers to avoid Podman netavark conflicts
      if [[ "$dir" == *"homepage"* ]]; then
        echo ""
        echo "Cleaning up existing homepage container if present..."
        podman rm -f homepage 2>/dev/null || true
      fi
      if [[ "$dir" == *"cloudflared"* ]]; then
        echo ""
        echo "Cleaning up existing cloudflared container if present..."
        podman rm -f cloudflared 2>/dev/null || true
      fi
      run_terraform "$dir"
    done
    echo ""
    echo "Deploy complete! homepage.nuga.dev should be live shortly."
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
    echo "Planning homelab..."
    for dir in "${DIRS[@]}"; do
      local name=$(basename "$dir")
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