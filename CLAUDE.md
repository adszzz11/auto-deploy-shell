# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Auto-Deploy-Shell은 Spring Boot 애플리케이션의 다중 인스턴스 배포를 자동화하는 Bash 기반 시스템입니다. 이중 서버 환경에서 machine-id 기반으로 인스턴스를 식별하고, Nginx 로드밸런싱과 연동하여 무중단 배포를 지원합니다.

**⚠️ 현재 상태 - 리팩터링 진행 중**:
- 모듈형 함수 기반 구조(`_shell/*/` 디렉터리)로의 전환이 **부분적으로 완료됨**
- `multi_deploy.sh`가 존재하지 않는 래퍼 스크립트들(`_shell/deploy.sh`, `_shell/rollback.sh`)을 호출하고 있어 **현재 실행 불가능**
- 개별 모듈(`_shell/deploy/`, `_shell/rollback/` 등)은 함수형으로 완성되었으나 메인 스크립트와 연결되지 않음
- 레거시 단일 스크립트(`_shell/deploy/deploy.sh`)는 여전히 존재하며 작동 가능

## 빠른 시작

### ⚠️ 현재 시스템 실행 불가
`multi_deploy.sh`는 현재 **작동하지 않습니다**. 다음 래퍼 스크립트들을 생성해야 합니다:
- `_shell/deploy.sh` → `_shell/deploy/deploy.sh` 또는 `_shell/deploy/deploy_main.sh` 호출
- `_shell/rollback.sh` → `_shell/rollback/rollback_main.sh` 호출

### 임시 대안 (레거시 스크립트 직접 사용)
```bash
# 1. 환경 설정 확인
cat test.env

# 2. 단일 인스턴스 배포 (레거시 방식)
./_shell/deploy/deploy.sh 0 test.env deploy

# 3. 인스턴스 상태 확인
./test_instance.sh 8080
```

### 시스템 상태 확인
```bash
# 공통 유틸리티 함수 테스트
source _shell/common_utils/common_utils_main.sh && log_info "System check"

# 스크립트 실행 권한 확인
find _shell -name "*_main.sh" -exec ls -la {} \;
```

## 핵심 명령어

### ⚠️ 현재 작동하는 명령어 (레거시 스크립트)
```bash
# 단일 인스턴스 배포/제거 (레거시 - 현재 유일한 작동 방식)
./_shell/deploy/deploy.sh <instance_number> <env_file> [deploy|remove]

# 인스턴스 테스트 (레거시)
./test_instance.sh <port>
```

### ❌ 현재 작동하지 않는 명령어
```bash
# 다중 인스턴스 배포 - 래퍼 스크립트 누락으로 실행 불가
./multi_deploy.sh <instance_count> <env_file>
```

### ✅ 모듈형 함수들 (직접 호출 가능 - 개발/테스트용)
이 함수들은 완성되었으나 래퍼 스크립트 없이는 메인 워크플로우에서 사용 불가:
```bash
# 배포 모듈 (함수형 - 완전 구현됨)
./_shell/deploy/deploy_main.sh <instance_number> <env_file> [deploy|remove]

# 롤백 모듈
./_shell/rollback/rollback_main.sh <instance_number> <env_file>

# 애플리케이션 관리
./_shell/runApp/runApp_main.sh <port> [stop|start|restart] [JAVA_OPTS]

# Nginx 제어
./_shell/controll_nginx/nginx_control_main.sh <port> <upstream_conf> <up|down>

# JAR 링크 관리
./_shell/link_jar/link_jar_main.sh <instance_number> <env_file> <jar_name>

# 로그 설정
./_shell/setup_logs/setup_logs_main.sh <instance_number> <env_file>

# 인스턴스 테스트
./_shell/test_instance/test_instance_main.sh <port> [custom_test_endpoint]
```

### 테스트 및 검증
```bash
# 인스턴스 헬스체크
./test_instance.sh <port>

# 예시: 테스트 환경에서 실행
./multi_deploy.sh 3 test.env
./test_instance.sh 8080
```

## 시스템 아키텍처

