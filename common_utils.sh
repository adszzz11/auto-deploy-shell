#!/bin/bash
set -euo pipefail

# 현재 날짜와 시간을 반환하는 함수
current_timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

# 공통 에러 출력 후 종료 함수
error_exit() {
  echo "[ERROR] $(current_timestamp) - $1" >&2
  exit 1
}

# 정보 출력용 공통 함수
log_info() {
  echo "[INFO] $(current_timestamp) - $1"
}

# 경고 출력용 공통 함수
log_warn() {
  echo "[WARN] $(current_timestamp) - $1"
}

# 성공 출력용 공통 함수
log_success() {
  echo "[SUCCESS] $(current_timestamp) - $1"
}
