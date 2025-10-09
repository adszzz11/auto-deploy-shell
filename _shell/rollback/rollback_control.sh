#!/bin/bash
set -euo pipefail

# rollback_control.sh - Single Instance Rollback
#
# Layer: 3 (Core Operations)
# 역할: 단일 인스턴스 롤백 실행
# 호출자: multi_deploy_control.sh (Layer 2)
# 호출 대상: nginx, run_app (Layer 4)
#
# 책임:
#   - 단일 인스턴스의 이전 버전으로 복원
#   - 10단계 롤백 프로세스 실행
#   - 백업 파일 검증 및 복원
#   - Layer 4 서비스 모듈 오케스트레이션

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 모든 함수 스크립트들 source (func 디렉터리에서)
source "${SCRIPT_DIR}/func/validate_rollback.sh"
source "${SCRIPT_DIR}/func/execute_rollback.sh"

# 사용법 출력
print_usage() {
    cat << EOF
Usage: rollback_control.sh <command> [arguments]

Commands:
  rollback <instance_num> <env_file>      - Execute rollback for instance
  status <instance_num> <env_file>        - Check rollback status
  validate <instance_num> <env_file>      - Validate rollback prerequisites
  preview <instance_num> <env_file>       - Preview rollback operation

Environment variables (set in rollback.env):
  ROLLBACK_VERIFY_BACKUP             - Verify backup file (default: true)
  ROLLBACK_VERIFY_INTEGRITY          - Verify backup integrity (default: false)
  ROLLBACK_CHECK_DISK_SPACE          - Check disk space (default: true)
  ROLLBACK_CREATE_FAILED_BACKUP      - Create failed deployment backup (default: true)
  ROLLBACK_VERIFY_AFTER_RESTORE      - Verify after restore (default: true)
  ROLLBACK_FIX_PERMISSIONS           - Fix permissions (default: true)
  ROLLBACK_RESTART_APP               - Restart application (default: true)
  ROLLBACK_APP_MODE                  - Restart mode (default: restart)
  ROLLBACK_RESTART_TIMEOUT           - Restart timeout (default: 60s)
  ROLLBACK_HEALTH_CHECK              - Run health check (default: false)
  ROLLBACK_HEALTH_CHECK_TIMEOUT      - Health check timeout (default: 30s)
  ROLLBACK_NGINX_CONTROL             - Control nginx (default: true)
  ROLLBACK_NGINX_DOWN_BEFORE         - Nginx down before rollback (default: true)
  ROLLBACK_NGINX_UP_AFTER            - Nginx up after rollback (default: true)

Examples:
  # Rollback instance 0
  ./rollback_control.sh rollback 0 /path/to/env.env

  # Check rollback status
  ./rollback_control.sh status 0 /path/to/env.env

  # Validate before rollback
  ./rollback_control.sh validate 0 /path/to/env.env

  # Preview rollback operation
  ./rollback_control.sh preview 0 /path/to/env.env
EOF
}

