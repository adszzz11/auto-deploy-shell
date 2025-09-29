#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 애플리케이션 배포 실행 함수
execute_deployment() {
    local instance_dir="$1"
    local port="$2"
    local app_mode="$3"
    local java_opts="$4"
    local script_dir="$5"

    log_info "Deploying application on port ${port} from instance directory ${instance_dir}"

    # 인스턴스 디렉터리로 이동하여 runApp.sh 실행
    if ( cd "$instance_dir" && ./runApp.sh "$port" "$app_mode" "$java_opts" "$script_dir" ); then
        log_success "Application deployed successfully on port $port"
    else
        error_exit "Failed to deploy application on port $port"
    fi
}

# 테스트 스크립트 실행 함수
execute_test_script() {
    local test_script="$1"
    local port="$2"

    if [ -z "$test_script" ]; then
        log_info "No test script provided. Skipping tests."
        return 0
    fi

    if [ ! -f "$test_script" ]; then
        log_warn "Test script not found: $test_script. Skipping tests."
        return 0
    fi

    if [ ! -x "$test_script" ]; then
        log_warn "Test script is not executable: $test_script. Skipping tests."
        return 0
    fi

    log_info "Running tests on instance at port ${port}"

    if "$test_script" "$port"; then
        log_success "Tests passed for instance on port $port"
        return 0
    else
        error_exit "Tests failed for instance on port $port"
    fi
}

# 배포 전 검증 함수
verify_deployment_prerequisites() {
    local instance_dir="$1"
    local script_dir="$2"

    log_info "Verifying deployment prerequisites"

    # 인스턴스 디렉터리 확인
    if [ ! -d "$instance_dir" ]; then
        error_exit "Instance directory not found: $instance_dir"
    fi

    # runApp.sh 확인
    local runapp_script="${instance_dir}/runApp.sh"
    if [ ! -f "$runapp_script" ]; then
        error_exit "runApp.sh not found in instance directory: $runapp_script"
    fi

    if [ ! -x "$runapp_script" ]; then
        error_exit "runApp.sh is not executable: $runapp_script"
    fi

    # current.jar 확인
    local jar_file="${instance_dir}/current.jar"
    if [ ! -e "$jar_file" ]; then
        error_exit "current.jar not found in instance directory: $jar_file"
    fi

    if [ -L "$jar_file" ]; then
        local target
        target=$(readlink "$jar_file")
        if [ ! -f "$target" ]; then
            error_exit "JAR symlink target not found: $target"
        fi
        log_info "JAR symlink verified: $jar_file -> $target"
    else
        log_info "JAR file verified: $jar_file"
    fi

    log_success "Deployment prerequisites verified"
}

# 배포 상태 확인 함수
check_deployment_status() {
    local instance_dir="$1"
    local port="$2"

    echo "=== Deployment Status ==="
    echo "Instance Directory: $instance_dir"
    echo "Port: $port"

    # 인스턴스 디렉터리 상태
    if [ -d "$instance_dir" ]; then
        echo "✅ Instance directory exists"

        # runApp.sh 상태
        local runapp_script="${instance_dir}/runApp.sh"
        if [ -f "$runapp_script" ] && [ -x "$runapp_script" ]; then
            echo "✅ runApp.sh is ready"
        else
            echo "❌ runApp.sh is missing or not executable"
        fi

        # JAR 파일 상태
        local jar_file="${instance_dir}/current.jar"
        if [ -e "$jar_file" ]; then
            if [ -L "$jar_file" ]; then
                local target
                target=$(readlink "$jar_file")
                echo "✅ JAR symlink: current.jar -> $(basename "$target")"
            else
                echo "✅ JAR file: current.jar"
            fi
        else
            echo "❌ current.jar missing"
        fi

        # 로그 디렉터리 상태
        local log_dir="${instance_dir}/logs"
        if [ -L "$log_dir" ]; then
            echo "✅ Log directory symlink configured"
        elif [ -d "$log_dir" ]; then
            echo "✅ Log directory exists"
        else
            echo "⚠️  Log directory not configured"
        fi
    else
        echo "❌ Instance directory missing"
    fi

    # 프로세스 상태 확인 (선택적)
    local search_pattern="java -jar current.jar --server.port=${port}"
    local pid
    pid=$(pgrep -f "$search_pattern" 2>/dev/null || echo "")

    if [ -n "$pid" ]; then
        echo "✅ Application is running (PID: $pid)"
    else
        echo "❌ Application is not running"
    fi
}

# 배포 롤백 함수
rollback_deployment() {
    local instance_dir="$1"
    local port="$2"
    local script_dir="$3"

    log_warn "Rolling back deployment for port $port"

    # 애플리케이션 중지
    local runapp_script="${instance_dir}/runApp.sh"
    if [ -f "$runapp_script" ] && [ -x "$runapp_script" ]; then
        log_info "Stopping application on port $port"
        ( cd "$instance_dir" && ./runApp.sh "$port" stop "" "$script_dir" ) || log_warn "Failed to stop application"
    fi

    # JAR 파일 복원
    local jar_file="${instance_dir}/current.jar"
    local backup_file="${jar_file}.bak"

    if [ -f "$backup_file" ]; then
        log_info "Restoring JAR from backup"
        if mv "$backup_file" "$jar_file"; then
            log_success "JAR restored from backup"
        else
            log_warn "Failed to restore JAR from backup"
        fi
    else
        log_warn "No JAR backup found for restoration"
    fi

    log_warn "Deployment rollback completed"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: execute_deployment.sh <instance_dir> <port> [deploy|test|verify|status|rollback] [app_mode] [java_opts] [script_dir] [test_script]"
        echo "  deploy: Execute deployment (requires app_mode, java_opts, script_dir)"
        echo "  test: Execute test script (requires test_script)"
        echo "  verify: Verify deployment prerequisites"
        echo "  status: Check deployment status"
        echo "  rollback: Rollback deployment (requires script_dir)"
        exit 1
    fi

    case "${3:-deploy}" in
        "test")
            execute_test_script "${7:-}" "$2"
            ;;
        "verify")
            verify_deployment_prerequisites "$1" "${6:-/path/to/script/dir}"
            ;;
        "status")
            check_deployment_status "$1" "$2"
            ;;
        "rollback")
            rollback_deployment "$1" "$2" "${6:-/path/to/script/dir}"
            ;;
        *)
            execute_deployment "$1" "$2" "${4:-restart}" "${5:-}" "${6:-/path/to/script/dir}"
            ;;
    esac
fi