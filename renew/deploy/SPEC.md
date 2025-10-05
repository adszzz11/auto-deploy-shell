# Deploy Control Functions Specification

## 개요

Spring Boot 애플리케이션 인스턴스 배포/제거를 관리하는 Bash 기반 시스템입니다. Nginx 로드밸런싱과 연동하여 무중단 배포를 지원하며, JAR 관리, 애플리케이션 프로세스 제어, 로그 설정을 자동화합니다.

## 1. 배포 파라미터 검증

### validate_deploy_parameters(instance_num, env_file, action)
**목적**: 배포 파라미터 유효성 검증

**파라미터**:
- `instance_num`: 인스턴스 번호 (0-9)
- `env_file`: 환경 설정 파일 경로
- `action`: 배포 액션 (deploy|remove)

**검증 항목**:
1. 인스턴스 번호 범위 (0-9)
2. 환경 파일 존재 여부
3. 액션 유효성 (deploy 또는 remove만 허용)

**에러 케이스**:
- 잘못된 인스턴스 번호: `[ERROR] Invalid instance number: X (must be 0-9)`
- 환경 파일 없음: `[ERROR] Environment file not found: path`
- 잘못된 액션: `[ERROR] Invalid action: X (must be 'deploy' or 'remove')`

### validate_jar_directory(jar_dir, validate_enabled)
**목적**: JAR 디렉터리 검증

**파라미터**:
- `jar_dir`: JAR trunk 디렉터리 경로
- `validate_enabled`: 검증 활성화 (선택, 기본값: true)

**검증 항목**:
1. 디렉터리 존재 여부
2. 읽기 권한 확인

### validate_instance_directory(instance_dir, validate_enabled)
**목적**: 인스턴스 디렉터리 검증

**파라미터**:
- `instance_dir`: 인스턴스 디렉터리 경로
- `validate_enabled`: 검증 활성화 (선택, 기본값: true)

**검증 항목**:
1. 디렉터리 존재 여부
2. 쓰기 권한 확인

### validate_required_scripts(script_dir)
**목적**: 필수 스크립트 존재 및 실행 권한 확인

**필수 스크립트**:
- `nginx_control.sh`: Nginx 업스트림 제어
- `link_jar_control.sh`: JAR 심볼릭 링크 관리
- `run_app_control.sh`: 애플리케이션 프로세스 관리
- `setup_logs_control.sh`: 로그 디렉터리 설정

## 2. 배포 환경 준비

### prepare_deploy_environment(instance_dir, jar_dir)
**목적**: 배포 환경 초기화

**동작**:
1. JAR 디렉터리 존재 확인
2. 인스턴스 디렉터리 생성 (없는 경우)
3. 디렉터리 권한 확인

**구현 예시**:
```bash
# JAR 디렉터리 검증
if [ ! -d "$jar_dir" ]; then
    error_exit "JAR trunk directory not found: $jar_dir"
fi

# 인스턴스 디렉터리 생성
if [ ! -d "$instance_dir" ]; then
    mkdir -p "$instance_dir"
fi
```

### backup_current_jar(target_link, backup_enabled)
**목적**: 기존 JAR 파일 백업

**파라미터**:
- `target_link`: 현재 JAR 심볼릭 링크 경로 (예: `/instances/0/current.jar`)
- `backup_enabled`: 백업 활성화 (선택, 기본값: true)

**동작**:
1. 기존 `current.jar` 존재 확인
2. `current.jar` → `current.jar.bak`으로 이동
3. 백업 성공 로그 출력

**백업 비활성화 시**:
- 백업 없이 진행
- 로그에 "JAR backup disabled" 기록

### sync_runapp_script(script_dir, instance_dir, backup_enabled)
**목적**: runApp.sh 스크립트 동기화

**파라미터**:
- `script_dir`: 배포 스크립트 디렉터리
- `instance_dir`: 인스턴스 디렉터리
- `backup_enabled`: 백업 활성화 (선택, 기본값: true)

