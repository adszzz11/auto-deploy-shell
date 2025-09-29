#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_runapp_parameters.sh"
source "${SCRIPT_DIR}/build_exec_command.sh"
source "${SCRIPT_DIR}/find_app_process.sh"
source "${SCRIPT_DIR}/start_application.sh"
source "${SCRIPT_DIR}/stop_application.sh"
source "${SCRIPT_DIR}/restart_application.sh"

# 메인 runApp 함수
runapp_main() {
    # 사용법: runapp_main <port> <mode> <java_opts> <common_utils_dir>
    if [ "$#" -ne 4 ]; then
        echo "Usage: runapp_main <port> <mode> <java_opts> <common_utils_dir>"
        exit 1
    fi

    local port="$1"
    local mode="$2"
    local java_opts="$3"
    local common_utils_dir="$4"

    # 1. 파라미터 검증
    validate_runapp_parameters "$port" "$mode" "$java_opts" "$common_utils_dir"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    # 2. 모드에 따른 실행
    case "$mode" in
        restart)
            log_info "Restarting application on port $port"
            restart_application "$port" "$java_opts" "$common_utils_dir"
            ;;
        stop)
            log_info "Stopping application on port $port"
            stop_application "$port" "$common_utils_dir"
            ;;
        start)
            log_info "Starting application on port $port"
            start_application "$port" "$java_opts" "$common_utils_dir"
            ;;
        *)
            error_exit "Invalid mode: use 'stop', 'start', or 'restart'"
            ;;
    esac
}

# 애플리케이션 상태 확인 함수
check_application_status() {
    local port="$1"
    local common_utils_dir="$2"

    echo "=== Application Status ==="
    echo "Port: $port"

    local status
    status=$(check_app_running "$port" "$common_utils_dir")

    case "$status" in
        "running")
            echo "Status: ✅ RUNNING"
            get_app_process_info "$port" "$common_utils_dir"
            ;;
        "stopped")
            echo "Status: ❌ STOPPED"
            ;;
    esac
}

# 고급 runApp 함수 (추가 옵션 지원)
runapp_advanced() {
    local port="$1"
    local mode="$2"
    local java_opts="$3"
    local common_utils_dir="$4"
    local option="${5:-normal}"

    # 파라미터 검증
    validate_runapp_parameters "$port" "$mode" "$java_opts" "$common_utils_dir"

    # common_utils 로드
    source "${common_utils_dir}/common_utils.sh"

    case "$mode" in
        restart)
            case "$option" in
                "safe")
                    restart_application_safe "$port" "$java_opts" "$common_utils_dir"
                    ;;
                "force")
                    restart_application_force "$port" "$java_opts" "$common_utils_dir"
                    ;;
                "health")
                    restart_with_healthcheck "$port" "$java_opts" "$common_utils_dir"
                    ;;
                *)
                    restart_application "$port" "$java_opts" "$common_utils_dir"
                    ;;
            esac
            ;;
        stop)
            case "$option" in
                "force")
                    force_stop_application "$port" "$common_utils_dir"
                    ;;
                "safe")
                    stop_application_safe "$port" "$common_utils_dir"
                    ;;
                *)
                    stop_application "$port" "$common_utils_dir"
                    ;;
            esac
            ;;
        start)
            case "$option" in
                "safe")
                    start_application_safe "$port" "$java_opts" "$common_utils_dir"
                    ;;
                *)
                    start_application "$port" "$java_opts" "$common_utils_dir"
                    ;;
            esac
            ;;
        *)
            error_exit "Invalid mode: use 'stop', 'start', or 'restart'"
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${5:-main}" in
        "main")
            runapp_main "$1" "$2" "$3" "$4"
            ;;
        "status")
            check_application_status "$1" "$4"
            ;;
        "advanced")
            runapp_advanced "$1" "$2" "$3" "$4" "${6:-normal}"
            ;;
        *)
            echo "Usage: runApp_main.sh <port> <mode> <java_opts> <common_utils_dir> [main|status|advanced] [option]"
            echo ""
            echo "Modes:"
            echo "  main: Standard runApp functionality (default)"
            echo "  status: Check application status"
            echo "  advanced: Advanced mode with additional options"
            echo ""
            echo "Advanced options:"
            echo "  For restart: normal, safe, force, health"
            echo "  For stop: normal, safe, force"
            echo "  For start: normal, safe"
            exit 1
            ;;
    esac
fi