# syntax=docker/dockerfile:1
# Stage 1: official xray image (no shell) - copy the binary out only
FROM ghcr.io/xtls/xray-core:latest AS xray
# Stage 2: Alpine with shell + entrypoint (lightweight)
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata caddy socat
COPY --from=xray /usr/local/bin/xray /usr/local/bin/xray
COPY entrypoint.sh /entrypoint.sh
COPY clash-template.yaml /clash-template.yaml
RUN chmod +x /entrypoint.sh /usr/local/bin/xray
EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
