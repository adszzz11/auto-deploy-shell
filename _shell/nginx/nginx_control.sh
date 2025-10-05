#!/bin/bash
set -euo pipefail

# nginx_control.sh - Nginx Upstream Server Control
#
# Layer: 4 (Support Services)
# 역할: Nginx 업스트림 서버 제어
# 호출자: deploy_control.sh, rollback_control.sh (Layer 3)
# 호출 대상: 없음 (최하위 계층)
#
# 책임:
#   - Nginx upstream 서버 활성화/비활성화
#   - 설정 파일 안전한 수정
#   - Nginx 리로드 및 검증

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 모든 함수 스크립트들 source (func 디렉터리에서)
source "${SCRIPT_DIR}/func/set_server_up.sh"
source "${SCRIPT_DIR}/func/set_server_down.sh"
source "${SCRIPT_DIR}/func/add_new_server.sh"
source "${SCRIPT_DIR}/func/test_nginx_config.sh"
source "${SCRIPT_DIR}/func/validate_upstream_format.sh"
source "${SCRIPT_DIR}/func/check_port_exists.sh"
source "${SCRIPT_DIR}/func/reload_nginx.sh"
source "${SCRIPT_DIR}/func/is_nginx_running.sh"
source "${SCRIPT_DIR}/func/backup_config.sh"
source "${SCRIPT_DIR}/func/list_active_servers.sh"
source "${SCRIPT_DIR}/func/list_inactive_servers.sh"
source "${SCRIPT_DIR}/func/get_server_status.sh"

# 사용법 출력
print_usage() {
    cat << EOF
Usage: nginx_control.sh <command> [arguments]

Commands:
  up <port> [upstream_conf] [server_ip] [config_postfix]     - Set server UP (uncomment or add)
  down <port> [upstream_conf]                                - Set server DOWN (comment out)
  add <port> [upstream_conf] [server_ip] [config_postfix]    - Add new server to upstream
  status <port> [upstream_conf]                              - Get server status (active/inactive/not_found)
  list-active [upstream_conf]                                - List all active servers
  list-inactive [upstream_conf]                              - List all inactive servers
  test-config                                                - Test nginx configuration
  validate [upstream_conf]                                   - Validate upstream config format
  check-port <port> [upstream_conf]                          - Check if port exists in config
  reload                                                     - Reload nginx
  is-running                                                 - Check if nginx is running
  backup <config_file>                                       - Backup configuration file

Note: Arguments in [brackets] are optional and can use defaults from nginx.env

Environment variables (set in nginx.env):
  NGINX_UPSTREAM_CONF  - Default upstream config path
  NGINX_SERVER_IP      - Default server IP (default: 127.0.0.1)
  NGINX_CONFIG_POSTFIX - Default config postfix (e.g., 'weight=5', 'backup')

Examples:
  # Using nginx.env defaults
  ./nginx_control.sh up 8080
  ./nginx_control.sh down 8080

  # Override upstream config
  ./nginx_control.sh up 8080 /etc/nginx/conf.d/upstream.conf

  # With custom IP and config
  ./nginx_control.sh up 8080 /etc/nginx/conf.d/upstream.conf 192.168.1.10 'weight=5'

  # Full deployment workflow
  ./nginx_control.sh down 8080
  # ... deploy application ...
  ./nginx_control.sh up 8080
EOF
}

# 메인 진입점
main() {
    if [ "$#" -lt 1 ]; then
        print_usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        up)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'up' requires at least <port>"
                exit 1
            fi
            set_server_up "$@"
            test_nginx_config
            reload_nginx
            ;;
        down)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'down' requires at least <port>"
                exit 1
            fi
            set_server_down "$@"
            test_nginx_config
            reload_nginx
            ;;
        add)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'add' requires at least <port>"
                exit 1
            fi
            add_new_server "$@"
            test_nginx_config
            reload_nginx
            ;;
        status)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'status' requires at least <port>"
                exit 1
            fi
            status=$(get_server_status "$@")
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Port $1 status: $status"
            ;;
        list-active)
            list_active_servers "${1:-${NGINX_UPSTREAM_CONF}}"
            ;;
        list-inactive)
            list_inactive_servers "${1:-${NGINX_UPSTREAM_CONF}}"
            ;;
        test-config)
            test_nginx_config
            ;;
        validate)
            validate_upstream_format "${1:-${NGINX_UPSTREAM_CONF}}"
            ;;
        check-port)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'check-port' requires at least <port>"
                exit 1
            fi
            check_port_exists "$@"
            ;;
        reload)
            reload_nginx
            ;;
        is-running)
            is_nginx_running
            ;;
        backup)
            if [ "$#" -ne 1 ]; then
                echo "Error: 'backup' requires <config_file>"
                exit 1
            fi
            backup_config "$1"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
