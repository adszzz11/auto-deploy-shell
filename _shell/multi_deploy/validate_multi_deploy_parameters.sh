#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 다중 배포 파라미터 유효성 검사 함수
validate_multi_deploy_parameters() {
    local target_count="$1"
    local env_file_raw="$2"

    # 파라미터 개수 검증
    if [ "$#" -ne 2 ]; then
        echo "Usage: validate_multi_deploy_parameters <target_instance_count> <env_file>"
        exit 1
    fi

    # 타겟 인스턴스 수 유효성 검증
    if ! [[ "$target_count" =~ ^[0-9]+$ ]]; then
        error_exit "Target instance count must be a valid number: $target_count"
    fi

    if [ "$target_count" -lt 2 ] || [ "$target_count" -gt 10 ]; then
        error_exit "Target instance count must be between 2-10: $target_count"
    fi

    # 환경 파일 이름에서 CR(\r) 제거
    local env_file
    env_file="$(echo "$env_file_raw" | tr -d '\r')"

    # 환경 파일 존재 확인
    if [ ! -f "$env_file" ]; then
        error_exit "Environment file not found: $env_file"
    fi

    # 환경 파일 읽기 권한 확인
    if [ ! -r "$env_file" ]; then
        error_exit "Environment file is not readable: $env_file"
    fi

    log_info "Parameters validated: target_count=$target_count, env_file=$env_file"
    echo "$env_file"  # 정제된 환경 파일 경로 반환
}

# 인스턴스 수 범위 검증 함수
validate_instance_count_range() {
    local count="$1"
    local min_count="${2:-2}"
    local max_count="${3:-10}"

    if [ "$count" -lt "$min_count" ] || [ "$count" -gt "$max_count" ]; then
        error_exit "Instance count $count is out of range. Must be between $min_count-$max_count"
    fi

    log_info "Instance count validated: $count (range: $min_count-$max_count)"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: validate_multi_deploy_parameters.sh <target_instance_count> <env_file>"
        exit 1
    fi
    validate_multi_deploy_parameters "$1" "$2"
fi