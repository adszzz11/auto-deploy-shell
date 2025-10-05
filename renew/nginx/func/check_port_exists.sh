#!/bin/bash
set -euo pipefail

# 특정 포트가 설정 파일에 이미 존재하는지 확인
check_port_exists() {
    local port="$1"
    local upstream_conf="$2"

    if grep -q "server.*:$port" "$upstream_conf"; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Port $port exists in configuration"
        return 0
    else
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Port $port does NOT exist in configuration"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: check_port_exists.sh <port> <upstream_conf>"
        exit 1
    fi
    check_port_exists "$1" "$2"
fi
