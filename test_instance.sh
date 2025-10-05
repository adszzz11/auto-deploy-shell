#!/bin/bash
set -euo pipefail

# Logging functions (inline)
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

error_exit() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
    exit 1
}

# 사용법: test_instance.sh <port>
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <port>"
  exit 1
fi

# 해당 instance의 PORT. 한 instance를 테스트할 경우 이 PORT를 반드시 사용해야 합니다.
PORT="$1"
FAIL=0

log_info "Starting tests for instance on port $PORT..."

################################################################
# 스크립트 적용법
# 이 아래에, 사용자가 원하는 테스트를 작성합니다.
# 테스트의 결과가 만족스럽지 않은 경우 FAIL을 1로 변경합니다.
# #====== 사이에 자유롭게 작성하고, FAIL을 변경하지 않으면 정상 처리됩니다.
# 아래는 예시입니다.
#
  #Test 1: HTTP 응답 상태 확인 (200 OK)
  #HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/")
  #if [ "$HTTP_STATUS" -eq 200 ]; then
  #  echo "HTTP test passed: Received 200 OK"
  #else
  #  echo "HTTP test failed: Expected 200 but got $HTTP_STATUS"
  #  FAIL=1
  #fi

  # Test 2: TCP 연결 확인 (nc가 설치되어 있어야 함)
  #if nc -z localhost "$PORT"; then
  #  echo "TCP connection test passed: Port $PORT is open"
  #else
  #  echo "TCP connection test failed: Port $PORT is not open"
  #  FAIL=1
  #fi
################################################################
#===============================================================
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/api/v1/global/commoncode/TX_DVCD/WDL")
if [ "$HTTP_STATUS" -eq 200 ]; then
  echo "HTTP test passed: Received 200 OK"
else
  echo "HTTP test failed: Expected 200 but got $HTTP_STATUS"
  FAIL=1
fi

#===============================================================
if [ "$FAIL" -eq 0 ]; then
  log_success "All tests passed for instance on port $PORT"
  exit 0
else
  error_exit "Some tests failed for instance on port $PORT"
fi
