#!/bin/bash
ip=$(docker inspect prometheus --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"