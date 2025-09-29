#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 롤백 환경 설정 로드 함수
load_rollback_environment() {
    local instance_num="$1"
    local env_file="$2"

    log_info "Loading rollback environment for instance $instance_num"

    # 환경 파일 로드
    source "$env_file"

    # 필수 환경 변수 확인
    local missing_vars=()
    [ -z "${BASE_PORT:-}" ] && missing_vars+=("BASE_PORT")
    [ -z "${SERVICE_BASE_DIR:-}" ] && missing_vars+=("SERVICE_BASE_DIR")
    [ -z "${SERVICE_NAME:-}" ] && missing_vars+=("SERVICE_NAME")
    [ -z "${APP_MODE:-}" ] && missing_vars+=("APP_MODE")

    if [ ${#missing_vars[@]} -gt 0 ]; then
        error_exit "Missing required environment variables: ${missing_vars[*]}"
    fi

    # 롤백 관련 변수 설정
    export PORT="${BASE_PORT}${instance_num}"
    export INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"
    export TARGET_LINK="${INSTANCE_DIR}/current.jar"
    export BACKUP_LINK="${TARGET_LINK}.bak"

    log_info "Rollback environment loaded:"
    log_info "  Service: $SERVICE_NAME"
    log_info "  Instance: $instance_num"
    log_info "  Port: $PORT"
    log_info "  Instance Dir: $INSTANCE_DIR"
    log_info "  Target Link: $TARGET_LINK"
    log_info "  Backup Link: $BACKUP_LINK"
}

# 롤백 환경 변수 검증 함수
verify_rollback_environment() {
    local instance_num="$1"

    log_info "Verifying rollback environment for instance $instance_num"

    # 인스턴스 디렉터리 존재 확인
    if [ ! -d "$INSTANCE_DIR" ]; then
        error_exit "Instance directory not found: $INSTANCE_DIR"
    fi

    # 인스턴스 디렉터리 접근 권한 확인
    if [ ! -r "$INSTANCE_DIR" ] || [ ! -w "$INSTANCE_DIR" ]; then
        error_exit "Insufficient permissions for instance directory: $INSTANCE_DIR"
    fi

    # 포트 번호 유효성 확인
    if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        error_exit "Invalid port number: $PORT"
    fi

    log_success "Rollback environment verification completed"
}

# 롤백 환경 상태 출력 함수
show_rollback_environment() {
    local instance_num="$1"

    echo "=== Rollback Environment Status ==="
    echo "Instance: $instance_num"
    echo "Service: ${SERVICE_NAME:-N/A}"
    echo "Port: ${PORT:-N/A}"
    echo "Instance Directory: ${INSTANCE_DIR:-N/A}"
    echo "Target Link: ${TARGET_LINK:-N/A}"
    echo "Backup Link: ${BACKUP_LINK:-N/A}"
    echo ""

    # 디렉터리 상태 확인
    if [ -d "${INSTANCE_DIR:-}" ]; then
        echo "✅ Instance directory exists"
    else
        echo "❌ Instance directory missing"
    fi

    # 현재 JAR 파일 상태
    if [ -L "${TARGET_LINK:-}" ]; then
        echo "✅ Current JAR link exists: $(readlink "$TARGET_LINK")"
    elif [ -f "${TARGET_LINK:-}" ]; then
        echo "⚠️  Current JAR file exists (not a link)"
    else
        echo "❌ Current JAR not found"
    fi

    # 백업 파일 상태
    if [ -L "${BACKUP_LINK:-}" ]; then
        echo "✅ Backup JAR link exists: $(readlink "$BACKUP_LINK")"
    elif [ -f "${BACKUP_LINK:-}" ]; then
        echo "✅ Backup JAR file exists"
    else
        echo "❌ Backup JAR not found"
    fi

    # runApp.sh 상태
    if [ -f "${INSTANCE_DIR:-}/runApp.sh" ]; then
        echo "✅ runApp.sh exists in instance directory"
    else
        echo "⚠️  runApp.sh not found in instance directory"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: load_rollback_environment.sh <instance_number> <env_file> [show|verify]"
        echo "  (default): Load environment"
        echo "  show: Show environment status"
        echo "  verify: Verify environment"
        exit 1
    fi

    case "${3:-default}" in
        "show")
            load_rollback_environment "$1" "$2"
            show_rollback_environment "$1"
            ;;
        "verify")
            load_rollback_environment "$1" "$2"
            verify_rollback_environment "$1"
            ;;
        *)
            load_rollback_environment "$1" "$2"
            ;;
    esac
fi