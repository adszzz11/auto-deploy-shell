#!/bin/bash
set -euo pipefail

# Nginx 설정 파일의 문법 검증
test_nginx_config() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Testing nginx configuration"

    if nginx -t 2>&1; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Nginx configuration test passed"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Nginx configuration test failed"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_nginx_config
fi
