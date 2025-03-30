#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/_shell/common_utils.sh"

# 인자 개수 체크: 첫 번째 인자는 2 이상이어야 하고, 두 번째 인자는 환경 파일
if [ "$#" -ne 2 ]; then
    echo "Usage: multi_deploy.sh <target_instance_count> <env_file>"
    exit 1
fi

TARGET_COUNT="$1"
ENV_FILE_RAW="$2"

# 첫 번째 인자 (인스턴스 갯수)가 2 미만이거나 10 이상일 경우 종료
if [ "$TARGET_COUNT" -lt 2 ] || [ "$TARGET_COUNT" -gt 10 ]; then
    echo "Error: You must specify at least 2 instances and at most 10 instances to deploy."
    exit 1
fi

# 환경 파일 이름에 포함된 CR(\r) 제거
ENV_FILE="$(echo "$ENV_FILE_RAW" | tr -d '\r')"

echo "=================================================="
echo "Multi Deployment for service: $(basename "$ENV_FILE")"
echo "Target instance count: ${TARGET_COUNT}"
echo "Using environment file: ${ENV_FILE}"
echo "=================================================="

if [ ! -f "$ENV_FILE" ]; then
    error_exit "Environment file $ENV_FILE not found."
fi

source "$ENV_FILE"

SERVICE_INSTANCES_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances"
current_instances=()
if [ -d "$SERVICE_INSTANCES_DIR" ]; then
    for d in "$SERVICE_INSTANCES_DIR"/*; do
        if [ -d "$d" ]; then
            instance_num=$(basename "$d")
            if [[ "$instance_num" =~ ^[0-9]+$ ]]; then
                current_instances+=("$instance_num")
            fi
        fi
    done
fi

if [ "${#current_instances[@]}" -gt 0 ]; then
    # 정렬 로직 개선: 배열의 마지막 원소를 직접 계산
    sorted_instances=($(printf '%s\n' "${current_instances[@]}" | sort -n))
    max_instance=${sorted_instances[${#sorted_instances[@]}-1]}
    CURRENT_COUNT=$((max_instance + 1))
else
    CURRENT_COUNT=0
fi

log_info "Current deployed instance count: ${CURRENT_COUNT}"
log_info "Target instance count: ${TARGET_COUNT}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SCRIPT_DIR

rollback_instance() {
    local instance_num="$1"
    log_info "Rolling back instance $instance_num..."
    if ./_shell/rollback.sh "$instance_num" "$ENV_FILE"; then
        log_info "Rollback succeeded for instance $instance_num."
    else
        log_warn "Rollback failed for instance $instance_num."
    fi
}

successful_instances=()

# 1. 대상 인스턴스 (0 ~ TARGET-1)는 항상 deploy(업데이트) 동작으로 반영
for (( i=0; i<TARGET_COUNT; i++ )); do
    echo "--------------------------------------------------"
    log_info "Updating/Deploying instance number: $i"
    if ./_shell/deploy.sh "$i" "$ENV_FILE" "deploy"; then
        log_info "Instance $i updated/deployed successfully."
        successful_instances+=("$i")
    else
        log_warn "Deployment failed for instance $i."
        log_warn "Initiating rollback for all successfully updated instances..."
        for instance in "${successful_instances[@]}"; do
            rollback_instance "$instance"
        done
        rollback_instance "$i"
        error_exit "Aborting further deployments due to failure in instance $i."
    fi
done

# 2. 현재 인스턴스 수가 TARGET보다 크면, TARGET 이상의 인스턴스는 제거
if [ "$CURRENT_COUNT" -gt "$TARGET_COUNT" ]; then
    log_info "Scaling in: Removing excess instances..."
    sorted_instances=($(printf '%s\n' "${current_instances[@]}" | sort -n))
    for instance in "${sorted_instances[@]}"; do
        if [ "$instance" -ge "$TARGET_COUNT" ]; then
            echo "--------------------------------------------------"
            log_info "Removing instance number: $instance"
            ./_shell/deploy.sh "$instance" "$ENV_FILE" "remove"
        fi
    done
fi

echo "--------------------------------------------------"
log_info "Multi Deployment complete."
exit 0