**동작**:
1. 소스 runApp.sh 존재 확인 (`run_app_control.sh`)
2. 기존 runApp.sh와 비교 (`cmp -s`)
3. 변경사항 있는 경우:
   - 백업 활성화 시: 기존 파일 백업
   - 새 파일 복사
   - 실행 권한 부여 (`chmod +x`)
4. 동일한 경우: "already up-to-date" 로그

## 3. 배포 실행

### execute_application_deployment(instance_dir, port, app_mode, java_opts)
**목적**: 애플리케이션 배포 실행

**파라미터**:
- `instance_dir`: 인스턴스 디렉터리
- `port`: 애플리케이션 포트
- `app_mode`: 실행 모드 (start|stop|restart, 기본값: restart)
- `java_opts`: Java 옵션 (선택, 예: `--spring.profiles.active=prod`)

**동작**:
```bash
# 인스턴스 디렉터리로 이동
cd "$instance_dir"

# runApp.sh 실행
./runApp.sh "$port" "$app_mode" "$java_opts"
```

**에러 처리**:
- 디렉터리 변경 실패: `[ERROR] Failed to change directory to $instance_dir`
- runApp.sh 없음: `[ERROR] runApp.sh not found in $instance_dir`
- 실행 실패: `[ERROR] Failed to execute runApp.sh`

### execute_test_script(test_script, port, run_tests, test_timeout)
**목적**: 배포 후 테스트 실행

**파라미터**:
- `test_script`: 테스트 스크립트 경로
- `port`: 테스트 대상 포트
- `run_tests`: 테스트 실행 여부 (선택, 기본값: true)
- `test_timeout`: 타임아웃 (초, 선택, 기본값: 60)

**동작**:
1. 테스트 실행 활성화 확인
2. 스크립트 존재 및 실행 권한 확인
3. `timeout` 명령으로 테스트 실행
4. 결과에 따른 처리:
   - 성공 (exit 0): `[SUCCESS] Tests passed for port $port`
   - 실패: `[ERROR] Tests failed for port $port`
   - 타임아웃: `[ERROR] Test timed out after ${test_timeout}s`

**구현 예시**:
```bash
if timeout "$test_timeout" "$test_script" "$port"; then
    log_success "Tests passed for port $port"
else
    error_exit "Tests failed for port $port"
fi
```

### control_nginx_upstream(action, port, upstream_conf, script_dir, nginx_control)
**목적**: Nginx 업스트림 서버 제어

**파라미터**:
- `action`: up 또는 down
- `port`: 업스트림 서버 포트
- `upstream_conf`: Nginx 업스트림 설정 파일 경로
- `script_dir`: 스크립트 디렉터리
- `nginx_control`: Nginx 제어 활성화 (선택, 기본값: true)

**동작**:
1. Nginx 제어 활성화 확인
2. nginx_control.sh 스크립트 존재 확인
3. 업스트림 설정 변경 (`up` 또는 `down`)
4. Nginx 설정 리로드

**에러 처리**:
- 스크립트 없음: `[ERROR] Nginx control script not found: $script_path`
- 실행 실패: `[ERROR] Failed to set nginx upstream $action`

### create_jar_link(jar_dir, target_link, jar_name, script_dir)
**목적**: JAR 파일 심볼릭 링크 생성

**파라미터**:
- `jar_dir`: JAR trunk 디렉터리
- `target_link`: 타겟 링크 경로 (예: `/instances/0/current.jar`)
- `jar_name`: JAR 파일명 (선택, PID 파일 또는 직접 지정)
- `script_dir`: 스크립트 디렉터리

**동작**:
1. link_jar_control.sh 스크립트 존재 확인
2. JAR 파일명 처리:
   - `jar_name` 지정: 직접 JAR 이름 사용
   - 미지정: PID 파일에서 읽기
3. 심볼릭 링크 생성
4. 링크 검증

### setup_instance_logs(service_name, instance_num, instance_dir, log_base_dir, script_dir)
**목적**: 인스턴스 로그 디렉터리 설정

**파라미터**:
- `service_name`: 서비스 이름
- `instance_num`: 인스턴스 번호
- `instance_dir`: 인스턴스 디렉터리
- `log_base_dir`: 로그 베이스 디렉터리
- `script_dir`: 스크립트 디렉터리

