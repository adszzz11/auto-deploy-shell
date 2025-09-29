#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 기존 로그 링크/파일 제거 함수
remove_existing_log_link() {
    local log_link="$1"

    # 기존 심볼릭 링크 또는 파일이 존재하는지 확인
    if [ -L "$log_link" ]; then
        log_warn "Removing existing symbolic link at $log_link"
        if rm -f "$log_link"; then
            log_success "Successfully removed existing symbolic link at $log_link"
        else
            error_exit "Failed to remove existing symbolic link at $log_link"
        fi
    elif [ -e "$log_link" ]; then
        log_warn "Removing existing file/directory at $log_link"
        if rm -rf "$log_link"; then
            log_success "Successfully removed existing file/directory at $log_link"
        else
            error_exit "Failed to remove existing file/directory at $log_link"
        fi
    else
        log_info "No existing link/file found at $log_link"
    fi
}

# 기존 링크 존재 여부 확인 함수
check_existing_log_link() {
    local log_link="$1"

    if [ -L "$log_link" ]; then
        echo "symlink"
    elif [ -e "$log_link" ]; then
        echo "file"
    else
        echo "none"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: remove_existing_log_link.sh <log_link_path>"
        exit 1
    fi
    remove_existing_log_link "$1"
fi