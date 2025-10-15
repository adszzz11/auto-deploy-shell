#!/bin/bash
set -euo pipefail


# 서버를 DOWN 상태로 설정하는 함수 (주석 처리)
set_server_down() {
    local port="$1"
    local upstream_conf="${2:-${NGINX_UPSTREAM_CONF}}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Setting server on port $port to DOWN state" >&2

    # 해당 포트의 서버 라인을 주석 처리
    if sed -i.bak "/^[[:space:]]*server.*:$port/ s/^/# /" "$upstream_conf"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Server on port $port set to DOWN (commented out)" >&2
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to set port $port DOWN" >&2
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: set_server_down.sh <port> [upstream_conf]"
        echo ""
        echo "Arguments:"
        echo "  port            - Server port number (required)"
        echo "  upstream_conf   - Path to upstream configuration file (default: from nginx.env)"
        echo ""
        echo "Environment variables (set in nginx.env):"
        echo "  NGINX_UPSTREAM_CONF  - Default upstream config path"
        echo ""
        echo "Examples:"
        echo "  # Using nginx.env defaults"
        echo "  set_server_down.sh 8080"
        echo ""
        echo "  # Override upstream config"
        echo "  set_server_down.sh 8080 /etc/nginx/conf.d/upstream.conf"
        exit 1
    fi
    set_server_down "$@"
fi
