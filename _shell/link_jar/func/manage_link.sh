#!/bin/bash
set -euo pipefail


# 기존 링크/파일 제거
remove_existing_link() {
    local target_link="$1"
    local backup_enabled="${2:-${LINK_JAR_BACKUP_ENABLED:-true}}"
    local backup_suffix="${3:-${LINK_JAR_BACKUP_SUFFIX:-.bak}}"

    if [ -L "$target_link" ] || [ -e "$target_link" ]; then
        if [ "$backup_enabled" = "true" ]; then
            local backup_file="${target_link}${backup_suffix}"
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backing up existing file: $target_link -> $backup_file"
            mv "$target_link" "$backup_file" || {
                echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to backup existing file" >&2
                return 1
            }
        else
            echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Removing existing link/file at $target_link"
            rm -f "$target_link" || {
                echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to remove existing link/file" >&2
                return 1
            }
        fi
    fi
}

# 심볼릭 링크 생성
create_symbolic_link() {
    local jar_path="$1"
    local target_link="$2"
    local verify="${3:-${LINK_JAR_VERIFY_LINK:-true}}"

    # 심볼릭 링크 생성
    if ln -s "$jar_path" "$target_link"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Symbolic link created: $target_link -> $jar_path"
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create symbolic link" >&2
        return 1
    fi

    # 생성된 링크 검증
    if [ "$verify" = "true" ]; then
        if [ -L "$target_link" ] && [ -e "$target_link" ]; then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Symbolic link verification passed"
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Symbolic link verification failed: $target_link" >&2
            return 1
        fi
    fi
}

# 링크 정보 조회
get_link_info() {
    local target_link="$1"

    if [ -L "$target_link" ]; then
        local link_target=$(readlink "$target_link")
        echo "Type: Symbolic Link"
        echo "Link: $target_link"
        echo "Target: $link_target"

        if [ -e "$target_link" ]; then
            echo "Status: Valid (target exists)"
        else
            echo "Status: Broken (target missing)"
        fi
    elif [ -e "$target_link" ]; then
        echo "Type: Regular File"
        echo "Path: $target_link"
    else
        echo "Not found: $target_link"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: manage_link.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  remove <target_link> [backup_enabled] [backup_suffix]  - Remove existing link/file"
        echo "  create <jar_path> <target_link> [verify]               - Create symbolic link"
        echo "  info <target_link>                                      - Get link information"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        remove)
            remove_existing_link "$@"
            ;;
        create)
            create_symbolic_link "$@"
            ;;
        info)
            get_link_info "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
