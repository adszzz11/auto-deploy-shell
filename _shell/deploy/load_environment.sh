#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 환경 변수 로드 및 검증 함수
load_environment() {
    local env_file="$1"

    log_info "Loading environment from: $env_file"

    # 환경 파일 source
    source "$env_file"

    log_success "Environment loaded from: $env_file"
}

# 필수 환경 변수 검증 함수
validate_required_env_vars() {
    local required_vars=(
        "BASE_PORT"
        "SERVICE_BASE_DIR"
        "SERVICE_NAME"
        "JAR_TRUNK_DIR"
        "UPSTREAM_CONF"
        "LOG_BASE_DIR"
        "APP_MODE"
    )

    log_info "Validating required environment variables"

    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error_exit "Required environment variable not set: $var"
        fi
        log_info "✅ $var: ${!var}"
    done

    # 선택적 환경 변수 확인
    log_info "Optional environment variables:"
    log_info "  JAVA_OPTS: ${JAVA_OPTS:-'(not set)'}"
    log_info "  TEST_SCRIPT: ${TEST_SCRIPT:-'(not set)'}"

    log_success "Environment variables validated"
}

# 환경 변수 기반 경로 계산 함수
calculate_deploy_paths() {
    local instance_num="$1"

    # 포트 계산
    export PORT="${BASE_PORT}${instance_num}"

    # 인스턴스 디렉터리 계산
    export INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"

    # JAR 링크 경로 계산
    export TARGET_LINK="${INSTANCE_DIR}/current.jar"

    log_info "Calculated deployment paths:"
    log_info "  PORT: $PORT"
    log_info "  INSTANCE_DIR: $INSTANCE_DIR"
    log_info "  TARGET_LINK: $TARGET_LINK"
}

# 환경 디렉터리 검증 함수
validate_environment_directories() {
    log_info "Validating environment directories"

    # JAR 트렁크 디렉터리 확인
    if [ ! -d "$JAR_TRUNK_DIR" ]; then
        error_exit "JAR trunk directory not found: $JAR_TRUNK_DIR"
    fi
    log_info "✅ JAR trunk directory: $JAR_TRUNK_DIR"

    # 서비스 베이스 디렉터리 확인
    if [ ! -d "$SERVICE_BASE_DIR" ]; then
        error_exit "Service base directory not found: $SERVICE_BASE_DIR"
    fi
    log_info "✅ Service base directory: $SERVICE_BASE_DIR"

    # Nginx 설정 파일 확인
    if [ ! -f "$UPSTREAM_CONF" ]; then
        error_exit "Nginx upstream configuration not found: $UPSTREAM_CONF"
    fi
    log_info "✅ Nginx upstream configuration: $UPSTREAM_CONF"

    log_success "Environment directories validated"
}

# 전체 환경 로드 및 검증 함수
load_and_validate_environment() {
    local env_file="$1"
    local instance_num="$2"

    # 1. 환경 파일 로드
    load_environment "$env_file"

    # 2. 필수 환경 변수 검증
    validate_required_env_vars

    # 3. 배포 경로 계산
    calculate_deploy_paths "$instance_num"

    # 4. 환경 디렉터리 검증
    validate_environment_directories

    log_success "Environment fully loaded and validated"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -ne 2 ]; then
        echo "Usage: load_environment.sh <env_file> <instance_number>"
        exit 1
    fi
    load_and_validate_environment "$1" "$2"
fi