#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/../common_utils/common_utils.sh"

# 백업 파일 가용성 확인 함수
verify_backup_availability() {
    local backup_link="$1"
    local instance_num="$2"

    log_info "Verifying backup availability for instance $instance_num"

    # 백업 파일 존재 확인
    if [ ! -e "$backup_link" ]; then
        error_exit "No backup found for instance $instance_num at: $backup_link"
    fi

    # 백업 파일 읽기 권한 확인
    if [ ! -r "$backup_link" ]; then
        error_exit "Backup file is not readable: $backup_link"
    fi

    # 백업이 심볼릭 링크인지 일반 파일인지 확인
    if [ -L "$backup_link" ]; then
        local backup_target
        backup_target=$(readlink "$backup_link")
        log_info "Backup is a symbolic link pointing to: $backup_target"

        # 링크 대상 파일 존재 확인
        if [ ! -f "$backup_target" ]; then
            error_exit "Backup link target not found: $backup_target"
        fi

        # 링크 대상 파일 읽기 권한 확인
        if [ ! -r "$backup_target" ]; then
            error_exit "Backup link target is not readable: $backup_target"
        fi

        log_success "Backup symbolic link and target verified"
    elif [ -f "$backup_link" ]; then
        log_info "Backup is a regular file"
        log_success "Backup file verified"
    else
        error_exit "Backup exists but is neither a file nor a symbolic link: $backup_link"
    fi
}

# 백업 파일 상세 정보 함수
show_backup_details() {
    local backup_link="$1"
    local instance_num="$2"

    echo "=== Backup Details for Instance $instance_num ==="
    echo "Backup Path: $backup_link"

    if [ ! -e "$backup_link" ]; then
        echo "Status: ❌ Not Found"
        return 1
    fi

    if [ -L "$backup_link" ]; then
        local backup_target
        backup_target=$(readlink "$backup_link")
        echo "Type: Symbolic Link"
        echo "Target: $backup_target"

        if [ -f "$backup_target" ]; then
            echo "Target Status: ✅ Exists"
            echo "Target Size: $(stat -f%z "$backup_target" 2>/dev/null || stat -c%s "$backup_target" 2>/dev/null || echo "Unknown") bytes"
            echo "Target Modified: $(stat -f%Sm "$backup_target" 2>/dev/null || stat -c%y "$backup_target" 2>/dev/null || echo "Unknown")"
        else
            echo "Target Status: ❌ Missing"
        fi
    elif [ -f "$backup_link" ]; then
        echo "Type: Regular File"
        echo "Size: $(stat -f%z "$backup_link" 2>/dev/null || stat -c%s "$backup_link" 2>/dev/null || echo "Unknown") bytes"
        echo "Modified: $(stat -f%Sm "$backup_link" 2>/dev/null || stat -c%y "$backup_link" 2>/dev/null || echo "Unknown")"
    else
        echo "Type: Unknown"
    fi

    # 권한 정보
    if [ -e "$backup_link" ]; then
        echo "Permissions: $(ls -la "$backup_link" | awk '{print $1, $3, $4}')"

        if [ -r "$backup_link" ]; then
            echo "Readable: ✅ Yes"
        else
            echo "Readable: ❌ No"
        fi
    fi

    echo "Status: ✅ Available"
}

# 백업 파일 무결성 검증 함수
verify_backup_integrity() {
    local backup_link="$1"
    local instance_num="$2"

    log_info "Verifying backup integrity for instance $instance_num"

    # 먼저 기본 가용성 확인
    verify_backup_availability "$backup_link" "$instance_num"

    # 백업 파일이 JAR 파일인지 확인
    local backup_file="$backup_link"
    if [ -L "$backup_link" ]; then
        backup_file=$(readlink "$backup_link")
    fi

    # 파일 크기 확인 (0 바이트가 아닌지)
    local file_size
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null || echo "0")

    if [ "$file_size" -eq 0 ]; then
        error_exit "Backup file is empty: $backup_file"
    fi

    log_info "Backup file size: $file_size bytes"

    # JAR 파일 헤더 확인 (PK로 시작하는지)
    if command -v file >/dev/null 2>&1; then
        local file_type
        file_type=$(file "$backup_file" 2>/dev/null || echo "unknown")
        log_info "Backup file type: $file_type"

        if [[ "$file_type" == *"Java archive"* ]] || [[ "$file_type" == *"Zip archive"* ]]; then
            log_success "Backup file appears to be a valid Java archive"
        else
            log_warn "Backup file may not be a valid Java archive: $file_type"
        fi
    fi

    # JAR 파일 구조 기본 확인
    if command -v unzip >/dev/null 2>&1; then
        if unzip -t "$backup_file" >/dev/null 2>&1; then
            log_success "Backup JAR file structure is valid"
        else
            log_warn "Backup JAR file structure may be corrupted"
        fi
    fi

    log_success "Backup integrity verification completed"
}

# 여러 인스턴스의 백업 상태 확인 함수
check_multiple_backups() {
    local service_base_dir="$1"
    local service_name="$2"
    local instance_list="$3"  # 공백으로 구분된 인스턴스 번호들

    local instances_array=($instance_list)

    echo "=== Multiple Backup Status Check ==="
    echo "Service: $service_name"
    echo "Instances: ${instances_array[*]}"
    echo ""

    local all_available=true

    for instance_num in "${instances_array[@]}"; do
        local instance_dir="${service_base_dir}/${service_name}/instances/${instance_num}"
        local backup_link="${instance_dir}/current.jar.bak"

        echo "Instance $instance_num:"
        if [ -e "$backup_link" ]; then
            echo "  ✅ Backup available"
            if [ -L "$backup_link" ]; then
                echo "  📁 Target: $(readlink "$backup_link")"
            fi
        else
            echo "  ❌ Backup missing"
            all_available=false
        fi
        echo ""
    done

    if [ "$all_available" = "true" ]; then
        echo "Result: ✅ All backups are available"
        return 0
    else
        echo "Result: ❌ Some backups are missing"
        return 1
    fi
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: verify_backup_availability.sh <backup_link> <instance_number> [details|integrity|multiple]"
        echo "  (default): Verify backup availability"
        echo "  details: Show detailed backup information"
        echo "  integrity: Verify backup file integrity"
        echo "  multiple: Check multiple instances (requires service_base_dir service_name instance_list)"
        exit 1
    fi

    case "${3:-default}" in
        "details")
            show_backup_details "$1" "$2"
            ;;
        "integrity")
            verify_backup_integrity "$1" "$2"
            ;;
        "multiple")
            if [ "$#" -ne 5 ]; then
                echo "Multiple mode requires: <service_base_dir> <service_name> <instance_list> multiple"
                exit 1
            fi
            check_multiple_backups "$1" "$2" "$3"
            ;;
        *)
            verify_backup_availability "$1" "$2"
            ;;
    esac
fi