#!/bin/bash
set -euo pipefail

# test_response_time.sh - Response Time Testing

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${SCRIPT_DIR}/test_instance.env" ]; then
    source "${SCRIPT_DIR}/test_instance.env"
fi

# 응답 시간 측정 (curl 사용)
measure_response_time_curl() {
    local url="$1"
    local timeout="$2"
    local method="${TEST_HTTP_METHOD:-GET}"

    # curl time_total 측정 (초 단위)
    local time_seconds
    if ! time_seconds=$(curl -X "$method" -s -o /dev/null -w "%{time_total}" --max-time "$timeout" "$url" 2>/dev/null); then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to measure response time" >&2
        return 1
    fi

    # 초를 밀리초로 변환 (bc 또는 awk 사용)
    local time_ms
    if command -v bc &> /dev/null; then
        time_ms=$(echo "$time_seconds * 1000" | bc | cut -d. -f1)
    else
        time_ms=$(awk "BEGIN {printf \"%.0f\", $time_seconds * 1000}")
    fi

    echo "$time_ms"
    return 0
}

# 응답 시간 측정 (time 명령 사용 - 폴백)
measure_response_time_fallback() {
    local url="$1"
    local timeout="$2"
    local method="${TEST_HTTP_METHOD:-GET}"

    # time 명령으로 실행 시간 측정
    local start_time=$(date +%s%3N)  # 밀리초 단위 타임스탬프

    if ! curl -X "$method" -s -o /dev/null --max-time "$timeout" "$url" 2>/dev/null; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to measure response time (fallback)" >&2
        return 1
    fi

    local end_time=$(date +%s%3N)
    local time_ms=$((end_time - start_time))

    echo "$time_ms"
    return 0
}

# 단일 응답 시간 테스트
test_response_time_single() {
    local port="$1"
    local endpoint="${2:-${TEST_RESPONSE_TIME_ENDPOINT:-${TEST_HTTP_ENDPOINT:-/actuator/health}}}"
    local max_time="${3:-${TEST_MAX_RESPONSE_TIME:-1000}}"
    local use_https="${TEST_USE_HTTPS:-false}"
    local host="${TEST_HOST:-localhost}"
    local timeout="${TEST_TIMEOUT:-30}"

    local protocol="http"
    if [ "$use_https" = "true" ]; then
        protocol="https"
    fi

    local url="${protocol}://${host}:${port}${endpoint}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Measuring response time: $url"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Maximum acceptable time: ${max_time}ms"

    # 응답 시간 측정
    local response_time_ms
    if ! response_time_ms=$(measure_response_time_curl "$url" "$timeout"); then
        # curl 실패 시 폴백 방식 시도
        if ! response_time_ms=$(measure_response_time_fallback "$url" "$timeout"); then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Could not measure response time" >&2
            return 1
        fi
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Response time: ${response_time_ms}ms"

    # 최대 시간과 비교
    if [ "$response_time_ms" -le "$max_time" ]; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Response time ${response_time_ms}ms ≤ ${max_time}ms ✓"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Response time ${response_time_ms}ms > ${max_time}ms ✗" >&2
        return 1
    fi
}

# 응답 시간 테스트 (재시도 포함)
test_response_time_with_retry() {
    local port="$1"
    local endpoint="${2:-}"
    local max_time="${3:-}"
    local retry_count="${TEST_RETRY_COUNT:-3}"
    local retry_delay="${TEST_RETRY_DELAY:-5}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Testing response time for port $port"

    local attempt=1
    while [ $attempt -le $retry_count ]; do
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Attempt $attempt/$retry_count"

        if test_response_time_single "$port" "$endpoint" "$max_time"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Response time test passed on attempt $attempt"
            return 0
        fi

        if [ $attempt -lt $retry_count ]; then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Response time test failed, retrying in ${retry_delay}s..."
            sleep "$retry_delay"
        fi

        attempt=$((attempt + 1))
    done

    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Response time test failed after $retry_count attempts" >&2
    return 1
}

# 다중 응답 시간 측정 (통계)
test_response_time_statistics() {
    local port="$1"
    local endpoint="${2:-${TEST_RESPONSE_TIME_ENDPOINT:-${TEST_HTTP_ENDPOINT:-/actuator/health}}}"
    local iterations="${4:-5}"
    local use_https="${TEST_USE_HTTPS:-false}"
    local host="${TEST_HOST:-localhost}"
    local timeout="${TEST_TIMEOUT:-30}"

    local protocol="http"
    if [ "$use_https" = "true" ]; then
        protocol="https"
    fi

    local url="${protocol}://${host}:${port}${endpoint}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Measuring response time statistics ($iterations iterations)"

    local times=()
    local total=0
    local min=999999
    local max=0

    for ((i=1; i<=iterations; i++)); do
        local response_time_ms
        if ! response_time_ms=$(measure_response_time_curl "$url" "$timeout"); then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Iteration $i failed, skipping"
            continue
        fi

        times+=("$response_time_ms")
        total=$((total + response_time_ms))

        if [ "$response_time_ms" -lt "$min" ]; then
            min=$response_time_ms
        fi

        if [ "$response_time_ms" -gt "$max" ]; then
            max=$response_time_ms
        fi

        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Iteration $i: ${response_time_ms}ms"
        sleep 0.5  # 짧은 대기
    done

    local count=${#times[@]}
    if [ "$count" -eq 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - No successful measurements" >&2
        return 1
    fi

    local avg=$((total / count))

    echo ""
    echo "=== Response Time Statistics ==="
    echo "Iterations: $count"
    echo "Minimum:    ${min}ms"
    echo "Maximum:    ${max}ms"
    echo "Average:    ${avg}ms"
    echo "Total:      ${total}ms"
    echo ""

    # 평균이 최대 허용 시간 내인지 확인
    local max_time="${TEST_MAX_RESPONSE_TIME:-1000}"
    if [ "$avg" -le "$max_time" ]; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Average response time ${avg}ms ≤ ${max_time}ms ✓"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Average response time ${avg}ms > ${max_time}ms ✗" >&2
        return 1
    fi
}

# 응답 시간 벤치마크 (부하 테스트)
test_response_time_benchmark() {
    local port="$1"
    local endpoint="${2:-${TEST_RESPONSE_TIME_ENDPOINT:-${TEST_HTTP_ENDPOINT:-/actuator/health}}}"
    local concurrent="${3:-5}"
    local requests="${4:-20}"
    local use_https="${TEST_USE_HTTPS:-false}"
    local host="${TEST_HOST:-localhost}"

    local protocol="http"
    if [ "$use_https" = "true" ]; then
        protocol="https"
    fi

    local url="${protocol}://${host}:${port}${endpoint}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running benchmark: $concurrent concurrent, $requests total requests"

    # ab (Apache Bench) 사용
    if command -v ab &> /dev/null; then
        local ab_output
        if ab_output=$(ab -n "$requests" -c "$concurrent" -q "$url" 2>&1); then
            echo "$ab_output" | grep -E "(Time per request|Requests per second|Transfer rate)"
            return 0
        fi
    fi

    # wrk 사용 (설치된 경우)
    if command -v wrk &> /dev/null; then
        wrk -t "$concurrent" -c "$concurrent" -d 10s "$url"
        return 0
    fi

    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - No benchmark tools found (ab, wrk), using simple statistics"
    test_response_time_statistics "$port" "$endpoint" "" "$requests"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: test_response_time.sh <port> [endpoint] [max_time_ms]"
        exit 1
    fi

    test_response_time_with_retry "$@"
fi
