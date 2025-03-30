#!/bin/bash
set -euo pipefail

# 사용법: runApp.sh <port> [stop|start|restart] [JAVA_OPTS] <common_utils_dir>
if [ "$#" -ne 4 ]; then
    echo "Usage: runApp.sh <port> [stop|start|restart] [JAVA_OPTS] <common_utils_dir>"
    exit 1
fi

PORT="$1"
MODE="$2"
JAVA_OPTS="$3"
COMMON_UTILS_DIR="$4"

source "${COMMON_UTILS_DIR}/common_utils.sh"

# 실행 명령어 구성 및 로깅
EXEC_COMMAND="java -jar current.jar --server.port=${PORT} ${JAVA_OPTS}"
log_info "EXEC_COMMAND: $EXEC_COMMAND"

stop_instance() {
  # 구체적인 패턴으로 프로세스 검색
  PID=$(pgrep -f "java -jar current.jar --server.port=${PORT}") || { log_info "No app running on port ${PORT}"; return; }
  log_info "Stopping app with PID: $PID"
  kill -15 "$PID"

  WAIT_TIME=0
  TIMEOUT=10
  while kill -0 "$PID" 2>/dev/null; do
    sleep 1
    WAIT_TIME=$((WAIT_TIME+1))
    if [ "$WAIT_TIME" -ge "$TIMEOUT" ]; then
      log_warn "Process $PID did not terminate after $TIMEOUT seconds, sending SIGKILL..."
      kill -9 "$PID"
      break
    fi
  done

  WAIT_TIME=0
  TIMEOUT=5
  while kill -0 "$PID" 2>/dev/null; do
    sleep 1
    WAIT_TIME=$((WAIT_TIME+1))
    if [ "$WAIT_TIME" -ge "$TIMEOUT" ]; then
      error_exit "Process $PID did not terminate even after SIGKILL"
    fi
  done

  log_success "Process $PID has terminated"
}

start_instance() {
  log_info "Starting application with command: $EXEC_COMMAND"
  nohup $EXEC_COMMAND >/dev/null 2>&1 &
  log_success "Application started on port $PORT"
}

case "$MODE" in
  restart)
    log_info "Restarting application on port $PORT"
    stop_instance
    start_instance
    ;;
  stop)
    log_info "Stopping application on port $PORT"
    stop_instance
    ;;
  start)
    log_info "Starting application on port $PORT"
    start_instance
    ;;
  *)
    error_exit "Invalid mode: use 'stop', 'start', or 'restart'"
    ;;
esac
