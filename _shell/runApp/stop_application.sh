#!/bin/bash
set -euo pipefail

# 애플리케이션 중지 함수 (Graceful Shutdown)
stop_application() {
    local port="$1"
    local common_utils_dir="$2"
    local sigterm_timeout="${3:-10}"  # SIGTERM 대기 시간 (기본 10초)
    local sigkill_timeout="${4:-5}"   # SIGKILL 대기 시간 (기본 5초)

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 필요한 스크립트 로드
    source "$(dirname "$0")/find_app_process.sh"

    # 프로세스 찾기
    local pid
    if ! pid=$(find_app_process "$port" "$common_utils_dir"); then
        log_info "No app running on port ${port}. Nothing to stop."
        return 0
    fi

    log_info "Stopping app with PID: $pid"

    # 1단계: SIGTERM 전송
    log_info "Sending SIGTERM to process $pid"
    kill -15 "$pid"

    # SIGTERM 대기
    local wait_time=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        wait_time=$((wait_time + 1))
        if [ "$wait_time" -ge "$sigterm_timeout" ]; then
            log_warn "Process $pid did not terminate after $sigterm_timeout seconds, sending SIGKILL..."
            break
        fi
    done

    # 프로세스가 종료되었는지 확인
    if ! kill -0 "$pid" 2>/dev/null; then
        log_success "Process $pid terminated gracefully"
        return 0
    fi

    # 2단계: SIGKILL 전송
    log_warn "Sending SIGKILL to process $pid"
    kill -9 "$pid"

    # SIGKILL 대기
    wait_time=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        wait_time=$((wait_time + 1))
        if [ "$wait_time" -ge "$sigkill_timeout" ]; then
            error_exit "Process $pid did not terminate even after SIGKILL"
        fi
    done

    log_success "Process $pid has terminated"
}

# 강제 중지 함수 (SIGKILL만 사용)
force_stop_application() {
    local port="$1"
    local common_utils_dir="$2"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 필요한 스크립트 로드
    source "$(dirname "$0")/find_app_process.sh"

    # 프로세스 찾기
    local pid
    if ! pid=$(find_app_process "$port" "$common_utils_dir"); then
        log_info "No app running on port ${port}. Nothing to stop."
        return 0
    fi

    log_warn "Force stopping app with PID: $pid (SIGKILL)"
    kill -9 "$pid"

    # 종료 확인
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        error_exit "Failed to force stop process $pid"
    else
        log_success "Process $pid force stopped"
    fi
}

# 안전한 중지 함수 (상태 확인 후 중지)
stop_application_safe() {
    local port="$1"
    local common_utils_dir="$2"

    source "$(dirname "$0")/find_app_process.sh"
    source "${common_utils_dir}/common_utils.sh"

    local status
    status=$(check_app_running "$port" "$common_utils_dir")

    case "$status" in
        "running")
            log_info "Stopping application on port $port"
            stop_application "$port" "$common_utils_dir"
            ;;
        "stopped")
            log_info "Application is already stopped on port $port"
            return 0
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: stop_application.sh <port> <common_utils_dir> [force|safe] [sigterm_timeout] [sigkill_timeout]"
        echo "  (default): Graceful stop with SIGTERM then SIGKILL"
        echo "  force: Force stop with SIGKILL only"
        echo "  safe: Check status before stopping"
        exit 1
    fi

    case "${3:-default}" in
        "force")
            force_stop_application "$1" "$2"
            ;;
        "safe")
            stop_application_safe "$1" "$2"
            ;;
        *)
            stop_application "$1" "$2" "${3:-10}" "${4:-5}"
            ;;
    esac
fi