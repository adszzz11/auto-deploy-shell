#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 롤백 후 애플리케이션 재시작 함수
restart_after_rollback() {
    local instance_dir="$1"
    local port="$2"
    local app_mode="$3"
    local java_opts="$4"
    local script_dir="$5"
    local instance_num="$6"

    log_info "Restarting application after rollback for instance $instance_num"

    # runApp.sh 스크립트 확인
    local runapp_script="${instance_dir}/runApp.sh"
    local fallback_runapp="${script_dir}/runApp.sh"

    if [ -f "$runapp_script" ]; then
        execute_runapp_restart "$runapp_script" "$instance_dir" "$port" "$app_mode" "$java_opts" "$script_dir" "$instance_num"
    elif [ -f "$fallback_runapp" ]; then
        log_warn "runApp.sh not found in instance directory, using fallback"
        execute_runapp_restart "$fallback_runapp" "$instance_dir" "$port" "$app_mode" "$java_opts" "$script_dir" "$instance_num"
    else
        log_warn "runApp.sh not found, skipping application restart"
        return 1
    fi

    log_success "Application restart completed for instance $instance_num"
}

# runApp.sh 실행 함수
execute_runapp_restart() {
    local runapp_script="$1"
    local instance_dir="$2"
    local port="$3"
    local app_mode="$4"
    local java_opts="$5"
    local script_dir="$6"
    local instance_num="$7"

    log_info "Executing runApp.sh for instance $instance_num"

    # runApp.sh 실행 권한 확인
    if [ ! -x "$runapp_script" ]; then
        log_warn "runApp.sh is not executable, attempting to fix permissions"
        chmod +x "$runapp_script" || log_warn "Failed to make runApp.sh executable"
    fi

    # 인스턴스 디렉터리로 이동하여 실행
    local restart_start_time
    restart_start_time=$(current_timestamp)

    if (cd "$instance_dir" && "$runapp_script" "$port" "$app_mode" "${java_opts:-}" "$script_dir"); then
        local restart_end_time
        restart_end_time=$(current_timestamp)
        local duration=$((restart_end_time - restart_start_time))

        log_success "Application restarted successfully in ${duration}s"
        audit_log "RESTART_AFTER_ROLLBACK_SUCCESS" "instance=$instance_num port=$port duration=${duration}s"
    else
        local restart_end_time
        restart_end_time=$(current_timestamp)
        local duration=$((restart_end_time - restart_start_time))

        audit_log "RESTART_AFTER_ROLLBACK_FAILED" "instance=$instance_num port=$port duration=${duration}s"
        error_exit "Failed to restart application for instance $instance_num"
    fi
}

# 새로운 runApp 시스템을 사용한 재시작 함수
restart_with_new_runapp() {
    local port="$1"
    local app_mode="$2"
    local java_opts="$3"
    local common_utils_dir="$4"
    local instance_num="$5"

    log_info "Restarting with new runApp system for instance $instance_num"

    local runapp_main_script="${common_utils_dir}/../runApp/runApp_main.sh"

    if [ ! -f "$runapp_main_script" ]; then
        log_error "New runApp main script not found: $runapp_main_script"
        return 1
    fi

    local restart_start_time
    restart_start_time=$(current_timestamp)

    # restart 모드로 실행
    if "$runapp_main_script" "$port" "restart" "${java_opts:-}" "$common_utils_dir"; then
        local restart_end_time
        restart_end_time=$(current_timestamp)
        local duration=$((restart_end_time - restart_start_time))

        log_success "Application restarted with new runApp system in ${duration}s"
        audit_log "NEW_RUNAPP_RESTART_SUCCESS" "instance=$instance_num port=$port duration=${duration}s"
    else
        local restart_end_time
        restart_end_time=$(current_timestamp)
        local duration=$((restart_end_time - restart_start_time))

        audit_log "NEW_RUNAPP_RESTART_FAILED" "instance=$instance_num port=$port duration=${duration}s"
        error_exit "Failed to restart with new runApp system for instance $instance_num"
    fi
}

# 롤백 후 헬스체크 함수
verify_restart_health() {
    local port="$1"
    local instance_num="$2"
    local max_wait="${3:-30}"

    log_info "Verifying application health after restart for instance $instance_num"

    local wait_time=0
    local health_endpoint="${HEALTH_ENDPOINT:-/actuator/health}"

    while [ "$wait_time" -lt "$max_wait" ]; do
        if curl -s -f "http://localhost:$port$health_endpoint" >/dev/null 2>&1; then
            log_success "Application is healthy after rollback restart (port $port)"
            return 0
        fi

        sleep 2
        wait_time=$((wait_time + 2))
        log_info "Waiting for health check... ($wait_time/${max_wait}s)"
    done

    log_warn "Health check timed out after ${max_wait}s for instance $instance_num"
    return 1
}