# 환경 로드
load_environment() {
    local instance_num="$1"
    local env_file="$2"

    if [ ! -f "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
        return 1
    fi

    source "$env_file"

    # 필수 환경 변수 확인
    validate_required_env_vars

    # 롤백 변수 설정
    export PORT="${BASE_PORT}${instance_num}"
    export INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"
    export TARGET_LINK="${INSTANCE_DIR}/current.jar"
    export BACKUP_LINK="${TARGET_LINK}.bak"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Environment loaded: SERVICE=$SERVICE_NAME, PORT=$PORT"
    return 0
}

# 롤백 실행
execute_rollback() {
    local instance_num="$1"
    local env_file="$2"

    echo "=================================================="
    echo "Rollback for instance: $instance_num"
    echo "Using environment file: $env_file"
    echo "=================================================="

    # 1. 파라미터 검증
    validate_rollback_parameters "$instance_num" "$env_file"

    # 2. 환경 로드
    load_environment "$instance_num" "$env_file"

    # 3. 롤백 환경 검증
    validate_rollback_environment "$instance_num"

    # 4. 백업 파일 확인
    verify_backup_exists "$BACKUP_LINK" "$instance_num"

    # 5. 백업 무결성 검증 (옵션에 따라)
    verify_backup_integrity "$BACKUP_LINK" "$instance_num"

    # 6. 디스크 공간 확인 (옵션에 따라)
    check_disk_space "$BACKUP_LINK" "$INSTANCE_DIR"

    echo ""
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Initiating rollback for instance $instance_num on port $PORT"

    # 7. Nginx DOWN (옵션에 따라)
    if [ "${ROLLBACK_NGINX_DOWN_BEFORE:-true}" = "true" ]; then
        control_nginx_upstream "down" "$PORT" "${UPSTREAM_CONF:-}" "$SCRIPT_DIR"
    fi

    # 8. JAR 롤백 실행
    execute_jar_rollback "$TARGET_LINK" "$BACKUP_LINK" "$instance_num" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR rollback failed" >&2
        if [ "${ROLLBACK_NGINX_UP_AFTER:-true}" = "true" ]; then
            control_nginx_upstream "up" "$PORT" "${UPSTREAM_CONF:-}" "$SCRIPT_DIR"
        fi
        return 1
    }

    # 9. 애플리케이션 재시작 (옵션에 따라)
    restart_application "$INSTANCE_DIR" "$PORT" "${ROLLBACK_APP_MODE:-restart}" "${JAVA_OPTS:-}" "$SCRIPT_DIR" || {
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Application restart failed"
    }

    # 10. Nginx UP (옵션에 따라)
    if [ "${ROLLBACK_NGINX_UP_AFTER:-true}" = "true" ]; then
        control_nginx_upstream "up" "$PORT" "${UPSTREAM_CONF:-}" "$SCRIPT_DIR"
    fi

    echo ""
    echo "=================================================="
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Rollback completed for instance $instance_num"
    echo "=================================================="
    return 0
}

# 상태 확인
check_status() {
    local instance_num="$1"
    local env_file="$2"

    echo "=== Rollback Status ==="

    # 환경 로드
    load_environment "$instance_num" "$env_file"

    echo "Instance: $instance_num"
    echo "Service: $SERVICE_NAME"
    echo "Port: $PORT"
    echo "Instance Directory: $INSTANCE_DIR"
    echo ""

    echo "=== Current State ==="
    # 현재 JAR 상태
    if [ -e "$TARGET_LINK" ]; then
        echo "✅ Current JAR exists: $TARGET_LINK"
        if [ -L "$TARGET_LINK" ]; then
            echo "   Type: Symbolic link -> $(readlink "$TARGET_LINK")"
        else
            echo "   Type: Regular file"
        fi
        echo "   Size: $(stat -f%z "$TARGET_LINK" 2>/dev/null || stat -c%s "$TARGET_LINK" 2>/dev/null || echo "Unknown") bytes"
    else
        echo "❌ Current JAR not found: $TARGET_LINK"
    fi

    echo ""
    echo "=== Backup State ==="
    # 백업 상태
    if [ -e "$BACKUP_LINK" ]; then
        echo "✅ Backup available: $BACKUP_LINK"
        if [ -L "$BACKUP_LINK" ]; then
            echo "   Type: Symbolic link -> $(readlink "$BACKUP_LINK")"
        else
            echo "   Type: Regular file"
        fi
        echo "   Size: $(stat -f%z "$BACKUP_LINK" 2>/dev/null || stat -c%s "$BACKUP_LINK" 2>/dev/null || echo "Unknown") bytes"

        # 백업 가능 여부
        echo ""
        echo "🔄 Rollback: Ready"
    else
        echo "❌ Backup not available: $BACKUP_LINK"
        echo ""
        echo "🚫 Rollback: Not possible (no backup)"
    fi

    echo ""
    echo "=== Application State ==="
    # 프로세스 상태
    if pgrep -f "java -jar current.jar --server.port=${PORT}" > /dev/null; then
        echo "✅ Application is running on port $PORT"
    else
        echo "❌ Application is not running"
    fi
}

