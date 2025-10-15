#!/bin/bash
set -euo pipefail

# upstream.conf 파일의 형식이 올바른지 검증
validate_upstream_format() {
    local upstream_conf="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Validating upstream configuration format" >&2

    # 파일 존재 여부 확인
    if [ ! -f "$upstream_conf" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Upstream configuration file not found: $upstream_conf" >&2
        return 1
    fi

    # upstream 블록이 존재하는지 확인
    if ! grep -q "^[[:space:]]*upstream" "$upstream_conf"; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - No 'upstream' block found in configuration" >&2
        return 1
    fi

    # 중괄호 짝 확인 (열린 { 개수와 닫힌 } 개수가 같아야 함)
    local open_braces=$(grep -o "{" "$upstream_conf" | wc -l)
    local close_braces=$(grep -o "}" "$upstream_conf" | wc -l)

    if [ "$open_braces" -ne "$close_braces" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Mismatched braces in configuration (open: $open_braces, close: $close_braces)" >&2
        return 1
    fi

    # server 지시자 형식 검증 (기본적인 패턴 확인)
    if grep -v "^#" "$upstream_conf" | grep "server" | grep -v "server[[:space:]]\+[0-9.]\+:[0-9]\+;" > /dev/null 2>&1; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Some server directives may have incorrect format" >&2
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Upstream configuration format is valid" >&2
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: validate_upstream_format.sh <upstream_conf>"
        exit 1
    fi
    validate_upstream_format "$1"
fi
