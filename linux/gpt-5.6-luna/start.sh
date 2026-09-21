#!/bin/sh
set -eu

if [ "${VT_HTTPS:-true}" = "true" ]; then
  tls_dir="${VT_TLS_DIR:-/data/tls}"
  tls_host="${VT_TLS_HOST:-tamclaw}"
  mkdir -p "$tls_dir"
  if [ ! -s "$tls_dir/server.key" ] || [ ! -s "$tls_dir/server.crt" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout "$tls_dir/server.key" \
      -out "$tls_dir/server.crt" \
      -days 825 \
      -subj "/CN=$tls_host" \
      -addext "subjectAltName=DNS:$tls_host,DNS:localhost,IP:127.0.0.1"
  fi
  exec uvicorn app.main:app --host 0.0.0.0 --port 8000 \
    --ws-ping-interval "${VT_WS_PING_INTERVAL:-15}" \
    --ws-ping-timeout "${VT_WS_PING_TIMEOUT:-30}" \
    --ssl-keyfile "$tls_dir/server.key" \
    --ssl-certfile "$tls_dir/server.crt"
fi

exec uvicorn app.main:app --host 0.0.0.0 --port 8000 \
  --ws-ping-interval "${VT_WS_PING_INTERVAL:-15}" \
  --ws-ping-timeout "${VT_WS_PING_TIMEOUT:-30}"
