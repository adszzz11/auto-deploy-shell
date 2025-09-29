#!/bin/bash
set -euo pipefail

# TCP 연결 테스트 함수
test_tcp_connection() {
    local port="$1"
    local host="${2:-localhost}"

    echo "Testing TCP connection to $host:$port"

    # nc (netcat) 명령어 존재 확인
    if ! command -v nc &>/dev/null; then
        echo "⚠️ nc (netcat) command not found. Skipping TCP connection test."
        return 0
    fi

    # TCP 연결 테스트
    if nc -z "$host" "$port" 2>/dev/null; then
        echo "✅ TCP connection test passed: Port $port is open on $host"
        return 0
    else
        echo "❌ TCP connection test failed: Port $port is not open on $host"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: test_tcp_connection.sh <port> [host]"
        echo "Example: test_tcp_connection.sh 8080"
        echo "Example: test_tcp_connection.sh 8080 localhost"
        exit 1
    fi

    test_tcp_connection "$@"
fi