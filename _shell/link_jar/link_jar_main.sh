#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common_utils/common_utils.sh"

# 개별 함수 스크립트들 source
source "${SCRIPT_DIR}/validate_link_jar_parameters.sh"
source "${SCRIPT_DIR}/validate_jar_environment.sh"
source "${SCRIPT_DIR}/read_jar_name_from_pid.sh"
source "${SCRIPT_DIR}/validate_jar_name.sh"
source "${SCRIPT_DIR}/validate_jar_file_exists.sh"
source "${SCRIPT_DIR}/remove_existing_link.sh"
source "${SCRIPT_DIR}/create_symbolic_link.sh"

# 메인 JAR 링크 생성 함수
link_jar_main() {
    # 사용법: link_jar_main <service_name> <target_link_path> <jar_trunk_dir>
    if [ "$#" -ne 3 ]; then
        echo "Usage: link_jar_main <service_name> <target_link_path> <jar_trunk_dir>"
        exit 1
    fi

    local service_name="$1"
    local target_link="$2"
    local jar_dir="$3"

    # 1. 파라미터 검증
    validate_link_jar_parameters "$service_name" "$target_link" "$jar_dir"

    # 2. 환경 검증
    validate_jar_environment "$jar_dir" "$target_link"

    # 3. PID 파일에서 JAR 파일명 읽기
    local jar_name
    jar_name=$(read_jar_name_from_pid "$jar_dir")

    # 4. JAR 파일명 유효성 검증
    validate_jar_name "$jar_name"

    # 5. JAR 파일 존재 확인
    local jar_path
    jar_path=$(validate_jar_file_exists "$jar_dir" "$jar_name")

    # 6. 기존 링크/파일 제거
    remove_existing_link "$target_link"

    # 7. 새 심볼릭 링크 생성
    create_symbolic_link "$jar_path" "$target_link"

    log_success "JAR linking completed successfully for service: $service_name"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    link_jar_main "$@"
fi