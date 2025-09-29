#!/bin/bash
set -euo pipefail

# 현재 날짜와 시간을 반환하는 함수
current_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    current_timestamp
fi