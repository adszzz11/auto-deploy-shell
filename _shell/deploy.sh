#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common_utils.sh"

# 현재 스크립트가 위치한 디렉터리(절대경로)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SCRIPT_DIR

# 필수 외부 스크립트 존재 및 실행 권한 확인
REQUIRED_SCRIPTS=( "controll_nginx.sh" "link_jar.sh" "runApp.sh" "setup_logs.sh" )
for script in "${REQUIRED_SCRIPTS[@]}"; do
  if [ ! -x "${SCRIPT_DIR}/${script}" ]; then
    error_exit "Required script ${script} not found or not executable in ${SCRIPT_DIR}"
  fi
done

# 인자 개수 체크: 최소 2개, 최대 3개 (예: deploy.sh <instance_number> <env_file> [deploy|remove])
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: deploy.sh <instance_number> <env_file> [deploy|remove]"
    exit 1
fi

INSTANCE_NUM="$1"
ENV_FILE="$2"
ACTION="${3:-deploy}"  # 기본값은 deploy

if [ ! -f "$ENV_FILE" ]; then
    error_exit "Environment file $ENV_FILE not found."
fi
source "$ENV_FILE"

PORT="${BASE_PORT}${INSTANCE_NUM}"
INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${INSTANCE_NUM}"
TARGET_LINK="${INSTANCE_DIR}/current.jar"

if [ "$ACTION" = "deploy" ]; then
    log_info "Deploying service: ${SERVICE_NAME}, instance: ${INSTANCE_NUM}, port: ${PORT}"

    [ ! -d "$JAR_TRUNK_DIR" ] && error_exit "jar_trunk directory not found at ${JAR_TRUNK_DIR}"
    [ ! -d "$INSTANCE_DIR" ] && { log_info "Creating instance directory ${INSTANCE_DIR}..."; mkdir -p "$INSTANCE_DIR"; }

    log_info "Setting nginx upstream DOWN for port ${PORT}"
    "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" down || error_exit "Failed to set nginx upstream DOWN"

    if [ -L "$TARGET_LINK" ] || [ -e "$TARGET_LINK" ]; then
        log_info "Backing up current.jar for instance ${INSTANCE_NUM}"
        mv "$TARGET_LINK" "${TARGET_LINK}.bak" || error_exit "Failed to backup current.jar"
    fi

    log_info "Creating jar symlink..."
    "${SCRIPT_DIR}/link_jar.sh" "$SERVICE_NAME" "$TARGET_LINK" "$JAR_TRUNK_DIR" || {
      "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up;
      error_exit "Jar symlink failed";
    }

    # --- runApp.sh 업데이트 로직 ---
    RUNAPP_SRC="${SCRIPT_DIR}/runApp.sh"
    RUNAPP_DEST="${INSTANCE_DIR}/runApp.sh"

    if [ -f "$RUNAPP_DEST" ]; then
        if ! cmp -s "$RUNAPP_SRC" "$RUNAPP_DEST"; then
            log_info "Existing runApp.sh in ${INSTANCE_DIR} is outdated. Backing up as runApp.sh.bak and updating..."
            mv "$RUNAPP_DEST" "${RUNAPP_DEST}.bak" || {
              "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up;
              error_exit "Failed to backup existing runApp.sh";
            }
            cp "$RUNAPP_SRC" "$RUNAPP_DEST" || {
              "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up;
              error_exit "runApp.sh copy failed";
            }
            chmod +x "$RUNAPP_DEST" || error_exit "runApp.sh permission set failed"
        else
            log_info "runApp.sh in ${INSTANCE_DIR} is already up-to-date."
        fi
    else
        log_info "Copying runApp.sh to ${INSTANCE_DIR}..."
        cp "$RUNAPP_SRC" "$RUNAPP_DEST" || {
          "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up;
          error_exit "runApp.sh copy failed";
        }
        chmod +x "$RUNAPP_DEST" || error_exit "runApp.sh permission set failed"
    fi
    # --- 여기까지 runApp.sh 업데이트 로직 ---

    log_info "Setting up logs for instance ${INSTANCE_NUM}"
    "${SCRIPT_DIR}/setup_logs.sh" "${SERVICE_NAME}" "${INSTANCE_NUM}" "${INSTANCE_DIR}" "${LOG_BASE_DIR}" || {
      "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up;
      error_exit "Log setup failed";
    }

    log_info "Deploying application on port ${PORT} from instance directory ${INSTANCE_DIR}..."
    ( cd "$INSTANCE_DIR" && ./runApp.sh "$PORT" "$APP_MODE" "${JAVA_OPTS:-}" "${SCRIPT_DIR}" ) || {
      "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up || error_exit "Failed to set nginx upstream UP";
      error_exit "Failed to deploy application.";
    }

    # --------------------- 테스트 스크립트 실행 추가 ---------------------
    # TEST_SCRIPT는 환경 파일에 지정되어 있어야 하며, 실행 가능해야 합니다.
    if [ -n "${TEST_SCRIPT:-}" ] && [ -x "${TEST_SCRIPT}" ]; then
         log_info "Running tests on instance at port ${PORT}"
         "${TEST_SCRIPT}" "$PORT" || {
             "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up || error_exit "Failed to set nginx upstream UP after test failure";
             error_exit "Tests failed for instance ${INSTANCE_NUM}.";
         }
    else
         log_info "No test script provided or test script not executable. Skipping tests."
    fi
    # ---------------------------------------------------------------------

    log_info "Setting nginx upstream UP for port ${PORT}"
    "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" up || error_exit "Failed to set nginx upstream UP"

    log_success "Deployment completed for instance: ${INSTANCE_NUM}, port: ${PORT}"

elif [ "$ACTION" = "remove" ]; then
    log_info "Removing instance: ${SERVICE_NAME}, instance: ${INSTANCE_NUM}, port: ${PORT}"

    if [ ! -d "$INSTANCE_DIR" ]; then
        log_warn "Instance directory ${INSTANCE_DIR} does not exist. Nothing to remove."
        exit 0
    fi

    log_info "Stopping application on port ${PORT} in ${INSTANCE_DIR}"
    if [ -f "${INSTANCE_DIR}/runApp.sh" ]; then
        ( cd "$INSTANCE_DIR" && ./runApp.sh "$PORT" stop "" "${SCRIPT_DIR}" ) || log_warn "Failed to stop application on port ${PORT}"
    else
        log_warn "No runApp.sh found in ${INSTANCE_DIR}"
    fi

    log_info "Setting nginx upstream DOWN for port ${PORT}"
    "${SCRIPT_DIR}/controll_nginx.sh" "$PORT" "$UPSTREAM_CONF" down || log_warn "Failed to set nginx upstream DOWN for port ${PORT}"

    log_info "Removing instance directory ${INSTANCE_DIR}"
    rm -rf "$INSTANCE_DIR" || error_exit "Failed to remove instance directory ${INSTANCE_DIR}"

    log_success "Instance ${INSTANCE_NUM} removed successfully."
else
    error_exit "Invalid action specified. Use 'deploy' or 'remove'."
fi
