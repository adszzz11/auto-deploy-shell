#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# JAR 환경 검증 함수
validate_jar_environment() {
    local jar_dir="$1"
    local target_link="$2"

    # JAR 트렁크 디렉터리 존재 확인
    if [ ! -d "$jar_dir" ]; then
        error_exit "JAR trunk directory does not exist: $jar_dir"
    fi

    # 타겟 디렉터리 존재 확인
    local target_dir
    target_dir=$(dirname "$target_link")
    if [ ! -d "$target_dir" ]; then
        error_exit "Target directory does not exist: $target_dir"
    fi

    log_info "JAR environment validated: jar_dir=$jar_dir, target_dir=$target_dir"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: validate_jar_environment.sh <jar_trunk_dir> <target_link_path>"
        exit 1
    fi
    validate_jar_environment "$1" "$2"
fi