**동작**:
1. setup_logs_control.sh 스크립트 호출
2. 로그 디렉터리 생성 및 심볼릭 링크 설정
3. 권한 설정

## 4. 인스턴스 제거

### handle_instance_removal(instance_dir, port, script_dir, upstream_conf)
**목적**: 인스턴스 제거 처리

**파라미터**:
- `instance_dir`: 인스턴스 디렉터리
- `port`: 인스턴스 포트
- `script_dir`: 스크립트 디렉터리
- `upstream_conf`: Nginx 업스트림 설정 파일

**제거 프로세스**:
1. 인스턴스 디렉터리 존재 확인
2. 애플리케이션 중지 (`stop_instance_application`)
3. Nginx 업스트림 DOWN (`stop_instance_nginx`)
4. 인스턴스 디렉터리 삭제 (`remove_instance_directory`)

**구현 예시**:
```bash
# 1. 애플리케이션 중지
if [ -f "${instance_dir}/runApp.sh" ]; then
    (cd "$instance_dir" && ./runApp.sh "$port" stop)
fi

# 2. Nginx DOWN
"${script_dir}/../nginx/nginx_control.sh" down "$port" "$upstream_conf"

# 3. 디렉터리 제거
rm -rf "$instance_dir"
```

### stop_instance_application(instance_dir, port, script_dir)
**목적**: 인스턴스 애플리케이션 중지

**동작**:
1. runApp.sh 존재 확인
2. `runApp.sh $port stop` 실행
3. 실패 시 경고 로그 (제거는 계속 진행)

### stop_instance_nginx(port, upstream_conf, script_dir, nginx_control)
**목적**: Nginx 업스트림 중지

**동작**:
1. Nginx 제어 활성화 확인
2. nginx_control.sh 호출하여 업스트림 DOWN
3. 실패 시 경고 로그 (제거는 계속 진행)

### remove_instance_directory(instance_dir)
**목적**: 인스턴스 디렉터리 삭제

**동작**:
- `rm -rf $instance_dir` 실행
- 실패 시 에러 반환 및 종료

## 5. 환경 설정 (deploy.env)

```bash
# 배포 액션 (기본값)
export DEPLOY_DEFAULT_ACTION="deploy"

# 환경 검증 옵션
export DEPLOY_VALIDATE_JAR_DIR="true"
export DEPLOY_VALIDATE_INSTANCE_DIR="true"

# 백업 옵션
export DEPLOY_BACKUP_JAR="true"
export DEPLOY_BACKUP_RUNAPP="true"

# Nginx 제어 옵션
export DEPLOY_NGINX_CONTROL="true"
export DEPLOY_NGINX_DOWN_ON_ERROR="true"

# 테스트 옵션
export DEPLOY_RUN_TESTS="true"
export DEPLOY_TEST_TIMEOUT="60"

# 롤백 옵션
export DEPLOY_AUTO_ROLLBACK="false"

# 로그 레벨
export DEPLOY_LOG_LEVEL="INFO"
```

## 6. 무중단 배포 워크플로우

### 배포 시나리오 (Zero-Downtime)
```bash
# 인스턴스 0 배포 (PID 파일에서 JAR 읽기)
./deploy_control.sh deploy 0 /path/to/env.env

# 배포 프로세스:
# 1. 파라미터 검증 (instance=0, env_file 존재 확인)
# 2. 환경 로드 (SERVICE_NAME, BASE_PORT, JAR_TRUNK_DIR 등)
# 3. 필수 스크립트 검증 (nginx_control, link_jar_control, run_app_control)
# 4. 배포 환경 준비 (인스턴스 디렉터리 생성)
# 5. Nginx DOWN (트래픽 차단)
# 6. JAR 백업 (current.jar -> current.jar.bak)
# 7. JAR 링크 생성 (PID 파일에서 읽은 새 JAR로 링크)
# 8. runApp.sh 동기화 (최신 버전으로 업데이트)
# 9. 로그 설정 (로그 디렉터리 및 심볼릭 링크)
# 10. 애플리케이션 재시작 (./runApp.sh $port restart)
# 11. 테스트 실행 (test_instance.sh $port)
# 12. Nginx UP (트래픽 복구)
```

