#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SCRIPT_DIR

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_rollback_parameters.sh"
source "${SCRIPT_DIR}/load_rollback_environment.sh"
source "${SCRIPT_DIR}/verify_backup_availability.sh"
source "${SCRIPT_DIR}/execute_jar_rollback.sh"
source "${SCRIPT_DIR}/restart_after_rollback.sh"

# 메인 롤백 함수
rollback_main() {
    # 사용법: rollback_main <instance_number> <env_file>
    if [ "$#" -ne 2 ]; then
        echo "Usage: rollback_main <instance_number> <env_file>"
        exit 1
    fi

    local instance_num="$1"
    local env_file="$2"

    # 1. 파라미터 검증
    validate_rollback_parameters "$instance_num" "$env_file"

    # 2. 환경 설정 로드
    load_rollback_environment "$instance_num" "$env_file"

    # 3. 환경 변수 검증
    verify_rollback_environment "$instance_num"

    # 4. 백업 파일 가용성 확인
    verify_backup_availability "$BACKUP_LINK" "$instance_num"

    # 롤백 시작 로그
    local rollback_start_time
    rollback_start_time=$(current_timestamp)
    log_info "Initiating rollback for instance $instance_num on port $PORT"
    audit_log "ROLLBACK_START" "instance=$instance_num port=$PORT"

    # 5. JAR 파일 롤백 실행
    execute_jar_rollback "$TARGET_LINK" "$BACKUP_LINK" "$instance_num"

    # 6. 애플리케이션 재시작
    restart_after_rollback "$INSTANCE_DIR" "$PORT" "$APP_MODE" "${JAVA_OPTS:-}" "$SCRIPT_DIR" "$instance_num"

    # 롤백 완료 로그
    local rollback_end_time
    rollback_end_time=$(current_timestamp)
    local duration=$((rollback_end_time - rollback_start_time))

    log_success "Rollback completed for instance $instance_num in ${duration}s"
    audit_log "ROLLBACK_SUCCESS" "instance=$instance_num port=$PORT duration=${duration}s"
}

# 안전한 롤백 함수 (추가 검증 포함)
rollback_safe() {
    local instance_num="$1"
    local env_file="$2"

    log_info "Starting safe rollback for instance $instance_num"

    # 기본 파라미터 및 환경 검증
    validate_rollback_parameters "$instance_num" "$env_file"
    load_rollback_environment "$instance_num" "$env_file"
    verify_rollback_environment "$instance_num"

    # 백업 무결성 검증
    verify_backup_integrity "$BACKUP_LINK" "$instance_num"

    local rollback_start_time
    rollback_start_time=$(current_timestamp)
    audit_log "SAFE_ROLLBACK_START" "instance=$instance_num port=$PORT"

    # 안전한 JAR 롤백 실행
    execute_safe_jar_rollback "$TARGET_LINK" "$BACKUP_LINK" "$instance_num"

    # 스마트 재시작 (여러 방법 시도)
    smart_restart_after_rollback "$INSTANCE_DIR" "$PORT" "$APP_MODE" "${JAVA_OPTS:-}" "$SCRIPT_DIR" "$instance_num"

    # 롤백 후 헬스체크
    if [ "${ENABLE_POST_ROLLBACK_HEALTH_CHECK:-true}" = "true" ]; then
        verify_restart_health "$PORT" "$instance_num" "${HEALTH_CHECK_TIMEOUT:-30}"
    fi

    local rollback_end_time
    rollback_end_time=$(current_timestamp)
    local duration=$((rollback_end_time - rollback_start_time))

    log_success "Safe rollback completed for instance $instance_num in ${duration}s"
    audit_log "SAFE_ROLLBACK_SUCCESS" "instance=$instance_num port=$PORT duration=${duration}s"
}

# 롤백 상태 확인 함수
check_rollback_status() {
    local instance_num="$1"
    local env_file="$2"

    echo "=== Rollback Status ===="

    # 환경 로드
    load_rollback_environment "$instance_num" "$env_file"

    echo "Instance: $instance_num"
    echo "Service: $SERVICE_NAME"
    echo "Port: $PORT"
    echo "Instance Directory: $INSTANCE_DIR"
    echo ""

    # 환경 상태 표시
    show_rollback_environment "$instance_num"

    echo ""

    # JAR 롤백 상태
    show_rollback_status "$TARGET_LINK" "$BACKUP_LINK" "$instance_num"

    echo ""

    # 재시작 상태
    show_restart_status "$PORT" "$instance_num" "$INSTANCE_DIR"
}

# 롤백 검증 함수
verify_rollback() {
    local instance_num="$1"
    local env_file="$2"

    echo "=== Rollback Verification ===="

    # 1. 파라미터 검증
    validate_rollback_parameters "$instance_num" "$env_file"
    echo "✅ Parameters validated"

    # 2. 환경 로드 및 검증
    load_rollback_environment "$instance_num" "$env_file"
    verify_rollback_environment "$instance_num"
    echo "✅ Environment verified"

    # 3. 백업 가용성 및 무결성 확인
    verify_backup_availability "$BACKUP_LINK" "$instance_num"
    echo "✅ Backup availability verified"

    # 4. 백업 무결성 검증
    verify_backup_integrity "$BACKUP_LINK" "$instance_num"
    echo "✅ Backup integrity verified"

    # 5. 롤백 전제조건 확인
    verify_rollback_prerequisites "$TARGET_LINK" "$BACKUP_LINK" "$instance_num"
    echo "✅ Rollback prerequisites verified"

    # 6. runApp.sh 확인
    local runapp_script="${INSTANCE_DIR}/runApp.sh"
    if [ -f "$runapp_script" ]; then
        if [ -x "$runapp_script" ]; then
            echo "✅ runApp.sh exists and is executable"
        else
            echo "⚠️  runApp.sh exists but is not executable"
        fi
    else
        echo "⚠️  runApp.sh not found (will use fallback)"
    fi

    echo ""
    echo "✅ Rollback verification completed successfully"
    echo "Ready to execute rollback for instance $instance_num"
}

