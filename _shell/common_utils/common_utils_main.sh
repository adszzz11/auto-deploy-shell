#!/bin/bash
set -euo pipefail

# 현재 날짜와 시간을 반환하는 함수
current_timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

# 정보 출력용 함수
log_info() {
    local message="$1"
    echo "[INFO] $(current_timestamp) - $message"
}

# 경고 출력용 함수
log_warn() {
    local message="$1"
    echo "[WARN] $(current_timestamp) - $message"
}

# 성공 출력용 함수
log_success() {
    local message="$1"
    echo "[SUCCESS] $(current_timestamp) - $message"
}

# 공통 에러 출력 후 종료 함수
error_exit() {
  echo "[ERROR] $(current_timestamp) - $1" >&2
  exit 1
}

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

# 스크립트가 직접 실행된 경우 (source되지 않은 경우)
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
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