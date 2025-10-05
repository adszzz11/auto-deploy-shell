#!/bin/bash
set -euo pipefail

# 설정 파일 변경 전 백업 생성
backup_config() {
    local config_file="$1"
    local backup_file="${config_file}.bak.$(date +%Y%m%d_%H%M%S)"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backing up configuration file"

    if [ ! -f "$config_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Configuration file not found: $config_file"
        return 1
    fi

    if cp "$config_file" "$backup_file"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Configuration backed up to: $backup_file"
        echo "$backup_file"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to backup configuration file"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 1 ]; then
        echo "Usage: backup_config.sh <config_file>"
        exit 1
    fi
    backup_config "$1"
fi
