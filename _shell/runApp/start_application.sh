#!/bin/bash
set -euo pipefail

# 애플리케이션 시작 함수
start_application() {
    local port="$1"
    local java_opts="$2"
    local common_utils_dir="$3"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 필요한 스크립트 로드
    source "$(dirname "$0")/build_exec_command.sh"
    source "$(dirname "$0")/find_app_process.sh"

    # 이미 실행 중인지 확인
    if find_app_process "$port" "$common_utils_dir" >/dev/null 2>&1; then
        log_warn "Application is already running on port $port"
        return 0
    fi

    # JAR 파일 확인
    verify_jar_file "$common_utils_dir"

    # 실행 명령어 구성
    local exec_command
    exec_command=$(build_exec_command "$port" "$java_opts" "$common_utils_dir")

    log_info "Starting application with command: $exec_command"

    # 백그라운드에서 애플리케이션 시작
    nohup $exec_command >/dev/null 2>&1 &
    local start_pid=$!

    # 잠시 대기 후 프로세스가 실제로 시작되었는지 확인
    sleep 2

    if kill -0 "$start_pid" 2>/dev/null; then
        log_success "Application started on port $port (PID: $start_pid)"
    else
        error_exit "Failed to start application on port $port"
    fi
}

# 애플리케이션 상태 확인 후 시작 함수
start_application_safe() {
    local port="$1"
    local java_opts="$2"
    local common_utils_dir="$3"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    source "$(dirname "$0")/find_app_process.sh"

    # 현재 상태 확인
    local status
    status=$(check_app_running "$port" "$common_utils_dir")

    case "$status" in
        "running")
            log_warn "Application is already running on port $port. Skipping start."
            return 0
            ;;
        "stopped")
            log_info "Starting application on port $port"
            start_application "$port" "$java_opts" "$common_utils_dir"
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: start_application.sh <port> <java_opts> <common_utils_dir> [safe]"
        echo "  (default): Start application"
        echo "  safe: Check status before starting"
        exit 1
    fi

    case "${4:-default}" in
        "safe")
            start_application_safe "$1" "$2" "$3"
            ;;
        *)
            start_application "$1" "$2" "$3"
            ;;
    esac
fi