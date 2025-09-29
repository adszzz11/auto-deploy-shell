#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 전체 서비스 롤백 함수
execute_bulk_rollback() {
    local env_file="$1"
    local service_base_dir="$2"
    local service_name="$3"
    local dry_run="${4:-false}"

    log_info "Starting bulk rollback for service: $service_name"

    if [ "$dry_run" = "true" ]; then
        log_info "[DRY RUN] Would execute bulk rollback"
        show_rollback_preview "$env_file" "$service_base_dir" "$service_name"
        return 0
    fi

    # 현재 배포된 인스턴스 분석
    local instances_str
    instances_str=$(analyze_current_instances "$service_base_dir" "$service_name")

    if [ -z "$instances_str" ] || [ "$instances_str" = " " ]; then
        log_warn "No instances found to rollback"
        return 0
    fi

    local instances_array=($instances_str)
    local rollback_start_time
    rollback_start_time=$(current_timestamp)

    log_info "Found ${#instances_array[@]} instances to rollback: ${instances_array[*]}"

    # 역순으로 롤백 (최신 배포부터)
    local rolled_back_instances=()
    local failed_rollbacks=()

    for ((i=${#instances_array[@]}-1; i>=0; i--)); do
        local instance_num="${instances_array[i]}"

        if rollback_single_instance "$instance_num" "$env_file" "$service_base_dir" "$service_name"; then
            rolled_back_instances+=("$instance_num")
            log_success "Instance $instance_num rolled back successfully"
        else
            failed_rollbacks+=("$instance_num")
            log_error "Failed to rollback instance $instance_num"
        fi
    done

    local rollback_end_time
    rollback_end_time=$(current_timestamp)
    local duration=$((rollback_end_time - rollback_start_time))

    # 결과 보고
    if [ ${#failed_rollbacks[@]} -eq 0 ]; then
        log_success "Bulk rollback completed successfully: ${#rolled_back_instances[@]} instances in ${duration}s"
        audit_log "ROLLBACK_SUCCESS" "service=$service_name instances=${rolled_back_instances[*]} duration=${duration}s"
    else
        log_error "Bulk rollback partially failed: ${#failed_rollbacks[@]} failures"
        audit_log "ROLLBACK_PARTIAL_FAILURE" "service=$service_name success=${rolled_back_instances[*]} failed=${failed_rollbacks[*]} duration=${duration}s"
        return 1
    fi
}

# 단일 인스턴스 롤백 함수
rollback_single_instance() {
    local instance_num="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"

    local rollback_script="${service_base_dir}/../rollback/rollback_main.sh"

    # 롤백 스크립트 존재 확인
    if [ ! -f "$rollback_script" ]; then
        log_error "Rollback script not found: $rollback_script"
        return 1
    fi

    # 단일 인스턴스 롤백 실행
    log_info "Executing rollback for instance $instance_num"
    if "$rollback_script" "$instance_num" "$env_file"; then
        log_info "Instance $instance_num rollback completed"
        return 0
    else
        log_error "Instance $instance_num rollback failed"
        return 1
    fi
}

# 선택적 인스턴스 롤백 함수
execute_selective_rollback() {
    local target_instances="$1"  # 공백으로 구분된 인스턴스 번호들
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local dry_run="${5:-false}"

    local instances_array=($target_instances)

    log_info "Starting selective rollback for instances: ${instances_array[*]}"

    if [ "$dry_run" = "true" ]; then
        log_info "[DRY RUN] Would rollback instances: ${instances_array[*]}"
        return 0
    fi

    local rollback_start_time
    rollback_start_time=$(current_timestamp)
    local rolled_back_instances=()
    local failed_rollbacks=()

    # 역순으로 롤백
    for ((i=${#instances_array[@]}-1; i>=0; i--)); do
        local instance_num="${instances_array[i]}"

        # 인스턴스 존재 확인
        if ! instance_exists "$instance_num" "$service_base_dir" "$service_name"; then
            log_warn "Instance $instance_num does not exist, skipping"
            continue
        fi

        if rollback_single_instance "$instance_num" "$env_file" "$service_base_dir" "$service_name"; then
            rolled_back_instances+=("$instance_num")
            log_success "Instance $instance_num rolled back successfully"
        else
            failed_rollbacks+=("$instance_num")
            log_error "Failed to rollback instance $instance_num"
        fi
    done

    local rollback_end_time
    rollback_end_time=$(current_timestamp)
    local duration=$((rollback_end_time - rollback_start_time))

    # 결과 보고
    if [ ${#failed_rollbacks[@]} -eq 0 ]; then
        log_success "Selective rollback completed: ${#rolled_back_instances[@]} instances in ${duration}s"
        audit_log "SELECTIVE_ROLLBACK_SUCCESS" "service=$service_name instances=${rolled_back_instances[*]} duration=${duration}s"
    else
        log_error "Selective rollback partially failed: ${#failed_rollbacks[@]} failures"
        audit_log "SELECTIVE_ROLLBACK_PARTIAL_FAILURE" "service=$service_name success=${rolled_back_instances[*]} failed=${failed_rollbacks[*]} duration=${duration}s"
        return 1
    fi
}

# 인스턴스 존재 확인 함수
instance_exists() {
    local instance_num="$1"
    local service_base_dir="$2"
    local service_name="$3"

    local instance_dir="${service_base_dir}/${service_name}/instances/${instance_num}"
    [ -d "$instance_dir" ]
}

# 롤백 미리보기 함수
show_rollback_preview() {
    local env_file="$1"
    local service_base_dir="$2"
    local service_name="$3"

    echo "=== Rollback Preview ==="
    echo "Service: $service_name"
    echo "Environment: $env_file"

    # 현재 배포된 인스턴스 분석
    local instances_str
    instances_str=$(analyze_current_instances "$service_base_dir" "$service_name")

    if [ -z "$instances_str" ] || [ "$instances_str" = " " ]; then
        echo "No instances found to rollback"
        return 0
    fi

    local instances_array=($instances_str)
    echo "Instances to rollback: ${instances_array[*]}"
    echo "Rollback order: $(printf '%s ' "${instances_array[@]}" | rev)"

    # 각 인스턴스의 백업 상태 확인
    for instance_num in "${instances_array[@]}"; do
        check_backup_availability "$instance_num" "$service_base_dir" "$service_name"
    done
}

# 백업 가용성 확인 함수
check_backup_availability() {
    local instance_num="$1"
    local service_base_dir="$2"
    local service_name="$3"

    local instance_dir="${service_base_dir}/${service_name}/instances/${instance_num}"
    local backup_link="${instance_dir}/app.jar.backup"

    echo "Instance $instance_num:"
    if [ -L "$backup_link" ]; then
        echo "  ✅ Backup available: $(readlink "$backup_link")"
    else
        echo "  ❌ No backup found"
    fi
}

# 롤백 전제조건 검증 함수
verify_rollback_prerequisites() {
    local env_file="$1"
    local service_base_dir="$2"
    local service_name="$3"

    log_info "Verifying rollback prerequisites"

    # 환경 파일 확인
    if [ ! -f "$env_file" ]; then
        error_exit "Environment file not found: $env_file"
    fi

    # 서비스 디렉터리 확인
    if [ ! -d "$service_base_dir" ]; then
        error_exit "Service base directory not found: $service_base_dir"
    fi

    # 롤백 스크립트 확인
    local rollback_script="${service_base_dir}/../rollback/rollback_main.sh"
    if [ ! -f "$rollback_script" ]; then
        error_exit "Rollback script not found: $rollback_script"
    fi

    # 실행 권한 확인
    if [ ! -x "$rollback_script" ]; then
        error_exit "Rollback script is not executable: $rollback_script"
    fi

    log_success "Rollback prerequisites verification completed"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: manage_rollback.sh <env_file> <service_base_dir> <service_name> [mode] [options]"
        echo ""
        echo "Modes:"
        echo "  bulk: Rollback all instances (default)"
        echo "  selective: Rollback specific instances"
        echo "  preview: Show rollback preview"
        echo "  verify: Verify rollback prerequisites"
        echo ""
        echo "Examples:"
        echo "  manage_rollback.sh server1.env /deploy/services myapp bulk [true|false]"
        echo "  manage_rollback.sh server1.env /deploy/services myapp selective \"0 2 4\" [true|false]"
        echo "  manage_rollback.sh server1.env /deploy/services myapp preview"
        exit 1
    fi

    local env_file="$1"
    local service_base_dir="$2"
    local service_name="$3"
    local mode="${4:-bulk}"

    case "$mode" in
        "bulk")
            execute_bulk_rollback "$env_file" "$service_base_dir" "$service_name" "${5:-false}"
            ;;
        "selective")
            if [ "$#" -lt 5 ]; then
                error_exit "Selective rollback requires target instances. Usage: ... selective \"0 2 4\" [dry_run]"
            fi
            execute_selective_rollback "$5" "$env_file" "$service_base_dir" "$service_name" "${6:-false}"
            ;;
        "preview")
            show_rollback_preview "$env_file" "$service_base_dir" "$service_name"
            ;;
        "verify")
            verify_rollback_prerequisites "$env_file" "$service_base_dir" "$service_name"
            ;;
        *)
            error_exit "Invalid mode: $mode. Use: bulk, selective, preview, verify"
            ;;
    esac
fi