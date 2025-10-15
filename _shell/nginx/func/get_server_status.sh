#!/bin/bash
set -euo pipefail

# 특정 포트의 현재 상태 조회 (active/inactive/not_found)
get_server_status() {
    local port="$1"
    local upstream_conf="$2"

    if [ ! -f "$upstream_conf" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Configuration file not found: $upstream_conf" >&2
        return 1
    fi

    # 활성 상태 확인 (주석 없이 존재)
    if grep "^[[:space:]]*server.*:$port" "$upstream_conf" | grep -v "^#" > /dev/null 2>&1; then
        echo "active"
        return 0
    fi

    # 비활성 상태 확인 (주석 처리됨)
    if grep "^[[:space:]]*#[[:space:]]*server.*:$port" "$upstream_conf" > /dev/null 2>&1; then
        echo "inactive"
        return 0
    fi

    # 설정에 없음
    echo "not_found"
    return 1
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: get_server_status.sh <port> <upstream_conf>"
        exit 1
    fi
    status=$(get_server_status "$1" "$2")
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Port $1 status: $status" >&2
fi
