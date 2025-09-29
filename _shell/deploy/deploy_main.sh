#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SCRIPT_DIR

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_deploy_parameters.sh"
source "${SCRIPT_DIR}/validate_required_scripts.sh"
source "${SCRIPT_DIR}/load_environment.sh"
source "${SCRIPT_DIR}/prepare_deploy_environment.sh"
source "${SCRIPT_DIR}/sync_runapp_script.sh"
source "${SCRIPT_DIR}/execute_deployment.sh"
source "${SCRIPT_DIR}/handle_instance_removal.sh"

# 메인 배포 함수
deploy_main() {
    # 사용법: deploy_main <instance_number> <env_file> <action>
    if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
        echo "Usage: deploy_main <instance_number> <env_file> [deploy|remove]"
        exit 1
    fi

    local instance_num="$1"
    local env_file="$2"
    local action="${3:-deploy}"

    # 1. 파라미터 검증
    validate_deploy_parameters "$instance_num" "$env_file" "$action"

    # 2. 필수 스크립트 검증
    validate_required_scripts "$SCRIPT_DIR"

    # 3. 환경 로드 및 검증
    load_and_validate_environment "$env_file" "$instance_num"

    # 액션에 따른 실행
    case "$action" in
        "deploy")
            execute_deploy_action "$instance_num"
            ;;
        "remove")
            execute_remove_action "$instance_num"
            ;;
        *)
            error_exit "Invalid action specified. Use 'deploy' or 'remove'."
            ;;
    esac
}

# 배포 액션 실행 함수
execute_deploy_action() {
    local instance_num="$1"

    log_info "Deploying service: ${SERVICE_NAME}, instance: ${instance_num}, port: ${PORT}"

    # 1. 배포 환경 준비
    prepare_deploy_environment "$INSTANCE_DIR" "$JAR_TRUNK_DIR"

    # 2. Nginx 트래픽 차단
    log_info "Setting nginx upstream DOWN for port ${PORT}"
    "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" down || error_exit "Failed to set nginx upstream DOWN"

    # 3. JAR 백업
    backup_current_jar "$TARGET_LINK"

    # 4. JAR 교체 (에러 시 Nginx 복구)
    log_info "Creating jar symlink..."
    if ! "${SCRIPT_DIR}/link_jar.sh" "$SERVICE_NAME" "$TARGET_LINK" "$JAR_TRUNK_DIR"; then
        "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up
        error_exit "Jar symlink failed"
    fi

    # 5. runApp.sh 동기화 (에러 시 Nginx 복구)
    if ! sync_runapp_script "$SCRIPT_DIR" "$INSTANCE_DIR"; then
        "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up
        error_exit "runApp.sh synchronization failed"
    fi

    # 6. 로그 설정 (에러 시 Nginx 복구)
    log_info "Setting up logs for instance ${instance_num}"
    if ! "${SCRIPT_DIR}/setup_logs.sh" "$SERVICE_NAME" "$instance_num" "$INSTANCE_DIR" "$LOG_BASE_DIR"; then
        "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up
        error_exit "Log setup failed"
    fi

    # 7. 애플리케이션 배포 (에러 시 Nginx 복구)
    if ! execute_deployment "$INSTANCE_DIR" "$PORT" "$APP_MODE" "${JAVA_OPTS:-}" "$SCRIPT_DIR"; then
        "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up
        error_exit "Failed to deploy application"
    fi

    # 8. 테스트 실행 (에러 시 Nginx 복구)
    if ! execute_test_script "${TEST_SCRIPT:-}" "$PORT"; then
        "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up
        error_exit "Tests failed for instance ${instance_num}"
    fi

    # 9. Nginx 트래픽 복구
    log_info "Setting nginx upstream UP for port ${PORT}"
    "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up || error_exit "Failed to set nginx upstream UP"

    log_success "Deployment completed for instance: ${instance_num}, port: ${PORT}"
}

# 제거 액션 실행 함수
execute_remove_action() {
    local instance_num="$1"

    log_info "Removing instance: ${SERVICE_NAME}, instance: ${instance_num}, port: ${PORT}"

    # 인스턴스 제거 처리
    handle_instance_removal "$INSTANCE_DIR" "$PORT" "$SCRIPT_DIR" "$UPSTREAM_CONF"

    log_success "Instance ${instance_num} removed successfully."
}

# 배포 상태 확인 함수
check_deploy_status() {
    local instance_num="$1"
    local env_file="$2"

    # 환경 로드
    load_and_validate_environment "$env_file" "$instance_num"

    echo "=== Deployment Status ==="
    echo "Service: $SERVICE_NAME"
    echo "Instance: $instance_num"
    echo "Port: $PORT"
    echo "Instance Directory: $INSTANCE_DIR"

    # 배포 준비 상태 확인
    check_deploy_readiness "$INSTANCE_DIR" "$JAR_TRUNK_DIR" "$SERVICE_NAME"

    echo ""

    # 배포 상태 확인
    check_deployment_status "$INSTANCE_DIR" "$PORT"
}

# 배포 검증 함수
verify_deployment() {
    local instance_num="$1"
    local env_file="$2"

    # 환경 로드
    load_and_validate_environment "$env_file" "$instance_num"

    echo "=== Deployment Verification ==="

    # 1. 필수 스크립트 검증
    validate_required_scripts "$SCRIPT_DIR"

    # 2. 환경 디렉터리 검증
    validate_environment_directories

    # 3. 배포 전제조건 검증
    verify_deployment_prerequisites "$INSTANCE_DIR" "$SCRIPT_DIR"

    # 4. runApp.sh 검증
    verify_runapp_script "$INSTANCE_DIR"

    echo "✅ Deployment verification completed successfully"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${4:-main}" in
        "main")
            deploy_main "$1" "$2" "${3:-deploy}"
            ;;
        "status")
            check_deploy_status "$1" "$2"
            ;;
        "verify")
            verify_deployment "$1" "$2"
            ;;
        *)
            echo "Usage: deploy_main.sh <instance_number> <env_file> [deploy|remove] [main|status|verify]"
            echo ""
            echo "Actions:"
            echo "  deploy: Deploy instance (default)"
            echo "  remove: Remove instance"
            echo ""
            echo "Modes:"
            echo "  main: Execute deployment/removal (default)"
            echo "  status: Check deployment status"
            echo "  verify: Verify deployment prerequisites"
            exit 1
            ;;
    esac
fi