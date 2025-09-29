#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SCRIPT_DIR

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_multi_deploy_parameters.sh"
source "${SCRIPT_DIR}/analyze_current_instances.sh"
source "${SCRIPT_DIR}/execute_multi_deployment.sh"
source "${SCRIPT_DIR}/manage_rollback.sh"
source "${SCRIPT_DIR}/manage_scaling.sh"

# 메인 다중 배포 함수
multi_deploy_main() {
    # 사용법: multi_deploy_main <target_count> <env_file> [action] [dry_run]
    if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
        echo "Usage: multi_deploy_main <target_count> <env_file> [deploy|rollback|scale] [dry_run]"
        exit 1
    fi

    local target_count="$1"
    local env_file="$2"
    local action="${3:-deploy}"
    local dry_run="${4:-false}"

    # 1. 파라미터 검증
    validate_multi_deploy_parameters "$target_count" "$env_file" "$action"

    # 2. 환경 설정 로드
    source "$env_file"

    # 3. 필수 변수 검증
    if [ -z "${SERVICE_NAME:-}" ] || [ -z "${SERVICE_BASE_DIR:-}" ]; then
        error_exit "Required environment variables missing: SERVICE_NAME, SERVICE_BASE_DIR"
    fi

    # 4. 디렉터리 유효성 검증 및 생성
    validate_instance_directories "$SERVICE_BASE_DIR" "$SERVICE_NAME"

    # 5. 액션에 따른 실행
    case "$action" in
        "deploy")
            execute_deploy_action "$target_count" "$env_file" "$SERVICE_BASE_DIR" "$SERVICE_NAME" "$dry_run"
            ;;
        "rollback")
            execute_rollback_action "$env_file" "$SERVICE_BASE_DIR" "$SERVICE_NAME" "$dry_run"
            ;;
        "scale")
            execute_scale_action "$target_count" "$env_file" "$SERVICE_BASE_DIR" "$SERVICE_NAME" "$dry_run"
            ;;
        *)
            error_exit "Invalid action specified. Use 'deploy', 'rollback', or 'scale'."
            ;;
    esac
}

# 배포 액션 실행 함수
execute_deploy_action() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local dry_run="$5"

    log_info "Starting multi-deploy action: target_count=$target_count, dry_run=$dry_run"

    # 현재 상태 분석
    show_instance_status "$service_base_dir" "$service_name" "$target_count"

    # 배포 준비 상태 확인
    verify_deployment_readiness "$target_count" "$env_file" "$service_base_dir" "$service_name"

    # 다중 배포 실행
    execute_multi_deployment "$target_count" "$env_file" "$service_base_dir" "$service_name" "$dry_run"

    # 배포 후 상태 확인 (실제 배포인 경우만)
    if [ "$dry_run" = "false" ]; then
        log_info "Waiting 5 seconds for services to stabilize..."
        sleep 5
        verify_all_instances_status "$target_count" "$env_file"
    fi

    log_success "Multi-deploy action completed successfully"
}

# 롤백 액션 실행 함수
execute_rollback_action() {
    local env_file="$1"
    local service_base_dir="$2"
    local service_name="$3"
    local dry_run="$4"

    log_info "Starting multi-rollback action: dry_run=$dry_run"

    # 롤백 준비 상태 확인
    verify_rollback_prerequisites "$env_file" "$service_base_dir" "$service_name"

    # 전체 롤백 실행
    execute_bulk_rollback "$env_file" "$service_base_dir" "$service_name" "$dry_run"

    log_success "Multi-rollback action completed successfully"
}

# 스케일링 액션 실행 함수
execute_scale_action() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local dry_run="$5"

    log_info "Starting scaling action: target_count=$target_count, dry_run=$dry_run"

    # 현재 상태 분석
    show_instance_status "$service_base_dir" "$service_name" "$target_count"

    # 스마트 스케일링 실행
    execute_smart_scaling "$target_count" "$env_file" "$service_base_dir" "$service_name" "$dry_run"

    # 스케일링 후 상태 확인 (실제 실행인 경우만)
    if [ "$dry_run" = "false" ]; then
        log_info "Waiting 5 seconds for services to stabilize..."
        sleep 5
        verify_all_instances_status "$target_count" "$env_file"
    fi

    log_success "Scaling action completed successfully"
}

# 상태 확인 함수
check_multi_deploy_status() {
    local env_file="$1"
    local service_base_dir="${2:-}"
    local service_name="${3:-}"

    echo "=== Multi-Deploy Status ===="

    # 환경 파일에서 설정 로드
    source "$env_file"

    # 서비스 정보 확인
    local actual_service_base_dir="${service_base_dir:-$SERVICE_BASE_DIR}"
    local actual_service_name="${service_name:-$SERVICE_NAME}"

    echo "Environment File: $env_file"
    echo "Service: $actual_service_name"
    echo "Service Base Dir: $actual_service_base_dir"
    echo ""

    # 현재 배포된 인스턴스 분석
    local instances_str
    instances_str=$(analyze_current_instances "$actual_service_base_dir" "$actual_service_name")

    if [ -z "$instances_str" ] || [ "$instances_str" = " " ]; then
        echo "Current Instances: None"
        echo "Current Count: 0"
    else
        local instances_array=($instances_str)
        echo "Current Instances: ${instances_array[*]}"

        local current_count
        current_count=$(calculate_current_instance_count "$actual_service_base_dir" "$actual_service_name")
        echo "Current Count: $current_count"

        # 각 인스턴스 상태 확인
        echo ""
        echo "=== Individual Instance Status ==="
        for instance_num in "${instances_array[@]}"; do
            local port=$((BASE_PORT + instance_num))
            echo "Instance $instance_num (port $port):"

            # 프로세스 상태 확인
            local runapp_script="${actual_service_base_dir}/../runApp/runApp_main.sh"
            if [ -f "$runapp_script" ]; then
                "$runapp_script" "$port" "start" "" "${actual_service_base_dir}/../common_utils" "status" 2>/dev/null || echo "  Status: Unknown"
            else
                echo "  Status: Cannot check (runApp script not found)"
            fi

            # 백업 상태 확인
            check_backup_availability "$instance_num" "$actual_service_base_dir" "$actual_service_name"
            echo ""
        done
    fi
}

