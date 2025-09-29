#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 로그 심볼릭 링크 생성 함수
create_log_symbolic_link() {
    local log_source_dir="$1"
    local log_link="$2"

    log_info "Creating symbolic link for logs: $log_link -> $log_source_dir"

    # 심볼릭 링크 생성
    if ln -s "$log_source_dir" "$log_link"; then
        log_success "Log symbolic link created: $log_link -> $log_source_dir"
    else
        error_exit "Failed to create symbolic link for logs: $log_link -> $log_source_dir"
    fi
}

# 심볼릭 링크 검증 함수
verify_log_symbolic_link() {
    local log_source_dir="$1"
    local log_link="$2"

    log_info "Verifying symbolic link: $log_link"

    # 심볼릭 링크가 존재하는지 확인
    if [ ! -L "$log_link" ]; then
        error_exit "Symbolic link verification failed: $log_link is not a symbolic link"
    fi

    # 심볼릭 링크가 올바른 대상을 가리키는지 확인
    local actual_target
    actual_target=$(readlink "$log_link")

    if [ "$actual_target" != "$log_source_dir" ]; then
        error_exit "Symbolic link verification failed: $log_link points to '$actual_target', expected '$log_source_dir'"
    fi

    # 대상 디렉터리가 실제로 존재하는지 확인
    if [ ! -d "$log_source_dir" ]; then
        error_exit "Symbolic link verification failed: target directory does not exist: $log_source_dir"
    fi

    log_success "Symbolic link verification passed: $log_link -> $log_source_dir"
}

# 전체 링크 생성 및 검증 함수
create_and_verify_log_link() {
    local log_source_dir="$1"
    local log_link="$2"

    # 1. 심볼릭 링크 생성
    create_log_symbolic_link "$log_source_dir" "$log_link"

    # 2. 심볼릭 링크 검증
    verify_log_symbolic_link "$log_source_dir" "$log_link"

    log_success "Log symbolic link created and verified: $log_link -> $log_source_dir"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: create_log_symbolic_link.sh <log_source_dir> <log_link_path>"
        exit 1
    fi
    create_and_verify_log_link "$1" "$2"
fi