# Rollback Control Functions Specification

## 개요

배포 실패 시 이전 버전으로 복원하는 Bash 기반 롤백 시스템입니다. JAR 백업 파일을 사용하여 안전하게 이전 상태로 되돌리며, 애플리케이션 재시작 및 Nginx 업스트림 제어를 자동화합니다.

## 1. 롤백 파라미터 검증

### validate_rollback_parameters(instance_num, env_file)
**목적**: 롤백 파라미터 유효성 검증

**파라미터**:
- `instance_num`: 인스턴스 번호 (0-9)
- `env_file`: 환경 설정 파일 경로

**검증 항목**:
1. 인스턴스 번호 범위 (0-9)
2. 환경 파일 존재 및 읽기 권한

**에러 케이스**:
- 잘못된 인스턴스 번호: `[ERROR] Invalid instance number: X (must be 0-9)`
- 환경 파일 없음: `[ERROR] Environment file not found: path`

### validate_required_env_vars()
**목적**: 필수 환경 변수 확인

**필수 변수**:
- `SERVICE_NAME`: 서비스 이름
- `SERVICE_BASE_DIR`: 서비스 베이스 디렉터리
- `BASE_PORT`: 기본 포트

### validate_rollback_environment(instance_num)
**목적**: 롤백 환경 검증

**검증 항목**:
1. 인스턴스 디렉터리 존재 확인
2. 인스턴스 디렉터리 쓰기 권한 확인

**구현 예시**:
```bash
if [ ! -d "$INSTANCE_DIR" ]; then
    error_exit "Instance directory not found: $INSTANCE_DIR"
fi

if [ ! -w "$INSTANCE_DIR" ]; then
    error_exit "Instance directory not writable: $INSTANCE_DIR"
fi
```

### verify_backup_exists(backup_link, instance_num, verify_enabled)
**목적**: 백업 파일 존재 확인

**파라미터**:
- `backup_link`: 백업 파일 경로 (예: `/instances/0/current.jar.bak`)
- `instance_num`: 인스턴스 번호
- `verify_enabled`: 검증 활성화 (선택, 기본값: true)

**검증 항목**:
1. 백업 파일 존재 확인
2. 백업 파일 읽기 권한 확인
3. 심볼릭 링크인 경우 타겟 파일 확인

**구현 예시**:
```bash
if [ ! -e "$backup_link" ]; then
    error_exit "No backup found for instance $instance_num at: $backup_link"
fi

if [ -L "$backup_link" ]; then
    backup_target=$(readlink "$backup_link")
    if [ ! -f "$backup_target" ]; then
        error_exit "Backup link target not found: $backup_target"
    fi
fi
```

### verify_backup_integrity(backup_link, instance_num, verify_enabled)
**목적**: 백업 파일 무결성 검증

**파라미터**:
- `backup_link`: 백업 파일 경로
- `instance_num`: 인스턴스 번호
- `verify_enabled`: 검증 활성화 (선택, 기본값: false)

**검증 항목**:
1. 파일 크기 확인 (0 바이트가 아닌지)
2. JAR 파일 구조 검증 (`unzip -t` 사용)

**구현 예시**:
```bash
file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file")

if [ "$file_size" -eq 0 ]; then
    error_exit "Backup file is empty: $backup_file"
fi

if command -v unzip >/dev/null 2>&1; then
    if unzip -t "$backup_file" >/dev/null 2>&1; then
        log_success "Backup JAR structure is valid"
    fi
fi
```

### check_disk_space(backup_link, target_dir, check_enabled)
**목적**: 디스크 공간 확인

**동작**:
1. 백업 파일 크기 측정
2. 타겟 디렉터리 여유 공간 확인 (`df` 명령어)
3. 공간 부족 시 경고 로그

## 2. JAR 롤백 실행

### execute_jar_rollback(target_link, backup_link, instance_num)
**목적**: JAR 파일 롤백 실행

**롤백 프로세스**:
```bash
1. 백업 파일 재확인
2. 실패한 배포 백업 생성 (옵션)
3. 현재 JAR 제거
4. 백업에서 복원
5. 복원 후 검증 (옵션)
```

