#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 롤백 파라미터 유효성 검사 함수
validate_rollback_parameters() {
    local instance_num="$1"
    local env_file="$2"

    # 파라미터 개수 검증
    if [ "$#" -ne 2 ]; then
        error_exit "Invalid parameters. Usage: validate_rollback_parameters <instance_number> <env_file>"
    fi

    # 인스턴스 번호 유효성 검증
    if ! [[ "$instance_num" =~ ^[0-9]+$ ]] || [ "$instance_num" -lt 0 ] || [ "$instance_num" -gt 9 ]; then
        error_exit "Invalid instance number: $instance_num. Must be between 0-9"
    fi

    # 환경 파일 존재 확인
    if [ ! -f "$env_file" ]; then
        error_exit "Environment file not found: $env_file"
    fi

    # 환경 파일 읽기 권한 확인
    if [ ! -r "$env_file" ]; then
        error_exit "Environment file is not readable: $env_file"
    fi

    log_info "Rollback parameters validated: instance=$instance_num, env_file=$env_file"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: validate_rollback_parameters.sh <instance_number> <env_file>"
        exit 1
    fi
    validate_rollback_parameters "$1" "$2"
fi