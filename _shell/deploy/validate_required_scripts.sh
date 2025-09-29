#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 필수 스크립트 존재 및 실행 권한 확인 함수
validate_required_scripts() {
    local script_dir="$1"

    # 필수 외부 스크립트 목록
    local required_scripts=("controll_nginx.sh" "link_jar.sh" "runApp.sh" "setup_logs.sh")

    log_info "Validating required scripts in: $script_dir"

    for script in "${required_scripts[@]}"; do
        local script_path="${script_dir}/${script}"

        # 파일 존재 확인
        if [ ! -f "$script_path" ]; then
            error_exit "Required script not found: $script_path"
        fi

        # 실행 권한 확인
        if [ ! -x "$script_path" ]; then
            error_exit "Required script is not executable: $script_path"
        fi

        log_info "✅ Script validated: $script"
    done

    log_success "All required scripts validated successfully"
}

# 개별 스크립트 검증 함수
validate_single_script() {
    local script_path="$1"
    local script_name=$(basename "$script_path")

    if [ ! -f "$script_path" ]; then
        error_exit "Script not found: $script_path"
    fi

    if [ ! -x "$script_path" ]; then
        error_exit "Script is not executable: $script_path"
    fi

    log_info "✅ Script validated: $script_name"
}

# 스크립트 실행 권한 설정 함수
fix_script_permissions() {
    local script_dir="$1"
    local required_scripts=("controll_nginx.sh" "link_jar.sh" "runApp.sh" "setup_logs.sh")

    log_info "Fixing script permissions in: $script_dir"

    for script in "${required_scripts[@]}"; do
        local script_path="${script_dir}/${script}"

        if [ -f "$script_path" ]; then
            chmod +x "$script_path" || error_exit "Failed to set execute permission for: $script_path"
            log_info "✅ Permission fixed: $script"
        else
            log_warn "Script not found for permission fix: $script_path"
        fi
    done

    log_success "Script permissions fixed"
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: validate_required_scripts.sh <script_dir> [fix]"
        echo "  fix: Also fix script permissions if needed"
        exit 1
    fi

    case "${2:-validate}" in
        "fix")
            fix_script_permissions "$1"
            validate_required_scripts "$1"
            ;;
        *)
            validate_required_scripts "$1"
            ;;
    esac
fi