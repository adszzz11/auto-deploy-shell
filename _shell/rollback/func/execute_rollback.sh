#!/bin/bash
set -euo pipefail


# JAR 롤백 실행
execute_jar_rollback() {
    local target_link="$1"
    local backup_link="$2"
    local instance_num="$3"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Executing JAR rollback for instance $instance_num"

    # 백업 파일 재확인
    if [ ! -e "$backup_link" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Backup file not found during rollback: $backup_link" >&2
        return 1
    fi

    # 실패한 배포 백업 생성 (옵션에 따라)
    create_failed_deployment_backup "$target_link" "$instance_num"

    # 현재 JAR 제거
    remove_current_jar "$target_link" "$instance_num"

    # 백업에서 복원
    restore_from_backup "$backup_link" "$target_link" "$instance_num"

    # 복원 후 검증 (옵션에 따라)
    verify_after_restore "$target_link" "$instance_num"

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - JAR rollback completed for instance $instance_num"
    return 0
}

# 실패한 배포 백업 생성
create_failed_deployment_backup() {
    local target_link="$1"
    local instance_num="$2"
    local create_backup="${3:-${ROLLBACK_CREATE_FAILED_BACKUP:-true}}"

    if [ "$create_backup" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Failed deployment backup disabled"
        return 0
    fi

    if [ -e "$target_link" ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local failed_backup="${target_link}.failed.${timestamp}"

        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Creating backup of failed deployment: $failed_backup"

        if cp -L "$target_link" "$failed_backup" 2>/dev/null; then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Failed deployment backed up to: $failed_backup"
        else
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to backup current deployment (proceeding with rollback)"
        fi
    else
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No current JAR to backup"
    fi

    return 0
}

# 현재 JAR 제거
remove_current_jar() {
    local target_link="$1"
    local instance_num="$2"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Removing current JAR: $target_link"

    if [ -e "$target_link" ]; then
        if rm -f "$target_link"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Current JAR removed successfully"
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to remove current JAR: $target_link" >&2
            return 1
        fi
    else
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Current JAR does not exist (nothing to remove)"
    fi

    return 0
}

# 백업에서 복원
restore_from_backup() {
    local backup_link="$1"
    local target_link="$2"
    local instance_num="$3"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Restoring from backup: $backup_link -> $target_link"

    # 심볼릭 링크인 경우
    if [ -L "$backup_link" ]; then
        local backup_target=$(readlink "$backup_link")
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backup is a symbolic link, creating new link to: $backup_target"

        if ln -s "$backup_target" "$target_link"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Symbolic link restored successfully"
            rm -f "$backup_link"
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to restore symbolic link" >&2
            return 1
        fi
    else
        # 일반 파일인 경우
        if mv "$backup_link" "$target_link"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - JAR file restored successfully"
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to restore JAR file" >&2
            return 1
        fi
    fi

    # 권한 수정 (옵션에 따라)
    fix_restored_permissions "$target_link"

    return 0
}

# 복원된 파일 권한 수정
fix_restored_permissions() {
    local target_link="$1"
    local fix_permissions="${2:-${ROLLBACK_FIX_PERMISSIONS:-true}}"

    if [ "$fix_permissions" != "true" ]; then
        return 0
    fi

    if [ ! -r "$target_link" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Restored JAR not readable, fixing permissions"
        chmod 644 "$target_link" 2>/dev/null || {
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to fix permissions"
        }
    fi

    return 0
}

# 복원 후 검증
verify_after_restore() {
    local target_link="$1"
    local instance_num="$2"
    local verify_enabled="${3:-${ROLLBACK_VERIFY_AFTER_RESTORE:-true}}"

    if [ "$verify_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Post-restore verification disabled"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Verifying restored JAR"

    # 파일 존재 확인
    if [ ! -e "$target_link" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Restored file not found: $target_link" >&2
        return 1
    fi

    # 읽기 권한 확인
    if [ ! -r "$target_link" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Restored file not readable: $target_link" >&2
        return 1
    fi

    # 파일 크기 확인
    local file_size
    file_size=$(stat -f%z "$target_link" 2>/dev/null || stat -c%s "$target_link" 2>/dev/null || echo "0")

    if [ "$file_size" -eq 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Restored file is empty" >&2
        return 1
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Restored JAR verified (size: $file_size bytes)"
    return 0
}

# 애플리케이션 재시작
restart_application() {
    local instance_dir="$1"
    local port="$2"
    local app_mode="${3:-${ROLLBACK_APP_MODE:-restart}}"
    local java_opts="${4:-}"
    local script_dir="${5:-}"
    local restart_enabled="${6:-${ROLLBACK_RESTART_APP:-true}}"

    if [ "$restart_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Application restart disabled"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Restarting application on port $port"

    local run_app_script="${script_dir}/../run_app/run_app_control.sh"

    if [ ! -x "$run_app_script" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - run_app_control.sh not found: $run_app_script"
        return 0
    fi

    (
        cd "$instance_dir" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to change to instance directory" >&2
            return 1
        }

        "$run_app_script" "$app_mode" "$port" "$java_opts" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to restart application" >&2
            return 1
        }
    ) || return 1

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Application restarted successfully"
    return 0
}

# Nginx 업스트림 제어
control_nginx_upstream() {
    local action="$1"  # up or down
    local port="$2"
    local upstream_conf="$3"
    local script_dir="$4"
    local nginx_control="${5:-${ROLLBACK_NGINX_CONTROL:-true}}"

    if [ "$nginx_control" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Nginx control disabled"
        return 0
    fi

    local nginx_script="${script_dir}/../nginx/nginx_control.sh"

    if [ ! -x "$nginx_script" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - nginx_control.sh not found: $nginx_script"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Setting nginx upstream $action for port $port"

    "$nginx_script" "$action" "$port" "$upstream_conf" || {
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to set nginx upstream $action"
        return 0
    }

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Nginx upstream $action completed"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: execute_rollback.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  rollback <target_link> <backup_link> <instance_num>               - Execute JAR rollback"
        echo "  restart <instance_dir> <port> <app_mode> [java_opts] <script_dir> - Restart application"
        echo "  nginx <action> <port> <upstream_conf> <script_dir>                 - Control nginx upstream"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        rollback)
            execute_jar_rollback "$@"
            ;;
        restart)
            restart_application "$@"
            ;;
        nginx)
            control_nginx_upstream "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
