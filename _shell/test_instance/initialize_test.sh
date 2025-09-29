#!/bin/bash
set -euo pipefail

# 테스트 초기화 함수
initialize_test() {
    local port="$1"

    echo "Starting tests for instance on port $port..."
    echo "================================================================"

    # FAIL 변수를 전역으로 설정 (0: 성공, 1: 실패)
    export FAIL=0

    echo "Test initialization completed for port $port"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: initialize_test.sh <port>"
        exit 1
    fi
    initialize_test "$1"
fi