# 프로세스 상태 확인 함수
check_process_status() {
    local port="$1"
    local instance_num="$2"

    log_info "Checking process status for instance $instance_num (port $port)"

    # 포트를 사용하는 프로세스 찾기
    local pid
    if command -v lsof >/dev/null 2>&1; then
        pid=$(lsof -ti:$port 2>/dev/null | head -1)
    elif command -v netstat >/dev/null 2>&1; then
        pid=$(netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | head -1)
    else
        log_warn "Cannot check process status (lsof and netstat not available)"
        return 1
    fi

    if [ -n "$pid" ] && [ "$pid" != "-" ]; then
        log_success "Application process running with PID $pid on port $port"

        # 프로세스 정보 출력
        if ps -p "$pid" >/dev/null 2>&1; then
            local process_info
            process_info=$(ps -p "$pid" -o pid,ppid,user,comm,etime 2>/dev/null | tail -1)
            log_info "Process info: $process_info"
        fi

        return 0
    else
        log_error "No process found on port $port for instance $instance_num"
        return 1
    fi
}

# 스마트 재시작 함수 (여러 방법 시도)
smart_restart_after_rollback() {
    local instance_dir="$1"
    local port="$2"
    local app_mode="$3"
    local java_opts="$4"
    local script_dir="$5"
    local instance_num="$6"

    log_info "Starting smart restart for instance $instance_num after rollback"

    # 방법 1: 기존 runApp.sh 시도
    if restart_after_rollback "$instance_dir" "$port" "$app_mode" "$java_opts" "$script_dir" "$instance_num" 2>/dev/null; then
        log_success "Restart successful with legacy runApp.sh"
    else
        log_warn "Legacy runApp.sh restart failed, trying new runApp system"

        # 방법 2: 새로운 runApp 시스템 시도
        local common_utils_dir="${script_dir}/../common_utils"
        if restart_with_new_runapp "$port" "$app_mode" "$java_opts" "$common_utils_dir" "$instance_num" 2>/dev/null; then
            log_success "Restart successful with new runApp system"
        else
            log_error "All restart methods failed for instance $instance_num"
            return 1
        fi
    fi

    # 재시작 후 상태 확인
    sleep 3

    # 프로세스 상태 확인
    if check_process_status "$port" "$instance_num"; then
        log_success "Process verification passed"
    else
        log_warn "Process verification failed"
    fi

    # 헬스체크 (선택적)
    if [ "${ENABLE_HEALTH_CHECK:-true}" = "true" ]; then
        if verify_restart_health "$port" "$instance_num" "${HEALTH_CHECK_TIMEOUT:-30}"; then
            log_success "Health check passed"
        else
            log_warn "Health check failed or timed out"
        fi
    fi

    log_success "Smart restart completed for instance $instance_num"
}

# 재시작 상태 확인 함수
show_restart_status() {
    local port="$1"
    local instance_num="$2"
    local instance_dir="$3"

    echo "=== Restart Status for Instance $instance_num ==="
    echo "Port: $port"
    echo "Instance Directory: $instance_dir"
    echo ""

    # runApp.sh 스크립트 상태
    local runapp_script="${instance_dir}/runApp.sh"
    if [ -f "$runapp_script" ]; then
        if [ -x "$runapp_script" ]; then
            echo "✅ runApp.sh exists and is executable"
        else
            echo "⚠️  runApp.sh exists but is not executable"
        fi
    else
        echo "❌ runApp.sh not found in instance directory"
    fi

    # 프로세스 상태
    if check_process_status "$port" "$instance_num" 2>/dev/null; then
        echo "✅ Application process is running"
    else
        echo "❌ Application process not found"
    fi

    # 포트 상태
    if command -v nc >/dev/null 2>&1; then
        if nc -z localhost "$port" 2>/dev/null; then
            echo "✅ Port $port is accessible"
        else
            echo "❌ Port $port is not accessible"
        fi
    else
        echo "⚠️  Cannot check port accessibility (nc not available)"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 6 ]; then
        echo "Usage: restart_after_rollback.sh <instance_dir> <port> <app_mode> <java_opts> <script_dir> <instance_number> [smart|new|status]"
        echo "  (default): Standard restart with legacy runApp.sh"
        echo "  smart: Try multiple restart methods"
        echo "  new: Use new runApp system"
        echo "  status: Show restart status"
        exit 1
    fi

    case "${7:-default}" in
        "smart")
            smart_restart_after_rollback "$1" "$2" "$3" "$4" "$5" "$6"
            ;;
        "new")
            local common_utils_dir="${5}/../common_utils"
            restart_with_new_runapp "$2" "$3" "$4" "$common_utils_dir" "$6"
            ;;
        "status")
            show_restart_status "$2" "$6" "$1"
            ;;
        *)
            restart_after_rollback "$1" "$2" "$3" "$4" "$5" "$6"
            ;;
    esac
fi