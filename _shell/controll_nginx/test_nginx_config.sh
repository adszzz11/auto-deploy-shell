#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# Nginx 설정 문법 검증 함수
test_nginx_config() {
    log_info "Testing nginx configuration syntax"

    if nginx -t 2>/dev/null; then
        log_success "Nginx configuration syntax is valid"
    else
        error_exit "Nginx configuration test failed. Please check your configuration"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_nginx_config
fi