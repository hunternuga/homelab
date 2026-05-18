#!/bin/bash
ip=$(docker inspect grafana --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"