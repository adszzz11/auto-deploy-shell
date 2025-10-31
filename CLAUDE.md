# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

**Auto-Deploy-Shell v2.0.0**은 Spring Boot 애플리케이션의 다중 인스턴스 배포를 자동화하는 Bash 기반 시스템입니다. 이중 서버 환경에서 machine-id 기반으로 인스턴스를 식별하고, Nginx 로드밸런싱과 연동하여 무중단 배포를 지원합니다.

**현재 상태**: ✅ **완전 구현 완료 및 배포 가능**

## 아키텍처

### 4-Layer 계층 구조

```
Layer 1 (User Interface)
  └─ main.sh                          사용자 진입점
       ↓
Layer 2 (Orchestration)
  └─ multi_deploy_control.sh          다중 인스턴스 오케스트레이션
       ↓
Layer 3 (Core Operations)
  ├─ deploy_control.sh                단일 인스턴스 배포
  └─ rollback_control.sh              단일 인스턴스 롤백
       ↓
Layer 4 (Support Services)
  ├─ nginx_control.sh                 Nginx 업스트림 제어
  ├─ link_jar_control.sh              JAR 파일 심볼릭 링크 관리
  ├─ run_app_control.sh               애플리케이션 프로세스 관리
  └─ test_instance_control.sh         인스턴스 헬스체크
```

### 디렉터리 구조

```
auto-deploy-shell/
├── main.sh                          # Layer 1 진입점
├── base.env                         # 사용자 환경 설정 템플릿
├── test_instance.sh                 # 사용자 정의 테스트 스크립트 (선택)
└── _shell/
    ├── deploy/
    │   ├── deploy_control.sh        # Layer 3 - 배포 컨트롤러
    │   └── func/*.sh                # 배포 기능 함수들
    ├── rollback/
    │   ├── rollback_control.sh      # Layer 3 - 롤백 컨트롤러
    │   └── func/*.sh                # 롤백 기능 함수들
    ├── multi_deploy/
    │   ├── multi_deploy_control.sh  # Layer 2 - 오케스트레이션 컨트롤러
    │   └── func/*.sh                # 오케스트레이션 함수들
    ├── nginx/
    │   ├── nginx_control.sh         # Layer 4 - Nginx 제어
    │   └── func/*.sh                # Nginx 제어 함수들
    ├── link_jar/
    │   ├── link_jar_control.sh      # Layer 4 - JAR 링크 관리
    │   └── func/*.sh                # JAR 링크 함수들
    ├── run_app/
    │   ├── run_app_control.sh       # Layer 4 - 앱 실행 제어
    │   └── func/*.sh                # 앱 실행 함수들
    └── test_instance/
        ├── test_instance_control.sh # Layer 4 - 테스트 제어
        └── func/*.sh                # 테스트 함수들
```

## 빠른 시작

### 1. 환경 설정

```bash
# base.env 복사 및 수정
cp base.env myapp.env
vi myapp.env

# 필수 설정 항목:
# - SERVICE_NAME: 서비스명
# - TYPE: 물리 서버 타입 (A 또는 B)
# - BASE_PORT: 기본 포트 (예: 808)
# - SERVICE_BASE_DIR: 서비스 루트 디렉터리
# - UPSTREAM_CONF: Nginx 설정 파일 경로
```

### 2. 배포 실행

```bash
# 5개 인스턴스 배포 (2-5개 범위 지원)
./main.sh deploy 5 myapp.env

# 배포 상태 확인
./main.sh status myapp.env

# 전체 롤백
./main.sh rollback myapp.env

# 배포 전 검증
./main.sh validate 5 myapp.env
```

## 핵심 명령어

### main.sh (Layer 1)

```bash
# 다중 인스턴스 배포
./main.sh deploy <count> <env_file>    # count: 2-5

# 전체 롤백
./main.sh rollback <env_file>

# 배포 상태 확인
./main.sh status <env_file>

# 배포 전 검증
./main.sh validate <count> <env_file>

# 버전 정보
./main.sh version

# 도움말
./main.sh help
```

### 고급 사용 (직접 모듈 제어)

```bash
# Layer 3 - 단일 인스턴스 배포
./_shell/deploy/deploy_control.sh deploy 0 myapp.env

# Layer 3 - 단일 인스턴스 롤백
./_shell/rollback/rollback_control.sh rollback 0 myapp.env

# Layer 4 - Nginx 제어
./_shell/nginx/nginx_control.sh up 8080 /etc/nginx/conf.d/upstream.conf
./_shell/nginx/nginx_control.sh down 8080

# Layer 4 - 애플리케이션 제어
./_shell/run_app/run_app_control.sh start 8080 '--spring.profiles.active=prod'
./_shell/run_app/run_app_control.sh restart 8080
./_shell/run_app/run_app_control.sh stop 8080

# Layer 4 - 테스트 실행
./_shell/test_instance/test_instance_control.sh test 8080 myapp.env
```

