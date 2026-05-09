#!/bin/bash

TUNNEL_ID=$1
TUNNEL_SECRET=$2
HOMEPAGE_IP=$3
IT_TOOLS_IP=$4
GRAFANA_IP=$5

podman run --rm -v cloudflared_config:/etc/cloudflared alpine sh -c "
cat > /etc/cloudflared/${TUNNEL_ID}.json << EOF
{
  \"AccountTag\": \"a1d47b88a31b30932d1974da0a55e80e\",
  \"TunnelID\": \"${TUNNEL_ID}\",
  \"TunnelSecret\": \"${TUNNEL_SECRET}\"
}
EOF

cat > /etc/cloudflared/config.yml << EOF
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json
ingress:
  - hostname: homepage.nuga.dev
    service: http://${HOMEPAGE_IP}:3000
  - hostname: tools.nuga.dev
    service: http://${IT_TOOLS_IP}:80
  - hostname: grafana.nuga.dev
    service: http://${GRAFANA_IP}:3000
  - service: http_status:404
EOF
"