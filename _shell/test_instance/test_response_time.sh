#!/bin/bash
set -euo pipefail

# 응답 시간 테스트 함수
test_response_time() {
    local port="$1"
    local endpoint="${2:-/api/v1/global/commoncode/TX_DVCD/WDL}"
    local max_time="${3:-5}"  # 기본 5초 제한

    echo "Testing response time for port $port on endpoint $endpoint (max: ${max_time}s)"

    # 응답 시간 측정
    local response_time
    response_time=$(curl -s -o /dev/null -w "%{time_total}" -m "$max_time" "http://localhost:$port$endpoint" 2>/dev/null || echo "99.999")

    # 응답 시간을 정수로 변환하여 비교 (소수점을 1000배하여 정수로 변환)
    local response_time_ms
    response_time_ms=$(echo "$response_time * 1000" | bc 2>/dev/null || echo "99999")
    response_time_ms=${response_time_ms%.*}  # 소수점 제거

    local max_time_ms
    max_time_ms=$(echo "$max_time * 1000" | bc 2>/dev/null || echo "$((max_time * 1000))")
    max_time_ms=${max_time_ms%.*}  # 소수점 제거

    if [ "$response_time_ms" -le "$max_time_ms" ]; then
        echo "✅ Response time test passed: ${response_time}s (within ${max_time}s limit)"
        return 0
    else
        echo "❌ Response time test failed: ${response_time}s (exceeds ${max_time}s limit)"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: test_response_time.sh <port> [endpoint] [max_time_seconds]"
        echo "Example: test_response_time.sh 8080"
        echo "Example: test_response_time.sh 8080 /health 3"
        exit 1
    fi

    test_response_time "$@"
fi