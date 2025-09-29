#!/bin/bash
set -euo pipefail

# runApp 파라미터 유효성 검사 함수
validate_runapp_parameters() {
    local port="$1"
    local mode="$2"
    local java_opts="$3"
    local common_utils_dir="$4"

    # 파라미터 개수 검증
    if [ "$#" -ne 4 ]; then
        echo "Usage: validate_runapp_parameters <port> <mode> <java_opts> <common_utils_dir>"
        exit 1
    fi

    # 포트 번호 유효성 검증
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "❌ Invalid port number: $port. Port must be between 1-65535"
        exit 1
    fi

    # 모드 유효성 검증
    case "$mode" in
        "start"|"stop"|"restart")
            ;;
        *)
            echo "❌ Invalid mode: $mode. Use 'start', 'stop', or 'restart'"
            exit 1
            ;;
    esac

    # common_utils 디렉터리 존재 확인
    if [ ! -d "$common_utils_dir" ]; then
        echo "❌ Common utils directory does not exist: $common_utils_dir"
        exit 1
    fi

    # common_utils.sh 파일 존재 확인
    if [ ! -f "$common_utils_dir/common_utils.sh" ]; then
        echo "❌ common_utils.sh not found in: $common_utils_dir"
        exit 1
    fi

    echo "✅ Parameters validated: port=$port, mode=$mode, common_utils_dir=$common_utils_dir"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 4 ]; then
        echo "Usage: validate_runapp_parameters.sh <port> <mode> <java_opts> <common_utils_dir>"
        exit 1
    fi
    validate_runapp_parameters "$1" "$2" "$3" "$4"
fi