**구현 예시**:
```bash
# 백업 재확인
if [ ! -e "$backup_link" ]; then
    error_exit "Backup file not found during rollback: $backup_link"
fi

# 실패한 배포 백업
create_failed_deployment_backup "$target_link" "$instance_num"

# 현재 JAR 제거
remove_current_jar "$target_link" "$instance_num"

# 백업에서 복원
restore_from_backup "$backup_link" "$target_link" "$instance_num"

# 검증
verify_after_restore "$target_link" "$instance_num"
```

### create_failed_deployment_backup(target_link, instance_num, create_backup)
**목적**: 실패한 배포 백업 생성

**파라미터**:
- `target_link`: 현재 JAR 링크 경로
- `instance_num`: 인스턴스 번호
- `create_backup`: 백업 생성 여부 (선택, 기본값: true)

**동작**:
- 현재 JAR을 `.failed.YYYYMMDD_HHMMSS` 접미사로 백업
- 예: `current.jar` → `current.jar.failed.20241003_143025`

**목적**:
- 롤백 후에도 실패한 버전 분석 가능
- 디버깅 및 문제 원인 파악

### remove_current_jar(target_link, instance_num)
**목적**: 현재 JAR 파일/링크 제거

**동작**:
```bash
if [ -e "$target_link" ]; then
    rm -f "$target_link"
fi
```

### restore_from_backup(backup_link, target_link, instance_num)
**목적**: 백업에서 JAR 복원

**복원 방법**:
- **심볼릭 링크인 경우**: 새 링크 생성 후 백업 링크 제거
- **일반 파일인 경우**: `mv` 명령으로 이동

**구현 예시**:
```bash
if [ -L "$backup_link" ]; then
    # 심볼릭 링크 복원
    backup_target=$(readlink "$backup_link")
    ln -s "$backup_target" "$target_link"
    rm -f "$backup_link"
else
    # 일반 파일 복원
    mv "$backup_link" "$target_link"
fi

# 권한 수정
fix_restored_permissions "$target_link"
```

### fix_restored_permissions(target_link, fix_permissions)
**목적**: 복원된 파일 권한 수정

**파라미터**:
- `target_link`: 복원된 JAR 경로
- `fix_permissions`: 권한 수정 활성화 (선택, 기본값: true)

**동작**:
```bash
if [ ! -r "$target_link" ]; then
    chmod 644 "$target_link"
fi
```

### verify_after_restore(target_link, instance_num, verify_enabled)
**목적**: 복원 후 검증

**검증 항목**:
1. 파일 존재 확인
2. 읽기 권한 확인
3. 파일 크기 확인 (0 바이트가 아닌지)

## 3. 애플리케이션 재시작

### restart_application(instance_dir, port, app_mode, java_opts, script_dir, restart_enabled)
**목적**: 롤백 후 애플리케이션 재시작

**파라미터**:
- `instance_dir`: 인스턴스 디렉터리
- `port`: 애플리케이션 포트
- `app_mode`: 재시작 모드 (선택, 기본값: restart)
- `java_opts`: Java 옵션 (선택)
- `script_dir`: 스크립트 디렉터리
- `restart_enabled`: 재시작 활성화 (선택, 기본값: true)

**동작**:
```bash
run_app_script="${script_dir}/../run_app/run_app_control.sh"

(
    cd "$instance_dir"
    "$run_app_script" "$app_mode" "$port" "$java_opts"
)
```

**재시작 모드**:
- `start`: 시작만 수행
- `stop`: 중지만 수행
- `restart`: 중지 후 시작 (기본값)

### control_nginx_upstream(action, port, upstream_conf, script_dir, nginx_control)
**목적**: Nginx 업스트림 제어

**파라미터**:
- `action`: up 또는 down
- `port`: 업스트림 서버 포트
- `upstream_conf`: Nginx 업스트림 설정 파일
- `script_dir`: 스크립트 디렉터리
- `nginx_control`: Nginx 제어 활성화 (선택, 기본값: true)

