#!/bin/bash
set -euo pipefail

# 테스트 결과 평가 함수
evaluate_test_results() {
    local fail_count="${FAIL:-0}"

    echo "================================================================"
    echo "Test Results Summary:"

    if [ "$fail_count" -eq 0 ]; then
        echo "✅ All tests passed."
        echo "Status: SUCCESS"
        return 0
    else
        echo "❌ Some tests failed. (Failed tests: $fail_count)"
        echo "Status: FAILURE"
        return 1
    fi
}

# 테스트 실패 카운트 증가 함수
increment_fail_count() {
    export FAIL=$((FAIL + 1))
    echo "⚠️ Test failure recorded. Total failures: $FAIL"
}

# 테스트 성공 로깅 함수
log_test_success() {
    local test_name="$1"
    echo "✅ $test_name: PASSED"
}

# 테스트 실패 로깅 함수
log_test_failure() {
    local test_name="$1"
    echo "❌ $test_name: FAILED"
    increment_fail_count
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # FAIL 변수가 설정되지 않은 경우 기본값 설정
    export FAIL=${FAIL:-0}
    evaluate_test_results
fi