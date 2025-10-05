#!/bin/bash
set -euo pipefail

# multi_deploy_control.sh - Multi-Instance Deployment Orchestration
#
# Layer: 2 (Orchestration)
# 역할: 다중 인스턴스 배포 오케스트레이션
# 호출자: main.sh (Layer 1)
# 호출 대상: deploy_control.sh, rollback_control.sh (Layer 3)
#
# 책임:
#   - 여러 인스턴스의 순차적 배포
#   - 스케일 업/다운 관리
#   - 배포 실패 시 자동 롤백
#   - 전체 인스턴스 상태 관리

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 모든 함수 스크립트들 source (func 디렉터리에서)
source "${SCRIPT_DIR}/func/validate_parameters.sh"
source "${SCRIPT_DIR}/func/analyze_instances.sh"
source "${SCRIPT_DIR}/func/execute_deployment.sh"

# 사용법 출력
print_usage() {
    cat << EOF
Usage: multi_deploy_control.sh <command> [arguments]

Commands:
  deploy <target_count> <env_file>     - Deploy multiple instances
  rollback <env_file>                  - Rollback all instances
  status <env_file>                    - Show current deployment status
  validate <target_count> <env_file>   - Validate deployment prerequisites

Note: Target count must be between 2-5 (hard limit, not configurable)

Environment variables (set in multi_deploy.env):
  MULTI_DEPLOY_PARALLEL               - Parallel deployment (default: false)
  MULTI_DEPLOY_AUTO_ROLLBACK          - Auto rollback on failure (default: true)
  MULTI_DEPLOY_CONTINUE_ON_ERROR      - Continue on error (default: false)
  MULTI_DEPLOY_DRY_RUN                - Dry run mode (default: false)
  MULTI_DEPLOY_STRATEGY               - Deployment strategy (default: sequential)
  MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS   - Wait time between deploys (default: 2s)
  MULTI_DEPLOY_STABILIZATION_WAIT     - Stabilization wait time (default: 5s)
  MULTI_DEPLOY_VERIFY_BEFORE_DEPLOY   - Verify before deploy (default: true)
  MULTI_DEPLOY_VERIFY_AFTER_DEPLOY    - Verify after deploy (default: true)
  MULTI_DEPLOY_SCALE_IN_REVERSE       - Scale down in reverse (default: true)
  MULTI_DEPLOY_SCALE_GRACEFUL         - Graceful scaling (default: true)

Examples:
  # Deploy 5 instances
  ./multi_deploy_control.sh deploy 5 /path/to/env.env

  # Rollback all instances
  ./multi_deploy_control.sh rollback /path/to/env.env

  # Check current status
  ./multi_deploy_control.sh status /path/to/env.env

  # Validate before deployment
  ./multi_deploy_control.sh validate 5 /path/to/env.env
EOF
}

# 환경 로드
load_environment() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
        return 1
    fi

    source "$env_file"

    # 필수 환경 변수 확인
    validate_required_env_vars "$env_file"
}

# 배포 실행
execute_deploy() {
    local target_count="$1"
    local env_file="$2"

    echo "=================================================="
    echo "Multi Deployment for service: $(basename "$env_file")"
    echo "Target instance count: ${target_count}"
    echo "Using environment file: ${env_file}"
    echo "=================================================="

    # 1. 파라미터 검증
    local cleaned_env_file
    cleaned_env_file=$(validate_multi_deploy_parameters "$target_count" "$env_file")

    # 2. 환경 로드
    load_environment "$cleaned_env_file"

    # 3. 인스턴스 디렉터리 검증
    validate_instance_directories "$SERVICE_BASE_DIR" "$SERVICE_NAME"

    # 4. 현재 상태 분석
    local current_count
    current_count=$(calculate_current_instance_count "$SERVICE_BASE_DIR" "$SERVICE_NAME")

    echo ""
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Current deployed instance count: ${current_count}"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Target instance count: ${target_count}"
    echo ""

    # 5. 현재 상태 표시
    show_instance_status "$SERVICE_BASE_DIR" "$SERVICE_NAME" "$target_count"

    # 6. 배포 실행
    execute_multi_deployment "$target_count" "$cleaned_env_file" "$SCRIPT_DIR" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Multi-deployment failed" >&2
        return 1
    }

    # 7. 스케일 다운 (필요한 경우)
    if [ "$current_count" -gt "$target_count" ]; then
        echo ""
        remove_excess_instances "$current_count" "$target_count" "$cleaned_env_file" "$SCRIPT_DIR"
    fi

    # 8. 안정화 대기
    local stabilization_wait="${MULTI_DEPLOY_STABILIZATION_WAIT:-5}"
    if [ "$stabilization_wait" -gt 0 ]; then
        echo ""
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Waiting ${stabilization_wait}s for services to stabilize..."
        sleep "$stabilization_wait"
    fi

    echo ""
    echo "=================================================="
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Multi Deployment complete"
    echo "=================================================="
    return 0
}