## 배포 프로세스

### 전체 배포 플로우

```
1. main.sh
   ↓ 파라미터 검증 (2-5 인스턴스)
   ↓
2. multi_deploy_control.sh
   ↓ 환경 로드 및 인스턴스 분석
   ↓
3. [Loop: instance 0 → count-1]
   ↓
   deploy_control.sh (단일 인스턴스 배포)
   ├─ 1. 환경 변수 설정 (PORT, MACHINE_ID)
   ├─ 2. 필수 스크립트 검증
   ├─ 3. 배포 환경 준비
   ├─ 4. Nginx DOWN (트래픽 차단)
   ├─ 5. JAR 백업 (current.jar → current.jar.bak)
   ├─ 6. JAR 링크 생성 (link_jar_control.sh)
   ├─ 7. runApp.sh 동기화
   ├─ 8. 로그 디렉터리 설정
   ├─ 9. 애플리케이션 재시작 (run_app_control.sh)
   ├─ 10. 테스트 실행 (test_instance_control.sh 또는 사용자 스크립트)
   ├─ 11. Nginx UP (트래픽 복구)
   └─ 12. 성공 확인
   ↓
   대기 (MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS: 2초)
   ↓
4. 안정화 대기 (MULTI_DEPLOY_STABILIZATION_WAIT: 5초)
   ↓
5. 배포 완료
```

### 롤백 프로세스

```
1. 현재 인스턴스 분석
   ↓
2. [Loop: 역순으로 각 인스턴스]
   ↓
   rollback_control.sh (단일 인스턴스 롤백)
   ├─ 1. 백업 파일 검증 (current.jar.bak)
   ├─ 2. 백업 무결성 확인
   ├─ 3. 디스크 공간 확인
   ├─ 4. Nginx DOWN
   ├─ 5. 실패한 JAR 백업 생성
   ├─ 6. JAR 복원 (current.jar.bak → current.jar)
   ├─ 7. 복원 검증
   ├─ 8. 애플리케이션 재시작
   └─ 9. Nginx UP
   ↓
3. 롤백 완료
```

## 핵심 메커니즘

### 1. 포트 할당 체계

```bash
PORT = ${BASE_PORT}${INSTANCE_NUM}

예시:
  BASE_PORT=808, Instance 0 → Port 8080
  BASE_PORT=808, Instance 1 → Port 8081
  BASE_PORT=808, Instance 4 → Port 8084
```

### 2. Machine ID 계산 (이중 서버 환경)

```bash
TYPE=A: machine_id = instance_num + 0  (0-4)
TYPE=B: machine_id = instance_num + 5  (5-9)

예시:
  TYPE=A, Instance 0 → MACHINE_ID=0
  TYPE=A, Instance 4 → MACHINE_ID=4
  TYPE=B, Instance 0 → MACHINE_ID=5
  TYPE=B, Instance 4 → MACHINE_ID=9
```

### 3. 프로세스 식별

```bash
# 포트 기반 프로세스 탐지
pgrep -f "java -jar current.jar --server.port=${PORT}"
```

### 4. Nginx 업스트림 제어

- **DOWN**: 배포 전 트래픽 차단 (서버 라인 주석 처리: `# server 127.0.0.1:8080;`)
- **UP**: 배포 후 트래픽 복구 (주석 제거 또는 새 서버 추가)
- **검증**: `nginx -t` (설정 검증)
- **적용**: `nginx -s reload` (설정 리로드)

### 5. JAR 관리

- **심볼릭 링크**: `current.jar` → 실제 JAR 파일 (jar_trunk에서)
- **백업**: 배포 전 `current.jar` → `current.jar.bak`
- **롤백**: `current.jar.bak` → `current.jar`

## 환경 변수

### base.env (필수 설정)

```bash
# 필수
export SERVICE_NAME="service_name"              # 서비스명
export TYPE="A"                                 # 물리 서버 타입 (A 또는 B)
export BASE_PORT="808"                          # 기본 포트
export SERVICE_BASE_DIR="/home/service"         # 서비스 루트
export UPSTREAM_CONF="/etc/nginx/conf.d/upstream.conf"  # Nginx 설정

# 선택
export LOG_BASE_DIR="/home/system/logs"         # 로그 디렉터리
export APP_JAVA_EXECUTABLE="java"               # Java 실행 파일 경로
export JVM_OPTS=""                              # JVM 옵션 (메모리, GC 등)
export JAVA_OPTS="--spring.profiles.active=prod --profile.machine_id=\${MACHINE_ID}"
export APP_MODE="restart"                       # restart, start, stop
export TEST_SCRIPT="./test_instance.sh"         # 사용자 테스트 스크립트
```

