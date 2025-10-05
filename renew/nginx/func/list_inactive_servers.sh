#!/bin/bash
set -euo pipefail

# 비활성화된 (주석 처리된) 서버 목록 출력
list_inactive_servers() {
    local upstream_conf="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Listing inactive servers"

    if [ ! -f "$upstream_conf" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Configuration file not found: $upstream_conf"
        return 1
    fi

    echo "Inactive servers:"
    grep "^[[:space:]]*#[[:space:]]*server" "$upstream_conf" || echo "  (none)"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: list_inactive_servers.sh <upstream_conf>"
        exit 1
    fi
    list_inactive_servers "$1"
fi
