#!/bin/sh
# Config is generated at container start from environment variables.
# Required: XRAY_UUID, WS_PATH. Optional: PORT (default 3000).
# DNS: xray resolves outbound domains via Google + Cloudflare DoH,
# not the platform default resolver.
set -eu
UUID="${XRAY_UUID:?XRAY_UUID env var is required}"
WS_PATH="${WS_PATH:?WS_PATH env var is required}"
PORT="${PORT:-3000}"
mkdir -p /etc/xray
cat > /etc/xray/config.json <<JSON
{
  "log": {"loglevel": "warning"},
  "dns": {"servers": ["https://dns.google/dns-query", "https://cloudflare-dns.com/dns-query", "8.8.8.8", "1.1.1.1"]},
  "inbounds": [{
    "port": ${PORT}, "listen": "0.0.0.0", "protocol": "vless",
    "settings": {"clients": [{"id": "${UUID}", "flow": ""}], "decryption": "none"},
    "streamSettings": {"network": "ws", "wsSettings": {"path": "${WS_PATH}"}}
  }],
  "outbounds": [{"protocol": "freedom", "settings": {}}, {"protocol": "blackhole", "settings": {}, "tag": "blocked"}]
}
JSON
exec /usr/local/bin/xray run -config /etc/xray/config.json
