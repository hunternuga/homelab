#!/bin/bash
ip=$(docker inspect minepanel --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"