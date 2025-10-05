#!/bin/bash
set -euo pipefail

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/..") && pwd)"
if [ -f "${SCRIPT_DIR}/deploy.env" ]; then
    source "${SCRIPT_DIR}/deploy.env"
fi

# 배포 파라미터 검증
validate_deploy_parameters() {
    local instance_num="$1"
    local env_file="$2"
    local action="$3"

    # 인스턴스 번호 검증 (0-9)
    if ! [[ "$instance_num" =~ ^[0-9]$ ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid instance number: $instance_num (must be 0-9)" >&2
        return 1
    fi

    # 환경 파일 존재 확인
    if [ ! -f "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
        return 1
    fi

    # 액션 검증
    if [[ "$action" != "deploy" ]] && [[ "$action" != "remove" ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Invalid action: $action (must be 'deploy' or 'remove')" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Parameters validated: instance=$instance_num, action=$action"
    return 0
}

# JAR 디렉터리 검증
validate_jar_directory() {
    local jar_dir="$1"
    local validate_enabled="${2:-${DEPLOY_VALIDATE_JAR_DIR:-true}}"

    if [ "$validate_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - JAR directory validation disabled"
        return 0
    fi

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

# 인스턴스 디렉터리 검증
validate_instance_directory() {
    local instance_dir="$1"
    local validate_enabled="${2:-${DEPLOY_VALIDATE_INSTANCE_DIR:-true}}"

    if [ "$validate_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Instance directory validation disabled"
        return 0
    fi

    if [ ! -d "$instance_dir" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Instance directory does not exist: $instance_dir"
        return 1
    fi

    if [ ! -w "$instance_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Instance directory not writable: $instance_dir" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Instance directory validated: $instance_dir"
    return 0
}

# 필수 스크립트 검증
validate_required_scripts() {
    local script_dir="$1"
    local required_scripts=(
        "nginx/nginx_control.sh"
        "link_jar/link_jar_control.sh"
        "run_app/run_app_control.sh"
    )

    for script in "${required_scripts[@]}"; do
        local script_path="${script_dir}/../${script}"

        if [ ! -x "$script_path" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Required script not found or not executable: $script_path" >&2
            return 1
        fi
    done

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - All required scripts validated"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: validate_deployment.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  params <instance_num> <env_file> <action>  - Validate deployment parameters"
        echo "  jar <jar_dir> [validate_enabled]           - Validate JAR directory"
        echo "  instance <instance_dir> [validate_enabled] - Validate instance directory"
        echo "  scripts <script_dir>                       - Validate required scripts"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        params)
            validate_deploy_parameters "$@"
            ;;
        jar)
            validate_jar_directory "$@"
            ;;
        instance)
            validate_instance_directory "$@"
            ;;
        scripts)
            validate_required_scripts "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