### 에러 시 Nginx 복구
```bash
# JAR 링크 실패 시
create_jar_link "$JAR_TRUNK_DIR" "$TARGET_LINK" "$jar_name" "$SCRIPT_DIR" || {
    # Nginx 업스트림 복구
    control_nginx_upstream "up" "$PORT" "$UPSTREAM_CONF" "$SCRIPT_DIR"
    error_exit "JAR link creation failed"
}
```

**에러 복구 포인트**:
- JAR 백업 실패 → Nginx UP
- JAR 링크 실패 → Nginx UP
- runApp.sh 동기화 실패 → Nginx UP
- 로그 설정 실패 → Nginx UP
- 애플리케이션 배포 실패 → Nginx UP
- 테스트 실패 → Nginx UP

### 특정 JAR 버전 배포
```bash
# JAR 파일명 직접 지정
./deploy_control.sh deploy 0 /path/to/env.env app-v2.5.0.jar

# PID 파일 대신 직접 지정된 JAR 사용
create_jar_link "$JAR_TRUNK_DIR" "$TARGET_LINK" "app-v2.5.0.jar" "$SCRIPT_DIR"
```

### 인스턴스 제거
```bash
# 인스턴스 0 제거
./deploy_control.sh remove 0 /path/to/env.env

# 제거 프로세스:
# 1. 파라미터 검증
# 2. 환경 로드
# 3. 애플리케이션 중지 (runApp.sh stop)
# 4. Nginx DOWN
# 5. 인스턴스 디렉터리 삭제
```

## 7. CLI 사용법

### deploy_control.sh - 메인 진입점

```bash
# 배포 (PID 파일에서 JAR 읽기)
./deploy_control.sh deploy 0 /path/to/env.env

# 배포 (특정 JAR 지정)
./deploy_control.sh deploy 0 /path/to/env.env app-v1.0.jar

# 제거
./deploy_control.sh remove 0 /path/to/env.env

# 상태 확인
./deploy_control.sh status 0 /path/to/env.env

# 배포 전제조건 검증
./deploy_control.sh validate 0 /path/to/env.env

# 도움말
./deploy_control.sh help
```

### 상태 확인 출력 예시
```
=== Deployment Status ===
Service: my-service
Instance: 0
Port: 8080
Instance Directory: /home/service/my-service/instances/0

✅ Instance directory exists
✅ JAR link: /instances/0/current.jar -> /jar_trunk/app-v1.0.jar
✅ runApp.sh exists and is executable
✅ Application is running on port 8080
```

### 검증 출력 예시
```
=== Deployment Validation ===
✅ JAR directory validation passed
✅ Required scripts validation passed
✅ All validations passed
```

## 8. 에러 처리

### 배포 파라미터 오류
1. **잘못된 인스턴스 번호**: `[ERROR] Invalid instance number: 10 (must be 0-9)`
2. **환경 파일 없음**: `[ERROR] Environment file not found: /path/to/env.env`
3. **잘못된 액션**: `[ERROR] Invalid action: redeploy (must be 'deploy' or 'remove')`

### 환경 검증 오류
1. **JAR 디렉터리 없음**: `[ERROR] JAR directory not found: /path/to/jar_trunk`
2. **JAR 디렉터리 읽기 불가**: `[ERROR] JAR directory not readable: /path/to/jar_trunk`
3. **인스턴스 디렉터리 쓰기 불가**: `[ERROR] Instance directory not writable: /path/to/instances/0`

### 스크립트 오류
1. **필수 스크립트 없음**: `[ERROR] Required script not found or not executable: nginx_control.sh`
2. **runApp.sh 백업 실패**: `[ERROR] Failed to backup existing runApp.sh`
3. **runApp.sh 복사 실패**: `[ERROR] Failed to copy runApp.sh`

### 배포 실행 오류
1. **디렉터리 변경 실패**: `[ERROR] Failed to change directory to $instance_dir`
2. **runApp.sh 실행 실패**: `[ERROR] Failed to execute runApp.sh`
3. **테스트 실패**: `[ERROR] Tests failed for port 8080`
4. **테스트 타임아웃**: `[ERROR] Test timed out after 60s`

