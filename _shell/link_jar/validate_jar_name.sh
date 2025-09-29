#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# JAR 파일명 유효성 검증 함수
validate_jar_name() {
    local jar_name="$1"

    # JAR 파일명이 .jar 확장자로 끝나는지 확인
    if [[ "$jar_name" != *.jar ]]; then
        error_exit "Invalid jar name '$jar_name'. Expected a file ending with .jar"
    fi

    log_info "JAR name validation passed: $jar_name"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: validate_jar_name.sh <jar_name>"
        exit 1
    fi
    validate_jar_name "$1"
fi