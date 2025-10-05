#!/bin/bash
set -euo pipefail

# run_custom_tests.sh - Custom Test Execution

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${SCRIPT_DIR}/test_instance.env" ]; then
    source "${SCRIPT_DIR}/test_instance.env"
fi

# 커스텀 테스트 스크립트 실행
run_custom_test_script() {
    local port="$1"
    local service_name="${2:-}"
    local env_file="${3:-}"
    local test_script="${TEST_CUSTOM_SCRIPT:-}"
    local timeout="${TEST_CUSTOM_TIMEOUT:-60}"
    local pass_env="${TEST_CUSTOM_PASS_ENV:-true}"

    if [ -z "$test_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - No custom test script specified (TEST_CUSTOM_SCRIPT)" >&2
        return 1
    fi

    if [ ! -f "$test_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Custom test script not found: $test_script" >&2
        return 1
    fi

    if [ ! -x "$test_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Custom test script not executable: $test_script" >&2
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Run: chmod +x $test_script"
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running custom test script: $test_script"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Arguments: port=$port, service=$service_name, env_file=$env_file"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Timeout: ${timeout}s"

    # 테스트 스크립트 인자 구성
    local test_args=("$port")

    if [ -n "$service_name" ]; then
        test_args+=("$service_name")
    fi

    if [ "$pass_env" = "true" ] && [ -n "$env_file" ]; then
        test_args+=("$env_file")
    fi

    # 타임아웃과 함께 실행
    local start_time=$(date +%s)
    local exit_code=0

    if ! timeout "$timeout" "$test_script" "${test_args[@]}" 2>&1; then
        exit_code=$?
    fi

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Custom test completed in ${elapsed}s"

    if [ "$exit_code" -eq 124 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Custom test timed out after ${timeout}s" >&2
        return 1
    elif [ "$exit_code" -ne 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Custom test failed with exit code $exit_code" >&2
        return 1
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Custom test passed"
    return 0
}

# 디렉터리 내 모든 테스트 스크립트 실행
run_custom_test_directory() {
    local port="$1"
    local service_name="${2:-}"
    local env_file="${3:-}"
    local test_dir="${TEST_CUSTOM_SCRIPT:-}"

    if [ ! -d "$test_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Test directory not found: $test_dir" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running all tests in directory: $test_dir"

    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$test_dir" -type f -name "*.sh" -executable -print0 | sort -z)

    if [ ${#test_files[@]} -eq 0 ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - No executable test scripts found in $test_dir"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Found ${#test_files[@]} test scripts"

    local passed=0
    local failed=0
    local failed_tests=()

    for test_file in "${test_files[@]}"; do
        local test_name=$(basename "$test_file")
        echo ""
        echo "==================================================[ Running: $test_name ]==="

        # 임시로 TEST_CUSTOM_SCRIPT 설정
        local original_script="${TEST_CUSTOM_SCRIPT}"
        export TEST_CUSTOM_SCRIPT="$test_file"

        if run_custom_test_script "$port" "$service_name" "$env_file"; then
            echo "[PASS] $test_name"
            passed=$((passed + 1))
        else
            echo "[FAIL] $test_name"
            failed=$((failed + 1))
            failed_tests+=("$test_name")
        fi

        # 원래 값 복원
        export TEST_CUSTOM_SCRIPT="$original_script"
    done

    echo ""
    echo "=== Custom Test Suite Results ==="
    echo "Total:  ${#test_files[@]}"
    echo "Passed: $passed"
    echo "Failed: $failed"

    if [ $failed -gt 0 ]; then
        echo ""
        echo "Failed tests:"
        for test_name in "${failed_tests[@]}"; do
            echo "  - $test_name"
        done
        return 1
    fi

    echo ""
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - All custom tests passed"
    return 0
}

# 커스텀 테스트 (스크립트 또는 디렉터리)
run_custom_tests() {
    local port="$1"
    local service_name="${2:-}"
    local env_file="${3:-}"
    local test_path="${TEST_CUSTOM_SCRIPT:-}"

    if [ -z "$test_path" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - No custom tests specified"
        return 0
    fi

    if [ ! -e "$test_path" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Test path not found: $test_path" >&2
        return 1
    fi

    if [ -d "$test_path" ]; then
        # 디렉터리: 모든 .sh 파일 실행
        run_custom_test_directory "$port" "$service_name" "$env_file"
    elif [ -f "$test_path" ]; then
        # 파일: 단일 스크립트 실행
        run_custom_test_script "$port" "$service_name" "$env_file"
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid test path: $test_path" >&2
        return 1
    fi
}

# 간단한 인라인 테스트 실행
run_inline_test() {
    local port="$1"
    local test_command="$2"
    local test_name="${3:-Inline Test}"
    local timeout="${TEST_CUSTOM_TIMEOUT:-60}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running inline test: $test_name"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Command: $test_command"

    local start_time=$(date +%s)
    local exit_code=0

    if ! timeout "$timeout" bash -c "$test_command" 2>&1; then
        exit_code=$?
    fi

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    if [ "$exit_code" -eq 124 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Test timed out after ${timeout}s" >&2
        return 1
    elif [ "$exit_code" -ne 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Test failed with exit code $exit_code" >&2
        return 1
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Test passed in ${elapsed}s"
    return 0
}

# 테스트 결과 로깅
log_test_result() {
    local port="$1"
    local test_name="$2"
    local result="$3"  # pass | fail
    local duration="$4"
    local details="${5:-}"

    if [ "${TEST_LOG_RESULTS:-false}" != "true" ]; then
        return 0
    fi

    local log_dir="${TEST_LOG_DIR:-/tmp/test_instance_logs}"
    mkdir -p "$log_dir"

    local log_file="${log_dir}/test_results_$(date '+%Y%m%d').log"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$timestamp | PORT=$port | TEST=$test_name | RESULT=$result | DURATION=${duration}s | DETAILS=$details" >> "$log_file"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Test result logged to $log_file"
}

# 실패 리포트 생성
create_failure_report() {
    local port="$1"
    local test_name="$2"
    local error_output="$3"

    if [ "${TEST_CREATE_FAILURE_REPORT:-true}" != "true" ]; then
        return 0
    fi

    local report_dir="${TEST_FAILURE_REPORT_DIR:-/tmp/test_failures}"
    mkdir -p "$report_dir"

    local report_file="${report_dir}/failure_port${port}_$(date '+%Y%m%d_%H%M%S').txt"

    cat > "$report_file" << EOF
=== Test Failure Report ===
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Port: $port
Test: $test_name

Error Output:
$error_output

Environment:
$(env | grep -E '^(TEST_|SERVICE_|PORT|BASE_PORT)' || true)

System Info:
Hostname: $(hostname)
User: $(whoami)
OS: $(uname -s)
EOF

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Failure report created: $report_file"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: run_custom_tests.sh <port> [service_name] [env_file]"
        exit 1
    fi

    run_custom_tests "$@"
fi
