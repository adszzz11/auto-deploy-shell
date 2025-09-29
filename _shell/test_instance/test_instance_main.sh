#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_test_parameters.sh"
source "${SCRIPT_DIR}/initialize_test.sh"
source "${SCRIPT_DIR}/test_http_status.sh"
source "${SCRIPT_DIR}/test_tcp_connection.sh"
source "${SCRIPT_DIR}/test_response_time.sh"
source "${SCRIPT_DIR}/run_custom_tests.sh"
source "${SCRIPT_DIR}/evaluate_test_results.sh"

# 메인 인스턴스 테스트 함수
test_instance_main() {
    # 사용법: test_instance_main <port>
    if [ "$#" -ne 1 ]; then
        echo "Usage: test_instance_main <port>"
        exit 1
    fi

    local port="$1"

    # 1. 파라미터 검증
    validate_test_parameters "$port"

    # 2. 테스트 초기화
    initialize_test "$port"

    # 3. HTTP 상태 코드 테스트
    if ! test_http_status "$port"; then
        log_test_failure "HTTP Status Test"
    else
        log_test_success "HTTP Status Test"
    fi

    # 4. TCP 연결 테스트 (선택적)
    if ! test_tcp_connection "$port"; then
        log_test_failure "TCP Connection Test"
    else
        log_test_success "TCP Connection Test"
    fi

    # 5. 응답 시간 테스트 (선택적)
    if ! test_response_time "$port" "/api/v1/global/commoncode/TX_DVCD/WDL" 5; then
        log_test_failure "Response Time Test"
    else
        log_test_success "Response Time Test"
    fi

    # 6. 커스텀 테스트 실행 (선택적)
    if ! run_custom_tests "$port"; then
        log_test_failure "Custom Tests"
    else
        log_test_success "Custom Tests"
    fi

    # 7. 결과 평가 및 반환
    if evaluate_test_results; then
        exit 0
    else
        exit 1
    fi
}

# 단순 테스트 모드 (원래 test_instance.sh와 동일한 동작)
test_instance_simple() {
    local port="$1"

    # 파라미터 검증
    validate_test_parameters "$port"

    # 테스트 초기화
    initialize_test "$port"

    # 기본 HTTP 테스트만 실행
    if ! test_http_status "$port"; then
        log_test_failure "HTTP Test"
    else
        log_test_success "HTTP Test"
    fi

    # 결과 평가
    if evaluate_test_results; then
        exit 0
    else
        exit 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${2:-simple}" in
        "full")
            test_instance_main "$1"
            ;;
        "simple")
            test_instance_simple "$1"
            ;;
        *)
            echo "Usage: test_instance_main.sh <port> [simple|full]"
            echo "  simple: Basic HTTP test only (default)"
            echo "  full: All available tests"
            exit 1
            ;;
    esac
fi