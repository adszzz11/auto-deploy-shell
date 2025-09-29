#!/bin/bash
set -euo pipefail

# HTTP 상태 코드 테스트 함수
test_http_status() {
    local port="$1"
    local endpoint="${2:-/api/v1/global/commoncode/TX_DVCD/WDL}"
    local expected_status="${3:-200}"

    echo "Testing HTTP status for port $port on endpoint $endpoint"

    # HTTP 상태 코드 확인
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$endpoint" 2>/dev/null || echo "000")

    if [ "$http_status" -eq "$expected_status" ]; then
        echo "✅ HTTP test passed: Received $expected_status OK"
        return 0
    else
        echo "❌ HTTP test failed: Expected $expected_status but got $http_status"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: test_http_status.sh <port> [endpoint] [expected_status]"
        echo "Example: test_http_status.sh 8080"
        echo "Example: test_http_status.sh 8080 /health 200"
        exit 1
    fi

    test_http_status "$@"
fi