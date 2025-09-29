#!/bin/bash
set -euo pipefail

# current_timestamp 함수 import
source "$(dirname "$0")/current_timestamp.sh"

# 경고 출력용 함수
log_warn() {
    local message="$1"
    echo "[WARN] $(current_timestamp) - $message"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: log_warn.sh <message>"
        exit 1
    fi
    log_warn "$1"
fi