#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# PID 파일에서 JAR 파일명 읽기 함수
read_jar_name_from_pid() {
    local jar_dir="$1"
    local pid_file="${jar_dir}/current_jar.pid"

    # PID 파일 존재 확인
    if [ ! -f "$pid_file" ]; then
        error_exit "PID file not found at $pid_file"
    fi

    # JAR 파일명 읽기 (앞뒤 공백 제거)
    local jar_name
    jar_name=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$pid_file")

    # JAR 파일명이 비어있는지 확인
    if [ -z "$jar_name" ]; then
        error_exit "No jar name found in $pid_file"
    fi

    log_info "JAR name read from PID file: $jar_name"
    echo "$jar_name"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: read_jar_name_from_pid.sh <jar_trunk_dir>"
        exit 1
    fi
    read_jar_name_from_pid "$1"
fi