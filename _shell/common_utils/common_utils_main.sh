#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/current_timestamp.sh"
source "${SCRIPT_DIR}/log_info.sh"
source "${SCRIPT_DIR}/log_warn.sh"
source "${SCRIPT_DIR}/log_success.sh"
source "${SCRIPT_DIR}/error_exit.sh"

# 모든 공통 유틸리티 함수들이 로드됨
# 이 스크립트를 source하면 모든 로깅 함수들을 사용할 수 있음

# 사용법 출력 함수 (테스트용)
show_usage() {
    echo "Common Utils Functions Available:"
    echo "- current_timestamp"
    echo "- log_info <message>"
    echo "- log_warn <message>"
    echo "- log_success <message>"
    echo "- error_exit <message>"
}

# 모든 함수 테스트 (직접 실행된 경우)
test_all_functions() {
    echo "=== Testing Common Utils Functions ==="
    echo "Current timestamp: $(current_timestamp)"
    log_info "This is an info message"
    log_warn "This is a warning message"
    log_success "This is a success message"
    echo "=== Test completed ==="
    echo "Note: error_exit function not tested as it would terminate the script"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-test}" in
        "usage")
            show_usage
            ;;
        "test")
            test_all_functions
            ;;
        *)
            echo "Usage: common_utils_main.sh [usage|test]"
            exit 1
            ;;
    esac
fi