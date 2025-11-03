#!/bin/bash
set -euo pipefail


# run_app_control.sh - Application Process Management
#
# Layer: 4 (Support Services)
# 역할: Spring Boot 애플리케이션 프로세스 관리
# 호출자: deploy_control.sh, rollback_control.sh (Layer 3)
# 호출 대상: 없음 (최하위 계층)
#
# 책임:
#   - 애플리케이션 시작/중지/재시작
#   - 프로세스 탐지 (포트 기반)
#   - PID 파일 관리
#   - Graceful shutdown
# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 모든 함수 스크립트들 source (func 디렉터리에서)
source "${SCRIPT_DIR}/func/find_app_process.sh"
source "${SCRIPT_DIR}/func/build_exec_command.sh"
source "${SCRIPT_DIR}/func/stop_application.sh"
source "${SCRIPT_DIR}/func/start_application.sh"
source "${SCRIPT_DIR}/func/restart_application.sh"

# 사용법 출력
print_usage() {
    cat << EOF
Usage: run_app_control.sh <command> [arguments]

Commands:
  start <port> [java_opts] [jar_name] [mode]       - Start application
  stop <port> [jar_name] [mode]                    - Stop application
  restart <port> [java_opts] [jar_name] [mode]     - Restart application
  status <port> [jar_name]                         - Check application status
  info <port> [jar_name]                           - Show detailed process info
  find <port> [jar_name]                           - Find process PID

Note: Arguments in [brackets] are optional and can use defaults from run_app.env

Environment variables (set in run_app.env):
  APP_JAR_NAME          - Default JAR file name (default: current.jar)
  APP_JAVA_EXECUTABLE   - Java executable path (default: java)
  JVM_OPTS              - JVM options (memory, GC, etc. e.g., -Xmx1024m -Xms512m)
  APP_JAVA_OPTS         - Default Java options (Spring options, profiles, etc.)
  APP_SIGTERM_TIMEOUT   - SIGTERM timeout in seconds (default: 10)
  APP_SIGKILL_TIMEOUT   - SIGKILL timeout in seconds (default: 5)
  APP_START_WAIT        - Wait time after start in seconds (default: 2)
  APP_PORT_WAIT_TIMEOUT - Port listening wait timeout in seconds (default: 10)
  APP_LOG_DIR           - Log directory (default: ./logs)

Modes:
  Start/Restart modes:
    normal - Standard start/restart (default)
    health - Start/restart with health check

  Stop modes:
    graceful - Graceful stop with SIGTERM then SIGKILL (default)
    force    - Force stop with SIGKILL only

Examples:
  # Using run_app.env defaults
  ./run_app_control.sh start 8080
  ./run_app_control.sh stop 8080
  ./run_app_control.sh restart 8080

  # Override Java options
  ./run_app_control.sh start 8080 '--spring.profiles.active=dev'

  # Specify JAR file
  ./run_app_control.sh start 8080 '--spring.profiles.active=prod' app.jar

  # Start with health check
  ./run_app_control.sh start 8080 '--spring.profiles.active=prod' current.jar health

  # Force stop
  ./run_app_control.sh stop 8080 current.jar force

  # Check status
  ./run_app_control.sh status 8080
  ./run_app_control.sh info 8080
EOF
}

# 메인 진입점
main() {
    if [ "$#" -lt 1 ]; then
        print_usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        start)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'start' requires at least <port>"
                exit 1
            fi
            start_application "$@"
            ;;
        stop)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'stop' requires at least <port>"
                exit 1
            fi
            stop_application "$@"
            ;;
        restart)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'restart' requires at least <port>"
                exit 1
            fi
            restart_application "$@"
            ;;
        status)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'status' requires at least <port>"
                exit 1
            fi
            status=$(check_app_running "$1" "${2:-}")
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Port $1 status: $status" >&2
            ;;
        info)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'info' requires at least <port>"
                exit 1
            fi
            get_app_process_info "$@"
            ;;
        find)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'find' requires at least <port>"
                exit 1
            fi
            find_app_process "$@"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
