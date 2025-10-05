#!/bin/bash
set -euo pipefail


# 완전히 새로운 서버를 업스트림에 추가
add_new_server() {
    local port="$1"
    local upstream_conf="${2:-${NGINX_UPSTREAM_CONF}}"
    local server_ip="${3:-${NGINX_SERVER_IP:-127.0.0.1}}"
    local config_postfix="${4:-${NGINX_CONFIG_POSTFIX:-}}"  # 예: "weight=5", "max_fails=3 fail_timeout=30s", "backup"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Adding new server on port $port"

    # 이미 존재하는 포트인지 확인
    if grep -q "server.*:$port" "$upstream_conf"; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Server on port $port already exists"
        return 0
    fi

    # 서버 라인 구성
    local server_line="    server ${server_ip}:${port}"
    if [ -n "$config_postfix" ]; then
        server_line="${server_line} ${config_postfix}"
    fi
    server_line="${server_line};"

    # upstream 블록의 마지막 } 앞에 새 서버 라인 삽입
    if sed -i.bak "/^[[:space:]]*}/ i\\
${server_line}
" "$upstream_conf"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - New server added: $server_line"
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to add new server for port $port"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: add_new_server.sh <port> [upstream_conf] [server_ip] [config_postfix]"
        echo ""
        echo "Arguments:"
        echo "  port            - Server port number (required)"
        echo "  upstream_conf   - Path to upstream configuration file (default: from nginx.env or 127.0.0.1)"
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
        echo "  add_new_server.sh 8080"
        echo ""
        echo "  # Override upstream config"
        echo "  add_new_server.sh 8080 /etc/nginx/conf.d/upstream.conf"
        echo ""
        echo "  # Override IP"
        echo "  add_new_server.sh 8080 /etc/nginx/conf.d/upstream.conf 192.168.1.10"
        echo ""
        echo "  # With config postfix"
        echo "  add_new_server.sh 8080 /etc/nginx/conf.d/upstream.conf 127.0.0.1 'weight=5'"
        echo "  add_new_server.sh 8081 /etc/nginx/conf.d/upstream.conf 127.0.0.1 'backup'"
        exit 1
    fi
    add_new_server "$@"
fi
