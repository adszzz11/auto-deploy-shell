#!/bin/bash
set -euo pipefail

# deploy_control.sh - Single Instance Deployment
#
# Layer: 3 (Core Operations)
# 역할: 단일 인스턴스 배포 실행
# 호출자: multi_deploy_control.sh (Layer 2)
# 호출 대상: nginx, link_jar, run_app, test_instance (Layer 4)
#
# 책임:
#   - 단일 인스턴스의 완전한 배포 라이프사이클
#   - 12단계 배포 프로세스 실행
#   - 에러 발생 시 안전한 복구
#   - Layer 4 서비스 모듈 오케스트레이션

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 모든 함수 스크립트들 source (func 디렉터리에서)
source "${SCRIPT_DIR}/func/validate_deployment.sh"
source "${SCRIPT_DIR}/func/prepare_deployment.sh"
source "${SCRIPT_DIR}/func/execute_deployment.sh"
source "${SCRIPT_DIR}/func/handle_removal.sh"

# 사용법 출력
print_usage() {
    cat << EOF
Usage: deploy_control.sh <command> [arguments]

Commands:
  deploy <instance_num> <env_file> [jar_name]     - Deploy instance
  remove <instance_num> <env_file>                - Remove instance
  status <instance_num> <env_file>                - Check deployment status
  validate <instance_num> <env_file>              - Validate deployment prerequisites

Note: Arguments in [brackets] are optional and can use defaults from deploy.env

Environment variables (set in deploy.env):
  DEPLOY_DEFAULT_ACTION         - Default action (default: deploy)
  DEPLOY_VALIDATE_JAR_DIR       - Validate JAR directory (default: true)
  DEPLOY_VALIDATE_INSTANCE_DIR  - Validate instance directory (default: true)
  DEPLOY_BACKUP_JAR             - Backup JAR before replacement (default: true)
  DEPLOY_BACKUP_RUNAPP          - Backup runApp script (default: true)
  DEPLOY_NGINX_CONTROL          - Enable nginx control (default: true)
  DEPLOY_NGINX_DOWN_ON_ERROR    - Set nginx down on error (default: true)
  DEPLOY_RUN_TESTS              - Run test script (default: true)
  DEPLOY_TEST_TIMEOUT           - Test timeout in seconds (default: 60)
  DEPLOY_AUTO_ROLLBACK          - Auto rollback on failure (default: false)
  DEPLOY_LOG_LEVEL              - Log level (default: INFO)

Examples:
  # Deploy instance using PID file
  ./deploy_control.sh deploy 0 /path/to/env.env

  # Deploy instance with specific JAR
  ./deploy_control.sh deploy 0 /path/to/env.env app-v1.0.jar

  # Remove instance
  ./deploy_control.sh remove 0 /path/to/env.env

  # Check deployment status
  ./deploy_control.sh status 0 /path/to/env.env

  # Validate deployment prerequisites
  ./deploy_control.sh validate 0 /path/to/env.env
EOF
}

# 환경 로드 및 변수 설정
load_environment() {
    local env_file="$1"
    local instance_num="$2"

    if [ ! -f "$env_file" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Environment file not found: $env_file" >&2
        return 1
    fi

    source "$env_file"

    # 필수 환경 변수 확인
    local required_vars=("SERVICE_NAME" "BASE_PORT" "SERVICE_BASE_DIR" "UPSTREAM_CONF")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Required environment variable not set: $var" >&2
            return 1
        fi
    done

    # 배포 변수 설정
    export PORT="${BASE_PORT}${instance_num}"
    export INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"
    export TARGET_LINK="${INSTANCE_DIR}/current.jar"
    export JAR_TRUNK_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/jar_trunk"  # 자동 생성

    # Machine ID 계산 (물리 서버 구분)
    local type="${TYPE:-A}"  # 기본값 A
    local machine_id_offset=0

    if [ "$type" = "B" ]; then
        machine_id_offset=5
    elif [ "$type" != "A" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Invalid TYPE: $type, using A (0-4)" >&2
        type="A"
    fi

    export MACHINE_ID=$((instance_num + machine_id_offset))

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Environment loaded: SERVICE=$SERVICE_NAME, PORT=$PORT, TYPE=$type, MACHINE_ID=$MACHINE_ID" >&2
    return 0
}

# 배포 실행 함수
execute_deploy() {
    local instance_num="$1"
    local env_file="$2"
    local jar_name="${3:-}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Starting deployment process" >&2

    # 1. 파라미터 검증
    validate_deploy_parameters "$instance_num" "$env_file" "deploy"

    # 2. 환경 로드
    load_environment "$env_file" "$instance_num"

    # 3. 필수 스크립트 검증
    validate_required_scripts "$SCRIPT_DIR"

    # 4. 배포 환경 준비
    prepare_deploy_environment "$INSTANCE_DIR" "$JAR_TRUNK_DIR"

    # 5. Nginx 트래픽 차단
    control_nginx_upstream "down" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_CONTROL:-true}" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to set nginx upstream DOWN" >&2
        return 1
    }

    # 6. JAR 백업
    backup_current_jar "$TARGET_LINK" "${DEPLOY_BACKUP_JAR:-true}" || {
        control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_DOWN_ON_ERROR:-true}"
        return 1
    }

    # 7. JAR 링크 생성
    create_jar_link "$JAR_TRUNK_DIR" "$TARGET_LINK" "$jar_name" "$SCRIPT_DIR" || {
        control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_DOWN_ON_ERROR:-true}"
        return 1
    }

    # 8. runApp.sh 동기화
    sync_runapp_script "$SCRIPT_DIR" "$INSTANCE_DIR" "${DEPLOY_BACKUP_RUNAPP:-true}" || {
        control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_DOWN_ON_ERROR:-true}"
        return 1
    }

    # 9. 로그 설정
    setup_instance_logs "$SERVICE_NAME" "$instance_num" "$INSTANCE_DIR" "$LOG_BASE_DIR" "$SCRIPT_DIR" || {
        control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_DOWN_ON_ERROR:-true}"
        return 1
    }

    # 10. 애플리케이션 배포
    execute_application_deployment "$INSTANCE_DIR" "$PORT" "${APP_MODE:-restart}" "${JAVA_OPTS:-}" "$SCRIPT_DIR" || {
        control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_DOWN_ON_ERROR:-true}"
        return 1
    }

    # 11. 테스트 실행 (사용자 정의 스크립트)
    execute_test_script "${TEST_SCRIPT:-}" "$PORT" "${DEPLOY_RUN_TESTS:-true}" "${DEPLOY_TEST_TIMEOUT:-60}" || {
        control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_DOWN_ON_ERROR:-true}"
        return 1
    }

    # 12. Nginx 트래픽 복구
    control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR" "${DEPLOY_NGINX_CONTROL:-true}" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to set nginx upstream UP" >&2
        return 1
    }

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Deployment completed for instance $instance_num (port $PORT)" >&2
    return 0
}