### Nginx 제어 오류
1. **Nginx 스크립트 없음**: `[ERROR] Nginx control script not found: nginx_control.sh`
2. **업스트림 DOWN 실패**: `[ERROR] Failed to set nginx upstream DOWN`
3. **업스트림 UP 실패**: `[ERROR] Failed to set nginx upstream UP`

## 9. 다중 인스턴스 배포 (multi_deploy.sh 연동)

### 병렬 배포 시나리오
```bash
# 3개 인스턴스 동시 배포
for i in 0 1 2; do
    ./deploy_control.sh deploy "$i" /path/to/env.env &
done
wait

# 결과: 인스턴스 0, 1, 2가 병렬로 배포됨
```

### 순차 배포 시나리오
```bash
# 하나씩 배포 및 테스트
for i in 0 1 2; do
    if ./deploy_control.sh deploy "$i" /path/to/env.env; then
        echo "Instance $i deployed successfully"
    else
        echo "Instance $i deployment failed"
        # 롤백 또는 중단 로직
        break
    fi
done
```

### 스케일 다운 시나리오
```bash
# 인스턴스 2, 3, 4 제거 (5개 → 2개로 축소)
for i in 4 3 2; do
    ./deploy_control.sh remove "$i" /path/to/env.env || {
        echo "Failed to remove instance $i"
    }
done

# 역순 제거로 안정성 확보
```

## 10. 환경 변수

### 필수 환경 변수 (env.env)
```bash
export SERVICE_NAME="my-service"                      # 서비스 이름
export BASE_PORT="808"                                # 기본 포트 (인스턴스별 +숫자)
export JAR_TRUNK_DIR="/home/service/jar_trunk"        # JAR 소스 디렉터리
export SERVICE_BASE_DIR="/home/service"               # 서비스 루트
export UPSTREAM_CONF="/etc/nginx/conf.d/upstream.conf" # Nginx 설정
export LOG_BASE_DIR="/home/system/logs"               # 로그 디렉터리
export APP_MODE="restart"                             # 앱 실행 모드
export JAVA_OPTS="--spring.profiles.active=prod"     # Java 옵션
export TEST_SCRIPT="./test_instance.sh"               # 테스트 스크립트
```

### 선택 환경 변수 (deploy.env)
```bash
export DEPLOY_VALIDATE_JAR_DIR="true"       # JAR 디렉터리 검증 (기본: true)
export DEPLOY_VALIDATE_INSTANCE_DIR="true"  # 인스턴스 디렉터리 검증 (기본: true)
export DEPLOY_BACKUP_JAR="true"             # JAR 백업 (기본: true)
export DEPLOY_BACKUP_RUNAPP="true"          # runApp.sh 백업 (기본: true)
export DEPLOY_NGINX_CONTROL="true"          # Nginx 제어 활성화 (기본: true)
export DEPLOY_NGINX_DOWN_ON_ERROR="true"    # 에러 시 Nginx UP (기본: true)
export DEPLOY_RUN_TESTS="true"              # 테스트 실행 (기본: true)
export DEPLOY_TEST_TIMEOUT="60"             # 테스트 타임아웃 (초, 기본: 60)
export DEPLOY_AUTO_ROLLBACK="false"         # 자동 롤백 (기본: false)
export DEPLOY_LOG_LEVEL="INFO"              # 로그 레벨 (기본: INFO)
```

## 11. 파일 구조

```
renew/deploy/
├── deploy.env              # 환경 변수 설정
├── deploy_control.sh       # 메인 CLI 스크립트
├── SPEC.md                 # 명세 문서
└── func/                   # 함수 스크립트들
    ├── validate_deployment.sh   # 배포 검증
    ├── prepare_deployment.sh    # 배포 준비
    ├── execute_deployment.sh    # 배포 실행
    └── handle_removal.sh        # 인스턴스 제거
```

## 12. 레거시 시스템과의 차이점

### pre/deploy.sh (레거시)
- 모놀리식 구조 (한 파일에 모든 로직)
- 하드코딩된 스크립트 경로
- 제한된 설정 옵션
- 에러 처리 시 Nginx 복구만 수행

