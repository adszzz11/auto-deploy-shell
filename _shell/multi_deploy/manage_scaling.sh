#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 스케일 아웃 함수 (인스턴스 추가)
execute_scale_out() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local dry_run="${5:-false}"

    log_info "Starting scale-out operation: target_count=$target_count"

    # 현재 인스턴스 수 확인
    local current_count
    current_count=$(calculate_current_instance_count "$service_base_dir" "$service_name")

    if [ "$current_count" -ge "$target_count" ]; then
        log_warn "Current instance count ($current_count) is already >= target ($target_count). No scale-out needed."
        return 0
    fi

    local need_deploy=$((target_count - current_count))
    log_info "Need to deploy $need_deploy additional instances (current: $current_count, target: $target_count)"

    if [ "$dry_run" = "true" ]; then
        log_info "[DRY RUN] Would deploy instances $current_count to $((target_count - 1))"
        return 0
    fi

    local scale_start_time
    scale_start_time=$(current_timestamp)
    local deployed_instances=()
    local failed_deployments=()

    # 새 인스턴스들 배포
    for ((i=current_count; i<target_count; i++)); do
        log_info "Deploying new instance $i..."

        if deploy_single_instance "$i" "$env_file" "$service_base_dir" "$service_name"; then
            deployed_instances+=("$i")
            log_success "Instance $i deployed successfully"
        else
            failed_deployments+=("$i")
            log_error "Failed to deploy instance $i"

            # 실패 시 이번에 배포한 인스턴스들만 롤백
            if [ ${#deployed_instances[@]} -gt 0 ]; then
                log_warn "Rolling back newly deployed instances due to failure"
                rollback_new_instances "${deployed_instances[@]}" "$env_file" "$service_base_dir" "$service_name"
            fi

            local scale_end_time
            scale_end_time=$(current_timestamp)
            audit_log "SCALE_OUT_FAILED" "service=$service_name current=$current_count target=$target_count failed_at=$i duration=$((scale_end_time - scale_start_time))s"
            error_exit "Scale-out failed at instance $i. Newly deployed instances rolled back."
        fi
    done

    local scale_end_time
    scale_end_time=$(current_timestamp)
    local duration=$((scale_end_time - scale_start_time))

    log_success "Scale-out completed successfully: deployed ${#deployed_instances[@]} instances in ${duration}s"
    audit_log "SCALE_OUT_SUCCESS" "service=$service_name from=$current_count to=$target_count instances=${deployed_instances[*]} duration=${duration}s"
}

# 스케일 인 함수 (인스턴스 제거)
execute_scale_in() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local dry_run="${5:-false}"

    log_info "Starting scale-in operation: target_count=$target_count"

    # 현재 인스턴스 수 확인
    local current_count
    current_count=$(calculate_current_instance_count "$service_base_dir" "$service_name")

    if [ "$current_count" -le "$target_count" ]; then
        log_warn "Current instance count ($current_count) is already <= target ($target_count). No scale-in needed."
        return 0
    fi

    local need_remove=$((current_count - target_count))
    log_info "Need to remove $need_remove instances (current: $current_count, target: $target_count)"

    # 제거할 인스턴스 결정 (높은 번호부터)
    local instances_to_remove=()
    for ((i=current_count-1; i>=target_count; i--)); do
        instances_to_remove+=("$i")
    done

    log_info "Instances to remove: ${instances_to_remove[*]}"

    if [ "$dry_run" = "true" ]; then
        log_info "[DRY RUN] Would remove instances: ${instances_to_remove[*]}"
        return 0
    fi

    local scale_start_time
    scale_start_time=$(current_timestamp)
    local removed_instances=()
    local failed_removals=()

    # 높은 번호부터 제거 (역순으로)
    for instance_num in "${instances_to_remove[@]}"; do
        log_info "Removing instance $instance_num..."

        if remove_single_instance "$instance_num" "$env_file" "$service_base_dir" "$service_name"; then
            removed_instances+=("$instance_num")
            log_success "Instance $instance_num removed successfully"
        else
            failed_removals+=("$instance_num")
            log_error "Failed to remove instance $instance_num"
        fi
    done

    local scale_end_time
    scale_end_time=$(current_timestamp)
    local duration=$((scale_end_time - scale_start_time))

    # 결과 보고
    if [ ${#failed_removals[@]} -eq 0 ]; then
        log_success "Scale-in completed successfully: removed ${#removed_instances[@]} instances in ${duration}s"
        audit_log "SCALE_IN_SUCCESS" "service=$service_name from=$current_count to=$target_count removed=${removed_instances[*]} duration=${duration}s"
    else
        log_error "Scale-in partially failed: ${#failed_removals[@]} removal failures"
        audit_log "SCALE_IN_PARTIAL_FAILURE" "service=$service_name from=$current_count target=$target_count removed=${removed_instances[*]} failed=${failed_removals[*]} duration=${duration}s"
        return 1
    fi
}

# 새로 배포된 인스턴스들 롤백 함수
rollback_new_instances() {
    local instances=("$@")
    local env_file="${instances[-3]}"
    local service_base_dir="${instances[-2]}"
    local service_name="${instances[-1]}"

    # 마지막 3개 인자는 환경 정보이므로 제외
    unset instances[-1] instances[-1] instances[-1]

    if [ ${#instances[@]} -eq 0 ]; then
        log_info "No new instances to rollback"
        return 0
    fi

    log_warn "Rolling back ${#instances[@]} newly deployed instances"

    # 역순으로 제거 (마지막 배포된 것부터)
    for ((i=${#instances[@]}-1; i>=0; i--)); do
        local instance_num="${instances[i]}"
        log_info "Removing newly deployed instance $instance_num"

        if remove_single_instance "$instance_num" "$env_file" "$service_base_dir" "$service_name"; then
            log_success "Instance $instance_num removed successfully"
        else
            log_error "Failed to remove instance $instance_num"
        fi
    done
}

# 단일 인스턴스 제거 함수
remove_single_instance() {
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

    # 단일 인스턴스 제거 실행
    log_info "Executing removal for instance $instance_num"
    if "$deploy_script" "$instance_num" "$env_file" "remove"; then
        log_info "Instance $instance_num removal completed"
        return 0
    else
        log_error "Instance $instance_num removal failed"
        return 1
    fi
}

# 스마트 스케일링 함수 (현재 상태 분석 후 자동 결정)
execute_smart_scaling() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local dry_run="${5:-false}"

    log_info "Starting smart scaling to target: $target_count instances"

    # 현재 상태 분석
    local current_count
    current_count=$(calculate_current_instance_count "$service_base_dir" "$service_name")

    log_info "Current instances: $current_count, Target: $target_count"

    if [ "$current_count" -lt "$target_count" ]; then
        log_info "Scale-out needed: current=$current_count < target=$target_count"
        execute_scale_out "$target_count" "$env_file" "$service_base_dir" "$service_name" "$dry_run"
    elif [ "$current_count" -gt "$target_count" ]; then
        log_info "Scale-in needed: current=$current_count > target=$target_count"
        execute_scale_in "$target_count" "$env_file" "$service_base_dir" "$service_name" "$dry_run"
    else
        log_info "No scaling needed: current count matches target ($target_count)"
        if [ "$dry_run" = "false" ]; then
            # 인스턴스 수가 맞지만 업데이트 배포 실행
            log_info "Executing update deployment for all $target_count instances"
            execute_update_deployment "$target_count" "$env_file" "$service_base_dir" "$service_name"
        else
            log_info "[DRY RUN] Would execute update deployment for all $target_count instances"
        fi
    fi
}

# 업데이트 배포 함수 (기존 인스턴스들 갱신)
execute_update_deployment() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"

    log_info "Starting update deployment for $target_count instances"

    local update_start_time
    update_start_time=$(current_timestamp)
    local updated_instances=()
    local failed_updates=()

    # 모든 인스턴스 순차 업데이트
    for ((i=0; i<target_count; i++)); do
        log_info "Updating instance $i..."

        if deploy_single_instance "$i" "$env_file" "$service_base_dir" "$service_name"; then
            updated_instances+=("$i")
            log_success "Instance $i updated successfully"
        else
            failed_updates+=("$i")
            log_error "Failed to update instance $i"
        fi
    done

    local update_end_time
    update_end_time=$(current_timestamp)
    local duration=$((update_end_time - update_start_time))

    # 결과 보고
    if [ ${#failed_updates[@]} -eq 0 ]; then
        log_success "Update deployment completed successfully: updated ${#updated_instances[@]} instances in ${duration}s"
        audit_log "UPDATE_DEPLOYMENT_SUCCESS" "service=$service_name instances=${updated_instances[*]} duration=${duration}s"
    else
        log_error "Update deployment partially failed: ${#failed_updates[@]} update failures"
        audit_log "UPDATE_DEPLOYMENT_PARTIAL_FAILURE" "service=$service_name updated=${updated_instances[*]} failed=${failed_updates[*]} duration=${duration}s"
        return 1
    fi
}

# 스케일링 미리보기 함수
show_scaling_preview() {
    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"

    echo "=== Scaling Preview ==="
    echo "Service: $service_name"
    echo "Environment: $env_file"
    echo "Target Count: $target_count"

    # 현재 상태 분석
    local current_count
    current_count=$(calculate_current_instance_count "$service_base_dir" "$service_name")
    echo "Current Count: $current_count"

    if [ "$current_count" -lt "$target_count" ]; then
        local need_deploy=$((target_count - current_count))
        echo "Action: Scale-out"
        echo "New instances to deploy: $need_deploy"
        echo "Instance range: $current_count to $((target_count - 1))"
    elif [ "$current_count" -gt "$target_count" ]; then
        local need_remove=$((current_count - target_count))
        echo "Action: Scale-in"
        echo "Instances to remove: $need_remove"
        echo "Remove instances: $target_count to $((current_count - 1))"
    else
        echo "Action: Update deployment"
        echo "All $target_count instances will be updated"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 4 ]; then
        echo "Usage: manage_scaling.sh <target_count> <env_file> <service_base_dir> <service_name> [mode] [dry_run]"
        echo ""
        echo "Modes:"
        echo "  smart: Auto-determine scaling direction (default)"
        echo "  out: Force scale-out"
        echo "  in: Force scale-in"
        echo "  update: Update existing instances"
        echo "  preview: Show scaling preview"
        echo ""
        echo "Examples:"
        echo "  manage_scaling.sh 5 server1.env /deploy/services myapp smart [true|false]"
        echo "  manage_scaling.sh 3 server1.env /deploy/services myapp in [true|false]"
        echo "  manage_scaling.sh 5 server1.env /deploy/services myapp preview"
        exit 1
    fi

    local target_count="$1"
    local env_file="$2"
    local service_base_dir="$3"
    local service_name="$4"
    local mode="${5:-smart}"
    local dry_run="${6:-false}"

    case "$mode" in
        "smart")
            execute_smart_scaling "$target_count" "$env_file" "$service_base_dir" "$service_name" "$dry_run"
            ;;
        "out")
            execute_scale_out "$target_count" "$env_file" "$service_base_dir" "$service_name" "$dry_run"
            ;;
        "in")
            execute_scale_in "$target_count" "$env_file" "$service_base_dir" "$service_name" "$dry_run"
            ;;
        "update")
            if [ "$dry_run" = "true" ]; then
                log_info "[DRY RUN] Would execute update deployment for $target_count instances"
            else
                execute_update_deployment "$target_count" "$env_file" "$service_base_dir" "$service_name"
            fi
            ;;
        "preview")
            show_scaling_preview "$target_count" "$env_file" "$service_base_dir" "$service_name"
            ;;
        *)
            error_exit "Invalid mode: $mode. Use: smart, out, in, update, preview"
            ;;
    esac
fi