### 포트 및 인스턴스 체계
- **포트 할당**: `${BASE_PORT}${INSTANCE_NUM}` (예: BASE_PORT=808, Instance 0 → Port 8080)
- **인스턴스 범위**: 0-9 (최대 10개 인스턴스 지원)
- **디렉터리 구조**: `${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/${INSTANCE_NUM}/`
- Spring Boot 애플리케이션은 `--server.port` 파라미터로 포트 지정

### 배포 프로세스 플로우
1. **환경 검증**: 필수 디렉터리, 스크립트 권한 확인
2. **Nginx DOWN**: `controll_nginx.sh`로 트래픽 차단
3. **JAR 백업**: 기존 `current.jar`를 `current.jar.bak`으로 백업
4. **JAR 교체**: `link_jar.sh`로 심볼릭 링크 업데이트
5. **runApp.sh 동기화**: 최신 버전으로 업데이트 및 권한 설정
6. **로그 설정**: `setup_logs.sh`로 로그 디렉터리 구성
7. **앱 재시작**: `runApp.sh`로 프로세스 관리 (포트 기반 식별)
8. **테스트 실행**: `TEST_SCRIPT` 환경 변수로 지정된 스크립트 실행
9. **Nginx UP**: 테스트 통과 후 트래픽 복구

### 에러 처리 전략
- **전체 롤백**: 하나라도 실패하면 모든 성공 인스턴스 롤백 (버전 일관성 보장)
- **Graceful Shutdown**: SIGTERM(10초) → SIGKILL(5초) 순차 처리
- **스케일링**: 타겟 인스턴스 수보다 많은 인스턴스는 자동 제거

## 파일 구조 및 역할

### 메인 스크립트
- `multi_deploy.sh`: 다중 인스턴스 배포 오케스트레이션 (**현재 작동 불가** - 래퍼 스크립트 누락)
- `test_instance.sh`: 개별 인스턴스 헬스체크 스크립트 (작동 중)

### 핵심 모듈 (_shell/ - 함수형 구조)

#### ⚠️ 누락된 래퍼 스크립트들 (생성 필요)
- `_shell/deploy.sh` → `deploy/deploy.sh` 또는 `deploy/deploy_main.sh` 호출 필요
- `_shell/rollback.sh` → `rollback/rollback_main.sh` 호출 필요
- `_shell/controll_nginx.sh` → `controll_nginx/nginx_control_main.sh` 호출 필요
- `_shell/link_jar.sh` → `link_jar/link_jar_main.sh` 호출 필요
- `_shell/setup_logs.sh` → `setup_logs/setup_logs_main.sh` 호출 필요
- `_shell/runApp.sh` → `runApp/runApp_main.sh` 호출 필요

#### 공통 유틸리티 (`_shell/common_utils/`)
- `common_utils_main.sh`: 메인 로딩 스크립트 (✅ 작동 중)
- `common_utils.sh`: 레거시 호환 래퍼 (✅ 작동 중)
- `log_info.sh`, `log_warn.sh`, `log_success.sh`: 구조화된 로깅 함수
- `error_exit.sh`: 에러 처리 및 종료 함수
- `current_timestamp.sh`: 타임스탬프 생성 함수

#### 배포 관리 (`_shell/deploy/`)
- `deploy.sh`: **레거시 단일 스크립트** (✅ 현재 유일하게 작동하는 배포 스크립트)
- `deploy_main.sh`: 모듈형 배포 메인 함수 (완성되었으나 래퍼 없음)
- `execute_deployment.sh`: 실제 배포 실행 로직
- `validate_deploy_parameters.sh`: 배포 파라미터 검증
- `sync_runapp_script.sh`: runApp 스크립트 동기화
- `handle_instance_removal.sh`: 인스턴스 제거 처리

#### 애플리케이션 관리 (`_shell/runApp/`)
- `runApp.sh`: **레거시 래퍼** (✅ 작동 중 - `deploy.sh`가 사용)
- `runApp_main.sh`: 모듈형 프로세스 관리 메인 함수
- `start_application.sh`, `stop_application.sh`, `restart_application.sh`: 프로세스 생명주기 관리
- `find_app_process.sh`: 포트 기반 프로세스 탐지
- `build_exec_command.sh`: 실행 명령어 빌드

