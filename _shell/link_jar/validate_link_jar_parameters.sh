#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# link_jar 파라미터 유효성 검사 함수
validate_link_jar_parameters() {
    local service_name="$1"
    local target_link="$2"
    local jar_dir="$3"

    # 파라미터 개수 검증
    if [ "$#" -ne 3 ]; then
        error_exit "Invalid parameters. Usage: validate_link_jar_parameters <service_name> <target_link_path> <jar_trunk_dir>"
    fi

    # 서비스명 유효성 검증
    if [ -z "$service_name" ]; then
        error_exit "Service name cannot be empty"
    fi

    # 타겟 링크 경로 유효성 검증
    if [ -z "$target_link" ]; then
        error_exit "Target link path cannot be empty"
    fi

    # JAR 디렉터리 경로 유효성 검증
    if [ -z "$jar_dir" ]; then
        error_exit "JAR trunk directory path cannot be empty"
    fi

    log_info "Parameters validated: service=$service_name, target=$target_link, jar_dir=$jar_dir"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 3 ]; then
        echo "Usage: validate_link_jar_parameters.sh <service_name> <target_link_path> <jar_trunk_dir>"
        exit 1
    fi
    validate_link_jar_parameters "$1" "$2" "$3"
fi