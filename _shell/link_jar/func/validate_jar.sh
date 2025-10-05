#!/bin/bash
set -euo pipefail


# JAR 파일명 유효성 검증
validate_jar_name() {
    local jar_name="$1"
    local validate_ext="${2:-${LINK_JAR_VALIDATE_EXTENSION:-true}}"

    # 비어있는지 확인
    if [ -z "$jar_name" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR name is empty" >&2
        return 1
    fi

    # .jar 확장자 확인
    if [ "$validate_ext" = "true" ]; then
        if [[ "$jar_name" != *.jar ]]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid jar name '$jar_name'. Expected a file ending with .jar" >&2
            return 1
        fi
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - JAR name validated: $jar_name"
    return 0
}

# JAR 파일 존재 확인
validate_jar_file_exists() {
    local jar_dir="$1"
    local jar_name="$2"
    local jar_path="${jar_dir}/${jar_name}"

    if [ ! -f "$jar_path" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR file not found: $jar_path" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - JAR file verified: $jar_path"
    echo "$jar_path"
}

# JAR 디렉터리 검증
validate_jar_directory() {
    local jar_dir="$1"

    if [ ! -d "$jar_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR directory not found: $jar_dir" >&2
        return 1
    fi

    if [ ! -r "$jar_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR directory not readable: $jar_dir" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - JAR directory validated: $jar_dir"
    return 0
}

# 타겟 디렉터리 검증
validate_target_directory() {
    local target_link="$1"
    local target_dir=$(dirname "$target_link")

    if [ ! -d "$target_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Target directory does not exist: $target_dir" >&2
        return 1
    fi

    if [ ! -w "$target_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Target directory not writable: $target_dir" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Target directory validated: $target_dir"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: validate_jar.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  name <jar_name> [validate_extension]  - Validate JAR file name"
        echo "  file <jar_dir> <jar_name>             - Validate JAR file exists"
        echo "  dir <jar_dir>                         - Validate JAR directory"
        echo "  target <target_link_path>             - Validate target directory"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        name)
            validate_jar_name "$@"
            ;;
        file)
            validate_jar_file_exists "$@"
            ;;
        dir)
            validate_jar_directory "$@"
            ;;
        target)
            validate_target_directory "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
