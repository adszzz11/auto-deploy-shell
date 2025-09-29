#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 파라미터 유효성 검사 함수
validate_parameters() {
    local port="$1"
    local upstream_conf="$2"
    local mode="$3"

    # 파라미터 개수 검증
    if [ "$#" -ne 3 ]; then
        error_exit "Invalid parameters. Usage: validate_parameters <port> <upstream_conf> <up|down>"
    fi

    # 포트 번호 유효성 검증
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        error_exit "Invalid port number: $port. Port must be between 1-65535"
    fi

    # 모드 유효성 검증
    if [ "$mode" != "up" ] && [ "$mode" != "down" ]; then
        error_exit "Invalid mode: $mode. Use 'up' or 'down'"
    fi

    log_info "Parameters validated: port=$port, config=$upstream_conf, mode=$mode"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 3 ]; then
        echo "Usage: validate_parameters.sh <port> <upstream_conf> <up|down>"
        exit 1
    fi
    validate_parameters "$1" "$2" "$3"
fi