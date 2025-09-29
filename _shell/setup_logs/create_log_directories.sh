#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 로그 디렉터리 생성 함수
create_log_directories() {
    local log_source_dir="$1"

    # 로그 소스 디렉터리가 이미 존재하는지 확인
    if [ -d "$log_source_dir" ]; then
        log_info "Log directory already exists: $log_source_dir"
        return 0
    fi

    log_info "Creating log directories at $log_source_dir"

    # 로그 디렉터리 생성 (중간 디렉터리도 함께 생성)
    if mkdir -p "$log_source_dir"; then
        log_success "Log directories created successfully: $log_source_dir"

        # 디렉터리 권한 설정 (필요한 경우)
        chmod 755 "$log_source_dir" || log_warn "Failed to set permissions for $log_source_dir"

        return 0
    else
        error_exit "Failed to create log directories at $log_source_dir"
    fi
}

# 로그 디렉터리 존재 확인 함수
verify_log_directory_exists() {
    local log_source_dir="$1"

    if [ -d "$log_source_dir" ]; then
        log_info "Log directory verified: $log_source_dir"
        return 0
    else
        error_exit "Log directory does not exist: $log_source_dir"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: create_log_directories.sh <log_source_dir>"
        exit 1
    fi
    create_log_directories "$1"
fi