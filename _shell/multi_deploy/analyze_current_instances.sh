#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 현재 배포된 인스턴스 분석 함수
analyze_current_instances() {
    local service_base_dir="$1"
    local service_name="$2"

    local service_instances_dir="${service_base_dir}/${service_name}/instances"
    local current_instances=()

    log_info "Analyzing current instances in: $service_instances_dir"

    if [ -d "$service_instances_dir" ]; then
        # 인스턴스 디렉터리 스캔
        for d in "$service_instances_dir"/*; do
            if [ -d "$d" ]; then
                local instance_num
                instance_num=$(basename "$d")

                # 숫자로만 구성된 디렉터리명인지 확인
                if [[ "$instance_num" =~ ^[0-9]+$ ]]; then
                    current_instances+=("$instance_num")
                    log_info "Found instance: $instance_num"
                fi
            fi
        done
    else
        log_info "Service instances directory does not exist: $service_instances_dir"
    fi

    # 결과 출력 (공백으로 구분)
    printf '%s\n' "${current_instances[@]}" | sort -n | tr '\n' ' '
    echo  # 마지막 줄바꿈
}

# 현재 인스턴스 수 계산 함수
calculate_current_instance_count() {
    local service_base_dir="$1"
    local service_name="$2"

    local instances_str
    instances_str=$(analyze_current_instances "$service_base_dir" "$service_name")

    if [ -z "$instances_str" ] || [ "$instances_str" = " " ]; then
        echo "0"
        return 0
    fi

    # 공백으로 구분된 인스턴스 번호들을 배열로 변환
    local instances_array=($instances_str)

    if [ "${#instances_array[@]}" -eq 0 ]; then
        echo "0"
        return 0
    fi

    # 정렬된 배열에서 최대 인스턴스 번호 추출
    local sorted_instances=($(printf '%s\n' "${instances_array[@]}" | sort -n))
    local max_instance=${sorted_instances[${#sorted_instances[@]}-1]}
    local current_count=$((max_instance + 1))

    log_info "Current instance count: $current_count (max instance: $max_instance)"
    echo "$current_count"
}

# 인스턴스 상태 정보 출력 함수
show_instance_status() {
    local service_base_dir="$1"
    local service_name="$2"
    local target_count="$3"

    echo "=== Instance Status Analysis ==="
    echo "Service: $service_name"
    echo "Service Base Dir: $service_base_dir"
    echo "Target Instance Count: $target_count"

    local instances_str
    instances_str=$(analyze_current_instances "$service_base_dir" "$service_name")

    if [ -z "$instances_str" ] || [ "$instances_str" = " " ]; then
        echo "Current Instances: None"
        echo "Current Count: 0"
        echo "Action Required: Deploy $target_count new instances"
    else
        local instances_array=($instances_str)
        echo "Current Instances: ${instances_array[*]}"

        local current_count
        current_count=$(calculate_current_instance_count "$service_base_dir" "$service_name")
        echo "Current Count: $current_count"

        # 액션 결정
        if [ "$current_count" -lt "$target_count" ]; then
            local need_deploy=$((target_count - current_count))
            echo "Action Required: Scale out - Deploy $need_deploy additional instances"
        elif [ "$current_count" -gt "$target_count" ]; then
            local need_remove=$((current_count - target_count))
            echo "Action Required: Scale in - Remove $need_remove excess instances"
        else
            echo "Action Required: Update all $current_count instances"
        fi
    fi
}

# 인스턴스 디렉터리 유효성 검증 함수
validate_instance_directories() {
    local service_base_dir="$1"
    local service_name="$2"

    local service_instances_dir="${service_base_dir}/${service_name}/instances"

    log_info "Validating instance directories"

    # 서비스 베이스 디렉터리 확인
    if [ ! -d "$service_base_dir" ]; then
        error_exit "Service base directory not found: $service_base_dir"
    fi

    # 서비스 디렉터리 확인 (없으면 생성)
    local service_dir="${service_base_dir}/${service_name}"
    if [ ! -d "$service_dir" ]; then
        log_info "Creating service directory: $service_dir"
        mkdir -p "$service_dir" || error_exit "Failed to create service directory: $service_dir"
    fi

    # 인스턴스 디렉터리 확인 (없으면 생성)
    if [ ! -d "$service_instances_dir" ]; then
        log_info "Creating instances directory: $service_instances_dir"
        mkdir -p "$service_instances_dir" || error_exit "Failed to create instances directory: $service_instances_dir"
    fi

    log_success "Instance directories validated"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: analyze_current_instances.sh <service_base_dir> <service_name> [status|count|validate] [target_count]"
        echo "  (default): List current instances"
        echo "  status: Show detailed status with target count"
        echo "  count: Calculate current instance count"
        echo "  validate: Validate and create directories"
        exit 1
    fi

    case "${3:-default}" in
        "status")
            show_instance_status "$1" "$2" "${4:-0}"
            ;;
        "count")
            calculate_current_instance_count "$1" "$2"
            ;;
        "validate")
            validate_instance_directories "$1" "$2"
            ;;
        *)
            analyze_current_instances "$1" "$2"
            ;;
    esac
fi