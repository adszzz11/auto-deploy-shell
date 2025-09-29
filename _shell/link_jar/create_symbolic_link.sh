#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 심볼릭 링크 생성 함수
create_symbolic_link() {
    local jar_path="$1"
    local target_link="$2"

    # 심볼릭 링크 생성
    if ln -s "$jar_path" "$target_link"; then
        log_success "Symbolic link created: $target_link -> $jar_path"
    else
        error_exit "Failed to create symbolic link from $target_link to $jar_path"
    fi

    # 생성된 링크 검증
    if [ -L "$target_link" ] && [ -e "$target_link" ]; then
        log_info "Symbolic link verification passed"
    else
        error_exit "Symbolic link verification failed: $target_link"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: create_symbolic_link.sh <jar_path> <target_link_path>"
        exit 1
    fi
    create_symbolic_link "$1" "$2"
fi