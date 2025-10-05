#!/bin/bash
set -euo pipefail

# Nginx 설정을 재로드하여 변경사항 적용
reload_nginx() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Reloading nginx configuration"

    if nginx -s reload 2>&1; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Nginx reloaded successfully"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Nginx reload failed"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    reload_nginx
fi
