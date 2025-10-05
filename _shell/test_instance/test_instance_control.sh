#!/bin/bash
set -euo pipefail


# test_instance_control.sh - Instance Health Check & Testing
#
# Layer: 4 (Support Services)
# 역할: 인스턴스 헬스 체크 및 테스트
# 호출자: deploy_control.sh (Layer 3)
# 호출 대상: 없음 (최하위 계층)
#
# 책임:
#   - HTTP 상태 코드 검증
#   - TCP 연결성 확인
#   - 응답 시간 측정
#   - 커스텀 테스트 실행
# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 모든 함수 스크립트들 source (func 디렉터리에서)
source "${SCRIPT_DIR}/func/validate_test_params.sh"
source "${SCRIPT_DIR}/func/test_http_status.sh"
source "${SCRIPT_DIR}/func/test_tcp_connection.sh"
source "${SCRIPT_DIR}/func/test_response_time.sh"
source "${SCRIPT_DIR}/func/run_custom_tests.sh"

# 사용법 출력
print_usage() {
    cat << EOF
Usage: test_instance_control.sh <command> [arguments]

Commands:
  test <port> [env_file]                    - Run tests based on TEST_MODE
  http <port> [env_file]                    - HTTP status test only
  tcp <port> [env_file]                     - TCP connection test only
  response <port> [env_file]                - Response time test only
  custom <port> [service_name] [env_file]   - Custom test script execution
  full <port> [service_name] [env_file]     - All tests (HTTP + TCP + response time + custom)
  quick <port>                              - Quick HTTP test (no retries)
  benchmark <port> [env_file]               - Response time benchmark
  validate <port> [env_file]                - Validate test parameters

Environment variables (set in test_instance.env):
  TEST_MODE                    - Test mode: simple, full, custom (default: simple)
  TEST_HTTP_ENDPOINT           - HTTP endpoint (default: /actuator/health)
  TEST_EXPECTED_STATUS         - Expected HTTP status (default: 200)
  TEST_RETRY_COUNT             - Retry attempts (default: 3)
  TEST_RETRY_DELAY             - Retry delay in seconds (default: 5)
  TEST_TIMEOUT                 - Overall timeout (default: 30s)
  TEST_WARMUP_WAIT             - Warmup wait time (default: 5s)
  TEST_TCP_ENABLED             - Enable TCP test (default: false)
  TEST_RESPONSE_TIME_ENABLED   - Enable response time test (default: false)
  TEST_MAX_RESPONSE_TIME       - Max response time in ms (default: 1000)
  TEST_CUSTOM_SCRIPT           - Custom test script path
  TEST_VERBOSE                 - Verbose output (default: false)

Examples:
  # Simple HTTP test (default mode)
  ./test_instance_control.sh test 8080 app.env

  # Full test suite
  ./test_instance_control.sh full 8080 myservice app.env

  # Quick test without retries
  ./test_instance_control.sh quick 8080

  # HTTP test only
  ./test_instance_control.sh http 8080

  # TCP connectivity test
  ./test_instance_control.sh tcp 8080

  # Response time test
  ./test_instance_control.sh response 8080

  # Custom test
  ./test_instance_control.sh custom 8080 myservice app.env

  # Benchmark
  ./test_instance_control.sh benchmark 8080

  # Validate parameters
  ./test_instance_control.sh validate 8080 app.env
EOF
}

