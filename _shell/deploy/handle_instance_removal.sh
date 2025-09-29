#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 인스턴스 제거 처리 함수
handle_instance_removal() {
    local instance_dir="$1"
    local port="$2"
    local script_dir="$3"
    local upstream_conf="$4"

    log_info "Removing instance: port ${port}, directory ${instance_dir}"

    # 인스턴스 디렉터리 존재 확인
    if [ ! -d "$instance_dir" ]; then
        log_warn "Instance directory ${instance_dir} does not exist. Nothing to remove."
        return 0
    fi

    # 1. 애플리케이션 중지
    stop_application_for_removal "$instance_dir" "$port" "$script_dir"

    # 2. Nginx 트래픽 차단
    disable_nginx_upstream "$port" "$upstream_conf" "$script_dir"

    # 3. 인스턴스 디렉터리 제거
    remove_instance_directory "$instance_dir"

    log_success "Instance removal completed for port $port"
}

# 제거를 위한 애플리케이션 중지 함수
stop_application_for_removal() {
    local instance_dir="$1"
    local port="$2"
    local script_dir="$3"

    log_info "Stopping application on port ${port} in ${instance_dir}"

    local runapp_script="${instance_dir}/runApp.sh"

    if [ -f "$runapp_script" ]; then
        if [ -x "$runapp_script" ]; then
            # runApp.sh가 존재하고 실행 가능한 경우
            if ( cd "$instance_dir" && ./runApp.sh "$port" stop "" "$script_dir" ); then
                log_success "Application stopped successfully on port $port"
            else
                log_warn "Failed to stop application on port ${port}, but continuing removal"
            fi
        else
            log_warn "runApp.sh found but not executable in ${instance_dir}"
        fi
    else
        log_warn "No runApp.sh found in ${instance_dir}"

        # runApp.sh가 없는 경우 직접 프로세스 종료 시도
        attempt_direct_process_termination "$port"
    fi
}

# 직접 프로세스 종료 시도 함수
attempt_direct_process_termination() {
    local port="$1"

    log_info "Attempting direct process termination for port $port"

    local search_pattern="java -jar current.jar --server.port=${port}"
    local pid

    pid=$(pgrep -f "$search_pattern" 2>/dev/null || echo "")

    if [ -n "$pid" ]; then
        log_info "Found process with PID: $pid, terminating..."

        # SIGTERM 먼저 시도
        if kill -15 "$pid" 2>/dev/null; then
            log_info "SIGTERM sent to process $pid"

            # 10초 대기
            local wait_time=0
            while [ $wait_time -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                wait_time=$((wait_time + 1))
            done

            # 여전히 실행 중이면 SIGKILL
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "Process $pid did not terminate, sending SIGKILL"
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi

        log_success "Process termination completed for port $port"
    else
        log_info "No process found for port $port"
    fi
}

# Nginx 업스트림 비활성화 함수
disable_nginx_upstream() {
    local port="$1"
    local upstream_conf="$2"
    local script_dir="$3"

    log_info "Setting nginx upstream DOWN for port ${port}"

    local nginx_script="${script_dir}/controll_nginx.sh"

    if [ -f "$nginx_script" ] && [ -x "$nginx_script" ]; then
        if "$nginx_script" "$port" "$upstream_conf" down; then
            log_success "Nginx upstream disabled for port $port"
        else
            log_warn "Failed to set nginx upstream DOWN for port ${port}"
        fi
    else
        log_warn "Nginx control script not found or not executable: $nginx_script"
    fi
}

# 인스턴스 디렉터리 제거 함수
remove_instance_directory() {
    local instance_dir="$1"

    log_info "Removing instance directory ${instance_dir}"

    # 안전성 검증 (실수로 중요한 디렉터리 삭제 방지)
    if [[ "$instance_dir" == "/" ]] || [[ "$instance_dir" == "/home" ]] || [[ "$instance_dir" == "/usr" ]]; then
        error_exit "Refusing to remove system directory: $instance_dir"
    fi

    # instances 디렉터리 하위가 아닌 경우 경고
    if [[ "$instance_dir" != *"/instances/"* ]]; then
        log_warn "Directory path doesn't contain 'instances', please verify: $instance_dir"
        read -p "Are you sure you want to remove this directory? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Directory removal cancelled by user"
            return 1
        fi
    fi

    if rm -rf "$instance_dir"; then
        log_success "Instance directory removed successfully: $instance_dir"
    else
        error_exit "Failed to remove instance directory: $instance_dir"
    fi
}

# 인스턴스 제거 상태 확인 함수
check_removal_status() {
    local instance_dir="$1"
    local port="$2"

    echo "=== Instance Removal Status ==="
    echo "Instance Directory: $instance_dir"
    echo "Port: $port"

    # 인스턴스 디렉터리 상태
    if [ -d "$instance_dir" ]; then
        echo "⚠️  Instance directory still exists"
        echo "    Contents:"
        ls -la "$instance_dir" 2>/dev/null || echo "    (Unable to list contents)"
    else
        echo "✅ Instance directory removed"
    fi

    # 프로세스 상태
    local search_pattern="java -jar current.jar --server.port=${port}"
    local pid
    pid=$(pgrep -f "$search_pattern" 2>/dev/null || echo "")

    if [ -n "$pid" ]; then
        echo "⚠️  Process still running (PID: $pid)"
    else
        echo "✅ No process running on port $port"
    fi
}

# 인스턴스 제거 준비 함수
prepare_for_removal() {
    local instance_dir="$1"
    local backup_dir="${2:-/tmp/instance_backups}"

    if [ ! -d "$instance_dir" ]; then
        log_info "Instance directory does not exist, no preparation needed"
        return 0
    fi

    log_info "Preparing for instance removal"

    # 백업 디렉터리 생성
    mkdir -p "$backup_dir" || error_exit "Failed to create backup directory: $backup_dir"

    # 중요한 파일들 백업 (선택적)
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="instance_backup_${timestamp}"
    local backup_path="${backup_dir}/${backup_name}"

    log_info "Creating backup: $backup_path"

    if cp -r "$instance_dir" "$backup_path"; then
        log_success "Instance backup created: $backup_path"
    else
        log_warn "Failed to create instance backup"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: handle_instance_removal.sh <instance_dir> <port> [remove|prepare|check] [script_dir] [upstream_conf] [backup_dir]"
        echo "  remove: Remove instance (requires script_dir, upstream_conf)"
        echo "  prepare: Prepare for removal (backup)"
        echo "  check: Check removal status"
        exit 1
    fi

    case "${3:-remove}" in
        "prepare")
            prepare_for_removal "$1" "${6:-/tmp/instance_backups}"
            ;;
        "check")
            check_removal_status "$1" "$2"
            ;;
        *)
            handle_instance_removal "$1" "$2" "${4:-/path/to/script/dir}" "${5:-/etc/nginx/conf.d/upstream.conf}"
            ;;
    esac
fi