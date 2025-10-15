#!/bin/bash
set -euo pipefail


# 배포 환경 준비
prepare_deploy_environment() {
    local instance_dir="$1"
    local jar_dir="$2"

    # JAR 디렉터리 검증
    if [ ! -d "$jar_dir" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - JAR trunk directory not found: $jar_dir" >&2
        return 1
    fi

    # 인스턴스 디렉터리 생성 (없는 경우)
    if [ ! -d "$instance_dir" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Creating instance directory: $instance_dir" >&2
        mkdir -p "$instance_dir" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to create instance directory" >&2
            return 1
        }
    fi

    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Deploy environment prepared successfully" >&2
    return 0
}

# JAR 백업
backup_current_jar() {
    local target_link="$1"
    local backup_enabled="${2:-${DEPLOY_BACKUP_JAR:-true}}"

    if [ "$backup_enabled" != "true" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - JAR backup disabled" >&2
        return 0
    fi

    if [ -L "$target_link" ] || [ -e "$target_link" ]; then
        local backup_file="${target_link}.bak"
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backing up current.jar: $target_link -> $backup_file" >&2

        mv "$target_link" "$backup_file" || {
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to backup current.jar" >&2
            return 1
        }

        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - JAR backup completed" >&2
    else
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - No existing JAR to backup" >&2
    fi

    return 0
}

# runApp.sh 동기화
sync_runapp_script() {
    local script_dir="$1"
    local instance_dir="$2"
    local backup_enabled="${3:-${DEPLOY_BACKUP_RUNAPP:-true}}"

    local runapp_src="${script_dir}/../run_app/run_app_control.sh"
    local runapp_dest="${instance_dir}/runApp.sh"

    if [ ! -f "$runapp_src" ]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Source runApp script not found: $runapp_src" >&2
        return 1
    fi

    # 기존 runApp.sh 존재 확인
    if [ -f "$runapp_dest" ]; then
        # 파일 비교 (동일한지 확인)
        if cmp -s "$runapp_src" "$runapp_dest"; then
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - runApp.sh is already up-to-date" >&2
            return 0
        fi

        # 백업 활성화 시
        if [ "$backup_enabled" = "true" ]; then
            local backup_file="${runapp_dest}.bak"
            echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Backing up existing runApp.sh: $runapp_dest -> $backup_file" >&2

            mv "$runapp_dest" "$backup_file" || {
                echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to backup existing runApp.sh" >&2
                return 1
            }
        fi
    fi

    # runApp.sh 복사
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Copying runApp.sh to $instance_dir" >&2
    cp "$runapp_src" "$runapp_dest" || {
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Failed to copy runApp.sh" >&2
        return 1
    }

    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - runApp.sh synchronized successfully" >&2

    # 실행 권한 부여 (복사된 파일에 자동으로 부여되므로 선택적)
    chmod +x "$runapp_dest" 2>/dev/null || true

    return 0
}

# 스크립트가 직접 실행된 경우
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: prepare_deployment.sh <command> <arguments...>"
        echo ""
        echo "Commands:"
        echo "  prepare <instance_dir> <jar_dir>                       - Prepare deploy environment"
        echo "  backup <target_link> [backup_enabled]                  - Backup current JAR"
        echo "  sync <script_dir> <instance_dir> [backup_enabled]      - Sync runApp script"
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        prepare)
            prepare_deploy_environment "$@"
            ;;
        backup)
            backup_current_jar "$@"
            ;;
        sync)
            sync_runapp_script "$@"
            ;;
        *)
            echo "Unknown command: $command"
            exit 1
            ;;
    esac
fi
