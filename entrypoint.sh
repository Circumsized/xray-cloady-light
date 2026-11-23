#!/bin/sh
# Config is generated at container start from environment variables.
# Required: XRAY_UUID, WS_PATH, DOMAIN. Optional: PORT (default 3000).
# Architecture: Caddy (front door on $PORT) routes /sub to the subscription
# endpoint (socat + CGI script with live traffic counters) and everything
# else to xray (VLESS+WS on 127.0.0.1:10000). xray stats (email-keyed)
# feed the subscription-userinfo header, so Clash shows the quota.
# Note: Alpine's busybox has no httpd applet, so socat serves the endpoint.
set -eu
UUID="${XRAY_UUID:?XRAY_UUID env var is required}"
WS_PATH="${WS_PATH:?WS_PATH env var is required}"
DOMAIN="${DOMAIN:?DOMAIN env var is required}"
PORT="${PORT:-3000}"
mkdir -p /etc/xray /etc/caddy /www/cgi-bin

# Full Clash config (rules + groups + DNS) with the live node values.
sed -e "s|__UUID__|${UUID}|g" -e "s|__DOMAIN__|${DOMAIN}|g" -e "s|__WS_PATH__|${WS_PATH}|g" \
  /clash-template.yaml > /www/clash.yaml

# Subscription endpoint: full config + live traffic counters.
# socat runs this script once per connection (socket = stdin/stdout),
# so the script drains the request headers, then writes a full HTTP reply.
cat > /www/cgi-bin/sub <<'EOS'
#!/bin/sh
while IFS= read -r _line; do
  _line=$(printf '%s' "$_line" | tr -d '\r')
  [ -z "$_line" ] && break
done
UP=$(/usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern "user>>>user@cloady>>>traffic>>>uplink" 2>/dev/null | grep -o '[0-9]*$' | head -1)
DOWN=$(/usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern "user>>>user@cloady>>>traffic>>>downlink" 2>/dev/null | grep -o '[0-9]*$' | head -1)
UP=${UP:-0}; DOWN=${DOWN:-0}
LEN=$(wc -c < /www/clash.yaml)
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/yaml; charset=utf-8\r\nsubscription-userinfo: upload=%s; download=%s; total=10737418240; expire=0\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' "$UP" "$DOWN" "$LEN"
cat /www/clash.yaml
EOS
chmod +x /www/cgi-bin/sub

# Caddy: front door on $PORT.
cat > /etc/caddy/Caddyfile <<EOF
{
    admin off
}
:${PORT} {
    handle /sub {
        rewrite * /cgi-bin/sub
        reverse_proxy 127.0.0.1:8080
    }
    handle {
        reverse_proxy 127.0.0.1:10000
    }
}
EOF

# xray: VLESS+WS on localhost, stats + api for the counters, DoH DNS.
cat > /etc/xray/config.json <<JSON
{
  "log": {"loglevel": "warning"},
  "stats": {},
  "policy": {"levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}}},
  "api": {"tag": "api", "services": ["StatsService"]},
  "dns": {"servers": ["https://dns.google/dns-query", "https://cloudflare-dns.com/dns-query", "8.8.8.8", "1.1.1.1"]},
  "inbounds": [
    {"port": 10085, "listen": "127.0.0.1", "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"}, "tag": "api"},
    {"port": 10000, "listen": "127.0.0.1", "protocol": "vless",
     "settings": {"clients": [{"id": "${UUID}", "flow": "", "email": "user@cloady"}], "decryption": "none"},
     "streamSettings": {"network": "ws", "wsSettings": {"path": "${WS_PATH}"}}}
  ],
  "outbounds": [{"protocol": "freedom", "settings": {}}, {"protocol": "blackhole", "settings": {}, "tag": "blocked"}],
  "routing": {"rules": [{"type": "field", "inboundTag": ["api"], "outboundTag": "api"}]}
}
JSON

socat TCP-LISTEN:8080,bind=127.0.0.1,fork,reuseaddr EXEC:/www/cgi-bin/sub &
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
exec /usr/local/bin/xray run -config /etc/xray/config.json
