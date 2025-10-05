#!/bin/bash
set -euo pipefail

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${SCRIPT_DIR}/nginx.env" ]; then
    source "${SCRIPT_DIR}/nginx.env"
fi

# 서버를 UP 상태로 설정하는 함수 (주석 제거 또는 신규 추가)
set_server_up() {
    local port="$1"
    local upstream_conf="${2:-${NGINX_UPSTREAM_CONF}}"
    local server_ip="${3:-${NGINX_SERVER_IP:-127.0.0.1}}"
    local config_postfix="${4:-${NGINX_CONFIG_POSTFIX:-}}"  # 예: "weight=5", "max_fails=3 fail_timeout=30s", "backup"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Setting server on port $port to UP state"

    # 해당 포트가 설정 파일에 존재하는지 확인
    if ! grep -q "server.*:$port" "$upstream_conf"; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Adding new server for port $port"

        # 서버 라인 구성
        local server_line="    server ${server_ip}:${port}"
        if [ -n "$config_postfix" ]; then
            server_line="${server_line} ${config_postfix}"
        fi
        server_line="${server_line};"

        # 새 서버 추가 (upstream 블록의 } 앞에 추가)
        if sed -i.bak "/^[[:space:]]*}/ i\\
${server_line}
" "$upstream_conf"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - New server added: $server_line"
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to add new server for port $port"
            return 1
        fi
    else
        # 기존 주석 처리된 서버 라인의 주석 제거
        if sed -i.bak "/^[[:space:]]*#[[:space:]]*server.*:$port/ s/^[[:space:]]*#[[:space:]]*/    /" "$upstream_conf"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Server on port $port uncommented (set to UP)"
        else
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Server may already be UP on port $port"
        fi
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: set_server_up.sh <port> [upstream_conf] [server_ip] [config_postfix]"
        echo ""
        echo "Arguments:"
        echo "  port            - Server port number (required)"
        echo "  upstream_conf   - Path to upstream configuration file (default: from nginx.env)"
        echo "  server_ip       - Server IP address (default: from nginx.env or 127.0.0.1)"
        echo "  config_postfix  - Additional nginx config (default: from nginx.env or empty)"
        echo ""
        echo "Environment variables (set in nginx.env):"
        echo "  NGINX_UPSTREAM_CONF  - Default upstream config path"
        echo "  NGINX_SERVER_IP      - Default server IP"
        echo "  NGINX_CONFIG_POSTFIX - Default config postfix"
        echo ""
        echo "Examples:"
        echo "  # Using nginx.env defaults"
        echo "  set_server_up.sh 8080"
        echo ""
        echo "  # Override upstream config"
        echo "  set_server_up.sh 8080 /etc/nginx/conf.d/upstream.conf"
        echo ""
        echo "  # With config postfix"
        echo "  set_server_up.sh 8080 /etc/nginx/conf.d/upstream.conf 127.0.0.1 'weight=5'"
        exit 1
    fi
    set_server_up "$@"
fi
