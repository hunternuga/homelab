#!/bin/bash
ip=$(docker inspect homepage --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"