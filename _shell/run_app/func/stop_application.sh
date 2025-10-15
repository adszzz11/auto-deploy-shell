#!/bin/bash
set -euo pipefail


# 애플리케이션 중지 함수 (Graceful Shutdown)
stop_application() {
    local port="$1"
    local jar_name="${2:-${APP_JAR_NAME:-current.jar}}"
    local sigterm_timeout="${3:-${APP_SIGTERM_TIMEOUT:-10}}"
    local sigkill_timeout="${4:-${APP_SIGKILL_TIMEOUT:-5}}"

    # 필요한 함수 로드
    source "${SCRIPT_DIR}/func/find_app_process.sh"

    # 프로세스 찾기
    local pid
    if ! pid=$(find_app_process "$port" "$jar_name"); then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No app running on port ${port}. Nothing to stop." >&2
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Stopping app with PID: $pid" >&2

    # 1단계: SIGTERM 전송
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Sending SIGTERM to process $pid" >&2
    kill -15 "$pid"

    # SIGTERM 대기
    local wait_time=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        wait_time=$((wait_time + 1))
        if [ "$wait_time" -ge "$sigterm_timeout" ]; then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Process $pid did not terminate after $sigterm_timeout seconds, sending SIGKILL..." >&2
            break
        fi
    done

    # 프로세스가 종료되었는지 확인
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Process $pid terminated gracefully" >&2
        return 0
    fi

    # 2단계: SIGKILL 전송
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Sending SIGKILL to process $pid" >&2
    kill -9 "$pid"

    # SIGKILL 대기
    wait_time=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        wait_time=$((wait_time + 1))
        if [ "$wait_time" -ge "$sigkill_timeout" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Process $pid did not terminate even after SIGKILL" >&2
            return 1
        fi
    done

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Process $pid has terminated" >&2
}

# 강제 중지 함수 (SIGKILL만 사용)
force_stop_application() {
    local port="$1"
    local jar_name="${2:-${APP_JAR_NAME:-current.jar}}"

    source "${SCRIPT_DIR}/func/find_app_process.sh"

    local pid
    if ! pid=$(find_app_process "$port" "$jar_name"); then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No app running on port ${port}. Nothing to stop." >&2
        return 0
    fi

    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Force stopping app with PID: $pid (SIGKILL)" >&2
    kill -9 "$pid"

    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to force stop process $pid" >&2
        return 1
    else
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Process $pid force stopped" >&2
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: stop_application.sh <port> [jar_name] [mode] [sigterm_timeout] [sigkill_timeout]"
        echo ""
        echo "Arguments:"
        echo "  port             - Application port number"
        echo "  jar_name         - JAR file name (default: from run_app.env)"
        echo "  mode             - 'force' for SIGKILL only (default: graceful)"
        echo "  sigterm_timeout  - SIGTERM timeout in seconds (default: from run_app.env or 10)"
        echo "  sigkill_timeout  - SIGKILL timeout in seconds (default: from run_app.env or 5)"
        echo ""
        echo "Examples:"
        echo "  stop_application.sh 8080"
        echo "  stop_application.sh 8080 current.jar force"
        exit 1
    fi

    case "${3:-graceful}" in
        "force")
            force_stop_application "$1" "${2:-}"
            ;;
        *)
            stop_application "$1" "${2:-}" "${4:-}" "${5:-}"
            ;;
    esac
fi