**사용 시점**:
- **롤백 전**: Nginx DOWN (트래픽 차단)
- **롤백 후**: Nginx UP (트래픽 복구)

## 4. 환경 설정 (rollback.env)

```bash
# 백업 검증 옵션
export ROLLBACK_VERIFY_BACKUP="true"              # 백업 파일 검증
export ROLLBACK_VERIFY_INTEGRITY="false"          # 백업 무결성 검증
export ROLLBACK_CHECK_DISK_SPACE="true"           # 디스크 공간 확인

# 롤백 실행 옵션
export ROLLBACK_CREATE_FAILED_BACKUP="true"       # 실패한 배포 백업 생성
export ROLLBACK_VERIFY_AFTER_RESTORE="true"       # 복원 후 검증
export ROLLBACK_FIX_PERMISSIONS="true"            # 권한 자동 수정

# 재시작 옵션
export ROLLBACK_RESTART_APP="true"                # 애플리케이션 재시작
export ROLLBACK_APP_MODE="restart"                # 재시작 모드
export ROLLBACK_RESTART_TIMEOUT="60"              # 재시작 타임아웃

# 헬스체크 옵션 (향후 확장)
export ROLLBACK_HEALTH_CHECK="false"              # 롤백 후 헬스체크
export ROLLBACK_HEALTH_CHECK_TIMEOUT="30"         # 헬스체크 타임아웃
export ROLLBACK_HEALTH_CHECK_RETRIES="3"          # 헬스체크 재시도

# Nginx 제어 옵션
export ROLLBACK_NGINX_CONTROL="true"              # Nginx 업스트림 제어
export ROLLBACK_NGINX_DOWN_BEFORE="true"          # 롤백 전 DOWN
export ROLLBACK_NGINX_UP_AFTER="true"             # 롤백 후 UP

# 로그 옵션
export ROLLBACK_LOG_LEVEL="INFO"
export ROLLBACK_AUDIT_LOG="true"                  # 감사 로그 기록
```

## 5. 롤백 워크플로우

### 표준 롤백 시나리오
```bash
./rollback_control.sh rollback 0 /path/to/env.env

# 실행 과정:
# 1. 파라미터 검증 (instance=0, env_file 존재 확인)
# 2. 환경 변수 로드 및 검증
# 3. 롤백 환경 검증 (인스턴스 디렉터리 확인)
# 4. 백업 파일 존재 확인 (/instances/0/current.jar.bak)
# 5. 백업 무결성 검증 (옵션)
# 6. 디스크 공간 확인 (옵션)
# 7. Nginx DOWN (트래픽 차단)
# 8. 실패한 배포 백업 생성 (current.jar -> current.jar.failed.timestamp)
# 9. 현재 JAR 제거 (current.jar)
# 10. 백업에서 복원 (current.jar.bak -> current.jar)
# 11. 복원 후 검증 (파일 존재, 크기, 권한)
# 12. 애플리케이션 재시작 (restart 모드)
# 13. Nginx UP (트래픽 복구)
# 14. 완료
```

### 롤백 상태 확인 시나리오
```bash
./rollback_control.sh status 0 /path/to/env.env

# 출력 예시:
=== Rollback Status ===
Instance: 0
Service: my-service
Port: 8080
Instance Directory: /home/service/my-service/instances/0

=== Current State ===
✅ Current JAR exists: /instances/0/current.jar
   Type: Symbolic link -> /jar_trunk/app-v2.0.jar
   Size: 52428800 bytes

=== Backup State ===
✅ Backup available: /instances/0/current.jar.bak
   Type: Symbolic link -> /jar_trunk/app-v1.0.jar
   Size: 51200000 bytes

🔄 Rollback: Ready

=== Application State ===
✅ Application is running on port 8080
```

