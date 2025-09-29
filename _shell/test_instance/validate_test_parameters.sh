#!/bin/bash
set -euo pipefail

# 테스트 파라미터 유효성 검사 함수
validate_test_parameters() {
    local port="$1"

    # 파라미터 개수 검증
    if [ "$#" -ne 1 ]; then
        echo "Usage: validate_test_parameters <port>"
        exit 1
    fi

    # 포트 번호 유효성 검증
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "❌ Invalid port number: $port. Port must be between 1-65535"
        exit 1
    fi

    echo "✅ Port is valid: $port"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: validate_test_parameters.sh <port>"
        exit 1
    fi
    validate_test_parameters "$1"
fi