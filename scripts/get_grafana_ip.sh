#!/bin/bash
ip=$(podman inspect grafana --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"