# 검증 실행
validate_rollback_cmd() {
    local instance_num="$1"
    local env_file="$2"

    echo "=== Rollback Validation ==="

    # 1. 파라미터 검증
    validate_rollback_parameters "$instance_num" "$env_file"
    echo "✅ Parameters validated"

    # 2. 환경 로드
    load_environment "$instance_num" "$env_file"
    echo "✅ Environment loaded"

    # 3. 롤백 환경 검증
    validate_rollback_environment "$instance_num"
    echo "✅ Rollback environment validated"

    # 4. 백업 확인
    verify_backup_exists "$BACKUP_LINK" "$instance_num"
    echo "✅ Backup file verified"

    # 5. 백업 무결성 (선택적)
    if [ "${ROLLBACK_VERIFY_INTEGRITY:-false}" = "true" ]; then
        verify_backup_integrity "$BACKUP_LINK" "$instance_num"
        echo "✅ Backup integrity verified"
    fi

    # 6. 디스크 공간
    check_disk_space "$BACKUP_LINK" "$INSTANCE_DIR"
    echo "✅ Disk space checked"

    # 7. run_app_control.sh 확인
    local run_app_script="${SCRIPT_DIR}/../run_app/run_app_control.sh"
    if [ -x "$run_app_script" ]; then
        echo "✅ run_app_control.sh found and executable"
    else
        echo "⚠️  run_app_control.sh not found (restart may fail)"
    fi

    # 8. nginx_control.sh 확인 (선택적)
    if [ "${ROLLBACK_NGINX_CONTROL:-true}" = "true" ]; then
        local nginx_script="${SCRIPT_DIR}/../nginx/nginx_control.sh"
        if [ -x "$nginx_script" ]; then
            echo "✅ nginx_control.sh found and executable"
        else
            echo "⚠️  nginx_control.sh not found (nginx control will be skipped)"
        fi
    fi

    echo ""
    echo "✅ All validations passed"
    echo "Ready to execute rollback for instance $instance_num"
}

# 롤백 미리보기
preview_rollback() {
    local instance_num="$1"
    local env_file="$2"

    echo "=== Rollback Preview ==="

    # 환경 로드
    load_environment "$instance_num" "$env_file"

    echo "Instance: $instance_num"
    echo "Service: $SERVICE_NAME"
    echo "Port: $PORT"
    echo ""

    echo "=== Rollback Steps ==="
    echo "1. Validate parameters and environment"
    echo "2. Verify backup file: $BACKUP_LINK"

    if [ "${ROLLBACK_NGINX_DOWN_BEFORE:-true}" = "true" ]; then
        echo "3. Nginx DOWN for port $PORT"
    fi

    if [ "${ROLLBACK_CREATE_FAILED_BACKUP:-true}" = "true" ]; then
        echo "4. Create failed deployment backup"
    fi

    echo "5. Remove current JAR: $TARGET_LINK"
    echo "6. Restore from backup: $BACKUP_LINK -> $TARGET_LINK"

    if [ "${ROLLBACK_VERIFY_AFTER_RESTORE:-true}" = "true" ]; then
        echo "7. Verify restored JAR"
    fi

    if [ "${ROLLBACK_RESTART_APP:-true}" = "true" ]; then
        echo "8. Restart application on port $PORT (mode: ${ROLLBACK_APP_MODE:-restart})"
    fi

    if [ "${ROLLBACK_NGINX_UP_AFTER:-true}" = "true" ]; then
        echo "9. Nginx UP for port $PORT"
    fi

    echo ""

    # 백업 파일 상세 정보
    if [ -e "$BACKUP_LINK" ]; then
        echo "=== Backup File Details ==="
        echo "Path: $BACKUP_LINK"

        if [ -L "$BACKUP_LINK" ]; then
            echo "Type: Symbolic link -> $(readlink "$BACKUP_LINK")"
        else
            echo "Type: Regular file"
        fi

        echo "Size: $(stat -f%z "$BACKUP_LINK" 2>/dev/null || stat -c%s "$BACKUP_LINK" 2>/dev/null || echo "Unknown") bytes"
        echo "Modified: $(stat -f%Sm "$BACKUP_LINK" 2>/dev/null || stat -c%y "$BACKUP_LINK" 2>/dev/null || echo "Unknown")"
        echo ""
        echo "✅ Rollback is ready to execute"
    else
        echo "❌ Backup file not found: $BACKUP_LINK"
        echo "🚫 Rollback not possible"
        return 1
    fi
}

# 메인 진입점
main() {
    if [ "$#" -lt 1 ]; then
        print_usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        rollback)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'rollback' requires <instance_num> <env_file>"
                exit 1
            fi
            execute_rollback "$@"
            ;;
        status)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'status' requires <instance_num> <env_file>"
                exit 1
            fi
            check_status "$@"
            ;;
        validate)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'validate' requires <instance_num> <env_file>"
                exit 1
            fi
            validate_rollback_cmd "$@"
            ;;
        preview)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'preview' requires <instance_num> <env_file>"
                exit 1
            fi
            preview_rollback "$@"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
