#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# JAR 파일 존재 확인 함수
validate_jar_file_exists() {
    local jar_dir="$1"
    local jar_name="$2"
    local jar_path="${jar_dir}/${jar_name}"

    # 실제 JAR 파일 존재 확인
    if [ ! -f "$jar_path" ]; then
        error_exit "JAR file not found: $jar_path"
    fi

    log_info "JAR file exists: $jar_path"
    echo "$jar_path"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: validate_jar_file_exists.sh <jar_trunk_dir> <jar_name>"
        exit 1
    fi
    validate_jar_file_exists "$1" "$2"
fi