### 롤백 미리보기 시나리오
```bash
./rollback_control.sh preview 0 /path/to/env.env

# 출력 예시:
=== Rollback Preview ===
Instance: 0
Service: my-service
Port: 8080

=== Rollback Steps ===
1. Validate parameters and environment
2. Verify backup file: /instances/0/current.jar.bak
3. Nginx DOWN for port 8080
4. Create failed deployment backup
5. Remove current JAR: /instances/0/current.jar
6. Restore from backup: current.jar.bak -> current.jar
7. Verify restored JAR
8. Restart application on port 8080 (mode: restart)
9. Nginx UP for port 8080

=== Backup File Details ===
Path: /instances/0/current.jar.bak
Type: Symbolic link -> /jar_trunk/app-v1.0.jar
Size: 51200000 bytes
Modified: 2024-10-03 14:25:30

✅ Rollback is ready to execute
```

### 롤백 검증 시나리오
```bash
./rollback_control.sh validate 0 /path/to/env.env

# 출력 예시:
=== Rollback Validation ===
✅ Parameters validated
✅ Environment loaded
✅ Rollback environment validated
✅ Backup file verified
✅ Disk space checked
✅ run_app_control.sh found and executable
✅ nginx_control.sh found and executable

✅ All validations passed
Ready to execute rollback for instance 0
```

## 6. CLI 사용법

### rollback_control.sh - 메인 진입점

```bash
# 롤백 실행
./rollback_control.sh rollback 0 /path/to/env.env

# 상태 확인
./rollback_control.sh status 0 /path/to/env.env

# 검증
./rollback_control.sh validate 0 /path/to/env.env

# 미리보기
./rollback_control.sh preview 0 /path/to/env.env

# 도움말
./rollback_control.sh help
```

## 7. 에러 처리

### 파라미터 오류
1. **잘못된 인스턴스 번호**: `[ERROR] Invalid instance number: 10 (must be 0-9)`
2. **환경 파일 없음**: `[ERROR] Environment file not found: /path/to/env.env`

### 환경 변수 오류
1. **필수 변수 누락**: `[ERROR] Missing required environment variables: SERVICE_NAME BASE_PORT`

### 백업 오류
1. **백업 없음**: `[ERROR] No backup found for instance 0 at: /instances/0/current.jar.bak`
2. **백업 링크 타겟 없음**: `[ERROR] Backup link target not found: /jar_trunk/app-v1.0.jar`
3. **백업 파일 비어있음**: `[ERROR] Backup file is empty: /instances/0/current.jar.bak`

### 복원 오류
1. **JAR 제거 실패**: `[ERROR] Failed to remove current JAR: /instances/0/current.jar`
2. **백업 복원 실패**: `[ERROR] Failed to restore JAR file`
3. **복원 파일 검증 실패**: `[ERROR] Restored file is empty`

### 재시작 오류
1. **run_app_control.sh 없음**: `[WARN] run_app_control.sh not found: /path/to/run_app_control.sh`
2. **재시작 실패**: `[WARN] Application restart failed`

## 8. 의존 스크립트

### 필수 스크립트 (renew/ 디렉터리)
```
renew/
├── run_app/run_app_control.sh       # 애플리케이션 재시작
└── nginx/nginx_control.sh           # Nginx 업스트림 제어 (선택)
```

### 사용 방식
```bash
# 애플리케이션 재시작
run_app_control.sh restart <port>

# Nginx 업스트림 제어
nginx_control.sh down <port> <upstream_conf>
nginx_control.sh up <port> <upstream_conf>
```

## 9. 파일 구조

```
renew/rollback/
├── rollback.env             # 환경 변수 설정
├── rollback_control.sh      # 메인 CLI 스크립트
├── SPEC.md                  # 명세 문서
└── func/                    # 함수 스크립트들
    ├── validate_rollback.sh    # 롤백 검증
    └── execute_rollback.sh     # 롤백 실행
```

## 10. 레거시 시스템과의 차이점

### pre/rollback.sh (레거시)
- 단일 파일 모놀리식 구조
- `runApp.sh` 절대 경로 하드코딩
- 제한된 에러 처리
- 백업 검증 없음

