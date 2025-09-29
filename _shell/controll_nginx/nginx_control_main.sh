#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common_utils/common_utils.sh"

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_parameters.sh"
source "${SCRIPT_DIR}/validate_nginx_env.sh"
source "${SCRIPT_DIR}/set_server_down.sh"
source "${SCRIPT_DIR}/set_server_up.sh"
source "${SCRIPT_DIR}/test_nginx_config.sh"
source "${SCRIPT_DIR}/reload_nginx.sh"

# 메인 nginx 제어 함수
nginx_control_main() {
    # 사용법: nginx_control_main <port> <upstream_conf> <up|down>
    if [ "$#" -ne 3 ]; then
        echo "Usage: nginx_control_main <port> <upstream_conf> <up|down>"
        exit 1
    fi

    local port="$1"
    local upstream_conf="$2"
    local mode="$3"

    # 1. 파라미터 검증
    validate_parameters "$port" "$upstream_conf" "$mode"

    # 2. Nginx 환경 검증
    validate_nginx_env "$upstream_conf"

    # 3. 업스트림 제어
    case "$mode" in
        down)
            set_server_down "$port" "$upstream_conf"
            ;;
        up)
            set_server_up "$port" "$upstream_conf"
            ;;
        *)
            error_exit "Invalid mode: $mode"
            ;;
    esac

    # 4. Nginx 설정 검증
    test_nginx_config

    # 5. Nginx 리로드
    reload_nginx

    log_success "Port $port set to '$mode' successfully"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    nginx_control_main "$@"
fi