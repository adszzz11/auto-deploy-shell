#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common_utils.sh"

# 사용법: rollback.sh <instance_number> <env_file>
if [ "$#" -ne 2 ]; then
    echo "Usage: rollback.sh <instance_number> <env_file>"
    exit 1
fi

INSTANCE_NUM="$1"
ENV_FILE="$2"

if [ ! -f "$ENV_FILE" ]; then
  error_exit "Environment file not found: $ENV_FILE"
fi
source "$ENV_FILE"

PORT="${BASE_PORT}${INSTANCE_NUM}"
INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${INSTANCE_NUM}"
TARGET_LINK="${INSTANCE_DIR}/current.jar"
BACKUP_LINK="${TARGET_LINK}.bak"

log_info "Initiating rollback for instance ${INSTANCE_NUM} on port ${PORT}"

if [ ! -e "$BACKUP_LINK" ]; then
  error_exit "No backup found for instance ${INSTANCE_NUM}"
fi

log_info "Removing current jar link/file at ${TARGET_LINK}"
rm -f "$TARGET_LINK" || error_exit "Failed to remove current jar link/file at ${TARGET_LINK}"

log_info "Restoring backup jar from ${BACKUP_LINK} to ${TARGET_LINK}"
mv "$BACKUP_LINK" "$TARGET_LINK" || error_exit "Rollback failed for instance ${INSTANCE_NUM}"

# 절대 경로를 사용해 runApp.sh 실행
RUNAPP_PATH="$(cd "$(dirname "$0")" && pwd)/runApp.sh"
if [ -f "${INSTANCE_DIR}/runApp.sh" ]; then
  log_info "Re-starting application for instance ${INSTANCE_NUM} using runApp.sh"
  (cd "$INSTANCE_DIR" && "${RUNAPP_PATH}" "$PORT" "$APP_MODE" "${JAVA_OPTS:-}" "$(cd "$(dirname "$0")" && pwd)") || error_exit "Failed to restart application for instance ${INSTANCE_NUM}"
else
  log_warn "runApp.sh not found in ${INSTANCE_DIR}, skipping application restart"
fi

log_success "Rollback completed for instance ${INSTANCE_NUM}"
