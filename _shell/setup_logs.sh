#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common_utils.sh"

# 사용법: setup_logs.sh <service_name> <instance_num> <instance_dir> <log_base_dir>
if [ "$#" -ne 4 ]; then
    echo "Usage: setup_logs.sh <service_name> <instance_num> <instance_dir> <log_base_dir>"
    exit 1
fi

SERVICE_NAME="$1"
INSTANCE_NUM="$2"
INSTANCE_DIR="$3"
LOG_BASE_DIR="$4"

LOG_SOURCE_DIR="${LOG_BASE_DIR}/${SERVICE_NAME}/instances/${INSTANCE_NUM}"
LOG_LINK="${INSTANCE_DIR}/logs"

if [ ! -d "$LOG_SOURCE_DIR" ]; then
  log_info "Creating log directories at $LOG_SOURCE_DIR"
  mkdir -p "$LOG_SOURCE_DIR" || error_exit "Failed to create log directories at $LOG_SOURCE_DIR"
fi

if [ -L "$LOG_LINK" ] || [ -e "$LOG_LINK" ]; then
  log_warn "Removing existing log link/file at $LOG_LINK"
  rm -f "$LOG_LINK" || error_exit "Failed to remove existing log link/file at $LOG_LINK"
fi

log_info "Creating symbolic link for logs: $LOG_LINK -> $LOG_SOURCE_DIR"
ln -s "$LOG_SOURCE_DIR" "$LOG_LINK" || error_exit "Failed to create symbolic link for logs"

# 심볼릭 링크 검증: 생성된 링크가 올바른 대상인지 확인
if [ "$(readlink "$LOG_LINK")" != "$LOG_SOURCE_DIR" ]; then
  error_exit "Symbolic link verification failed: $LOG_LINK does not point to $LOG_SOURCE_DIR"
fi

log_success "Log symbolic link created and verified: $LOG_LINK -> $LOG_SOURCE_DIR"
