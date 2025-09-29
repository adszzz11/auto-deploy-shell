#!/bin/bash
set -euo pipefail

# 커스텀 테스트 실행 함수
run_custom_tests() {
    local port="$1"

    echo "Running custom tests for port $port..."

    # 여기에 사용자 정의 테스트들을 추가할 수 있습니다.
    # 각 테스트는 성공시 0, 실패시 1을 반환해야 합니다.

    # 예시: 특정 API 엔드포인트 테스트
    run_api_endpoint_test() {
        local test_port="$1"
        local endpoint="/api/v1/global/commoncode/TX_DVCD/WDL"

        echo "Custom API test: $endpoint"
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$test_port$endpoint" 2>/dev/null || echo "000")

        if [ "$status" -eq 200 ]; then
            echo "✅ Custom API test passed"
            return 0
        else
            echo "❌ Custom API test failed (Status: $status)"
            return 1
        fi
    }

    # 예시: 헬스체크 엔드포인트 테스트
    run_health_check_test() {
        local test_port="$1"
        local endpoint="/actuator/health"

        echo "Health check test: $endpoint"
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$test_port$endpoint" 2>/dev/null || echo "000")

        if [ "$status" -eq 200 ] || [ "$status" -eq 404 ]; then
            echo "✅ Health check accessible (Status: $status)"
            return 0
        else
            echo "❌ Health check failed (Status: $status)"
            return 1
        fi
    }

    local test_failed=0

    # 커스텀 테스트 실행
    if ! run_api_endpoint_test "$port"; then
        ((test_failed++))
    fi

    if ! run_health_check_test "$port"; then
        ((test_failed++))
    fi

    # 추가 커스텀 테스트들을 여기에 추가...

    if [ "$test_failed" -eq 0 ]; then
        echo "✅ All custom tests passed"
        return 0
    else
        echo "❌ $test_failed custom test(s) failed"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: run_custom_tests.sh <port>"
        exit 1
    fi
    run_custom_tests "$1"
fi