### 자동 생성 변수 (deploy_control.sh)

```bash
export PORT="${BASE_PORT}${instance_num}"                                       # 8080, 8081, ...
export MACHINE_ID=$((instance_num + (TYPE=="B" ? 5 : 0)))                      # 0-4 (A), 5-9 (B)
export INSTANCE_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"
export JAR_TRUNK_DIR="${SERVICE_BASE_DIR}/${SERVICE_NAME}/jar_trunk"
export TARGET_LINK="${INSTANCE_DIR}/current.jar"
```

## 에러 처리

### 자동 롤백

```bash
# 배포 실패 시 성공한 인스턴스도 모두 롤백 (버전 일관성 보장)
export MULTI_DEPLOY_AUTO_ROLLBACK=true  # 기본값
```

### Graceful Shutdown

```bash
# 애플리케이션 중지 시
1. SIGTERM 전송 → 10초 대기
2. 프로세스 살아있으면 SIGKILL 전송 → 5초 대기
```

### 배포 실패 시

```
1. Nginx 트래픽 즉시 복구 (DOWN → UP)
2. 에러 로그 출력
3. 자동 롤백 실행 (MULTI_DEPLOY_AUTO_ROLLBACK=true인 경우)
```

## 디렉터리 구조 (실행 시 자동 생성)

```
${SERVICE_BASE_DIR}/${SERVICE_NAME}/
├── jar_trunk/                      # JAR 파일 저장소 (자동 생성)
│   ├── app-v1.0.jar
│   ├── app-v1.1.jar
│   └── app-v2.0.jar
└── instances/
    ├── 0/
    │   ├── current.jar             # 심볼릭 링크 → jar_trunk/app-v2.0.jar
    │   ├── current.jar.bak         # 백업 (롤백용)
    │   ├── runApp.sh               # 애플리케이션 실행 스크립트
    │   └── logs/                   # 심볼릭 링크 → LOG_BASE_DIR
    ├── 1/
    ├── 2/
    ├── 3/
    └── 4/
```

## 개발 가이드

### 모듈 구조

모든 모듈은 동일한 패턴을 따릅니다:

```
_shell/<module_name>/
├── <module_name>_control.sh        # 진입점 (Layer 2-4)
└── func/                            # 기능 함수들
    ├── function1.sh
    ├── function2.sh
    └── function3.sh
```

### 컨트롤러 스크립트 패턴

```bash
#!/bin/bash
set -euo pipefail

# 현재 디렉터리 설정
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 함수 스크립트들 source
source "${SCRIPT_DIR}/func/function1.sh"
source "${SCRIPT_DIR}/func/function2.sh"

# 사용법 출력
print_usage() { ... }

# 메인 진입점
main() {
    case "$command" in
        action1) execute_action1 "$@" ;;
        action2) execute_action2 "$@" ;;
        *) print_usage; exit 1 ;;
    esac
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### 로깅 규칙

```bash
# 일반 로그: stderr로 출력
echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Message" >&2
echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - Warning" >&2
echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Error" >&2
echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Success" >&2

# 반환 값: stdout으로 출력
echo "$result_value"
```

### 계층 간 호출 규칙

- Layer 1은 오직 Layer 2만 호출
- Layer 2는 Layer 3만 호출
- Layer 3은 Layer 4만 호출
- Layer 4는 외부 명령(nginx, pgrep 등)만 호출
- 상위 계층으로의 역호출 금지

## 테스트

### 사용자 정의 테스트 스크립트 작성

```bash
# test_instance.sh 예시
#!/bin/bash
set -euo pipefail

# Logging functions (inline)
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

error_exit() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
    exit 1
}

PORT="$1"
FAIL=0

log_info "Starting tests for instance on port $PORT..."

# HTTP 상태 코드 테스트
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/health")
if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "Health check failed: $HTTP_STATUS"
    FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
    log_success "All tests passed for port $PORT"
    exit 0
else
    error_exit "Tests failed for port $PORT"
fi
```

### Java 버전 관리

여러 Java 버전을 사용하는 환경에서는 `APP_JAVA_EXECUTABLE` 변수를 설정하여 특정 Java 버전을 사용할 수 있습니다.

```bash
# base.env 또는 myapp.env에서 설정

# Java 8 사용
export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-8-openjdk/bin/java"

# Java 11 사용
export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-11-openjdk/bin/java"

# Java 17 사용 (Amazon Corretto)
export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-17-amazon-corretto/bin/java"

