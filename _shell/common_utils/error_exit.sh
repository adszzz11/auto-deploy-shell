#!/bin/bash
set -euo pipefail

# current_timestamp 함수 import
source "$(dirname "$0")/current_timestamp.sh"

# 에러 출력 후 종료 함수
error_exit() {
    local message="$1"
    echo "[ERROR] $(current_timestamp) - $message" >&2
    exit 1
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: error_exit.sh <message>"
        exit 1
    fi
    error_exit "$1"
fi