# 전체 롤백 실행
execute_rollback_all() {
    local env_file="$1"

    echo "=================================================="
    echo "Multi-Instance Rollback"
    echo "Using environment file: $env_file"
    echo "=================================================="

    # 환경 로드
    load_environment "0" "$env_file"

    # 현재 인스턴스 분석
    local instances_str
    instances_str=$(analyze_current_instances "$SERVICE_BASE_DIR" "$SERVICE_NAME" 2>/dev/null)

    local trimmed_instances=$(echo "$instances_str" | tr -d ' ')

    if [ -z "$trimmed_instances" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No instances found to rollback"
        return 0
    fi

    local instances_array=($instances_str)
    local instance_count=${#instances_array[@]}

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Found $instance_count instances to rollback: ${instances_array[*]}"
    echo ""

    # rollback_control.sh 경로
    local rollback_script="${SCRIPT_DIR}/../rollback/rollback_control.sh"

    if [ ! -x "$rollback_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - rollback_control.sh not found or not executable: $rollback_script" >&2
        return 1
    fi

    # 각 인스턴스 롤백 (역순으로)
    local rollback_failed=false
    for (( i=${#instances_array[@]}-1; i>=0; i-- )); do
        local instance=${instances_array[$i]}
        echo "==================================================[ Rollback Instance $instance ]=="

        if "$rollback_script" rollback "$instance" "$env_file"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance $instance rolled back successfully"
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to rollback instance $instance" >&2
            rollback_failed=true
        fi

        # 다음 롤백 전 대기
        if [ "$i" -gt 0 ] && [ "${MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS:-2}" -gt 0 ]; then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Waiting ${MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS}s before next rollback"
            sleep "${MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS}"
        fi
    done

    echo ""
    echo "=================================================="
    if [ "$rollback_failed" = "true" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Multi-instance rollback completed with some failures"
        return 1
    else
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Multi-instance rollback completed successfully"
        return 0
    fi
}

# 상태 확인
check_status() {
    local env_file="$1"

    echo "=== Multi-Deploy Status ==="
    echo "Environment File: $env_file"

    # 환경 로드
    load_environment "$env_file"

    echo "Service: $SERVICE_NAME"
    echo "Service Base Dir: $SERVICE_BASE_DIR"
    echo "Base Port: $BASE_PORT"
    echo ""

    # 현재 인스턴스 분석
    local instances_str
    instances_str=$(analyze_current_instances "$SERVICE_BASE_DIR" "$SERVICE_NAME" 2>/dev/null)

    local trimmed_instances=$(echo "$instances_str" | tr -d ' ')

    if [ -z "$trimmed_instances" ]; then
        echo "Current Instances: None"
        echo "Current Count: 0"
    else
        local instances_array=($instances_str)
        echo "Current Instances: ${instances_array[*]}"

        local current_count
        current_count=$(calculate_current_instance_count "$SERVICE_BASE_DIR" "$SERVICE_NAME")
        echo "Current Count: $current_count"

        # 각 인스턴스 상태 확인
        echo ""
        echo "=== Individual Instance Status ==="
        for instance_num in "${instances_array[@]}"; do
            local port="${BASE_PORT}${instance_num}"
            local instance_dir="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"

            echo "Instance $instance_num (port $port):"

            # 디렉터리 확인
            if [ -d "$instance_dir" ]; then
                echo "  Directory: ✅ $instance_dir"

                # JAR 링크 확인
                if [ -L "${instance_dir}/current.jar" ]; then
                    local jar_target=$(readlink "${instance_dir}/current.jar")
                    echo "  JAR Link: ✅ -> $jar_target"
                else
                    echo "  JAR Link: ❌ Not found"
                fi

                # 프로세스 확인
                if pgrep -f "java -jar current.jar --server.port=${port}" > /dev/null; then
                    echo "  Process: ✅ Running"
                else
                    echo "  Process: ❌ Not running"
                fi

                # 백업 확인
                if [ -f "${instance_dir}/current.jar.bak" ]; then
                    echo "  Backup: ✅ Available"
                else
                    echo "  Backup: ⚠️  Not available"
                fi
            else
                echo "  Directory: ❌ Not found"
            fi
            echo ""
        done
    fi
}

# 검증 실행
validate_deployment() {
    local target_count="$1"
    local env_file="$2"

    echo "=== Multi-Deploy Validation ==="

    # 1. 파라미터 검증
    local cleaned_env_file
    cleaned_env_file=$(validate_multi_deploy_parameters "$target_count" "$env_file")
    echo "✅ Parameters validated"

    # 2. 환경 변수 검증
    load_environment "$cleaned_env_file"
    echo "✅ Environment variables validated"

    # 3. 디렉터리 검증
    validate_instance_directories "$SERVICE_BASE_DIR" "$SERVICE_NAME"
    echo "✅ Instance directories validated"

    # 4. deploy_control.sh 확인
    local deploy_script="${SCRIPT_DIR}/../deploy/deploy_control.sh"
    if [ -x "$deploy_script" ]; then
        echo "✅ deploy_control.sh found and executable"
    else
        echo "❌ deploy_control.sh not found or not executable: $deploy_script"
        return 1
    fi

    # 5. 기타 필수 스크립트 확인
    local required_scripts=(
        "nginx/nginx_control.sh"
        "link_jar/link_jar_control.sh"
        "run_app/run_app_control.sh"
    )

    for script in "${required_scripts[@]}"; do
        local script_path="${SCRIPT_DIR}/../${script}"
        if [ -x "$script_path" ]; then
            echo "✅ $script found and executable"
        else
            echo "❌ $script not found or not executable: $script_path"
            return 1
        fi
    done

    echo ""
    echo "✅ All validations passed"
    return 0
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
        deploy)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'deploy' requires <target_count> <env_file>"
                exit 1
            fi
            execute_deploy "$@"
            ;;
        rollback)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'rollback' requires <env_file>"
                exit 1
            fi
            execute_rollback_all "$@"
            ;;
        status)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'status' requires <env_file>"
                exit 1
            fi
            check_status "$@"
            ;;
        validate)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'validate' requires <target_count> <env_file>"
                exit 1
            fi
            validate_deployment "$@"
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
