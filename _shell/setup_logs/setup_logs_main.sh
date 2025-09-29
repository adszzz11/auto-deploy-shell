#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common_utils/common_utils.sh"

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_logs_parameters.sh"
source "${SCRIPT_DIR}/calculate_log_paths.sh"
source "${SCRIPT_DIR}/create_log_directories.sh"
source "${SCRIPT_DIR}/remove_existing_log_link.sh"
source "${SCRIPT_DIR}/create_log_symbolic_link.sh"

# 메인 로그 설정 함수
setup_logs_main() {
    # 사용법: setup_logs_main <service_name> <instance_num> <instance_dir> <log_base_dir>
    if [ "$#" -ne 4 ]; then
        echo "Usage: setup_logs_main <service_name> <instance_num> <instance_dir> <log_base_dir>"
        exit 1
    fi

    local service_name="$1"
    local instance_num="$2"
    local instance_dir="$3"
    local log_base_dir="$4"

    log_info "Starting log setup for service: $service_name, instance: $instance_num"

    # 1. 파라미터 검증
    validate_logs_parameters "$service_name" "$instance_num" "$instance_dir" "$log_base_dir"

    # 2. 로그 경로 계산
    local log_source_dir
    local log_link
    log_source_dir=$(get_log_source_dir "$service_name" "$instance_num" "$log_base_dir")
    log_link=$(get_log_link_path "$instance_dir")

    # 3. 로그 디렉터리 생성
    create_log_directories "$log_source_dir"

    # 4. 기존 로그 링크/파일 제거
    remove_existing_log_link "$log_link"

    # 5. 새 심볼릭 링크 생성 및 검증
    create_and_verify_log_link "$log_source_dir" "$log_link"

    log_success "Log setup completed successfully for service: $service_name, instance: $instance_num"
}

# 로그 설정 상태 확인 함수
check_logs_status() {
    local service_name="$1"
    local instance_num="$2"
    local instance_dir="$3"
    local log_base_dir="$4"

    echo "=== Log Setup Status ==="

    local log_source_dir
    local log_link
    log_source_dir=$(get_log_source_dir "$service_name" "$instance_num" "$log_base_dir")
    log_link=$(get_log_link_path "$instance_dir")

    echo "Service: $service_name"
    echo "Instance: $instance_num"
    echo "Log Source Directory: $log_source_dir"
    echo "Log Link: $log_link"

    # 로그 소스 디렉터리 상태 확인
    if [ -d "$log_source_dir" ]; then
        echo "✅ Log source directory exists"
    else
        echo "❌ Log source directory does not exist"
    fi

    # 로그 링크 상태 확인
    local link_status
    link_status=$(check_existing_log_link "$log_link")

    case "$link_status" in
        "symlink")
            local target
            target=$(readlink "$log_link" 2>/dev/null || echo "unknown")
            if [ "$target" = "$log_source_dir" ]; then
                echo "✅ Log symbolic link is correctly configured"
            else
                echo "❌ Log symbolic link points to wrong target: $target"
            fi
            ;;
        "file")
            echo "❌ Log link path exists but is not a symbolic link"
            ;;
        "none")
            echo "❌ Log symbolic link does not exist"
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${5:-setup}" in
        "setup")
            setup_logs_main "$1" "$2" "$3" "$4"
            ;;
        "check")
            check_logs_status "$1" "$2" "$3" "$4"
            ;;
        *)
            echo "Usage: setup_logs_main.sh <service_name> <instance_num> <instance_dir> <log_base_dir> [setup|check]"
            echo "  setup: Configure log directories and symbolic links (default)"
            echo "  check: Check current log setup status"
            exit 1
            ;;
    esac
fi