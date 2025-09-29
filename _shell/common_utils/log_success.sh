#!/bin/bash
set -euo pipefail

# current_timestamp 함수 import
source "$(dirname "$0")/current_timestamp.sh"

# 성공 출력용 함수
log_success() {
    local message="$1"
    echo "[SUCCESS] $(current_timestamp) - $message"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: log_success.sh <message>"
        exit 1
    fi
    log_success "$1"
fi