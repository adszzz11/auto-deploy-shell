#!/bin/bash
set -euo pipefail

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/..") && pwd)"
if [ -f "${SCRIPT_DIR}/multi_deploy.env" ]; then
    source "${SCRIPT_DIR}/multi_deploy.env"
fi

# 현재 배포된 인스턴스 분석
analyze_current_instances() {
    local service_base_dir="$1"
    local service_name="$2"

    local service_instances_dir="${service_base_dir}/${service_name}/instances"
    local current_instances=()

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Analyzing current instances in: $service_instances_dir" >&2

    if [ -d "$service_instances_dir" ]; then
        # 인스턴스 디렉터리 스캔
        for d in "$service_instances_dir"/*; do
            if [ -d "$d" ]; then
                local instance_num
                instance_num=$(basename "$d")

                # 숫자로만 구성된 디렉터리명인지 확인
                if [[ "$instance_num" =~ ^[0-9]+$ ]]; then
                    current_instances+=("$instance_num")
                fi
            fi
        done
    fi

    # 결과 출력 (공백으로 구분, 정렬됨)
    if [ ${#current_instances[@]} -gt 0 ]; then
        printf '%s\n' "${current_instances[@]}" | sort -n | tr '\n' ' '
    fi
    echo  # 마지막 줄바꿈
}

# 현재 인스턴스 수 계산
calculate_current_instance_count() {
    local service_base_dir="$1"
    local service_name="$2"

    local instances_str
    instances_str=$(analyze_current_instances "$service_base_dir" "$service_name" 2>/dev/null)

    # 공백 제거 후 확인
    instances_str=$(echo "$instances_str" | tr -d ' ')

    if [ -z "$instances_str" ]; then
        echo "0"
        return 0
    fi

    # 공백으로 구분된 인스턴스 번호들을 배열로 변환
    local instances_array=($(analyze_current_instances "$service_base_dir" "$service_name" 2>/dev/null))

    if [ "${#instances_array[@]}" -eq 0 ]; then
        echo "0"
        return 0
    fi

    # 정렬된 배열에서 최대 인스턴스 번호 추출
    local sorted_instances=($(printf '%s\n' "${instances_array[@]}" | sort -n))
    local max_instance=${sorted_instances[${#sorted_instances[@]}-1]}
    local current_count=$((max_instance + 1))

    echo "$current_count"
}

# 인스턴스 상태 정보 출력
show_instance_status() {
    local service_base_dir="$1"
    local service_name="$2"
    local target_count="$3"

    echo "=== Instance Status Analysis ==="
    echo "Service: $service_name"
    echo "Service Base Dir: $service_base_dir"
    echo "Target Instance Count: $target_count"

    local instances_str
    instances_str=$(analyze_current_instances "$service_base_dir" "$service_name" 2>/dev/null)

    # 공백 제거 후 확인
    local trimmed_instances=$(echo "$instances_str" | tr -d ' ')

    if [ -z "$trimmed_instances" ]; then
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
    echo ""
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: analyze_instances.sh <command> <service_base_dir> <service_name> [target_count]"
        echo ""
        echo "Commands:"
        echo "  list      - List current instances"
        echo "  count     - Calculate current instance count"
        echo "  status    - Show detailed status (requires target_count)"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        list)
            analyze_current_instances "$@"
            ;;
        count)
            calculate_current_instance_count "$@"
            ;;
        status)
            if [ "$#" -lt 3 ]; then
                echo "Error: 'status' requires <service_base_dir> <service_name> <target_count>"
                exit 1
            fi
            show_instance_status "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
