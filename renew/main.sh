#!/bin/bash
set -euo pipefail

# main.sh - Auto Deploy Shell Main Entry Point
#
# 역할: 사용자가 사용하는 유일한 진입점
# 책임: multi_deploy 모듈만 호출 (계층 구조 준수)
#
# 계층 구조:
#   Layer 1 (User Interface): main.sh
#              ↓
#   Layer 2 (Orchestration): multi_deploy
#              ↓
#   Layer 3 (Core Ops): deploy, rollback
#              ↓
#   Layer 4 (Services): nginx, link_jar, run_app, test_instance

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 버전 정보
VERSION="2.0.0"
MODULE_NAME="Auto Deploy Shell (Renew)"

# 색상 정의 (출력용)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 사용법 출력
print_usage() {
    cat << EOF
${MODULE_NAME} v${VERSION}

Usage: main.sh <command> [arguments]

Commands:
  deploy <count> <env_file>           - Deploy multiple instances (2-10)
  rollback <env_file>                 - Rollback all instances
  status <env_file>                   - Show deployment status
  validate <count> <env_file>         - Validate before deployment
  version                             - Show version information
  help                                - Show this help message

Environment File:
  You only need to manage ONE config file: base.env

  1. Copy template:    cp base.env myapp.env
  2. Edit settings:    vi myapp.env
  3. Deploy:           ./main.sh deploy 5 myapp.env

  Module .env files (deploy.env, nginx.env, etc.) provide defaults.
  Your base.env overrides them all.

Examples:
  # First time setup
  cp base.env myapp.env
  vi myapp.env  # Edit SERVICE_NAME, BASE_PORT, etc.

  # Deploy 5 instances
  ./main.sh deploy 5 myapp.env

  # Check deployment status
  ./main.sh status myapp.env

  # Rollback all instances
  ./main.sh rollback myapp.env

  # Validate before deployment
  ./main.sh validate 5 myapp.env

Architecture:
  Layer 1 (UI):     main.sh (this script)
  Layer 2 (Orch):   multi_deploy
  Layer 3 (Core):   deploy, rollback
  Layer 4 (Svc):    nginx, link_jar, run_app, test_instance

Advanced Usage (for debugging or single instance control):
  # Multi-deploy module directly
  ${SCRIPT_DIR}/multi_deploy/multi_deploy_control.sh --help

  # Individual modules (Layer 3-4)
  ${SCRIPT_DIR}/deploy/deploy_control.sh --help
  ${SCRIPT_DIR}/rollback/rollback_control.sh --help
  ${SCRIPT_DIR}/test_instance/test_instance_control.sh --help

Documentation:
  ${SCRIPT_DIR}/README.md          - User guide
  ${SCRIPT_DIR}/ARCHITECTURE.md    - System architecture
  ${SCRIPT_DIR}/HIERARCHY.md       - Module hierarchy

Note: For most use cases, use this main.sh script only.
      Direct module access is for advanced users.
EOF
}

# 버전 정보 출력
print_version() {
    cat << EOF
${MODULE_NAME}
Version: ${VERSION}
Location: ${SCRIPT_DIR}

Module Hierarchy:
  Layer 1 (User Interface):
    └─ main.sh (this script)

  Layer 2 (Orchestration):
    └─ multi_deploy/multi_deploy_control.sh

  Layer 3 (Core Operations):
    ├─ deploy/deploy_control.sh
    └─ rollback/rollback_control.sh

  Layer 4 (Support Services):
    ├─ nginx/nginx_control.sh
    ├─ link_jar/link_jar_control.sh
    ├─ run_app/run_app_control.sh
    └─ test_instance/test_instance_control.sh

Design:
  - main.sh only calls multi_deploy (strict layer separation)
  - multi_deploy orchestrates deploy and rollback
  - deploy/rollback use Layer 4 services

For details: ./main.sh help
EOF
}

# 모듈 스크립트 존재 확인
check_module_script() {
    local module_name="$1"
    local script_name="$2"
    local script_path="${SCRIPT_DIR}/${module_name}/${script_name}"

    if [ ! -f "$script_path" ]; then
        echo -e "${RED}[ERROR]${NC} Module script not found: $script_path" >&2
        return 1
    fi

    if [ ! -x "$script_path" ]; then
        echo -e "${YELLOW}[WARN]${NC} Module script not executable, fixing: $script_path"
        chmod +x "$script_path" || {
            echo -e "${RED}[ERROR]${NC} Failed to make script executable: $script_path" >&2
            return 1
        }
    fi

    echo "$script_path"
    return 0
}

