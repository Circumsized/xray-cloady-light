# xray on Cloady (lightweight)

Multi-stage Dockerfile: xray binary from the official image + Alpine shell.
No secrets in this repo. Set these environment variables in the Cloady dashboard:
- `XRAY_UUID` — VLESS client UUID
- `WS_PATH` — WebSocket path, e.g. `/random-path`
- `PORT` — listen port (default 3000; set to the port configured in Cloady)
