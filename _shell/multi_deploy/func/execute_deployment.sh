#!/bin/bash
set -euo pipefail


# 다중 배포 실행
execute_multi_deployment() {
    local target_count="$1"
    local env_file="$2"
    local script_dir="$3"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Starting multi-deployment for $target_count instances"

    local successful_instances=()
    local auto_rollback="${MULTI_DEPLOY_AUTO_ROLLBACK:-true}"
    local wait_time="${MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS:-2}"

    # deploy_control.sh 경로
    local deploy_script="${script_dir}/../deploy/deploy_control.sh"

    if [ ! -x "$deploy_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - deploy_control.sh not found or not executable: $deploy_script" >&2
        return 1
    fi

    # 각 인스턴스 배포
    for (( i=0; i<target_count; i++ )); do
        echo "==================================================[ Instance $i ]=="
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Deploying instance $i"

        if "$deploy_script" deploy "$i" "$env_file"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance $i deployed successfully"
            successful_instances+=("$i")

            # 다음 배포 전 대기
            if [ "$i" -lt $((target_count - 1)) ] && [ "$wait_time" -gt 0 ]; then
                echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Waiting ${wait_time}s before next deployment"
                sleep "$wait_time"
            fi
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Deployment failed for instance $i" >&2

            if [ "$auto_rollback" = "true" ]; then
                echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Initiating rollback for all successfully deployed instances"
                rollback_successful_instances "${successful_instances[@]}" "$env_file" "$script_dir"
            fi

            return 1
        fi
    done

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Multi-deployment completed successfully"
    return 0
}

# 성공한 인스턴스 롤백
rollback_successful_instances() {
    local -a instances=("${@:1:$#-2}")  # 마지막 2개 인자 제외
    local env_file="${@:$#-1:1}"        # 끝에서 두 번째 인자
    local script_dir="${@:$#}"          # 마지막 인자

    if [ ${#instances[@]} -eq 0 ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No instances to rollback"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Rolling back ${#instances[@]} instances: ${instances[*]}"

    # rollback_control.sh 사용
    local rollback_script="${script_dir}/../rollback/rollback_control.sh"

    if [ ! -x "$rollback_script" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - rollback_control.sh not found, using fallback method"
        rollback_instances_fallback "${instances[@]}" "$env_file" "$script_dir"
        return $?
    fi

    # 각 인스턴스 롤백 실행
    for instance in "${instances[@]}"; do
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Rolling back instance $instance"

        if "$rollback_script" rollback "$instance" "$env_file"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance $instance rolled back successfully"
        else
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to rollback instance $instance"
        fi
    done
}

# 롤백 폴백 방식 (rollback_control.sh 없는 경우)
rollback_instances_fallback() {
    local -a instances=("${@:1:$#-2}")
    local env_file="${@:$#-1:1}"
    local script_dir="${@:$#}"

    for instance in "${instances[@]}"; do
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Fallback rollback for instance $instance"

        # 환경 변수 로드
        source "$env_file"

        local instance_dir="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance}"
        local current_jar="${instance_dir}/current.jar"
        local backup_jar="${current_jar}.bak"

        if [ -f "$backup_jar" ]; then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Restoring JAR backup for instance $instance"
            mv "$backup_jar" "$current_jar" || {
                echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to restore backup for instance $instance"
                continue
            }

            # 애플리케이션 재시작
            local run_app_script="${script_dir}/../run_app/run_app_control.sh"
            if [ -x "$run_app_script" ]; then
                local port="${BASE_PORT}${instance}"
                (cd "$instance_dir" && "$run_app_script" restart "$port") || {
                    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to restart instance $instance after rollback"
                }
            fi
        else
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - No backup found for instance $instance"
        fi
    done
}

# 인스턴스 제거 (스케일 다운)
remove_excess_instances() {
    local current_count="$1"
    local target_count="$2"
    local env_file="$3"
    local script_dir="$4"

    if [ "$current_count" -le "$target_count" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No excess instances to remove"
        return 0
    fi

    local scale_in_reverse="${MULTI_DEPLOY_SCALE_IN_REVERSE:-true}"
    local remove_count=$((current_count - target_count))

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Scaling in: Removing $remove_count excess instances"

    local deploy_script="${script_dir}/../deploy/deploy_control.sh"

    if [ ! -x "$deploy_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - deploy_control.sh not found: $deploy_script" >&2
        return 1
    fi

    # 제거할 인스턴스 번호 결정
    local instances_to_remove=()
    if [ "$scale_in_reverse" = "true" ]; then
        # 역순으로 제거 (큰 번호부터)
        for (( i=current_count-1; i>=target_count; i-- )); do
            instances_to_remove+=("$i")
        done
    else
        # 순차적으로 제거
        for (( i=target_count; i<current_count; i++ )); do
            instances_to_remove+=("$i")
        done
    fi

    # 인스턴스 제거 실행
    for instance in "${instances_to_remove[@]}"; do
        echo "==================================================[ Remove Instance $instance ]=="
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Removing instance $instance"

        "$deploy_script" remove "$instance" "$env_file" || {
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Failed to remove instance $instance"
        }
    done

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Scale-in completed"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: execute_deployment.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  deploy <target_count> <env_file> <script_dir>                           - Execute multi-deployment"
        echo "  remove <current_count> <target_count> <env_file> <script_dir>           - Remove excess instances"
        echo "  rollback <instance1> <instance2> ... <env_file> <script_dir>            - Rollback instances"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        deploy)
            execute_multi_deployment "$@"
            ;;
        remove)
            remove_excess_instances "$@"
            ;;
        rollback)
            rollback_successful_instances "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
