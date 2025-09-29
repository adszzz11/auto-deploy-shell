#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# JAR 파일 롤백 실행 함수
execute_jar_rollback() {
    local target_link="$1"
    local backup_link="$2"
    local instance_num="$3"

    log_info "Executing JAR rollback for instance $instance_num"

    # 백업 파일 재확인
    if [ ! -e "$backup_link" ]; then
        error_exit "Backup file not found during rollback: $backup_link"
    fi

    # 현재 JAR 파일 백업 (안전을 위해)
    create_failed_deployment_backup "$target_link" "$instance_num"

    # 현재 JAR 파일/링크 제거
    remove_current_jar "$target_link" "$instance_num"

    # 백업에서 복원
    restore_from_backup "$backup_link" "$target_link" "$instance_num"

    log_success "JAR rollback completed for instance $instance_num"
}

# 실패한 배포 백업 생성 함수
create_failed_deployment_backup() {
    local target_link="$1"
    local instance_num="$2"

    if [ -e "$target_link" ]; then
        local failed_backup="${target_link}.failed.$(current_timestamp)"

        log_info "Creating backup of failed deployment: $failed_backup"

        if cp "$target_link" "$failed_backup" 2>/dev/null; then
            log_info "Failed deployment backed up to: $failed_backup"
        else
            log_warn "Failed to backup current deployment (proceeding with rollback)"
        fi
    else
        log_info "No current JAR to backup"
    fi
}

# 현재 JAR 파일 제거 함수
remove_current_jar() {
    local target_link="$1"
    local instance_num="$2"

    log_info "Removing current jar link/file at $target_link"

    if [ -e "$target_link" ]; then
        if rm -f "$target_link"; then
            log_success "Current JAR removed successfully"
        else
            error_exit "Failed to remove current jar link/file at $target_link"
        fi
    else
        log_info "Current JAR file does not exist (nothing to remove)"
    fi
}

# 백업에서 복원 함수
restore_from_backup() {
    local backup_link="$1"
    local target_link="$2"
    local instance_num="$3"

    log_info "Restoring backup jar from $backup_link to $target_link"

    # 백업 파일이 심볼릭 링크인지 일반 파일인지 확인
    if [ -L "$backup_link" ]; then
        # 심볼릭 링크인 경우 링크를 복사
        local backup_target
        backup_target=$(readlink "$backup_link")

        log_info "Backup is a symbolic link, creating new link to: $backup_target"

        if ln -s "$backup_target" "$target_link"; then
            log_success "Symbolic link restored successfully"
        else
            error_exit "Failed to restore symbolic link from backup"
        fi

        # 원래 백업 링크 제거
        rm -f "$backup_link"

    else
        # 일반 파일인 경우 이동
        if mv "$backup_link" "$target_link"; then
            log_success "JAR file restored successfully"
        else
            error_exit "Rollback failed for instance $instance_num"
        fi
    fi

    # 복원된 파일 권한 확인
    verify_restored_jar_permissions "$target_link" "$instance_num"
}

# 복원된 JAR 파일 권한 검증 함수
verify_restored_jar_permissions() {
    local target_link="$1"
    local instance_num="$2"

    log_info "Verifying restored JAR permissions"

    if [ ! -r "$target_link" ]; then
        log_warn "Restored JAR is not readable, attempting to fix permissions"
        chmod 644 "$target_link" || log_warn "Failed to fix JAR permissions"
    fi

    if [ -r "$target_link" ]; then
        log_success "Restored JAR permissions verified"
    else
        log_warn "Restored JAR may have permission issues"
    fi
}

# 안전한 JAR 롤백 함수 (추가 검증 포함)
execute_safe_jar_rollback() {
    local target_link="$1"
    local backup_link="$2"
    local instance_num="$3"

    log_info "Executing safe JAR rollback for instance $instance_num"

    # 사전 검증
    verify_rollback_prerequisites "$target_link" "$backup_link" "$instance_num"

    # 롤백 실행
    execute_jar_rollback "$target_link" "$backup_link" "$instance_num"

    # 사후 검증
    verify_rollback_success "$target_link" "$instance_num"

    log_success "Safe JAR rollback completed for instance $instance_num"
}

