#!/bin/bash
ip=$(docker inspect it-tools --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"