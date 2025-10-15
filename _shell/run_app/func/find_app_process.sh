#!/bin/bash
set -euo pipefail

# 애플리케이션 프로세스 찾기 함수
find_app_process() {
    local port="$1"
    local jar_name="${2:-${APP_JAR_NAME:-current.jar}}"

    # 프로세스 검색 패턴: java -jar <jar_name> --server.port=<port>
    local pid
    pid=$(pgrep -f "java -jar ${jar_name} --server.port=${port}" 2>/dev/null || true)

    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    else
        return 1
    fi
}

# 애플리케이션 실행 여부 확인
check_app_running() {
    local port="$1"
    local jar_name="${2:-${APP_JAR_NAME:-current.jar}}"

    if find_app_process "$port" "$jar_name" >/dev/null 2>&1; then
        echo "running"
        return 0
    else
        echo "stopped"
        return 1
    fi
}

# 프로세스 정보 출력
get_app_process_info() {
    local port="$1"
    local jar_name="${2:-${APP_JAR_NAME:-current.jar}}"

    local pid
    if pid=$(find_app_process "$port" "$jar_name"); then
        echo "PID: $pid"
        echo "Command: $(ps -p "$pid" -o command= 2>/dev/null || echo 'N/A')"
        echo "Memory: $(ps -p "$pid" -o rss= 2>/dev/null || echo '0') KB"
        echo "CPU: $(ps -p "$pid" -o %cpu= 2>/dev/null || echo '0')%"
    else
        echo "No process found for port $port"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: find_app_process.sh <port> [jar_name] [info]"
        echo ""
        echo "Arguments:"
        echo "  port      - Application port number"
        echo "  jar_name  - JAR file name (default: from run_app.env or 'current.jar')"
        echo "  info      - Show detailed process info"
        exit 1
    fi

    case "${3:-find}" in
        "info")
            get_app_process_info "$1" "${2:-}"
            ;;
        "check")
            check_app_running "$1" "${2:-}"
            ;;
        *)
            find_app_process "$1" "${2:-}"
            ;;
    esac
fi