# 제거 실행 함수
execute_remove() {
    local instance_num="$1"
    local env_file="$2"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Starting instance removal process" >&2

    # 1. 파라미터 검증
    validate_deploy_parameters "$instance_num" "$env_file" "remove"

    # 2. 환경 로드
    load_environment "$env_file" "$instance_num"

    # 3. 인스턴스 제거
    handle_instance_removal "$INSTANCE_DIR" "$PORT" "$SCRIPT_DIR" "$UPSTREAM_CONF"

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance $instance_num removed successfully" >&2
    return 0
}

# 상태 확인 함수
check_status() {
    local instance_num="$1"
    local env_file="$2"

    load_environment "$env_file" "$instance_num"

    echo "=== Deployment Status ==="
    echo "Service: $SERVICE_NAME"
    echo "Instance: $instance_num"
    echo "Port: $PORT"
    echo "Instance Directory: $INSTANCE_DIR"
    echo ""

    # 인스턴스 디렉터리 확인
    if [ -d "$INSTANCE_DIR" ]; then
        echo "✅ Instance directory exists"

        # JAR 링크 확인
        if [ -L "$TARGET_LINK" ]; then
            local jar_target=$(readlink "$TARGET_LINK")
            echo "✅ JAR link: $TARGET_LINK -> $jar_target"
        else
            echo "❌ JAR link not found"
        fi

        # runApp.sh 확인
        if [ -x "${INSTANCE_DIR}/runApp.sh" ]; then
            echo "✅ runApp.sh exists and is executable"
        else
            echo "❌ runApp.sh not found or not executable"
        fi

        # 프로세스 확인
        if pgrep -f "java -jar current.jar --server.port=${PORT}" > /dev/null; then
            echo "✅ Application is running on port $PORT"
        else
            echo "❌ Application is not running"
        fi
    else
        echo "❌ Instance directory does not exist"
    fi
}

# 검증 함수
validate_prerequisites() {
    local instance_num="$1"
    local env_file="$2"

    echo "=== Deployment Validation ==="

    load_environment "$env_file" "$instance_num"

    # 1. JAR 디렉터리 검증
    if validate_jar_directory "$JAR_TRUNK_DIR" "${DEPLOY_VALIDATE_JAR_DIR:-true}"; then
        echo "✅ JAR directory validation passed"
    else
        echo "❌ JAR directory validation failed"
        return 1
    fi

    # 2. 필수 스크립트 검증
    if validate_required_scripts "$SCRIPT_DIR"; then
        echo "✅ Required scripts validation passed"
    else
        echo "❌ Required scripts validation failed"
        return 1
    fi

    echo "✅ All validations passed"
    return 0
}

# 메인 진입점
main() {
    if [ "$#" -lt 1 ]; then
        print_usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        deploy)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'deploy' requires <instance_num> <env_file> [jar_name]"
                exit 1
            fi
            execute_deploy "$@"
            ;;
        remove)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'remove' requires <instance_num> <env_file>"
                exit 1
            fi
            execute_remove "$@"
            ;;
        status)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'status' requires <instance_num> <env_file>"
                exit 1
            fi
            check_status "$@"
            ;;
        validate)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'validate' requires <instance_num> <env_file>"
                exit 1
            fi
            validate_prerequisites "$@"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
