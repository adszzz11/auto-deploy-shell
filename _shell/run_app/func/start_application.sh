#!/bin/bash
set -euo pipefail


# 애플리케이션 시작 함수
start_application() {
    local port="$1"
    local java_opts="${2:-${APP_JAVA_OPTS:-}}"
    local jar_name="${3:-${APP_JAR_NAME:-current.jar}}"
    local start_wait="${4:-${APP_START_WAIT:-2}}"

    # 필요한 함수 로드
    source "${SCRIPT_DIR}/func/find_app_process.sh"
    source "${SCRIPT_DIR}/func/build_exec_command.sh"

    # 이미 실행 중인지 확인
    if find_app_process "$port" "$jar_name" >/dev/null 2>&1; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Application is already running on port $port" >&2
        return 0
    fi

    # Java 실행 파일 검증
    verify_java_executable "${APP_JAVA_EXECUTABLE:-java}" || return 1

    # JAR 파일 확인
    verify_jar_file "$jar_name"

    # 로그 디렉터리 준비
    local log_dir
    log_dir=$(prepare_log_directory)

    # 실행 명령어 구성
    local exec_command
    exec_command=$(build_exec_command "$port" "$java_opts" "$jar_name")

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Starting application with command: $exec_command" >&2

    # 백그라운드에서 애플리케이션 시작
    nohup $exec_command > "${log_dir}/app-${port}.log" 2>&1 &
    local start_pid=$!

    # 잠시 대기 후 프로세스가 실제로 시작되었는지 확인
    sleep "$start_wait"

    if kill -0 "$start_pid" 2>/dev/null; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Application started on port $port (PID: $start_pid)" >&2
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to start application on port $port" >&2
        return 1
    fi
}

# 헬스체크와 함께 시작
start_with_healthcheck() {
    local port="$1"
    local java_opts="${2:-${APP_JAVA_OPTS:-}}"
    local jar_name="${3:-${APP_JAR_NAME:-current.jar}}"

    # 애플리케이션 시작
    start_application "$port" "$java_opts" "$jar_name"

    # 헬스체크 설정 로드
    local health_check_enabled="${APP_HEALTH_CHECK_ENABLED:-false}"

    if [ "$health_check_enabled" = "true" ]; then
        local health_url="${APP_HEALTH_CHECK_URL:-http://localhost}:${port}${APP_HEALTH_CHECK_PATH:-/actuator/health}"
        local timeout="${APP_HEALTH_CHECK_TIMEOUT:-30}"
        local interval="${APP_HEALTH_CHECK_INTERVAL:-2}"

        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Performing health check on $health_url" >&2

        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if curl -sf "$health_url" > /dev/null 2>&1; then
                echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Health check passed" >&2
                return 0
            fi
            sleep "$interval"
            elapsed=$((elapsed + interval))
        done

        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Health check failed after ${timeout}s" >&2
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: start_application.sh <port> [java_opts] [jar_name] [mode]"
        echo ""
        echo "Arguments:"
        echo "  port       - Application port number"
        echo "  java_opts  - Java options (default: from run_app.env)"
        echo "  jar_name   - JAR file name (default: from run_app.env)"
        echo "  mode       - 'health' for health check (default: normal)"
        echo ""
        echo "Examples:"
        echo "  start_application.sh 8080"
        echo "  start_application.sh 8080 '--spring.profiles.active=dev'"
        echo "  start_application.sh 8080 '--spring.profiles.active=prod' current.jar health"
        exit 1
    fi

    case "${4:-normal}" in
        "health")
            start_with_healthcheck "$1" "${2:-}" "${3:-}"
            ;;
        *)
            start_application "$1" "${2:-}" "${3:-}"
            ;;
    esac
fi