# 전체 시스템 검증 함수
verify_multi_deploy_system() {
    local env_file="$1"

    echo "=== Multi-Deploy System Verification ==="

    # 환경 파일 로드
    if [ ! -f "$env_file" ]; then
        error_exit "Environment file not found: $env_file"
    fi

    source "$env_file"

    # 필수 변수 확인
    local missing_vars=()
    [ -z "${SERVICE_NAME:-}" ] && missing_vars+=("SERVICE_NAME")
    [ -z "${SERVICE_BASE_DIR:-}" ] && missing_vars+=("SERVICE_BASE_DIR")
    [ -z "${BASE_PORT:-}" ] && missing_vars+=("BASE_PORT")

    if [ ${#missing_vars[@]} -gt 0 ]; then
        error_exit "Missing required environment variables: ${missing_vars[*]}"
    fi

    echo "✅ Environment variables validated"

    # 디렉터리 구조 확인
    validate_instance_directories "$SERVICE_BASE_DIR" "$SERVICE_NAME"
    echo "✅ Directory structure validated"

    # 필수 스크립트 확인
    local required_scripts=(
        "${SERVICE_BASE_DIR}/../deploy/deploy_main.sh"
        "${SERVICE_BASE_DIR}/../rollback/rollback_main.sh"
        "${SERVICE_BASE_DIR}/../runApp/runApp_main.sh"
        "${SERVICE_BASE_DIR}/../common_utils/common_utils.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                echo "✅ $script (executable)"
            else
                echo "⚠️  $script (not executable)"
            fi
        else
            echo "❌ $script (missing)"
        fi
    done

    echo ""
    echo "System verification completed"
}

# 도움말 함수
show_multi_deploy_help() {
    cat << 'EOF'
Multi-Deploy System - Advanced Usage Guide

BASIC USAGE:
  multi_deploy_main.sh <target_count> <env_file> [action] [dry_run]

ACTIONS:
  deploy    - Deploy or update instances (default)
  rollback  - Rollback all instances
  scale     - Smart scaling (auto-detect scale-in/out/update)

OPTIONS:
  dry_run   - true|false (default: false)

EXAMPLES:
  # Deploy 5 instances
  ./multi_deploy_main.sh 5 server1.env deploy

  # Dry-run deployment
  ./multi_deploy_main.sh 5 server1.env deploy true

  # Rollback all instances
  ./multi_deploy_main.sh 0 server1.env rollback

  # Scale to 3 instances (auto-detect)
  ./multi_deploy_main.sh 3 server1.env scale

ADVANCED MODES:
  status    - Check current deployment status
  verify    - Verify system prerequisites

ADVANCED EXAMPLES:
  # Check status
  ./multi_deploy_main.sh 0 server1.env deploy false status

  # Verify system
  ./multi_deploy_main.sh 0 server1.env deploy false verify

ENVIRONMENT FILE:
  Must contain: SERVICE_NAME, SERVICE_BASE_DIR, BASE_PORT
  Example:
    SERVICE_NAME=myapp
    SERVICE_BASE_DIR=/opt/deploy/services
    BASE_PORT=8080

NOTES:
  - Target count range: 2-10
  - Failed deployments trigger automatic rollback
  - All operations support dry-run mode
  - Comprehensive logging and auditing included
EOF
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${5:-main}" in
        "main")
            multi_deploy_main "$1" "$2" "${3:-deploy}" "${4:-false}"
            ;;
        "status")
            check_multi_deploy_status "$2" "${SERVICE_BASE_DIR:-}" "${SERVICE_NAME:-}"
            ;;
        "verify")
            verify_multi_deploy_system "$2"
            ;;
        "help")
            show_multi_deploy_help
            ;;
        *)
            echo "Usage: multi_deploy_main.sh <target_count> <env_file> [deploy|rollback|scale] [dry_run] [main|status|verify|help]"
            echo ""
            echo "Actions:"
            echo "  deploy: Deploy or update instances (default)"
            echo "  rollback: Rollback all instances"
            echo "  scale: Smart scaling operation"
            echo ""
            echo "Modes:"
            echo "  main: Execute deployment/rollback/scaling (default)"
            echo "  status: Check current deployment status"
            echo "  verify: Verify system prerequisites"
            echo "  help: Show detailed help"
            echo ""
            echo "For detailed help: multi_deploy_main.sh 0 any.env deploy false help"
            exit 1
            ;;
    esac
fi