#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 배포 환경 준비 함수
prepare_deploy_environment() {
    local instance_dir="$1"
    local jar_trunk_dir="$2"

    log_info "Preparing deployment environment"

    # JAR 트렁크 디렉터리 검증
    if [ ! -d "$jar_trunk_dir" ]; then
        error_exit "JAR trunk directory not found: $jar_trunk_dir"
    fi

    # 인스턴스 디렉터리 생성 (필요시)
    if [ ! -d "$instance_dir" ]; then
        log_info "Creating instance directory: $instance_dir"
        if mkdir -p "$instance_dir"; then
            log_success "Instance directory created: $instance_dir"
        else
            error_exit "Failed to create instance directory: $instance_dir"
        fi
    else
        log_info "Instance directory already exists: $instance_dir"
    fi

    # 디렉터리 권한 확인
    if [ ! -w "$instance_dir" ]; then
        error_exit "Instance directory is not writable: $instance_dir"
    fi

    log_success "Deployment environment prepared"
}

# JAR 백업 함수
backup_current_jar() {
    local target_link="$1"

    if [ -L "$target_link" ] || [ -e "$target_link" ]; then
        local backup_path="${target_link}.bak"
        log_info "Backing up current.jar: $target_link -> $backup_path"

        if mv "$target_link" "$backup_path"; then
            log_success "JAR backup completed: $backup_path"
        else
            error_exit "Failed to backup current.jar: $target_link"
        fi
    else
        log_info "No existing JAR to backup at: $target_link"
    fi
}

# 인스턴스 디렉터리 정리 함수
cleanup_instance_directory() {
    local instance_dir="$1"
    local preserve_logs="${2:-true}"

    log_info "Cleaning up instance directory: $instance_dir"

    if [ ! -d "$instance_dir" ]; then
        log_warn "Instance directory does not exist: $instance_dir"
        return 0
    fi

    # 로그 보존 여부에 따른 처리
    if [ "$preserve_logs" = "true" ]; then
        # 로그 디렉터리를 제외한 정리
        local items_to_remove=()

        # 인스턴스 디렉터리 내 항목들 확인
        for item in "$instance_dir"/*; do
            if [ -e "$item" ]; then
                local basename_item=$(basename "$item")
                if [ "$basename_item" != "logs" ]; then
                    items_to_remove+=("$item")
                fi
            fi
        done

        # 로그를 제외한 항목들 제거
        for item in "${items_to_remove[@]}"; do
            if rm -rf "$item"; then
                log_info "Removed: $(basename "$item")"
            else
                log_warn "Failed to remove: $item"
            fi
        done

        log_info "Instance directory cleaned (logs preserved)"
    else
        # 전체 디렉터리 제거
        if rm -rf "$instance_dir"; then
            log_success "Instance directory completely removed: $instance_dir"
        else
            error_exit "Failed to remove instance directory: $instance_dir"
        fi
    fi
}

# 배포 준비 상태 확인 함수
check_deploy_readiness() {
    local instance_dir="$1"
    local jar_trunk_dir="$2"
    local service_name="$3"

    echo "=== Deployment Readiness Check ==="
    echo "Instance Directory: $instance_dir"
    echo "JAR Trunk Directory: $jar_trunk_dir"
    echo "Service Name: $service_name"

    # 인스턴스 디렉터리 상태
    if [ -d "$instance_dir" ]; then
        echo "✅ Instance directory exists"
        if [ -w "$instance_dir" ]; then
            echo "✅ Instance directory is writable"
        else
            echo "❌ Instance directory is not writable"
            return 1
        fi
    else
        echo "ℹ️  Instance directory will be created"
    fi

    # JAR 트렁크 디렉터리 상태
    if [ -d "$jar_trunk_dir" ]; then
        echo "✅ JAR trunk directory exists"

        # current_jar.pid 파일 확인
        if [ -f "$jar_trunk_dir/current_jar.pid" ]; then
            local jar_name
            jar_name=$(cat "$jar_trunk_dir/current_jar.pid" | tr -d '\r\n')
            echo "✅ JAR PID file exists: $jar_name"

            if [ -f "$jar_trunk_dir/$jar_name" ]; then
                echo "✅ Target JAR file exists: $jar_name"
            else
                echo "❌ Target JAR file missing: $jar_name"
                return 1
            fi
        else
            echo "❌ JAR PID file missing: current_jar.pid"
            return 1
        fi
    else
        echo "❌ JAR trunk directory missing"
        return 1
    fi

    echo "✅ Deployment readiness check passed"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: prepare_deploy_environment.sh <instance_dir> <jar_trunk_dir> [check|prepare|backup|cleanup] [service_name]"
        echo "  check: Check deployment readiness"
        echo "  prepare: Prepare deployment environment (default)"
        echo "  backup: Backup current JAR"
        echo "  cleanup: Clean instance directory"
        exit 1
    fi

    case "${3:-prepare}" in
        "check")
            check_deploy_readiness "$1" "$2" "${4:-unknown}"
            ;;
        "backup")
            backup_current_jar "$1/current.jar"
            ;;
        "cleanup")
            cleanup_instance_directory "$1" "${4:-true}"
            ;;
        *)
            prepare_deploy_environment "$1" "$2"
            ;;
    esac
fi