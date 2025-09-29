#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 서버를 UP 상태로 설정하는 함수 (주석 제거 및 새 서버 추가)
set_server_up() {
    local port="$1"
    local upstream_conf="$2"

    log_info "Setting server on port $port to UP state"

    # 해당 포트가 설정에 존재하는지 확인
    if ! grep -q "server.*:$port" "$upstream_conf"; then
        log_info "Adding new server for port $port"
        # 새 서버 추가 (upstream 블록의 } 앞에 추가)
        if sed -i "/^[[:space:]]*}/ i\    server 127.0.0.1:$port;" "$upstream_conf"; then
            log_success "New server added for port $port"
        else
            error_exit "Failed to add new server for port $port"
        fi
    else
        # 기존 주석 처리된 서버 라인의 주석 제거
        if sed -i "/^[[:space:]]*#[[:space:]]*server.*:$port/ s/^# //" "$upstream_conf"; then
            log_success "Server on port $port uncommented (set to UP)"
        fi
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: set_server_up.sh <port> <upstream_conf>"
        exit 1
    fi
    set_server_up "$1" "$2"
fi