#### Nginx 제어 (`_shell/controll_nginx/`)
- `nginx_control_main.sh`: Nginx 업스트림 제어 메인 함수
- `set_server_up.sh`, `set_server_down.sh`: 업스트림 서버 활성화/비활성화
- `reload_nginx.sh`: Nginx 설정 리로드
- `test_nginx_config.sh`: 설정 파일 유효성 검증

#### 기타 핵심 모듈
- `_shell/rollback/`: JAR 백업에서 복원 관련 함수들
- `_shell/link_jar/`: JAR 파일 심볼릭 링크 관리 함수들
- `_shell/setup_logs/`: 로그 디렉터리 구성 함수들
- `_shell/test_instance/`: 인스턴스 헬스체크 관련 함수들
- `_shell/multi_deploy/`: 다중 배포 로직 관련 함수들

### 환경 설정
- `base.env`: 공통 설정 템플릿 (프로덕션용)
- `test.env`: 테스트 환경 설정 (/tmp 기반)

## 로깅 및 모니터링

### 로그 시스템
- **구조화된 로깅**: `log_info()`, `log_warn()`, `log_success()`, `error_exit()` 함수 사용
- **타임스탬프**: 모든 로그에 `[INFO/WARN/ERROR] YYYY-MM-DD HH:MM:SS` 형식 적용
- **프로세스 식별**: `pgrep -f "java -jar current.jar --server.port=${PORT}"` 패턴 사용

### 주요 환경 변수
```bash
# 필수 설정
export SERVICE_NAME="service_name"           # 서비스 명
export BASE_PORT="808"                       # 기본 포트 (인스턴스별로 +숫자)
export JAR_TRUNK_DIR="/path/to/jar_trunk"    # JAR 파일 소스 디렉터리
export APP_MODE="restart"                    # 애플리케이션 실행 모드
export UPSTREAM_CONF="/etc/nginx/conf.d/upstream.conf"  # Nginx 설정 파일
export SERVICE_BASE_DIR="/home/service"      # 서비스 루트 디렉터리
export LOG_BASE_DIR="/home/system/logs"      # 로그 디렉터리
export JAVA_OPTS="--spring.profiles.active=prod"  # Spring Boot 옵션
export TEST_SCRIPT="./test_instance.sh"      # 헬스체크 스크립트 (선택사항)
```

## 개발 시 주의사항

### 스크립트 수정 가이드
1. **에러 처리**: 모든 함수에서 `error_exit()` 사용하여 일관된 에러 처리
2. **로깅 일관성**: `echo` 대신 `log_info()`, `log_warn()`, `log_success()` 함수 사용
3. **스크립트 헤더**: 모든 스크립트에 `set -euo pipefail` 포함
4. **함수형 구조**: 각 모듈은 `*_main.sh` 파일에서 개별 함수들을 source하여 로드
5. **공통 유틸리티 사용**: `source "$(dirname "$0")/../common_utils/common_utils_main.sh"` 패턴 사용
6. **권한 검증**: 필수 스크립트 실행 권한 확인 후 진행

### 모듈형 아키텍처 특징
- **단일 책임**: 각 함수 파일은 하나의 명확한 기능만 담당
- **재사용성**: 공통 로직을 개별 함수로 분리하여 재사용 가능
- **테스트 용이성**: 개별 함수 단위로 테스트 가능
- **유지보수성**: 기능별로 파일이 분리되어 수정 영향 범위 최소화

### 배포 버전 일관성
- 모든 인스턴스는 동일한 버전으로 배포되어야 함
- 부분 실패 시 전체 롤백으로 일관성 보장
- 포트 기반 정확한 프로세스 식별 (`pgrep -f` 패턴 사용)
- `current.jar` 심볼릭 링크로 JAR 버전 관리

### 테스트 및 헬스체크
- `TEST_SCRIPT` 환경 변수로 커스텀 테스트 스크립트 지정 가능
- `test_instance.sh`는 HTTP 상태 코드 검증 (기본: `/api/v1/global/commoncode/TX_DVCD/WDL`)
- 테스트 실패 시 Nginx 업스트림 복구 후 배포 중단

## 리팩터링 상태 및 해결 필요 사항