# 롤백 미리보기 함수
preview_rollback() {
    local instance_num="$1"
    local env_file="$2"

    echo "=== Rollback Preview ===="

    # 환경 로드
    load_rollback_environment "$instance_num" "$env_file"

    echo "Instance: $instance_num"
    echo "Service: $SERVICE_NAME"
    echo "Port: $PORT"
    echo ""

    echo "=== What will happen ==="
    echo "1. Validate parameters and environment"
    echo "2. Verify backup file availability: $BACKUP_LINK"
    echo "3. Remove current JAR: $TARGET_LINK"
    echo "4. Restore from backup: $BACKUP_LINK → $TARGET_LINK"
    echo "5. Restart application on port $PORT"
    echo ""

    # 백업 파일 상세 정보
    if [ -e "$BACKUP_LINK" ]; then
        show_backup_details "$BACKUP_LINK" "$instance_num"
    else
        echo "❌ Backup file not found: $BACKUP_LINK"
        echo "🚫 Rollback not possible"
        return 1
    fi

    echo ""
    echo "✅ Rollback is ready to execute"
}

# 응급 롤백 함수 (최소 검증으로 빠른 롤백)
emergency_rollback() {
    local instance_num="$1"
    local env_file="$2"

    log_warn "Starting EMERGENCY rollback for instance $instance_num"

    # 최소 검증만 수행
    if [ "$#" -ne 2 ]; then
        error_exit "Usage: emergency_rollback <instance_number> <env_file>"
    fi

    if [ ! -f "$env_file" ]; then
        error_exit "Environment file not found: $env_file"
    fi

    source "$env_file"

    # 필수 변수만 확인
    if [ -z "${SERVICE_BASE_DIR:-}" ] || [ -z "${SERVICE_NAME:-}" ] || [ -z "${BASE_PORT:-}" ]; then
        error_exit "Required environment variables missing"
    fi

    # 변수 설정
    export PORT="${BASE_PORT}${instance_num}"
    export INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"
    export TARGET_LINK="${INSTANCE_DIR}/current.jar"
    export BACKUP_LINK="${TARGET_LINK}.bak"

    local emergency_start_time
    emergency_start_time=$(current_timestamp)
    audit_log "EMERGENCY_ROLLBACK_START" "instance=$instance_num port=$PORT"

    # 백업 존재 확인 (최소)
    if [ ! -e "$BACKUP_LINK" ]; then
        error_exit "EMERGENCY: No backup found at $BACKUP_LINK"
    fi

    # 즉시 롤백 실행
    log_warn "EMERGENCY: Removing current JAR"
    rm -f "$TARGET_LINK"

    log_warn "EMERGENCY: Restoring from backup"
    mv "$BACKUP_LINK" "$TARGET_LINK"

    # 애플리케이션 재시작 시도
    local runapp_script="${INSTANCE_DIR}/runApp.sh"
    if [ -f "$runapp_script" ]; then
        log_warn "EMERGENCY: Restarting application"
        (cd "$INSTANCE_DIR" && "$runapp_script" "$PORT" "${APP_MODE:-restart}" "${JAVA_OPTS:-}" "$SCRIPT_DIR") || log_error "EMERGENCY: Restart failed"
    else
        log_warn "EMERGENCY: runApp.sh not found, manual restart required"
    fi

    local emergency_end_time
    emergency_end_time=$(current_timestamp)
    local duration=$((emergency_end_time - emergency_start_time))

    log_warn "EMERGENCY rollback completed for instance $instance_num in ${duration}s"
    audit_log "EMERGENCY_ROLLBACK_COMPLETE" "instance=$instance_num port=$PORT duration=${duration}s"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${3:-main}" in
        "main")
            rollback_main "$1" "$2"
            ;;
        "safe")
            rollback_safe "$1" "$2"
            ;;
        "status")
            check_rollback_status "$1" "$2"
            ;;
        "verify")
            verify_rollback "$1" "$2"
            ;;
        "preview")
            preview_rollback "$1" "$2"
            ;;
        "emergency")
            emergency_rollback "$1" "$2"
            ;;
        *)
            echo "Usage: rollback_main.sh <instance_number> <env_file> [main|safe|status|verify|preview|emergency]"
            echo ""
            echo "Modes:"
            echo "  main: Standard rollback (default)"
            echo "  safe: Safe rollback with additional verification"
            echo "  status: Check rollback status"
            echo "  verify: Verify rollback prerequisites"
            echo "  preview: Preview rollback operation"
            echo "  emergency: Emergency rollback with minimal checks"
            echo ""
            echo "Examples:"
            echo "  rollback_main.sh 0 production.env"
            echo "  rollback_main.sh 0 production.env safe"
            echo "  rollback_main.sh 0 production.env status"
            exit 1
            ;;
    esac
fi