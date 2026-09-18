#!/bin/bash

set -e

HOMELAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.homelab-state"

DIRS=(
  "$HOMELAB_DIR/network"
  "$HOMELAB_DIR/services/home-assistant"
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

case "${1:-apply}" in
  apply)
    echo "Deploying homelab..."

    restore_state

    for dir in "${DIRS[@]}"; do
      run_terraform "$dir"
    done

    backup_state

    echo ""
    echo "Deploy complete!"
    echo "  home-assistant -> https://home.nuga.dev"
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
