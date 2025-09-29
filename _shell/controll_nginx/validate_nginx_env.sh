#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# Nginx 환경 검증 함수
validate_nginx_env() {
    local upstream_conf="$1"

    # Nginx 설정 파일 존재 확인
    if [ ! -f "$upstream_conf" ]; then
        error_exit "Upstream configuration not found: $upstream_conf"
    fi

    # Nginx 명령어 존재 확인
    if ! command -v nginx &>/dev/null; then
        error_exit "nginx command not found. Please install nginx"
    fi

    log_info "Nginx environment validated: config file exists, nginx command available"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: validate_nginx_env.sh <upstream_conf>"
        exit 1
    fi
    validate_nginx_env "$1"
fi