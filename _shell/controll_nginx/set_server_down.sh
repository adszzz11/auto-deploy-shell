#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 서버를 DOWN 상태로 설정하는 함수 (주석 처리)
set_server_down() {
    local port="$1"
    local upstream_conf="$2"

    log_info "Setting server on port $port to DOWN state"

    # 해당 포트의 서버 라인을 주석 처리
    if sed -i "/^[[:space:]]*server.*:$port/ s/^/# /" "$upstream_conf"; then
        log_success "Server on port $port set to DOWN (commented out)"
    else
        error_exit "Failed to set port $port DOWN"
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: set_server_down.sh <port> <upstream_conf>"
        exit 1
    fi
    set_server_down "$1" "$2"
fi