#!/bin/bash
set -euo pipefail

# 실행 명령어 구성 함수
build_exec_command() {
    local port="$1"
    local java_opts="$2"
    local common_utils_dir="$3"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 실행 명령어 구성
    local exec_command="java -jar current.jar --server.port=${port} ${java_opts}"

    log_info "EXEC_COMMAND: $exec_command"
    echo "$exec_command"
}

# current.jar 파일 존재 확인 함수
verify_jar_file() {
    local common_utils_dir="$1"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    if [ ! -f "current.jar" ]; then
        error_exit "current.jar not found in current directory"
    fi

    # 심볼릭 링크인지 확인
    if [ -L "current.jar" ]; then
        local target
        target=$(readlink "current.jar")
        log_info "current.jar is a symbolic link pointing to: $target"

        # 링크 대상이 실제로 존재하는지 확인
        if [ ! -f "$target" ]; then
            error_exit "Symbolic link target does not exist: $target"
        fi
    else
        log_info "current.jar is a regular file"
    fi

    log_info "JAR file verification passed: current.jar"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: build_exec_command.sh <port> <java_opts> <common_utils_dir> [verify]"
        echo "  verify: Also verify current.jar file exists"
        exit 1
    fi

    if [ "${4:-}" = "verify" ]; then
        verify_jar_file "$3"
    fi

    build_exec_command "$1" "$2" "$3"
fi