# Java 21 사용
export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-21-openjdk/bin/java"

# 시스템 기본 Java 사용 (기본값)
export APP_JAVA_EXECUTABLE="java"
```

**Java 버전 확인**:
```bash
# 설정된 Java 실행 파일의 버전 확인
${APP_JAVA_EXECUTABLE} -version

# 또는 배포 시 자동으로 로그에 출력됨
# [INFO] Using Java: openjdk version "17.0.9" 2023-10-17
```

### JVM 옵션 관리

JVM 옵션과 Spring Boot 옵션을 분리하여 관리합니다:

- **JVM_OPTS**: JVM 레벨 설정 (메모리, GC, 디버깅 등)
- **JAVA_OPTS**: 애플리케이션 레벨 설정 (Spring 프로필, 커스텀 속성 등)

```bash
# base.env 또는 myapp.env에서 설정

# JVM 메모리 설정
export JVM_OPTS="-Xmx1024m -Xms512m"

# JVM + GC 최적화
export JVM_OPTS="-Xmx2048m -Xms1024m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# JVM + 쓰레드 풀 설정
export JVM_OPTS="-Xmx1024m -Xms512m -XX:+UseG1GC -Dspring.threads.virtual.enabled=true"

# 디버깅 활성화
export JVM_OPTS="-Xmx1024m -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"

# Spring Boot 옵션 (별도 설정)
export JAVA_OPTS="--spring.profiles.active=prod --profile.machine_id=\${MACHINE_ID}"
```

**최종 실행 명령**: `java [JVM_OPTS] -jar current.jar --server.port=PORT [JAVA_OPTS]`

예:
```bash
# JVM_OPTS="-Xmx1024m -Xms512m"
# JAVA_OPTS="--spring.profiles.active=prod"
# 실행 명령: java -Xmx1024m -Xms512m -jar current.jar --server.port=8080 --spring.profiles.active=prod
```

### 검증 명령

```bash
# 배포 전 검증
./main.sh validate 5 myapp.env

# 개별 모듈 검증
./_shell/deploy/deploy_control.sh validate 0 myapp.env
./_shell/nginx/nginx_control.sh test-config
```

## 문제 해결

### 일반적인 문제

```bash
# 권한 문제
chmod +x main.sh
find _shell -name "*.sh" -exec chmod +x {} \;

# 환경 파일 문제
dos2unix base.env  # Windows에서 생성한 경우

# Nginx 설정 확인
nginx -t
./_shell/nginx/nginx_control.sh test-config

# 프로세스 확인
pgrep -f "\-jar current.jar.*--server.port=8080"

# 로그 확인
tail -f ${LOG_BASE_DIR}/${SERVICE_NAME}/instances/0/*.log
```

### 디버그 모드

```bash
# 상세 로그 출력
bash -x ./main.sh deploy 5 myapp.env

# 개별 모듈 디버그
bash -x ./_shell/deploy/deploy_control.sh deploy 0 myapp.env
```

## 제약 사항

- **인스턴스 수**: 2-5개 고정 (확장 불가)
- **물리 서버**: 최대 2대 (TYPE A, B)
- **포트 범위**: BASE_PORT는 3자리 숫자 권장 (예: 808)
- **OS**: Linux/macOS (bash 4.0+)
- **필수 도구**: nginx, curl, pgrep/pkill, Java

## 참고 사항

### 버전 관리

- **현재 버전**: v2.0.0 (Renew)
- **Git 브랜치**: feature-001
- **최근 커밋**: TYPE 별 machine_id 부여, 리팩터링 완료

### 성능 최적화

- 순차 배포: 인스턴스당 약 10-30초 (애플리케이션 시작 시간 포함)
- 대기 시간: 인스턴스 간 2초, 전체 안정화 5초
- 5개 인스턴스 배포: 약 1-3분 소요

### 보안

- 환경 변수에 민감 정보 저장 금지 (별도 관리 권장)
- Nginx 설정 파일 권한: 644 이상
- 인스턴스 디렉터리 권한: 755 이상
- JAR 파일 권한: 644 이상

## 기여 가이드

1. **코드 스타일**: 모든 스크립트에 `set -euo pipefail` 포함
2. **함수 분리**: 각 기능은 개별 함수 파일로 작성
3. **로깅**: stderr 사용, 타임스탬프 포함
4. **에러 처리**: 모든 에러는 return 1 또는 exit 1
5. **문서화**: 함수 상단에 주석으로 역할 명시
6. **테스트**: 수정 후 validate 명령으로 검증

## 라이선스

이 프로젝트는 내부 배포 자동화 도구로, 상용 라이선스 정보는 별도 문서 참조.
