#!/bin/bash
set -euo pipefail

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${SCRIPT_DIR}/run_app.env" ]; then
    source "${SCRIPT_DIR}/run_app.env"
fi

# 애플리케이션 재시작 함수
restart_application() {
    local port="$1"
    local java_opts="${2:-${APP_JAVA_OPTS:-}}"
    local jar_name="${3:-${APP_JAR_NAME:-current.jar}}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Restarting application on port $port"

    # 필요한 함수 로드
    source "${SCRIPT_DIR}/func/stop_application.sh"
    source "${SCRIPT_DIR}/func/start_application.sh"

    # 중지
    stop_application "$port" "$jar_name"

    # 시작
    start_application "$port" "$java_opts" "$jar_name"

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Application restarted successfully on port $port"
}

# 헬스체크와 함께 재시작
restart_with_healthcheck() {
    local port="$1"
    local java_opts="${2:-${APP_JAVA_OPTS:-}}"
    local jar_name="${3:-${APP_JAR_NAME:-current.jar}}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Restarting application on port $port with health check"

    source "${SCRIPT_DIR}/func/stop_application.sh"
    source "${SCRIPT_DIR}/func/start_application.sh"

    # 중지
    stop_application "$port" "$jar_name"

    # 헬스체크와 함께 시작
    start_with_healthcheck "$port" "$java_opts" "$jar_name"

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Application restarted and health check passed on port $port"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: restart_application.sh <port> [java_opts] [jar_name] [mode]"
        echo ""
        echo "Arguments:"
        echo "  port       - Application port number"
        echo "  java_opts  - Java options (default: from run_app.env)"
        echo "  jar_name   - JAR file name (default: from run_app.env)"
        echo "  mode       - 'health' for health check (default: normal)"
        echo ""
        echo "Examples:"
        echo "  restart_application.sh 8080"
        echo "  restart_application.sh 8080 '--spring.profiles.active=prod' current.jar health"
        exit 1
    fi

    case "${4:-normal}" in
        "health")
            restart_with_healthcheck "$1" "${2:-}" "${3:-}"
            ;;
        *)
            restart_application "$1" "${2:-}" "${3:-}"
            ;;
    esac
fi