### renew/rollback (신규)
- 환경 변수 기반 설정 (rollback.env)
- 모듈형 함수 구조 (func/ 디렉터리)
- renew/ 모듈 통합 (run_app, nginx)
- 백업 무결성 검증 옵션
- 실패한 배포 백업 생성
- 복원 후 검증
- 상태 확인 및 미리보기 기능
- CLI 인터페이스 개선

## 11. 테스트 시나리오

### 단위 테스트
```bash
# 1. 백업 존재 확인
./func/validate_rollback.sh backup /instances/0/current.jar.bak 0
# 출력: [SUCCESS] Backup verified

# 2. 백업 무결성 검증
./func/validate_rollback.sh integrity /instances/0/current.jar.bak 0
# 출력: [SUCCESS] Backup integrity verified

# 3. JAR 롤백 실행
./func/execute_rollback.sh rollback /instances/0/current.jar /instances/0/current.jar.bak 0
# 출력: [SUCCESS] JAR rollback completed
```

### 통합 테스트
```bash
# 전체 롤백 워크플로우
export ROLLBACK_VERIFY_INTEGRITY="true"
export ROLLBACK_CREATE_FAILED_BACKUP="true"

# 1. 롤백 검증
./rollback_control.sh validate 0 /tmp/test.env

# 2. 롤백 실행
./rollback_control.sh rollback 0 /tmp/test.env

# 3. 상태 확인
./rollback_control.sh status 0 /tmp/test.env
```

## 12. 모범 사례

### 롤백 전
1. **상태 확인**: `./rollback_control.sh status 0 /path/to/env.env`
2. **백업 검증**: `./rollback_control.sh validate 0 /path/to/env.env`
3. **미리보기**: `./rollback_control.sh preview 0 /path/to/env.env`

### 롤백 중
1. **로그 모니터링**: 롤백 로그 실시간 확인
2. **백업 확인**: 실패한 배포 백업 생성 여부 확인

### 롤백 후
1. **상태 재확인**: `./rollback_control.sh status 0 /path/to/env.env`
2. **애플리케이션 확인**: 프로세스 및 헬스체크
3. **실패 분석**: `.failed.timestamp` 백업 파일로 문제 분석

### 트러블슈팅
```bash
# 백업 없는 경우 - 수동 복원
cp /jar_trunk/app-v1.0.jar /instances/0/current.jar
cd /instances/0
../../../renew/run_app/run_app_control.sh restart 8080

# 재시작 실패 - 수동 재시작
cd /instances/0
java -jar current.jar --server.port=8080 &
```

## 13. 안전성 기능

### 실패한 배포 백업
- 롤백 전에 현재 JAR을 `.failed.timestamp` 형식으로 백업
- 롤백 후에도 문제 분석 가능
- 디스크 공간 허용 시 자동 생성

### 복원 후 검증
- 파일 존재 확인
- 파일 크기 확인 (0 바이트 방지)
- 읽기 권한 확인

### 권한 자동 수정
- 복원된 JAR 파일 권한 자동 수정 (644)
- 읽기 권한 문제 자동 해결

### Nginx 연동
- 롤백 전 트래픽 차단
- 롤백 후 트래픽 복구
- 무중단 롤백 지원

## 14. 향후 확장 가능성

### 헬스체크 통합
```bash
# 롤백 후 헬스체크 실행
if [ "${ROLLBACK_HEALTH_CHECK}" = "true" ]; then
    verify_restart_health "$PORT" "$instance_num" "$ROLLBACK_HEALTH_CHECK_TIMEOUT"
fi
```

### 안전 모드
```bash
# 추가 검증 포함 롤백
./rollback_control.sh safe-rollback 0 /path/to/env.env
```

### 응급 모드
```bash
# 최소 검증으로 빠른 롤백
./rollback_control.sh emergency-rollback 0 /path/to/env.env
```

### 감사 로그
```bash
# 롤백 이력 기록
audit_log "ROLLBACK_START" "instance=$instance_num port=$PORT"
audit_log "ROLLBACK_SUCCESS" "instance=$instance_num duration=5s"
```