# 환경 로드
load_environment() {
    local env_file="${1:-}"

    if [ -n "$env_file" ]; then
        if [ ! -f "$env_file" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
            return 1
        fi

        source "$env_file"
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Environment loaded from: $env_file"
    fi

    return 0
}

# Warmup 대기
wait_for_warmup() {
    local warmup_wait="${TEST_WARMUP_WAIT:-5}"

    if [ "$warmup_wait" -gt 0 ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Waiting ${warmup_wait}s for application warmup..."
        sleep "$warmup_wait"
    fi
}

# 테스트 모드별 실행
execute_test_by_mode() {
    local port="$1"
    local service_name="${2:-}"
    local env_file="${3:-}"

    # 환경 로드
    load_environment "$env_file"

    # 파라미터 검증
    validate_test_parameters "$port" "$env_file"

    # 테스트 설정 검증
    validate_test_configuration

    local mode="${TEST_MODE:-simple}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Test mode: $mode"

    # Warmup 대기
    wait_for_warmup

    case "$mode" in
        simple)
            # Simple: HTTP 상태 테스트만
            test_http_status_with_retry "$port"
            ;;
        full)
            # Full: HTTP + TCP + Response Time
            execute_full_test "$port" "$service_name" "$env_file"
            ;;
        custom)
            # Custom: 사용자 정의 테스트
            run_custom_tests "$port" "$service_name" "$env_file"
            ;;
        *)
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid test mode: $mode" >&2
            return 1
            ;;
    esac
}

# HTTP 테스트 실행
execute_http_test() {
    local port="$1"
    local env_file="${2:-}"

    load_environment "$env_file"
    validate_test_parameters "$port" "$env_file"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running HTTP test for port $port"
    wait_for_warmup

    test_http_status_with_retry "$port"
}

# TCP 테스트 실행
execute_tcp_test() {
    local port="$1"
    local env_file="${2:-}"

    load_environment "$env_file"
    validate_test_parameters "$port" "$env_file"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running TCP test for port $port"

    test_tcp_connection_with_retry "$port"
}

# Response Time 테스트 실행
execute_response_test() {
    local port="$1"
    local env_file="${2:-}"

    load_environment "$env_file"
    validate_test_parameters "$port" "$env_file"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running response time test for port $port"
    wait_for_warmup

    test_response_time_with_retry "$port"
}

# Custom 테스트 실행
execute_custom_test() {
    local port="$1"
    local service_name="${2:-}"
    local env_file="${3:-}"

    load_environment "$env_file"
    validate_test_parameters "$port" "$env_file"
    validate_custom_test_script

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running custom tests for port $port"

    run_custom_tests "$port" "$service_name" "$env_file"
}

