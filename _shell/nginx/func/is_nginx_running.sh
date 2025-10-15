#!/bin/bash
set -euo pipefail

# Nginx 프로세스가 실행 중인지 확인
is_nginx_running() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Checking if nginx is running" >&2

    # nginx 명령어 존재 여부 확인
    if ! command -v nginx &>/dev/null; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - nginx command not found" >&2
        return 1
    fi

    # nginx 프로세스 확인
    if pgrep nginx >/dev/null 2>&1; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Nginx is running" >&2
        return 0
    else
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Nginx is NOT running" >&2
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    is_nginx_running
fi
