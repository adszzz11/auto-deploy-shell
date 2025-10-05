#!/bin/bash
set -euo pipefail


# link_jar_control.sh - JAR Symbolic Link Management
#
# Layer: 4 (Support Services)
# 역할: JAR 파일 심볼릭 링크 관리
# 호출자: deploy_control.sh (Layer 3)
# 호출 대상: 없음 (최하위 계층)
#
# 책임:
#   - JAR 파일 심볼릭 링크 생성/제거
#   - PID 파일에서 JAR 이름 읽기
#   - 링크 유효성 검증
# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# link_jar.env 파일 로드 (존재하는 경우)
if [ -f "${SCRIPT_DIR}/link_jar.env" ]; then
    source "${SCRIPT_DIR}/link_jar.env"
fi

# 모든 함수 스크립트들 source (func 디렉터리에서)
source "${SCRIPT_DIR}/func/read_jar_name.sh"
source "${SCRIPT_DIR}/func/validate_jar.sh"
source "${SCRIPT_DIR}/func/manage_link.sh"

# 사용법 출력
print_usage() {
    cat << EOF
Usage: link_jar_control.sh <command> [arguments]

Commands:
  link <jar_trunk_dir> <target_link> [jar_name|pid_file]  - Create JAR symbolic link
  unlink <target_link> [backup]                           - Remove symbolic link
  info <target_link>                                       - Show link information
  validate <jar_trunk_dir> <jar_name>                      - Validate JAR file
  read-pid <jar_trunk_dir> [pid_file]                      - Read JAR name from PID file

Note: Arguments in [brackets] are optional and can use defaults from link_jar.env

Environment variables (set in link_jar.env):
  LINK_JAR_PID_FILE          - PID file name (default: current_jar.pid)
  LINK_JAR_TARGET_NAME       - Target link name (default: current.jar)
  LINK_JAR_VALIDATE_EXTENSION - Validate .jar extension (default: true)
  LINK_JAR_BACKUP_ENABLED    - Enable backup before removal (default: true)
  LINK_JAR_BACKUP_SUFFIX     - Backup file suffix (default: .bak)
  LINK_JAR_VERIFY_LINK       - Verify link after creation (default: true)

Examples:
  # Create link using PID file
  ./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar

  # Create link with specific JAR name (skip PID file)
  ./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar app-v1.0.jar

  # Create link with custom PID file
  ./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar /custom/path/jar.pid

  # Remove link (with backup)
  ./link_jar_control.sh unlink /path/to/current.jar

  # Remove link (without backup)
  ./link_jar_control.sh unlink /path/to/current.jar false

  # Show link information
  ./link_jar_control.sh info /path/to/current.jar

  # Validate JAR file
  ./link_jar_control.sh validate /path/to/jar_trunk app-v1.0.jar

  # Read JAR name from PID file
  ./link_jar_control.sh read-pid /path/to/jar_trunk
EOF
}

# JAR 링크 생성 메인 함수
create_jar_link() {
    local jar_dir="$1"
    local target_link="$2"
    local jar_source="${3:-}"  # jar_name 또는 pid_file

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Starting JAR link creation process"

    # 1. JAR 디렉터리 검증
    validate_jar_directory "$jar_dir"

    # 2. 타겟 디렉터리 검증
    validate_target_directory "$target_link"

    # 3. JAR 파일명 결정
    local jar_name
    if [ -z "$jar_source" ]; then
        # PID 파일에서 읽기 (기본 동작)
        jar_name=$(read_jar_name_from_pid "$jar_dir")
    elif [ -f "$jar_source" ]; then
        # PID 파일 경로가 직접 지정된 경우
        jar_name=$(read_jar_name_from_pid "$jar_dir" "$jar_source")
    else
        # JAR 파일명이 직접 지정된 경우
        jar_name="$jar_source"
    fi

    # 4. JAR 파일명 검증
    validate_jar_name "$jar_name"

    # 5. JAR 파일 존재 확인
    local jar_path
    jar_path=$(validate_jar_file_exists "$jar_dir" "$jar_name")

    # 6. 기존 링크/파일 제거
    remove_existing_link "$target_link"

    # 7. 새 심볼릭 링크 생성
    create_symbolic_link "$jar_path" "$target_link"

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - JAR link creation completed successfully"
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
        link)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'link' requires at least <jar_trunk_dir> <target_link>"
                exit 1
            fi
            create_jar_link "$@"
            ;;
        unlink)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'unlink' requires <target_link>"
                exit 1
            fi
            remove_existing_link "$@"
            ;;
        info)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'info' requires <target_link>"
                exit 1
            fi
            get_link_info "$@"
            ;;
        validate)
            if [ "$#" -lt 2 ]; then
                echo "Error: 'validate' requires <jar_trunk_dir> <jar_name>"
                exit 1
            fi
            validate_jar_directory "$1"
            validate_jar_name "$2"
            validate_jar_file_exists "$1" "$2"
            ;;
        read-pid)
            if [ "$#" -lt 1 ]; then
                echo "Error: 'read-pid' requires <jar_trunk_dir>"
                exit 1
            fi
            read_jar_name_from_pid "$@"
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
