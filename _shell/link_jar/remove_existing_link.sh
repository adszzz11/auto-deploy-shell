#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 기존 링크/파일 제거 함수
remove_existing_link() {
    local target_link="$1"

    # 기존 심볼릭 링크 또는 파일이 존재하는지 확인
    if [ -L "$target_link" ] || [ -e "$target_link" ]; then
        log_warn "Removing existing link/file at $target_link"

        if rm -f "$target_link"; then
            log_success "Successfully removed existing link/file at $target_link"
        else
            error_exit "Failed to remove existing link/file at $target_link"
        fi
    else
        log_info "No existing link/file found at $target_link"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: remove_existing_link.sh <target_link_path>"
        exit 1
    fi
    remove_existing_link "$1"
fi