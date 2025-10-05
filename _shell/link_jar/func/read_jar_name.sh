#!/bin/bash
set -euo pipefail


# PID 파일에서 JAR 파일명 읽기
read_jar_name_from_pid() {
    local jar_dir="$1"
    local pid_file="${2:-${jar_dir}/${LINK_JAR_PID_FILE:-current_jar.pid}}"

    # PID 파일 존재 확인
    if [ ! -f "$pid_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - PID file not found at $pid_file" >&2
        return 1
    fi

    # JAR 파일명 읽기 (앞뒤 공백 제거)
    local jar_name
    jar_name=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$pid_file")

    # JAR 파일명이 비어있는지 확인
    if [ -z "$jar_name" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - No jar name found in $pid_file" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - JAR name read from PID file: $jar_name"
    echo "$jar_name"
}

# JAR 이름 직접 지정 (PID 파일 사용 안 함)
use_jar_name_directly() {
    local jar_name="$1"

    if [ -z "$jar_name" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR name is empty" >&2
        return 1
    fi

    echo "$jar_name"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: read_jar_name.sh <jar_trunk_dir> [pid_file]"
        echo ""
        echo "Arguments:"
        echo "  jar_trunk_dir - JAR trunk directory"
        echo "  pid_file      - PID file path (default: <jar_trunk_dir>/current_jar.pid)"
        exit 1
    fi
    read_jar_name_from_pid "$@"
fi