### renew/deploy (신규)
- 환경 변수 기반 설정 (deploy.env)
- 모듈형 함수 구조 (func/ 디렉터리)
- 세밀한 검증 옵션 (JAR 디렉터리, 인스턴스 디렉터리)
- 백업 옵션 제어 (JAR, runApp.sh)
- 테스트 타임아웃 설정
- 상태 확인 및 검증 기능
- CLI 인터페이스 개선

## 13. 테스트 시나리오

### 단위 테스트
```bash
# 1. 파라미터 검증 테스트
./func/validate_deployment.sh params 0 /tmp/test.env deploy
# 출력: [INFO] Parameters validated: instance=0, action=deploy

# 2. JAR 디렉터리 검증
./func/validate_deployment.sh jar /tmp/jar_trunk
# 출력: [INFO] JAR directory validated: /tmp/jar_trunk

# 3. 배포 환경 준비
./func/prepare_deployment.sh prepare /tmp/instances/0 /tmp/jar_trunk
# 출력: [INFO] Deploy environment prepared successfully

# 4. JAR 백업
./func/prepare_deployment.sh backup /tmp/instances/0/current.jar
# 출력: [SUCCESS] JAR backup completed
```

### 통합 테스트
```bash
# 전체 배포 워크플로우 테스트
export DEPLOY_RUN_TESTS="false"  # 테스트 비활성화 (개발 환경)

# 1. 초기 배포
./deploy_control.sh deploy 0 /tmp/test.env

# 2. 상태 확인
./deploy_control.sh status 0 /tmp/test.env

# 3. 새 버전 배포
echo "app-v2.0.jar" > /tmp/jar_trunk/current_jar.pid
./deploy_control.sh deploy 0 /tmp/test.env

# 4. 제거
./deploy_control.sh remove 0 /tmp/test.env
```

### 에러 처리 테스트
```bash
# 1. 잘못된 JAR 디렉터리
export JAR_TRUNK_DIR="/invalid/path"
./deploy_control.sh deploy 0 /tmp/test.env
# 출력: [ERROR] JAR directory not found: /invalid/path

# 2. 테스트 실패 시나리오
export TEST_SCRIPT="/tmp/failing_test.sh"
./deploy_control.sh deploy 0 /tmp/test.env
# 출력: [ERROR] Tests failed for port 8080
# Nginx 자동 복구 확인
```

## 14. 보안 고려사항

### 권한 관리
- JAR 디렉터리 읽기 권한 필요
- 인스턴스 디렉터리 쓰기 권한 필요
- Nginx 설정 파일 쓰기 권한 필요
- runApp.sh 실행 권한 자동 부여 (`chmod +x`)

### 에러 시 자동 복구
- 배포 실패 시 Nginx 업스트림 자동 복구
- 백업 파일 보존 (롤백 가능)
- 인스턴스 디렉터리 보존 (제거 실패 시)

### 테스트 타임아웃
- 무한 대기 방지 (`timeout` 명령 사용)
- 기본 60초 타임아웃 (설정 가능)
- 타임아웃 발생 시 명확한 에러 메시지

## 15. 모범 사례

### 배포 전
1. 환경 변수 검증: `./deploy_control.sh validate 0 /path/to/env.env`
2. JAR 파일 준비: PID 파일 또는 직접 지정
3. 테스트 스크립트 준비: 헬스체크 엔드포인트 확인

### 배포 중
1. 상태 모니터링: `./deploy_control.sh status 0 /path/to/env.env`
2. 로그 확인: 인스턴스 로그 디렉터리 모니터링
3. Nginx 상태: 업스트림 활성화 여부 확인

### 배포 후
1. 테스트 실행: 자동 또는 수동 테스트
2. 로그 검증: 에러 로그 확인
3. 백업 확인: `.bak` 파일 존재 확인 (롤백 대비)

### 롤백
```bash
# 1. 백업 파일 복원
mv /instances/0/current.jar.bak /instances/0/current.jar

# 2. 애플리케이션 재시작
./deploy_control.sh deploy 0 /path/to/env.env
```
