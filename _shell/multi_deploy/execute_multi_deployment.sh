#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 다중 인스턴스 배포 실행 함수
execute_multi_deployment() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local dry_run="${5:-false}"

    local deployed_instances=()
    local failed_instances=()
    local deployment_start_time
    deployment_start_time=$(current_timestamp)

    log_info "Starting multi-instance deployment: target_count=$target_count, service=$service_name"

    if [ "$dry_run" = "true" ]; then
        log_info "[DRY RUN] Would deploy $target_count instances"
        return 0
    fi

    # 순차적으로 각 인스턴스 배포
    for ((i=0; i<target_count; i++)); do
        log_info "Deploying instance $i..."

        if deploy_single_instance "$i" "$env_file" "$service_base_dir" "$service_name"; then
            deployed_instances+=("$i")
            log_success "Instance $i deployed successfully"
        else
            failed_instances+=("$i")
            log_error "Failed to deploy instance $i"

            # 실패 시 전체 롤백 실행
            log_warn "Rolling back all deployed instances due to failure"
            rollback_deployed_instances "${deployed_instances[@]}" "$env_file" "$service_base_dir" "$service_name"

            local deployment_end_time
            deployment_end_time=$(current_timestamp)
            audit_log "DEPLOYMENT_FAILED" "service=$service_name instances=${deployed_instances[*]} failed_instance=$i duration=$((deployment_end_time - deployment_start_time))s"
            error_exit "Multi-deployment failed at instance $i. All instances rolled back."
        fi
    done

    local deployment_end_time
    deployment_end_time=$(current_timestamp)
    local duration=$((deployment_end_time - deployment_start_time))

    log_success "Multi-deployment completed successfully: $target_count instances in ${duration}s"
    audit_log "DEPLOYMENT_SUCCESS" "service=$service_name instances=${deployed_instances[*]} duration=${duration}s"
}

# 단일 인스턴스 배포 함수
deploy_single_instance() {
    local instance_num="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"

    local deploy_script="${service_base_dir}/../deploy/deploy_main.sh"

    # 배포 스크립트 존재 확인
    if [ ! -f "$deploy_script" ]; then
        log_error "Deploy script not found: $deploy_script"
        return 1
    fi

    # 단일 인스턴스 배포 실행
    log_info "Executing deployment for instance $instance_num"
    if "$deploy_script" "$instance_num" "$env_file" "deploy"; then
        log_info "Instance $instance_num deployment completed"
        return 0
    else
        log_error "Instance $instance_num deployment failed"
        return 1
    fi
}

# 배포된 인스턴스들 롤백 함수
rollback_deployed_instances() {
    local instances=("$@")
    local env_file="${instances[-3]}"
    local service_base_dir="${instances[-2]}"
    local service_name="${instances[-1]}"

    # 마지막 3개 인자는 환경 정보이므로 제외
    unset instances[-1] instances[-1] instances[-1]

    if [ ${#instances[@]} -eq 0 ]; then
        log_info "No instances to rollback"
        return 0
    fi

    log_warn "Rolling back ${#instances[@]} deployed instances"

    local rollback_script="${service_base_dir}/../rollback/rollback_main.sh"

    # 역순으로 롤백 (마지막 배포된 것부터)
    for ((i=${#instances[@]}-1; i>=0; i--)); do
        local instance_num="${instances[i]}"
        log_info "Rolling back instance $instance_num"

        if [ -f "$rollback_script" ]; then
            if "$rollback_script" "$instance_num" "$env_file"; then
                log_success "Instance $instance_num rolled back successfully"
            else
                log_error "Failed to rollback instance $instance_num"
            fi
        else
            log_warn "Rollback script not found: $rollback_script"
        fi
    done
}

# 배포 전 준비 확인 함수
verify_deployment_readiness() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"

    log_info "Verifying deployment readiness"

    # 환경 파일 확인
    if [ ! -f "$env_file" ]; then
        error_exit "Environment file not found: $env_file"
    fi

    # 서비스 디렉터리 확인
    if [ ! -d "$service_base_dir" ]; then
        error_exit "Service base directory not found: $service_base_dir"
    fi

    # 배포 스크립트 확인
    local deploy_script="${service_base_dir}/../deploy/deploy_main.sh"
    if [ ! -f "$deploy_script" ]; then
        error_exit "Deploy script not found: $deploy_script"
    fi

    # 실행 권한 확인
    if [ ! -x "$deploy_script" ]; then
        error_exit "Deploy script is not executable: $deploy_script"
    fi

    log_success "Deployment readiness verification completed"
}

# 배포 후 전체 상태 확인 함수
verify_all_instances_status() {
    local target_count="$1"
    local env_file="$2"

    log_info "Verifying status of all $target_count instances"

    local all_healthy=true
    local test_script="$(dirname "$0")/../test_instance/test_instance_main.sh"

    # 환경 파일에서 포트 계산을 위한 기본 정보 로드
    source "$env_file"

    for ((i=0; i<target_count; i++)); do
        local port=$((BASE_PORT + i))

        if [ -f "$test_script" ]; then
            if "$test_script" "$port" "health"; then
                log_success "Instance $i (port $port) is healthy"
            else
                log_error "Instance $i (port $port) is not healthy"
                all_healthy=false
            fi
        else
            log_warn "Test script not found, skipping health check for instance $i"
        fi
    done

    if [ "$all_healthy" = "true" ]; then
        log_success "All $target_count instances are healthy"
        return 0
    else
        log_error "Some instances are not healthy"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 4 ]; then
        echo "Usage: execute_multi_deployment.sh <target_count> <env_file> <service_base_dir> <service_name> [dry_run]"
        echo "  dry_run: true|false (default: false)"
        exit 1
    fi

    case "${6:-deploy}" in
        "deploy")
            execute_multi_deployment "$1" "$2" "$3" "$4" "${5:-false}"
            ;;
        "verify_readiness")
            verify_deployment_readiness "$1" "$2" "$3" "$4"
            ;;
        "verify_status")
            verify_all_instances_status "$1" "$2"
            ;;
        *)
            echo "Invalid mode. Use: deploy, verify_readiness, verify_status"
            exit 1
            ;;
    esac
fi