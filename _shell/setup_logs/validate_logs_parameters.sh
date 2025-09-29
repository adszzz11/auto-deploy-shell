#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 로그 설정 파라미터 유효성 검사 함수
validate_logs_parameters() {
    local service_name="$1"
    local instance_num="$2"
    local instance_dir="$3"
    local log_base_dir="$4"

    # 파라미터 개수 검증
    if [ "$#" -ne 4 ]; then
        error_exit "Invalid parameters. Usage: validate_logs_parameters <service_name> <instance_num> <instance_dir> <log_base_dir>"
    fi

    # 서비스명 유효성 검증
    if [ -z "$service_name" ]; then
        error_exit "Service name cannot be empty"
    fi

    # 인스턴스 번호 유효성 검증
    if ! [[ "$instance_num" =~ ^[0-9]+$ ]]; then
        error_exit "Instance number must be a valid number: $instance_num"
    fi

    # 인스턴스 디렉터리 유효성 검증
    if [ -z "$instance_dir" ]; then
        error_exit "Instance directory path cannot be empty"
    fi

    # 로그 베이스 디렉터리 유효성 검증
    if [ -z "$log_base_dir" ]; then
        error_exit "Log base directory path cannot be empty"
    fi

    log_info "Parameters validated: service=$service_name, instance=$instance_num, instance_dir=$instance_dir, log_base_dir=$log_base_dir"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 4 ]; then
        echo "Usage: validate_logs_parameters.sh <service_name> <instance_num> <instance_dir> <log_base_dir>"
        exit 1
    fi
    validate_logs_parameters "$1" "$2" "$3" "$4"
fi