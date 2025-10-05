#!/bin/bash
set -euo pipefail

# .env 파일 로드 (존재하는 경우)
SCRIPT_DIR="$(cd "$(dirname "$0")/..") && pwd)"
if [ -f "${SCRIPT_DIR}/deploy.env" ]; then
    source "${SCRIPT_DIR}/deploy.env"
fi

# 배포 실행
execute_application_deployment() {
    local instance_dir="$1"
    local port="$2"
    local app_mode="${3:-restart}"
    local java_opts="${4:-}"
    local script_dir="${5:-}"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Deploying application on port $port from $instance_dir"

    # run_app_control.sh 사용: <command> <port> [java_opts]
    local run_app_script="${script_dir}/../run_app/run_app_control.sh"

    if [ ! -x "$run_app_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - run_app_control.sh not found or not executable: $run_app_script" >&2
        return 1
    fi

    # 인스턴스 디렉터리로 이동하여 실행
    (
        cd "$instance_dir" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to change directory to $instance_dir" >&2
            return 1
        }

        # run_app_control.sh 실행
        "$run_app_script" "$app_mode" "$port" "$java_opts" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to execute run_app_control.sh" >&2
            return 1
        }
    ) || return 1

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Application deployment completed"
    return 0
}

# 테스트 실행 (test_instance 모듈 사용)
execute_instance_tests() {
    local port="$1"
    local env_file="$2"
    local script_dir="$3"
    local service_name="${4:-}"

    # test_instance 모듈이 비활성화된 경우
    if [ "${TEST_INSTANCE_ENABLED:-false}" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - test_instance module disabled"
        return 0
    fi

    local test_script="${script_dir}/../test_instance/test_instance_control.sh"

    if [ ! -x "$test_script" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - test_instance_control.sh not found or not executable: $test_script"
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Skipping instance tests"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running instance tests (mode: ${TEST_MODE:-simple})"

    # test_instance_control.sh 실행: test <port> [env_file]
    if "$test_script" test "$port" "$env_file"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance tests passed for port $port"
        return 0
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Instance tests failed for port $port" >&2
        return 1
    fi
}

# 레거시 테스트 스크립트 실행 (하위 호환성)
execute_test_script() {
    local test_script="$1"
    local port="$2"
    local run_tests="${3:-${DEPLOY_RUN_TESTS:-true}}"
    local test_timeout="${4:-${DEPLOY_TEST_TIMEOUT:-60}}"

    if [ "$run_tests" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Test execution disabled"
        return 0
    fi

    if [ -z "$test_script" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No legacy test script provided, skipping"
        return 0
    fi

    if [ ! -x "$test_script" ]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Test script not executable: $test_script"
        return 0
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running legacy test script on port $port"

    # 타임아웃과 함께 테스트 실행
    if timeout "$test_timeout" "$test_script" "$port"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Legacy tests passed for port $port"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Test timed out after ${test_timeout}s" >&2
        else
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Legacy tests failed for port $port" >&2
        fi
        return 1
    fi
}

# Nginx 업스트림 제어
control_nginx_upstream() {
    local action="$1"  # up or down
    local port="$2"
    local upstream_conf="$3"
    local script_dir="$4"
    local nginx_control="${5:-${DEPLOY_NGINX_CONTROL:-true}}"

    if [ "$nginx_control" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Nginx control disabled"
        return 0
    fi

    local nginx_script="${script_dir}/../nginx/nginx_control.sh"

    if [ ! -x "$nginx_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Nginx control script not found or not executable: $nginx_script" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Setting nginx upstream $action for port $port"

    # nginx_control.sh 사용: <command> [port] [upstream_conf]
    "$nginx_script" "$action" "$port" "$upstream_conf" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to set nginx upstream $action" >&2
        return 1
    }

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Nginx upstream $action completed"
    return 0
}

# JAR 링크 생성
create_jar_link() {
    local jar_dir="$1"
    local target_link="$2"
    local jar_name="${3:-}"
    local script_dir="$4"

    local link_jar_script="${script_dir}/../link_jar/link_jar_control.sh"

    if [ ! -x "$link_jar_script" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Link JAR script not found or not executable: $link_jar_script" >&2
        return 1
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Creating JAR symbolic link"

    # link_jar_control.sh 사용: link <jar_trunk_dir> <target_link> [jar_name|pid_file]
    if [ -n "$jar_name" ]; then
        # JAR 이름 직접 지정
        "$link_jar_script" link "$jar_dir" "$target_link" "$jar_name" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create JAR link" >&2
            return 1
        }
    else
        # PID 파일에서 읽기
        "$link_jar_script" link "$jar_dir" "$target_link" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create JAR link" >&2
            return 1
        }
    fi

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - JAR link created successfully"
    return 0
}

# 로그 설정
setup_instance_logs() {
    local service_name="$1"
    local instance_num="$2"
    local instance_dir="$3"
    local log_base_dir="$4"
    local script_dir="$5"

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Setting up logs for instance $instance_num"

    # 로그 디렉터리 생성
    local log_dir="${log_base_dir}/${service_name}/instance-${instance_num}"
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create log directory: $log_dir" >&2
            return 1
        }
    fi

    # 인스턴스 디렉터리에 로그 심볼릭 링크 생성
    local log_link="${instance_dir}/logs"
    if [ -L "$log_link" ]; then
        rm -f "$log_link"
    fi

    ln -s "$log_dir" "$log_link" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create log symbolic link" >&2
        return 1
    }

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Logs setup completed: $log_link -> $log_dir"
    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: execute_deployment.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  app <instance_dir> <port> <app_mode> [java_opts] <script_dir>           - Deploy application"
        echo "  test <test_script> <port> [run_tests] [timeout]                         - Execute test script"
        echo "  nginx <action> <port> <upstream_conf> <script_dir> [nginx_control]      - Control nginx upstream"
        echo "  link <jar_dir> <target_link> [jar_name] <script_dir>                    - Create JAR link"
        echo "  logs <service_name> <instance_num> <instance_dir> <log_dir> <script_dir> - Setup logs"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        app)
            execute_application_deployment "$@"
            ;;
        test)
            execute_test_script "$@"
            ;;
        nginx)
            control_nginx_upstream "$@"
            ;;
        link)
            create_jar_link "$@"
            ;;
        logs)
            setup_instance_logs "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