# Full 테스트 실행 (모든 테스트)
execute_full_test() {
    local port="$1"
    local service_name="${2:-}"
    local env_file="${3:-}"

    echo "=================================================="
    echo "Full Test Suite for port $port"
    echo "=================================================="

    load_environment "$env_file"
    validate_test_parameters "$port" "$env_file"

    wait_for_warmup

    local all_passed=true

    # 1. HTTP 테스트
    echo ""
    echo "==================================================[ HTTP Test ]==="
    if ! test_http_full "$port"; then
        echo "[FAIL] HTTP test failed"
        all_passed=false

        if [ "${TEST_CONTINUE_ON_FAIL:-false}" != "true" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Stopping tests due to HTTP failure" >&2
            return 1
        fi
    else
        echo "[PASS] HTTP test passed"
    fi

    # 2. TCP 테스트 (활성화된 경우)
    if [ "${TEST_TCP_ENABLED:-false}" = "true" ]; then
        echo ""
        echo "==================================================[ TCP Test ]==="
        if ! test_tcp_full "$port"; then
            echo "[FAIL] TCP test failed"
            all_passed=false

            if [ "${TEST_CONTINUE_ON_FAIL:-false}" != "true" ]; then
                echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Stopping tests due to TCP failure" >&2
                return 1
            fi
        else
            echo "[PASS] TCP test passed"
        fi
    fi

    # 3. Response Time 테스트 (활성화된 경우)
    if [ "${TEST_RESPONSE_TIME_ENABLED:-false}" = "true" ]; then
        echo ""
        echo "==================================================[ Response Time Test ]==="
        if ! test_response_time_with_retry "$port"; then
            echo "[FAIL] Response time test failed"
            all_passed=false

            if [ "${TEST_CONTINUE_ON_FAIL:-false}" != "true" ]; then
                echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Stopping tests due to response time failure" >&2
                return 1
            fi
        else
            echo "[PASS] Response time test passed"
        fi
    fi

    # 4. Custom 테스트 (설정된 경우)
    if [ -n "${TEST_CUSTOM_SCRIPT:-}" ]; then
        echo ""
        echo "==================================================[ Custom Tests ]==="
        if ! run_custom_tests "$port" "$service_name" "$env_file"; then
            echo "[FAIL] Custom tests failed"
            all_passed=false

            if [ "${TEST_CONTINUE_ON_FAIL:-false}" != "true" ]; then
                echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Stopping tests due to custom test failure" >&2
                return 1
            fi
        else
            echo "[PASS] Custom tests passed"
        fi
    fi

    echo ""
    echo "=================================================="
    if [ "$all_passed" = "true" ]; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - All tests passed"
        return 0
    else
        echo "[PARTIAL] $(date '+%Y-%m-%d %H:%M:%S') - Some tests failed"
        return 1
    fi
}

# Quick 테스트 (재시도 없음)
execute_quick_test() {
    local port="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running quick test for port $port (no retries)"

    # 재시도 설정 무시
    export TEST_RETRY_COUNT=1
    export TEST_WARMUP_WAIT=0

    test_http_status_with_retry "$port"
}

# Benchmark 실행
execute_benchmark() {
    local port="$1"
    local env_file="${2:-}"

    load_environment "$env_file"
    validate_test_parameters "$port" "$env_file"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running benchmark for port $port"

    test_response_time_benchmark "$port"
}

# 검증 실행
execute_validation() {
    local port="$1"
    local env_file="${2:-}"

    echo "=== Test Validation ==="

    # 환경 로드
    load_environment "$env_file"

    # 파라미터 검증
    validate_test_parameters "$port" "$env_file"
    echo "✅ Parameters validated"

    # 테스트 설정 검증
    validate_test_configuration
    echo "✅ Test configuration validated"

    # 포트 접근성 검증
    if validate_port_accessibility "$port"; then
        echo "✅ Port is accessible"
    else
        echo "⚠️  Port is not currently accessible (may need warmup)"
    fi

    # HTTP 엔드포인트 검증
    validate_http_endpoint
    echo "✅ HTTP endpoint validated"

    # Custom 스크립트 검증 (모드가 custom인 경우)
    if [ "${TEST_MODE:-simple}" = "custom" ]; then
        validate_custom_test_script
        echo "✅ Custom test script validated"
    fi

    echo ""
    echo "✅ All validations passed"
    echo "Ready to execute tests for port $port"
}

# 메인 진입점
main() {
    if [ "$#" -lt 1 ]; then
        print_usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        test)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'test' requires <port> [env_file]"
                exit 1
            fi
            execute_test_by_mode "$@"
            ;;
        http)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'http' requires <port> [env_file]"
                exit 1
            fi
            execute_http_test "$@"
            ;;
        tcp)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'tcp' requires <port> [env_file]"
                exit 1
            fi
            execute_tcp_test "$@"
            ;;
        response)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'response' requires <port> [env_file]"
                exit 1
            fi
            execute_response_test "$@"
            ;;
        custom)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'custom' requires <port> [service_name] [env_file]"
                exit 1
            fi
            execute_custom_test "$@"
            ;;
        full)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'full' requires <port> [service_name] [env_file]"
                exit 1
            fi
            execute_full_test "$@"
            ;;
        quick)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'quick' requires <port>"
                exit 1
            fi
            execute_quick_test "$@"
            ;;
        benchmark)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'benchmark' requires <port> [env_file]"
                exit 1
            fi
            execute_benchmark "$@"
            ;;
        validate)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'validate' requires <port> [env_file]"
                exit 1
            fi
            execute_validation "$@"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
