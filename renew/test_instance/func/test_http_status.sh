#!/bin/bash
set -euo pipefail

# test_http_status.sh - HTTP Status Code Testing

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${SCRIPT_DIR}/test_instance.env" ]; then
    source "${SCRIPT_DIR}/test_instance.env"
fi

# HTTP 상태 코드 테스트 (재시도 포함)
test_http_status_with_retry() {
    local port="$1"
    local endpoint="${TEST_HTTP_ENDPOINT:-/actuator/health}"
    local expected_status="${TEST_EXPECTED_STATUS:-200}"
    local retry_count="${TEST_RETRY_COUNT:-3}"
    local retry_delay="${TEST_RETRY_DELAY:-5}"
    local use_https="${TEST_USE_HTTPS:-false}"
    local host="${TEST_HOST:-localhost}"

    local protocol="http"
    if [ "$use_https" = "true" ]; then
        protocol="https"
    fi

    local url="${protocol}://${host}:${port}${endpoint}"
    local attempt=1

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Testing HTTP endpoint: $url"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Expected status: $expected_status"

    while [ $attempt -le $retry_count ]; do
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Attempt $attempt/$retry_count"

        if test_http_status_single "$url" "$expected_status"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - HTTP test passed on attempt $attempt"
            return 0
        fi

        if [ $attempt -lt $retry_count ]; then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - HTTP test failed, retrying in ${retry_delay}s..."
            sleep "$retry_delay"
        fi

        attempt=$((attempt + 1))
    done

    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - HTTP test failed after $retry_count attempts" >&2
    return 1
}

# 단일 HTTP 상태 코드 테스트
test_http_status_single() {
    local url="$1"
    local expected_status="$2"
    local timeout="${TEST_TIMEOUT:-30}"
    local method="${TEST_HTTP_METHOD:-GET}"
    local verbose="${TEST_VERBOSE:-false}"

    # curl 옵션
    local curl_opts=(
        -X "$method"
        -s                          # Silent mode
        -o /dev/null                # Discard body
        -w "%{http_code}"           # Output only status code
        --max-time "$timeout"       # Timeout
        --connect-timeout 10        # Connection timeout
    )

    # HTTPS insecure 옵션 (자체 서명 인증서 허용)
    if [[ "$url" =~ ^https:// ]]; then
        curl_opts+=(-k)
    fi

    # verbose 모드
    if [ "$verbose" = "true" ]; then
        curl_opts+=(-v)
    fi

    # HTTP 요청 실행
    local actual_status
    if ! actual_status=$(curl "${curl_opts[@]}" "$url" 2>&1); then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to connect to $url" >&2

        if [ "${TEST_SHOW_RESPONSE_ON_FAIL:-true}" = "true" ]; then
            echo "[DEBUG] curl output: $actual_status" >&2
        fi

        return 1
    fi

    # 상태 코드 검증
    if [ "$actual_status" = "$expected_status" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - HTTP $method $url → $actual_status (expected: $expected_status) ✓"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - HTTP $method $url → $actual_status (expected: $expected_status) ✗" >&2

        # 실패 시 응답 본문 가져오기
        if [ "${TEST_SHOW_RESPONSE_ON_FAIL:-true}" = "true" ]; then
            local response_body
            response_body=$(curl -X "$method" -s --max-time "$timeout" "$url" 2>&1 | head -20)
            echo "[DEBUG] Response body (first 20 lines):" >&2
            echo "$response_body" >&2
        fi

        return 1
    fi
}

# HTTP 응답 본문 패턴 검증
test_http_response_body() {
    local port="$1"
    local endpoint="${TEST_HTTP_ENDPOINT:-/actuator/health}"
    local pattern="${TEST_HEALTH_BODY_PATTERN:-}"
    local use_https="${TEST_USE_HTTPS:-false}"
    local host="${TEST_HOST:-localhost}"
    local timeout="${TEST_TIMEOUT:-30}"

    if [ -z "$pattern" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No response body pattern specified, skipping"
        return 0
    fi

    local protocol="http"
    if [ "$use_https" = "true" ]; then
        protocol="https"
    fi

    local url="${protocol}://${host}:${port}${endpoint}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Testing response body pattern: $pattern"

    local response_body
    if ! response_body=$(curl -X GET -s --max-time "$timeout" "$url" 2>&1); then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to get response body from $url" >&2
        return 1
    fi

    if echo "$response_body" | grep -qE "$pattern"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Response body matches pattern: $pattern"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Response body does not match pattern: $pattern" >&2

        if [ "${TEST_SHOW_RESPONSE_ON_FAIL:-true}" = "true" ]; then
            echo "[DEBUG] Response body:" >&2
            echo "$response_body" >&2
        fi

        return 1
    fi
}

# HTTP 헤더 검증
test_http_headers() {
    local port="$1"
    local endpoint="${TEST_HTTP_ENDPOINT:-/actuator/health}"
    local required_headers="${TEST_REQUIRED_HEADERS:-}"
    local use_https="${TEST_USE_HTTPS:-false}"
    local host="${TEST_HOST:-localhost}"
    local timeout="${TEST_TIMEOUT:-30}"

    if [ -z "$required_headers" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No required headers specified, skipping"
        return 0
    fi

    local protocol="http"
    if [ "$use_https" = "true" ]; then
        protocol="https"
    fi

    local url="${protocol}://${host}:${port}${endpoint}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Testing required headers: $required_headers"

    # 헤더 가져오기
    local response_headers
    if ! response_headers=$(curl -X GET -s -I --max-time "$timeout" "$url" 2>&1); then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to get headers from $url" >&2
        return 1
    fi

    # 쉼표로 구분된 헤더 검증 (형식: "Header1:Value1,Header2:Value2")
    IFS=',' read -ra HEADERS <<< "$required_headers"
    local all_passed=true

    for header_spec in "${HEADERS[@]}"; do
        local header_name="${header_spec%%:*}"
        local header_value="${header_spec#*:}"

        if echo "$response_headers" | grep -qi "^${header_name}:.*${header_value}"; then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Header '$header_name: $header_value' found ✓"
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Header '$header_name: $header_value' not found ✗" >&2
            all_passed=false
        fi
    done

    if [ "$all_passed" = "true" ]; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - All required headers present"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Some required headers missing" >&2

        if [ "${TEST_SHOW_RESPONSE_ON_FAIL:-true}" = "true" ]; then
            echo "[DEBUG] Response headers:" >&2
            echo "$response_headers" >&2
        fi

        return 1
    fi
}

# 통합 HTTP 테스트 (상태 + 본문 + 헤더)
test_http_full() {
    local port="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running full HTTP test for port $port"

    # 1. HTTP 상태 코드 테스트
    if ! test_http_status_with_retry "$port"; then
        return 1
    fi

    # 2. 응답 본문 패턴 테스트 (설정된 경우)
    if [ -n "${TEST_HEALTH_BODY_PATTERN:-}" ]; then
        if ! test_http_response_body "$port"; then
            return 1
        fi
    fi

    # 3. 헤더 테스트 (설정된 경우)
    if [ -n "${TEST_REQUIRED_HEADERS:-}" ]; then
        if ! test_http_headers "$port"; then
            return 1
        fi
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Full HTTP test passed"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: test_http_status.sh <port> [endpoint] [expected_status]"
        exit 1
    fi

    port="$1"

    if [ "$#" -ge 2 ]; then
        export TEST_HTTP_ENDPOINT="$2"
    fi

    if [ "$#" -ge 3 ]; then
        export TEST_EXPECTED_STATUS="$3"
    fi

    test_http_status_with_retry "$port"
fi
