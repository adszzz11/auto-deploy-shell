#!/bin/bash
set -euo pipefail

# 실행 명령어 구성 함수
build_exec_command() {
    local port="$1"
    local java_opts="${2:-${APP_JAVA_OPTS:-}}"
    local jar_name="${3:-${APP_JAR_NAME:-current.jar}}"

    # 기본 명령어 구성
    local exec_command="java -jar ${jar_name} --server.port=${port}"

    # JAVA_OPTS가 있으면 추가
    if [ -n "$java_opts" ]; then
        exec_command="${exec_command} ${java_opts}"
    fi

    echo "$exec_command"
}

# JAR 파일 존재 확인
verify_jar_file() {
    local jar_name="${1:-${APP_JAR_NAME:-current.jar}}"

    if [ ! -f "$jar_name" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR file not found: $jar_name" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - JAR file verified: $jar_name"
    return 0
}

# 로그 디렉터리 확인 및 생성
prepare_log_directory() {
    local log_dir="${1:-${APP_LOG_DIR:-./logs}}"

    if [ ! -d "$log_dir" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Creating log directory: $log_dir"
        mkdir -p "$log_dir"
    fi

    echo "$log_dir"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: build_exec_command.sh <port> [java_opts] [jar_name]"
        echo ""
        echo "Arguments:"
        echo "  port       - Application port number"
        echo "  java_opts  - Java options (default: from run_app.env)"
        echo "  jar_name   - JAR file name (default: from run_app.env or 'current.jar')"
        exit 1
    fi

    build_exec_command "$@"
fi
