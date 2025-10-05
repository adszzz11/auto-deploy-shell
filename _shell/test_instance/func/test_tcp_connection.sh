#!/bin/bash
set -euo pipefail

# test_tcp_connection.sh - TCP Connection Testing


# TCP 연결 테스트 (nc 사용)
test_tcp_with_nc() {
    local host="$1"
    local port="$2"
    local timeout="$3"

    if nc -z -w "$timeout" "$host" "$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# TCP 연결 테스트 (/dev/tcp 사용)
test_tcp_with_dev_tcp() {
    local host="$1"
    local port="$2"
    local timeout="$3"

    if timeout "$timeout" bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# TCP 연결 테스트 (telnet 사용)
test_tcp_with_telnet() {
    local host="$1"
    local port="$2"
    local timeout="$3"

    if timeout "$timeout" telnet "$host" "$port" </dev/null 2>&1 | grep -q "Connected"; then
        return 0
    else
        return 1
    fi
}

# TCP 연결 테스트 (자동 도구 선택)
test_tcp_connection_single() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Testing TCP connection to $host:$port (timeout: ${timeout}s)"

    # nc(netcat)가 있으면 사용
    if command -v nc &> /dev/null; then
        if test_tcp_with_nc "$host" "$port" "$timeout"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - TCP connection successful (nc)"
            return 0
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - TCP connection failed (nc)" >&2
            return 1
        fi
    fi

    # /dev/tcp 사용 (bash 내장)
    if test_tcp_with_dev_tcp "$host" "$port" "$timeout"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - TCP connection successful (/dev/tcp)"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - TCP connection failed (/dev/tcp)" >&2

        # telnet으로 재시도 (최후의 수단)
        if command -v telnet &> /dev/null; then
            if test_tcp_with_telnet "$host" "$port" "$timeout"; then
                echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - TCP connection successful (telnet)"
                return 0
            fi
        fi

        return 1
    fi
}

# TCP 연결 테스트 (재시도 포함)
test_tcp_connection_with_retry() {
    local port="$1"
    local host="${TEST_HOST:-localhost}"
    local timeout="${TEST_TCP_TIMEOUT:-5}"
    local retry_count="${TEST_RETRY_COUNT:-3}"
    local retry_delay="${TEST_RETRY_DELAY:-5}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Testing TCP connectivity: $host:$port"

    local attempt=1
    while [ $attempt -le $retry_count ]; do
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Attempt $attempt/$retry_count"

        if test_tcp_connection_single "$host" "$port" "$timeout"; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - TCP test passed on attempt $attempt"
            return 0
        fi

        if [ $attempt -lt $retry_count ]; then
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - TCP test failed, retrying in ${retry_delay}s..."
            sleep "$retry_delay"
        fi

        attempt=$((attempt + 1))
    done

    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - TCP test failed after $retry_count attempts" >&2
    return 1
}

# 포트가 LISTEN 상태인지 확인
test_port_listening() {
    local port="$1"
    local host="${TEST_HOST:-localhost}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Checking if port $port is in LISTEN state"

    # netstat 사용 (macOS/Linux 호환)
    if command -v netstat &> /dev/null; then
        if netstat -an 2>/dev/null | grep -E "(:${port}|\.${port})" | grep -q LISTEN; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is in LISTEN state (netstat)"
            return 0
        fi
    fi

    # ss 사용 (Linux)
    if command -v ss &> /dev/null; then
        if ss -an 2>/dev/null | grep -E ":${port}" | grep -q LISTEN; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is in LISTEN state (ss)"
            return 0
        fi
    fi

    # lsof 사용 (macOS/Linux)
    if command -v lsof &> /dev/null; then
        if lsof -i ":${port}" -sTCP:LISTEN &> /dev/null; then
            echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is in LISTEN state (lsof)"
            return 0
        fi
    fi

    # TCP 연결 테스트로 폴백
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - No port checking tools found, falling back to connection test"
    if test_tcp_connection_single "$host" "$port" 2; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is accessible (connection test)"
        return 0
    fi

    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Port $port is not in LISTEN state" >&2
    return 1
}

# 포트에서 실행 중인 프로세스 확인
check_port_process() {
    local port="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Checking process on port $port"

    # lsof 사용
    if command -v lsof &> /dev/null; then
        local process_info
        if process_info=$(lsof -i ":${port}" -sTCP:LISTEN 2>/dev/null); then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Process information:"
            echo "$process_info" | head -5
            return 0
        fi
    fi

    # netstat + ps 조합 (macOS)
    if command -v netstat &> /dev/null && [[ "$OSTYPE" == "darwin"* ]]; then
        local pid
        if pid=$(netstat -anv 2>/dev/null | grep "\.${port} " | grep LISTEN | awk '{print $9}' | head -1); then
            if [ -n "$pid" ]; then
                echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - PID: $pid"
                ps -p "$pid" 2>/dev/null || true
                return 0
            fi
        fi
    fi

    # ss 사용 (Linux)
    if command -v ss &> /dev/null; then
        local process_info
        if process_info=$(ss -tlnp 2>/dev/null | grep ":${port} "); then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Process information:"
            echo "$process_info"
            return 0
        fi
    fi

    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Could not determine process information"
    return 1
}

# 통합 TCP 테스트
test_tcp_full() {
    local port="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running full TCP test for port $port"

    # 1. 포트 LISTEN 상태 확인
    if ! test_port_listening "$port"; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Port not in LISTEN state, proceeding with connection test"
    fi

    # 2. TCP 연결 테스트
    if ! test_tcp_connection_with_retry "$port"; then
        return 1
    fi

    # 3. 프로세스 정보 확인 (선택적)
    if [ "${TEST_VERBOSE:-false}" = "true" ]; then
        check_port_process "$port" || true
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Full TCP test passed"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: test_tcp_connection.sh <port> [host] [timeout]"
        exit 1
    fi

    port="$1"

    if [ "$#" -ge 2 ]; then
        export TEST_HOST="$2"
    fi

    if [ "$#" -ge 3 ]; then
        export TEST_TCP_TIMEOUT="$3"
    fi

    test_tcp_connection_with_retry "$port"
fi
