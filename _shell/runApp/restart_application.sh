#!/bin/bash
set -euo pipefail

# 애플리케이션 재시작 함수
restart_application() {
    local port="$1"
    local java_opts="$2"
    local common_utils_dir="$3"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 필요한 스크립트 로드
    source "$(dirname "$0")/stop_application.sh"
    source "$(dirname "$0")/start_application.sh"

    log_info "Restarting application on port $port"

    # 1단계: 애플리케이션 중지
    stop_application "$port" "$common_utils_dir"

    # 잠시 대기 (완전한 정리를 위해)
    sleep 2

    # 2단계: 애플리케이션 시작
    start_application "$port" "$java_opts" "$common_utils_dir"

    log_success "Application restarted successfully on port $port"
}

# 안전한 재시작 함수 (상태 확인 후 재시작)
restart_application_safe() {
    local port="$1"
    local java_opts="$2"
    local common_utils_dir="$3"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 필요한 스크립트 로드
    source "$(dirname "$0")/find_app_process.sh"
    source "$(dirname "$0")/stop_application.sh"
    source "$(dirname "$0")/start_application.sh"

    local status
    status=$(check_app_running "$port" "$common_utils_dir")

    case "$status" in
        "running")
            log_info "Application is running. Performing restart on port $port"
            restart_application "$port" "$java_opts" "$common_utils_dir"
            ;;
        "stopped")
            log_info "Application is stopped. Starting application on port $port"
            start_application "$port" "$java_opts" "$common_utils_dir"
            ;;
    esac
}

# 강제 재시작 함수 (강제 중지 후 시작)
restart_application_force() {
    local port="$1"
    local java_opts="$2"
    local common_utils_dir="$3"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 필요한 스크립트 로드
    source "$(dirname "$0")/stop_application.sh"
    source "$(dirname "$0")/start_application.sh"

    log_info "Force restarting application on port $port"

    # 1단계: 강제 중지
    force_stop_application "$port" "$common_utils_dir"

    # 잠시 대기
    sleep 2

    # 2단계: 시작
    start_application "$port" "$java_opts" "$common_utils_dir"

    log_success "Application force restarted successfully on port $port"
}

# 재시작 후 헬스체크 함수
restart_with_healthcheck() {
    local port="$1"
    local java_opts="$2"
    local common_utils_dir="$3"
    local health_endpoint="${4:-/actuator/health}"
    local max_wait="${5:-30}"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 재시작 실행
    restart_application "$port" "$java_opts" "$common_utils_dir"

    # 헬스체크 대기
    log_info "Waiting for application to be ready on port $port..."
    local wait_time=0

    while [ "$wait_time" -lt "$max_wait" ]; do
        if curl -s -f "http://localhost:$port$health_endpoint" >/dev/null 2>&1; then
            log_success "Application is healthy and ready on port $port"
            return 0
        fi

        sleep 2
        wait_time=$((wait_time + 2))
        log_info "Waiting... ($wait_time/${max_wait}s)"
    done

    log_warn "Health check timed out after ${max_wait}s, but application may still be starting"
    return 1
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: restart_application.sh <port> <java_opts> <common_utils_dir> [safe|force|health] [health_endpoint] [max_wait]"
        echo "  (default): Normal restart (stop then start)"
        echo "  safe: Check status before restarting"
        echo "  force: Force restart with SIGKILL"
        echo "  health: Restart with health check"
        exit 1
    fi

    case "${4:-default}" in
        "safe")
            restart_application_safe "$1" "$2" "$3"
            ;;
        "force")
            restart_application_force "$1" "$2" "$3"
            ;;
        "health")
            restart_with_healthcheck "$1" "$2" "$3" "${5:-/actuator/health}" "${6:-30}"
            ;;
        *)
            restart_application "$1" "$2" "$3"
            ;;
    esac
fi