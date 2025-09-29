#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 로그 경로 계산 함수
calculate_log_paths() {
    local service_name="$1"
    local instance_num="$2"
    local instance_dir="$3"
    local log_base_dir="$4"

    # 로그 소스 디렉터리 경로 계산
    local log_source_dir="${log_base_dir}/${service_name}/instances/${instance_num}"

    # 로그 링크 경로 계산
    local log_link="${instance_dir}/logs"

    log_info "Calculated log paths:"
    log_info "  Source directory: $log_source_dir"
    log_info "  Link path: $log_link"

    # 계산된 경로들을 반환 (공백으로 구분)
    echo "$log_source_dir|$log_link"
}

# 로그 소스 디렉터리 경로만 반환하는 함수
get_log_source_dir() {
    local service_name="$1"
    local instance_num="$2"
    local log_base_dir="$3"

    echo "${log_base_dir}/${service_name}/instances/${instance_num}"
}

# 로그 링크 경로만 반환하는 함수
get_log_link_path() {
    local instance_dir="$1"

    echo "${instance_dir}/logs"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 4 ]; then
        echo "Usage: calculate_log_paths.sh <service_name> <instance_num> <instance_dir> <log_base_dir>"
        exit 1
    fi
    calculate_log_paths "$1" "$2" "$3" "$4"
fi