#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common_utils.sh"

# 사용법: link_jar.sh <service_name> <target_link_path> <jar_trunk_dir>
if [ "$#" -ne 3 ]; then
    echo "Usage: link_jar.sh <service_name> <target_link_path> <jar_trunk_dir>"
    exit 1
fi

SERVICE_NAME="$1"
TARGET_LINK="$2"
JAR_DIR="$3"

if [ ! -d "$JAR_DIR" ]; then
  error_exit "Directory ${JAR_DIR} does not exist."
fi

PID_FILE="${JAR_DIR}/current_jar.pid"
if [ ! -f "$PID_FILE" ]; then
  error_exit "PID file not found at $PID_FILE"
fi

JAR_NAME=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$PID_FILE")
if [ -z "$JAR_NAME" ]; then
  error_exit "No jar name found in $PID_FILE"
fi

# 검증: JAR_NAME이 .jar 확장자로 끝나는지 확인
if [[ "$JAR_NAME" != *.jar ]]; then
  error_exit "Invalid jar name '$JAR_NAME'. Expected a file ending with .jar"
fi

log_info "Jar name from PID file: $JAR_NAME"

JAR_PATH="${JAR_DIR}/${JAR_NAME}"
if [ ! -f "$JAR_PATH" ]; then
  error_exit "Jar file ${JAR_PATH} not found."
fi

TARGET_DIR=$(dirname "$TARGET_LINK")
if [ ! -d "$TARGET_DIR" ]; then
  error_exit "Target directory ${TARGET_DIR} does not exist."
fi

if [ -L "$TARGET_LINK" ] || [ -e "$TARGET_LINK" ]; then
  log_warn "Removing existing link/file at $TARGET_LINK"
  rm -f "$TARGET_LINK" || error_exit "Failed to remove existing link/file at $TARGET_LINK"
fi

ln -s "$JAR_PATH" "$TARGET_LINK" || error_exit "Failed to create symbolic link"
log_success "Symbolic link created: $TARGET_LINK -> $JAR_PATH"
exit 0
