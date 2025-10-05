#!/bin/bash
set -euo pipefail

# validate_test_params.sh - Test Parameter Validation

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${SCRIPT_DIR}/test_instance.env" ]; then
    source "${SCRIPT_DIR}/test_instance.env"
fi

# 필수 환경 변수 검증
validate_required_env_vars() {
    local missing_vars=()

    # PORT는 테스트 대상이므로 필수는 아님 (파라미터로 받음)
    # SERVICE_NAME도 선택적

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Missing required environment variables: ${missing_vars[*]}" >&2
        return 1
    fi

    return 0
}

# 테스트 파라미터 검증
validate_test_parameters() {
    local port="$1"
    local env_file="${2:-}"

    # 포트 검증
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid port: $port (must be numeric)" >&2
        return 1
    fi

    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid port: $port (must be 1-65535)" >&2
        return 1
    fi

    # env_file 검증 (선택적)
    if [ -n "$env_file" ]; then
        if [ ! -f "$env_file" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
            return 1
        fi

        if [ ! -r "$env_file" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not readable: $env_file" >&2
            return 1
        fi
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Test parameters validated: port=$port"
    return 0
}

# 테스트 모드 검증
validate_test_mode() {
    local mode="${TEST_MODE:-simple}"

    case "$mode" in
        simple|full|custom)
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Test mode: $mode"
            return 0
            ;;
        *)
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid test mode: $mode (must be simple, full, or custom)" >&2
            return 1
            ;;
    esac
}

# 커스텀 테스트 스크립트 검증
validate_custom_test_script() {
    local test_script="${TEST_CUSTOM_SCRIPT:-}"

    if [ -z "$test_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Custom test mode requires TEST_CUSTOM_SCRIPT" >&2
        return 1
    fi

    if [ ! -f "$test_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Custom test script not found: $test_script" >&2
        return 1
    fi

    if [ ! -x "$test_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Custom test script not executable: $test_script" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Custom test script validated: $test_script"
    return 0
}

# 테스트 설정 검증
validate_test_configuration() {
    local mode="${TEST_MODE:-simple}"

    # 공통 검증
    validate_test_mode

    # 타임아웃 검증
    local timeout="${TEST_TIMEOUT:-30}"
    if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -lt 1 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid TEST_TIMEOUT: $timeout" >&2
        return 1
    fi

    # 재시도 설정 검증
    local retry_count="${TEST_RETRY_COUNT:-3}"
    if ! [[ "$retry_count" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid TEST_RETRY_COUNT: $retry_count" >&2
        return 1
    fi

    local retry_delay="${TEST_RETRY_DELAY:-5}"
    if ! [[ "$retry_delay" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid TEST_RETRY_DELAY: $retry_delay" >&2
        return 1
    fi

    # 모드별 검증
    case "$mode" in
        custom)
            validate_custom_test_script
            ;;
        full)
            # Full 모드는 HTTP + TCP + Response Time
            local max_response_time="${TEST_MAX_RESPONSE_TIME:-1000}"
            if ! [[ "$max_response_time" =~ ^[0-9]+$ ]] || [ "$max_response_time" -lt 1 ]; then
                echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid TEST_MAX_RESPONSE_TIME: $max_response_time" >&2
                return 1
            fi
            ;;
    esac

    return 0
}

# HTTP 엔드포인트 검증
validate_http_endpoint() {
    local endpoint="${TEST_HTTP_ENDPOINT:-/actuator/health}"

    # 엔드포인트는 /로 시작해야 함
    if [[ ! "$endpoint" =~ ^/ ]]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - HTTP endpoint should start with /: $endpoint"
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Auto-correcting to: /$endpoint"
        export TEST_HTTP_ENDPOINT="/$endpoint"
    fi

    return 0
}

# 포트 접근성 사전 검증
validate_port_accessibility() {
    local port="$1"
    local host="${TEST_HOST:-localhost}"

    # 포트가 리스닝 중인지 확인 (nc 또는 /dev/tcp 사용)
    if command -v nc &> /dev/null; then
        if ! nc -z "$host" "$port" 2>/dev/null; then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is not accessible (may not be listening yet)"
            return 1
        fi
    else
        # nc가 없으면 /dev/tcp 사용
        if ! timeout 2 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is not accessible (may not be listening yet)"
            return 1
        fi
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is accessible"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: validate_test_params.sh <port> [env_file]"
        exit 1
    fi

    validate_test_parameters "$@"
fi
