#!/bin/bash
set -euo pipefail

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/..") && pwd)"
if [ -f "${SCRIPT_DIR}/deploy.env" ]; then
    source "${SCRIPT_DIR}/deploy.env"
fi

# 인스턴스 제거 처리
handle_instance_removal() {
    local instance_dir="$1"
    local port="$2"
    local script_dir="$3"
    local upstream_conf="$4"

    # 인스턴스 디렉터리 존재 확인
    if [ ! -d "$instance_dir" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Instance directory does not exist: $instance_dir"
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Nothing to remove"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Removing instance directory: $instance_dir"

    # 1. 애플리케이션 중지
    stop_instance_application "$instance_dir" "$port" "$script_dir"

    # 2. Nginx 업스트림 DOWN
    stop_instance_nginx "$port" "$upstream_conf" "$script_dir"

    # 3. 인스턴스 디렉터리 제거
    remove_instance_directory "$instance_dir"

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance removal completed"
    return 0
}

# 애플리케이션 중지
stop_instance_application() {
    local instance_dir="$1"
    local port="$2"
    local script_dir="$3"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Stopping application on port $port"

    local run_app_script="${script_dir}/../run_app/run_app_control.sh"

    if [ ! -x "$run_app_script" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - run_app_control.sh not found: $run_app_script"
        return 0
    fi

    # run_app_control.sh를 통해 애플리케이션 중지
    (
        cd "$instance_dir" || return 0
        "$run_app_script" stop "$port" || {
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to stop application on port $port"
            return 0
        }
    )

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Application stopped successfully"
    return 0
}

# Nginx 업스트림 중지
stop_instance_nginx() {
    local port="$1"
    local upstream_conf="$2"
    local script_dir="$3"
    local nginx_control="${4:-${DEPLOY_NGINX_CONTROL:-true}}"

    if [ "$nginx_control" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Nginx control disabled"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Setting nginx upstream DOWN for port $port"

    local nginx_script="${script_dir}/../nginx/nginx_control.sh"

    if [ ! -x "$nginx_script" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Nginx control script not found: $nginx_script"
        return 0
    fi

    "$nginx_script" down "$port" "$upstream_conf" || {
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to set nginx upstream DOWN for port $port"
        return 0
    }

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Nginx upstream set to DOWN"
    return 0
}

# 인스턴스 디렉터리 제거
remove_instance_directory() {
    local instance_dir="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Removing directory: $instance_dir"

    rm -rf "$instance_dir" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to remove instance directory: $instance_dir" >&2
        return 1
    }

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Directory removed successfully"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: handle_removal.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  remove <instance_dir> <port> <script_dir> <upstream_conf>  - Handle instance removal"
        echo "  stop-app <instance_dir> <port> <script_dir>                 - Stop instance application"
        echo "  stop-nginx <port> <upstream_conf> <script_dir>              - Stop nginx upstream"
        echo "  remove-dir <instance_dir>                                   - Remove instance directory"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        remove)
            handle_instance_removal "$@"
            ;;
        stop-app)
            stop_instance_application "$@"
            ;;
        stop-nginx)
            stop_instance_nginx "$@"
            ;;
        remove-dir)
            remove_instance_directory "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