# Multi-instance 배포
execute_multi_deploy() {
    local count="$1"
    local env_file="$2"

    echo -e "${BLUE}[INFO]${NC} Starting multi-instance deployment"
    echo -e "${BLUE}[INFO]${NC} Target instances: $count"
    echo -e "${BLUE}[INFO]${NC} Environment file: $env_file"
    echo ""

    local script_path
    script_path=$(check_module_script "multi_deploy" "multi_deploy_control.sh") || return 1

    "$script_path" deploy "$count" "$env_file"
}

# Multi-instance 롤백
execute_multi_rollback() {
    local env_file="$1"

    echo -e "${BLUE}[INFO]${NC} Starting multi-instance rollback"
    echo -e "${BLUE}[INFO]${NC} Environment file: $env_file"
    echo ""

    local script_path
    script_path=$(check_module_script "multi_deploy" "multi_deploy_control.sh") || return 1

    "$script_path" rollback "$env_file"
}

# 배포 상태 확인
execute_status() {
    local env_file="$1"

    echo -e "${BLUE}[INFO]${NC} Checking deployment status"
    echo ""

    local script_path
    script_path=$(check_module_script "multi_deploy" "multi_deploy_control.sh") || return 1

    "$script_path" status "$env_file"
}

# 배포 전 검증
execute_validate() {
    local count="$1"
    local env_file="$2"

    echo -e "${BLUE}[INFO]${NC} Validating deployment prerequisites"
    echo ""

    local script_path
    script_path=$(check_module_script "multi_deploy" "multi_deploy_control.sh") || return 1

    "$script_path" validate "$count" "$env_file"
}


# 환경 파일 검증
validate_env_file() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        echo -e "${RED}[ERROR]${NC} Environment file not found: $env_file" >&2
        return 1
    fi

    if [ ! -r "$env_file" ]; then
        echo -e "${RED}[ERROR]${NC} Environment file not readable: $env_file" >&2
        return 1
    fi

    return 0
}

# 인스턴스 카운트 검증
validate_instance_count() {
    local count="$1"

    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid instance count: $count (must be numeric)" >&2
        return 1
    fi

    if [ "$count" -lt 2 ] || [ "$count" -gt 10 ]; then
        echo -e "${RED}[ERROR]${NC} Invalid instance count: $count (must be 2-10)" >&2
        return 1
    fi

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
                echo -e "${RED}[ERROR]${NC} 'deploy' requires <count> <env_file>"
                echo ""
                print_usage
                exit 1
            fi

            local count="$1"
            local env_file="$2"

            validate_instance_count "$count" || exit 1
            validate_env_file "$env_file" || exit 1

            execute_multi_deploy "$count" "$env_file"
            ;;

        rollback)
            if [ "$#" -lt 1 ]; then
                echo -e "${RED}[ERROR]${NC} 'rollback' requires <env_file>"
                echo ""
                print_usage
                exit 1
            fi

            local env_file="$1"
            validate_env_file "$env_file" || exit 1

            execute_multi_rollback "$env_file"
            ;;

        status)
            if [ "$#" -lt 1 ]; then
                echo -e "${RED}[ERROR]${NC} 'status' requires <env_file>"
                echo ""
                print_usage
                exit 1
            fi

            local env_file="$1"
            validate_env_file "$env_file" || exit 1

            execute_status "$env_file"
            ;;

        validate)
            if [ "$#" -lt 2 ]; then
                echo -e "${RED}[ERROR]${NC} 'validate' requires <count> <env_file>"
                echo ""
                print_usage
                exit 1
            fi

            local count="$1"
            local env_file="$2"

            validate_instance_count "$count" || exit 1
            validate_env_file "$env_file" || exit 1

            execute_validate "$count" "$env_file"
            ;;

        version|--version|-v)
            print_version
            ;;

        help|--help|-h)
            print_usage
            ;;

        *)
            echo -e "${RED}[ERROR]${NC} Unknown command: '$command'"
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
