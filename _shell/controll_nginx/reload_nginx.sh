#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# Nginx 리로드 함수
reload_nginx() {
    log_info "Reloading nginx configuration"

    if nginx -s reload; then
        log_success "Nginx configuration reloaded successfully"
    else
        error_exit "nginx reload failed"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    reload_nginx
fi