# 롤백 전제조건 검증 함수
verify_rollback_prerequisites() {
    local target_link="$1"
    local backup_link="$2"
    local instance_num="$3"

    log_info "Verifying rollback prerequisites"

    # 백업 파일 검증
    if [ ! -e "$backup_link" ]; then
        error_exit "Backup file not found: $backup_link"
    fi

    # 대상 디렉터리 쓰기 권한 확인
    local target_dir
    target_dir=$(dirname "$target_link")

    if [ ! -w "$target_dir" ]; then
        error_exit "No write permission for target directory: $target_dir"
    fi

    # 디스크 공간 확인 (백업 파일 크기만큼 여유 공간 필요)
    check_disk_space "$backup_link" "$target_dir"

    log_success "Rollback prerequisites verified"
}

# 디스크 공간 확인 함수
check_disk_space() {
    local backup_link="$1"
    local target_dir="$2"

    local backup_file="$backup_link"
    if [ -L "$backup_link" ]; then
        backup_file=$(readlink "$backup_link")
    fi

    local file_size
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null || echo "0")

    # 여유 공간 확인 (df 명령어 사용)
    local available_space
    if command -v df >/dev/null 2>&1; then
        available_space=$(df "$target_dir" | tail -1 | awk '{print $4}' || echo "0")
        # df 출력은 보통 KB 단위이므로 바이트로 변환
        available_space=$((available_space * 1024))

        if [ "$file_size" -gt "$available_space" ]; then
            log_warn "Low disk space: need $file_size bytes, available $available_space bytes"
        else
            log_info "Sufficient disk space available"
        fi
    else
        log_warn "Cannot check disk space (df command not available)"
    fi
}

# 롤백 성공 검증 함수
verify_rollback_success() {
    local target_link="$1"
    local instance_num="$2"

    log_info "Verifying rollback success"

    # 복원된 파일 존재 확인
    if [ ! -e "$target_link" ]; then
        error_exit "Rollback verification failed: restored file not found at $target_link"
    fi

    # 파일 읽기 가능 확인
    if [ ! -r "$target_link" ]; then
        error_exit "Rollback verification failed: restored file is not readable"
    fi

    # 파일 크기 확인 (0 바이트가 아닌지)
    local file_size
    file_size=$(stat -f%z "$target_link" 2>/dev/null || stat -c%s "$target_link" 2>/dev/null || echo "0")

    if [ "$file_size" -eq 0 ]; then
        error_exit "Rollback verification failed: restored file is empty"
    fi

    log_success "Rollback verification passed: file size $file_size bytes"
}

# 롤백 상태 확인 함수
show_rollback_status() {
    local target_link="$1"
    local backup_link="$2"
    local instance_num="$3"

    echo "=== Rollback Status for Instance $instance_num ==="
    echo "Target: $target_link"
    echo "Backup: $backup_link"
    echo ""

    # 현재 상태
    if [ -e "$target_link" ]; then
        echo "✅ Current JAR exists"
        if [ -L "$target_link" ]; then
            echo "   Type: Symbolic link → $(readlink "$target_link")"
        else
            echo "   Type: Regular file"
        fi
        echo "   Size: $(stat -f%z "$target_link" 2>/dev/null || stat -c%s "$target_link" 2>/dev/null || echo "Unknown") bytes"
    else
        echo "❌ Current JAR missing"
    fi

    # 백업 상태
    if [ -e "$backup_link" ]; then
        echo "✅ Backup available"
        if [ -L "$backup_link" ]; then
            echo "   Type: Symbolic link → $(readlink "$backup_link")"
        else
            echo "   Type: Regular file"
        fi
        echo "   Size: $(stat -f%z "$backup_link" 2>/dev/null || stat -c%s "$backup_link" 2>/dev/null || echo "Unknown") bytes"
    else
        echo "❌ Backup not available"
    fi

    # 롤백 가능 여부
    if [ -e "$backup_link" ]; then
        echo ""
        echo "🔄 Rollback: Ready"
    else
        echo ""
        echo "🚫 Rollback: Not possible (no backup)"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: execute_jar_rollback.sh <target_link> <backup_link> <instance_number> [safe|status]"
        echo "  (default): Execute JAR rollback"
        echo "  safe: Execute safe rollback with additional verification"
        echo "  status: Show rollback status"
        exit 1
    fi

    case "${4:-default}" in
        "safe")
            execute_safe_jar_rollback "$1" "$2" "$3"
            ;;
        "status")
            show_rollback_status "$1" "$2" "$3"
            ;;
        *)
            execute_jar_rollback "$1" "$2" "$3"
            ;;
    esac
fi