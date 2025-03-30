#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common_utils.sh"

# 사용법: controll_nginx.sh <port> <upstream_conf> <up|down>
if [ "$#" -ne 3 ]; then
    echo "Usage: controll_nginx.sh <port> <upstream_conf> <up|down>"
    exit 1
fi

PORT="$1"
UPSTREAM_CONF="$2"
MODE="$3"

[ ! -f "$UPSTREAM_CONF" ] && error_exit "Upstream configuration not found: $UPSTREAM_CONF"
command -v nginx &>/dev/null || error_exit "nginx command not found"

case "$MODE" in
  down)
    sed -i "/^[[:space:]]*server.*:$PORT/ s/^/# /" "$UPSTREAM_CONF" || error_exit "Failed to set port $PORT DOWN"
    ;;
  up)
    if ! grep -q "server.*:$PORT" "$UPSTREAM_CONF"; then
      log_info "Adding new server for port $PORT"
      sed -i "/^[[:space:]]*}/ i\    server 127.0.0.1:$PORT;" "$UPSTREAM_CONF" || error_exit "Failed to add new server for port $PORT"
    fi
    sed -i "/^[[:space:]]*#[[:space:]]*server.*:$PORT/ s/^# //" "$UPSTREAM_CONF" || true
    ;;
  *)
    error_exit "Invalid mode: use 'up' or 'down'"
    ;;
esac

# Nginx 설정 변경 후 문법 검증
nginx -t || error_exit "Nginx configuration test failed"

nginx -s reload || error_exit "nginx reload failed"
log_success "Port $PORT set to '$MODE'"
