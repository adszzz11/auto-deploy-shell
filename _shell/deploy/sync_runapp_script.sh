#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# runApp.sh 동기화 함수
sync_runapp_script() {
    local script_dir="$1"
    local instance_dir="$2"

    local runapp_src="${script_dir}/runApp.sh"
    local runapp_dest="${instance_dir}/runApp.sh"

    log_info "Synchronizing runApp.sh to instance directory"

    # 소스 파일 존재 확인
    if [ ! -f "$runapp_src" ]; then
        error_exit "Source runApp.sh not found: $runapp_src"
    fi

    # 대상 디렉터리 존재 확인
    if [ ! -d "$instance_dir" ]; then
        error_exit "Instance directory not found: $instance_dir"
    fi

    # 기존 파일이 있는 경우 비교
    if [ -f "$runapp_dest" ]; then
        if cmp -s "$runapp_src" "$runapp_dest"; then
            log_info "runApp.sh in ${instance_dir} is already up-to-date"
            return 0
        else
            log_info "Existing runApp.sh in ${instance_dir} is outdated. Updating..."

            # 기존 파일 백업
            local backup_path="${runapp_dest}.bak"
            if mv "$runapp_dest" "$backup_path"; then
                log_info "Backup created: $backup_path"
            else
                error_exit "Failed to backup existing runApp.sh"
            fi
        fi
    else
        log_info "Copying runApp.sh to ${instance_dir}..."
    fi

    # 새 파일 복사
    if cp "$runapp_src" "$runapp_dest"; then
        log_success "runApp.sh copied successfully"
    else
        error_exit "runApp.sh copy failed"
    fi

    # 실행 권한 설정
    if chmod +x "$runapp_dest"; then
        log_success "Execute permission set for runApp.sh"
    else
        error_exit "Failed to set execute permission for runApp.sh"
    fi

    log_success "runApp.sh synchronization completed"
}

# runApp.sh 검증 함수
verify_runapp_script() {
    local instance_dir="$1"
    local runapp_dest="${instance_dir}/runApp.sh"

    log_info "Verifying runApp.sh in instance directory"

    # 파일 존재 확인
    if [ ! -f "$runapp_dest" ]; then
        error_exit "runApp.sh not found in instance directory: $runapp_dest"
    fi

    # 실행 권한 확인
    if [ ! -x "$runapp_dest" ]; then
        error_exit "runApp.sh is not executable: $runapp_dest"
    fi

    # 기본 문법 확인 (선택적)
    if bash -n "$runapp_dest"; then
        log_success "runApp.sh syntax is valid"
    else
        error_exit "runApp.sh syntax error detected"
    fi

    log_success "runApp.sh verification completed"
}

# runApp.sh 복원 함수
restore_runapp_script() {
    local instance_dir="$1"
    local runapp_dest="${instance_dir}/runApp.sh"
    local backup_path="${runapp_dest}.bak"

    log_info "Restoring runApp.sh from backup"

    if [ ! -f "$backup_path" ]; then
        error_exit "Backup file not found: $backup_path"
    fi

    if mv "$backup_path" "$runapp_dest"; then
        log_success "runApp.sh restored from backup"
    else
        error_exit "Failed to restore runApp.sh from backup"
    fi
}

# runApp.sh 상태 확인 함수
check_runapp_status() {
    local script_dir="$1"
    local instance_dir="$2"

    local runapp_src="${script_dir}/runApp.sh"
    local runapp_dest="${instance_dir}/runApp.sh"

    echo "=== runApp.sh Status ==="
    echo "Source: $runapp_src"
    echo "Destination: $runapp_dest"

    # 소스 파일 상태
    if [ -f "$runapp_src" ]; then
        echo "✅ Source file exists"
        if [ -x "$runapp_src" ]; then
            echo "✅ Source file is executable"
        else
            echo "❌ Source file is not executable"
        fi
    else
        echo "❌ Source file missing"
        return 1
    fi

    # 대상 파일 상태
    if [ -f "$runapp_dest" ]; then
        echo "✅ Destination file exists"
        if [ -x "$runapp_dest" ]; then
            echo "✅ Destination file is executable"
        else
            echo "❌ Destination file is not executable"
        fi

        # 파일 비교
        if cmp -s "$runapp_src" "$runapp_dest"; then
            echo "✅ Files are identical (up-to-date)"
        else
            echo "⚠️  Files differ (update needed)"
        fi
    else
        echo "ℹ️  Destination file missing (needs copy)"
    fi

    # 백업 파일 상태
    local backup_path="${runapp_dest}.bak"
    if [ -f "$backup_path" ]; then
        echo "ℹ️  Backup file exists: $(basename "$backup_path")"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: sync_runapp_script.sh <script_dir> <instance_dir> [sync|verify|restore|status]"
        echo "  sync: Synchronize runApp.sh (default)"
        echo "  verify: Verify runApp.sh in instance directory"
        echo "  restore: Restore runApp.sh from backup"
        echo "  status: Check runApp.sh status"
        exit 1
    fi

    case "${3:-sync}" in
        "verify")
            verify_runapp_script "$2"
            ;;
        "restore")
            restore_runapp_script "$2"
            ;;
        "status")
            check_runapp_status "$1" "$2"
            ;;
        *)
            sync_runapp_script "$1" "$2"
            ;;
    esac
fi