#!/bin/bash
ip=$(podman inspect prometheus --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"