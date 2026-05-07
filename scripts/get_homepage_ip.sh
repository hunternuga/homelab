#!/bin/bash
ip=$(podman inspect homepage --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"
