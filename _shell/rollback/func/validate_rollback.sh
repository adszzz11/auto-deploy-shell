#!/bin/bash
set -euo pipefail


# 롤백 파라미터 검증
validate_rollback_parameters() {
    local instance_num="$1"
    local env_file="$2"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Validating rollback parameters"

    # 인스턴스 번호 검증
    if ! [[ "$instance_num" =~ ^[0-9]$ ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid instance number: $instance_num (must be 0-9)" >&2
        return 1
    fi

    # 환경 파일 존재 확인
    if [ ! -f "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
        return 1
    fi

    # 환경 파일 읽기 권한 확인
    if [ ! -r "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not readable: $env_file" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Parameters validated: instance=$instance_num"
    return 0
}

# 필수 환경 변수 검증
validate_required_env_vars() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Validating required environment variables"

    local missing_vars=()
    [ -z "${SERVICE_NAME:-}" ] && missing_vars+=("SERVICE_NAME")
    [ -z "${SERVICE_BASE_DIR:-}" ] && missing_vars+=("SERVICE_BASE_DIR")
    [ -z "${BASE_PORT:-}" ] && missing_vars+=("BASE_PORT")

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Missing required environment variables: ${missing_vars[*]}" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - All required environment variables present"
    return 0
}

# 롤백 환경 검증
validate_rollback_environment() {
    local instance_num="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Validating rollback environment for instance $instance_num"

    # 인스턴스 디렉터리 존재 확인
    if [ ! -d "$INSTANCE_DIR" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Instance directory not found: $INSTANCE_DIR" >&2
        return 1
    fi

    # 인스턴스 디렉터리 쓰기 권한 확인
    if [ ! -w "$INSTANCE_DIR" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Instance directory not writable: $INSTANCE_DIR" >&2
        return 1
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Rollback environment validated"
    return 0
}

# 백업 파일 존재 확인
verify_backup_exists() {
    local backup_link="$1"
    local instance_num="$2"
    local verify_enabled="${3:-${ROLLBACK_VERIFY_BACKUP:-true}}"

    if [ "$verify_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backup verification disabled"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Verifying backup for instance $instance_num"

    if [ ! -e "$backup_link" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - No backup found for instance $instance_num at: $backup_link" >&2
        return 1
    fi

    # 백업 파일 읽기 권한 확인
    if [ ! -r "$backup_link" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Backup file not readable: $backup_link" >&2
        return 1
    fi

    # 심볼릭 링크인 경우 타겟 확인
    if [ -L "$backup_link" ]; then
        local backup_target=$(readlink "$backup_link")
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backup is a symbolic link: $backup_link -> $backup_target"

        if [ ! -f "$backup_target" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Backup link target not found: $backup_target" >&2
            return 1
        fi
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Backup verified"
    return 0
}

# 백업 무결성 검증
verify_backup_integrity() {
    local backup_link="$1"
    local instance_num="$2"
    local verify_enabled="${3:-${ROLLBACK_VERIFY_INTEGRITY:-false}}"

    if [ "$verify_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backup integrity verification disabled"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Verifying backup integrity for instance $instance_num"

    local backup_file="$backup_link"
    if [ -L "$backup_link" ]; then
        backup_file=$(readlink "$backup_link")
    fi

    # 파일 크기 확인
    local file_size
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null || echo "0")

    if [ "$file_size" -eq 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Backup file is empty: $backup_file" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backup file size: $file_size bytes"

    # JAR 파일 구조 검증 (unzip 사용 가능한 경우)
    if command -v unzip >/dev/null 2>&1; then
        if unzip -t "$backup_file" >/dev/null 2>&1; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Backup JAR structure is valid"
        else
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Backup JAR structure may be corrupted"
        fi
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Backup integrity verified"
    return 0
}

# 디스크 공간 확인
check_disk_space() {
    local backup_link="$1"
    local target_dir="$2"
    local check_enabled="${3:-${ROLLBACK_CHECK_DISK_SPACE:-true}}"

    if [ "$check_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Disk space check disabled"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Checking disk space"

    local backup_file="$backup_link"
    if [ -L "$backup_link" ]; then
        backup_file=$(readlink "$backup_link")
    fi

    local file_size
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null || echo "0")

    # df 명령어로 여유 공간 확인
    if command -v df >/dev/null 2>&1; then
        local available_space
        available_space=$(df "$target_dir" | tail -1 | awk '{print $4}')
        available_space=$((available_space * 1024))

        if [ "$file_size" -gt "$available_space" ]; then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Low disk space: need $file_size bytes, available $available_space bytes"
        else
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Sufficient disk space available"
        fi
    fi

    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: validate_rollback.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  params <instance_num> <env_file>                 - Validate rollback parameters"
        echo "  env                                               - Validate required environment variables"
        echo "  environment <instance_num>                        - Validate rollback environment"
        echo "  backup <backup_link> <instance_num>               - Verify backup exists"
        echo "  integrity <backup_link> <instance_num>            - Verify backup integrity"
        echo "  disk <backup_link> <target_dir>                   - Check disk space"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        params)
            validate_rollback_parameters "$@"
            ;;
        env)
            validate_required_env_vars
            ;;
        environment)
            validate_rollback_environment "$@"
            ;;
        backup)
            verify_backup_exists "$@"
            ;;
        integrity)
            verify_backup_integrity "$@"
            ;;
        disk)
            check_disk_space "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