### ✅ 완료된 작업
1. **공통 유틸리티 모듈화**: `_shell/common_utils/` 디렉터리에 함수별 분리 완료
2. **개별 모듈 함수화**: deploy, rollback, runApp, controll_nginx, link_jar, setup_logs, test_instance 모듈 완성
3. **레거시 호환 래퍼**: `_shell/common_utils.sh` 생성으로 기존 코드 호환성 유지
4. **레거시 스크립트 유지**: `_shell/deploy/deploy.sh`, `_shell/runApp/runApp.sh` 작동 중

### ❌ 미완료 작업 (시스템 실행 불가 원인)
1. **래퍼 스크립트 누락**: `multi_deploy.sh`가 호출하는 다음 스크립트들이 존재하지 않음
   - `_shell/deploy.sh` (line 79, 101에서 호출)
   - `_shell/rollback.sh` (line 66에서 호출)

2. **선택 사항**:
   - 옵션 A: 누락된 래퍼 스크립트 생성 (권장)
   - 옵션 B: `multi_deploy.sh`를 레거시 스크립트 경로로 수정
   - 옵션 C: `multi_deploy.sh`를 완전히 모듈형으로 재작성

### 현재 작동 가능한 워크플로우
- ✅ **단일 인스턴스 배포**: `_shell/deploy/deploy.sh` (레거시 스크립트)
- ✅ **헬스체크**: `test_instance.sh`
- ✅ **개별 모듈 테스트**: 모든 `*_main.sh` 스크립트들
- ❌ **다중 인스턴스 배포**: `multi_deploy.sh` (래퍼 스크립트 누락)

## 문제 해결

### 즉시 해결 필요한 문제
```bash
# ❌ 문제: multi_deploy.sh 실행 시 "No such file or directory" 에러
# 원인: _shell/deploy.sh, _shell/rollback.sh 래퍼 스크립트 누락
# 해결책 옵션 A: 래퍼 스크립트 생성
cat > _shell/deploy.sh << 'EOF'
#!/bin/bash
exec "$(dirname "$0")/deploy/deploy.sh" "$@"
EOF
chmod +x _shell/deploy.sh

cat > _shell/rollback.sh << 'EOF'
#!/bin/bash
exec "$(dirname "$0")/rollback/rollback_main.sh" "$@"
EOF
chmod +x _shell/rollback.sh
```

### 공통 문제들
```bash
# 권한 문제 해결
chmod +x multi_deploy.sh
find _shell -name "*.sh" -exec chmod +x {} \;

# 공통 유틸리티 로딩 문제
source _shell/common_utils/common_utils_main.sh

# 함수 사용 가능 여부 확인
declare -f log_info log_warn log_success error_exit current_timestamp
```

### 디버깅 모드
```bash
# 레거시 스크립트 직접 실행하여 우회
./_shell/deploy/deploy.sh 0 test.env deploy

# 상세한 실행 로그 확인 (현재 작동 안 함)
bash -x ./multi_deploy.sh 3 test.env

# 개별 모듈 테스트
bash _shell/common_utils/common_utils_main.sh test
```

## 개발자 가이드: 시스템 복구 방법

### 빠른 복구 (래퍼 스크립트 생성)
`multi_deploy.sh`를 즉시 작동시키려면 6개의 래퍼 스크립트를 `_shell/` 디렉터리에 생성하세요:
1. `deploy.sh` → `deploy/deploy.sh` 호출
2. `rollback.sh` → `rollback/rollback_main.sh` 호출
3. `controll_nginx.sh` → `controll_nginx/nginx_control_main.sh` 호출
4. `link_jar.sh` → `link_jar/link_jar_main.sh` 호출
5. `setup_logs.sh` → `setup_logs/setup_logs_main.sh` 호출
6. `runApp.sh` → 이미 존재 (✅)

### 장기 해결책
모듈형 아키텍처로 완전 전환:
- `multi_deploy.sh`를 `_shell/multi_deploy/multi_deploy_main.sh`와 통합
- 모든 레거시 단일 스크립트(`deploy.sh`, `runApp.sh`) 제거
- 순수 함수형 호출 구조로 전환