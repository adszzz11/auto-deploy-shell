# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Auto-Deploy-Shell은 Spring Boot 애플리케이션의 다중 인스턴스 배포를 자동화하는 Bash 기반 시스템입니다. 이중 서버 환경에서 machine-id 기반으로 인스턴스를 식별하고, Nginx 로드밸런싱과 연동하여 무중단 배포를 지원합니다.

## 핵심 명령어

### 배포 관련
```bash
# 다중 인스턴스 배포 (2-10개 인스턴스)
./multi_deploy.sh <instance_count> <env_file>

# 단일 인스턴스 배포/제거
./_shell/deploy.sh <instance_number> <env_file> [deploy|remove]

# 롤백 실행
./_shell/rollback.sh <instance_number> <env_file>

# 애플리케이션 프로세스 관리
./_shell/runApp.sh <port> [stop|start|restart] [JAVA_OPTS] <common_utils_dir>

# Nginx 업스트림 제어
./_shell/controll_nginx.sh <port> <upstream_conf> <up|down>
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
- `multi_deploy.sh`: 다중 인스턴스 배포 오케스트레이션 (2-10개 인스턴스)
- `test_instance.sh`: 개별 인스턴스 헬스체크 스크립트

### 핵심 모듈 (_shell/)
- `common_utils.sh`: 공통 함수, 로깅 (`log_info`, `log_warn`, `error_exit`)
- `deploy.sh`: 단일 인스턴스 배포/제거 오케스트레이션
- `runApp.sh`: Spring Boot 애플리케이션 프로세스 관리 (포트 기반)
- `controll_nginx.sh`: Nginx 업스트림 동적 제어 (up/down)
- `rollback.sh`: JAR 백업에서 복원
- `link_jar.sh`: JAR 파일 심볼릭 링크 관리
- `setup_logs.sh`: 로그 디렉터리 구성

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
3. **스크립트 헤더**: 모든 스크립트에 `set -euo pipefail`과 `source common_utils.sh` 포함
4. **권한 검증**: 필수 스크립트 실행 권한 확인 후 진행

### 배포 버전 일관성
- 모든 인스턴스는 동일한 버전으로 배포되어야 함
- 부분 실패 시 전체 롤백으로 일관성 보장
- 포트 기반 정확한 프로세스 식별 (`pgrep -f` 패턴 사용)
- `current.jar` 심볼릭 링크로 JAR 버전 관리

### 테스트 및 헬스체크
- `TEST_SCRIPT` 환경 변수로 커스텀 테스트 스크립트 지정 가능
- `test_instance.sh`는 HTTP 상태 코드 검증 (기본: `/api/v1/global/commoncode/TX_DVCD/WDL`)
- 테스트 실패 시 Nginx 업스트림 복구 후 배포 중단

이 시스템은 안정성과 운영 편의성에 중점을 둔 엔터프라이즈 배포 솔루션으로 설계되었습니다.