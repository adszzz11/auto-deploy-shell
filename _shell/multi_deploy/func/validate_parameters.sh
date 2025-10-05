#!/bin/bash
set -euo pipefail


# 다중 배포 파라미터 검증
validate_multi_deploy_parameters() {
    local target_count="$1"
    local env_file_raw="$2"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Validating multi-deploy parameters"

    # 타겟 인스턴스 수 유효성 검증
    if ! [[ "$target_count" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Target instance count must be a valid number: $target_count" >&2
        return 1
    fi

    local min_instances=2  # 하드코딩: 최소 2개 인스턴스 필수
    local max_instances=5  # 하드코딩: 최대 5개 인스턴스 고정

    if [ "$target_count" -lt "$min_instances" ] || [ "$target_count" -gt "$max_instances" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Target instance count must be between $min_instances-$max_instances: $target_count" >&2
        return 1
    fi

    # 환경 파일 이름에서 CR(\r) 제거
    local env_file
    env_file="$(echo "$env_file_raw" | tr -d '\r')"

    # 환경 파일 존재 확인
    if [ ! -f "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
        return 1
    fi

    # 환경 파일 읽기 권한 확인
    if [ ! -r "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file is not readable: $env_file" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Parameters validated: target_count=$target_count, env_file=$env_file"
    echo "$env_file"  # 정제된 환경 파일 경로 반환
}

# 필수 환경 변수 검증
validate_required_env_vars() {
    local env_file="$1"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Validating required environment variables"

    # 환경 파일 로드
    source "$env_file"

    local missing_vars=()
    [ -z "${SERVICE_NAME:-}" ] && missing_vars+=("SERVICE_NAME")
    [ -z "${SERVICE_BASE_DIR:-}" ] && missing_vars+=("SERVICE_BASE_DIR")
    [ -z "${BASE_PORT:-}" ] && missing_vars+=("BASE_PORT")
    [ -z "${UPSTREAM_CONF:-}" ] && missing_vars+=("UPSTREAM_CONF")

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Missing required environment variables: ${missing_vars[*]}" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - All required environment variables present"
    return 0
}

# 인스턴스 디렉터리 검증
validate_instance_directories() {
    local service_base_dir="$1"
    local service_name="$2"

    local service_instances_dir="${service_base_dir}/${service_name}/instances"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Validating instance directories"

    # 서비스 베이스 디렉터리 확인
    if [ ! -d "$service_base_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Service base directory not found: $service_base_dir" >&2
        return 1
    fi

    # 서비스 디렉터리 확인 (없으면 생성)
    local service_dir="${service_base_dir}/${service_name}"
    if [ ! -d "$service_dir" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Creating service directory: $service_dir"
        mkdir -p "$service_dir" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create service directory: $service_dir" >&2
            return 1
        }
    fi

    # 인스턴스 디렉터리 확인 (없으면 생성)
    if [ ! -d "$service_instances_dir" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Creating instances directory: $service_instances_dir"
        mkdir -p "$service_instances_dir" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create instances directory: $service_instances_dir" >&2
            return 1
        }
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance directories validated"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: validate_parameters.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  params <target_count> <env_file>         - Validate multi-deploy parameters"
        echo "  env <env_file>                            - Validate required environment variables"
        echo "  dirs <service_base_dir> <service_name>    - Validate instance directories"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        params)
            validate_multi_deploy_parameters "$@"
            ;;
        env)
            validate_required_env_vars "$@"
            ;;
        dirs)
            validate_instance_directories "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
