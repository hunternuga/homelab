#!/bin/bash
ip=$(docker inspect cadvisor --format '{{.NetworkSettings.Networks.homelab.IPAddress}}')
echo "{\"ip\": \"$ip\"}"