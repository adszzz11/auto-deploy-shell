#!/bin/bash
set -euo pipefail

# 애플리케이션 프로세스 검색 함수
find_app_process() {
    local port="$1"
    local common_utils_dir="$2"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 구체적인 패턴으로 프로세스 검색
    local search_pattern="java -jar current.jar --server.port=${port}"
    local pid

    pid=$(pgrep -f "$search_pattern" 2>/dev/null || echo "")

    if [ -z "$pid" ]; then
        log_info "No app running on port ${port}"
        return 1
    else
        log_info "Found app process with PID: $pid on port ${port}"
        echo "$pid"
        return 0
    fi
}

# 프로세스 존재 여부만 확인하는 함수
check_app_running() {
    local port="$1"
    local common_utils_dir="$2"

    if find_app_process "$port" "$common_utils_dir" >/dev/null 2>&1; then
        echo "running"
        return 0
    else
        echo "stopped"
        return 1
    fi
}

# 프로세스 정보 상세 조회 함수
get_app_process_info() {
    local port="$1"
    local common_utils_dir="$2"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    local pid
    if pid=$(find_app_process "$port" "$common_utils_dir"); then
        echo "=== Process Information ==="
        echo "PID: $pid"
        echo "Port: $port"
        echo "Command: $(ps -p "$pid" -o command= 2>/dev/null || echo 'N/A')"
        echo "Start Time: $(ps -p "$pid" -o lstart= 2>/dev/null || echo 'N/A')"
        echo "CPU Time: $(ps -p "$pid" -o cputime= 2>/dev/null || echo 'N/A')"
        echo "Memory: $(ps -p "$pid" -o rss= 2>/dev/null || echo 'N/A') KB"
    else
        echo "No process found for port $port"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: find_app_process.sh <port> <common_utils_dir> [info|check]"
        echo "  (default): Find and return PID"
        echo "  info: Show detailed process information"
        echo "  check: Check if process is running (returns running/stopped)"
        exit 1
    fi

    case "${3:-default}" in
        "info")
            get_app_process_info "$1" "$2"
            ;;
        "check")
            check_app_running "$1" "$2"
            ;;
        *)
            find_app_process "$1" "$2"
            ;;
    esac
fi