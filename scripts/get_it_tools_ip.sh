#!/bin/bash
ip=$(podman inspect it-tools --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"