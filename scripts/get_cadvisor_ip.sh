#!/bin/bash
ip=$(podman inspect cadvisor --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"