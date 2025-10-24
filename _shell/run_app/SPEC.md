# Run App Control Functions Specification

## 개요

Spring Boot 애플리케이션의 프로세스를 관리하는 Bash 기반 제어 시스템입니다. 포트 기반으로 프로세스를 식별하고, Graceful Shutdown을 지원하며, 헬스체크 기능을 제공합니다.

## 1. 프로세스 관리

### start_application(port, java_opts, jar_name, mode)
**목적**: 애플리케이션 시작

**파라미터**:
- `port`: 애플리케이션 포트 (필수)
- `java_opts`: Java 옵션 (선택, 기본값: run_app.env의 APP_JAVA_OPTS)
- `jar_name`: JAR 파일명 (선택, 기본값: current.jar)
- `mode`: 시작 모드 - `normal` 또는 `health` (선택, 기본값: normal)

**동작**:
1. 이미 실행 중인 프로세스 확인
2. JAR 파일 존재 확인
3. 로그 디렉터리 생성
4. nohup으로 백그라운드 실행
5. 프로세스 시작 확인
6. (health 모드) 헬스체크 수행

**구현 예시**:
```bash
# 기본 시작
start_application 8080

# Java 옵션 지정
start_application 8080 "--spring.profiles.active=prod"

# 헬스체크와 함께 시작
start_application 8080 "--spring.profiles.active=prod" "current.jar" "health"
```

### stop_application(port, jar_name, mode, sigterm_timeout, sigkill_timeout)
**목적**: 애플리케이션 중지 (Graceful Shutdown)

**파라미터**:
- `port`: 애플리케이션 포트 (필수)
- `jar_name`: JAR 파일명 (선택)
- `mode`: 중지 모드 - `graceful` 또는 `force` (선택, 기본값: graceful)
- `sigterm_timeout`: SIGTERM 대기 시간 (초, 기본값: 10)
- `sigkill_timeout`: SIGKILL 대기 시간 (초, 기본값: 5)

**동작 (graceful 모드)**:
1. 프로세스 검색 (pgrep 사용)
2. SIGTERM(15) 전송
3. 최대 10초 대기
4. 종료되지 않으면 SIGKILL(9) 전송
5. 최대 5초 대기
6. 종료 확인

**동작 (force 모드)**:
1. 프로세스 검색
2. 즉시 SIGKILL(9) 전송
3. 종료 확인

**구현 예시**:
```bash
# Graceful shutdown
stop_application 8080

# 강제 종료
stop_application 8080 "current.jar" "force"

# 타임아웃 커스터마이징
stop_application 8080 "current.jar" "graceful" 20 10
```

### restart_application(port, java_opts, jar_name, mode)
**목적**: 애플리케이션 재시작

**파라미터**:
- `port`: 애플리케이션 포트 (필수)
- `java_opts`: Java 옵션 (선택)
- `jar_name`: JAR 파일명 (선택)
- `mode`: 재시작 모드 - `normal` 또는 `health` (선택, 기본값: normal)

**동작**:
1. stop_application 호출
2. start_application 호출
3. (health 모드) 헬스체크 수행

**구현 예시**:
```bash
# 기본 재시작
restart_application 8080

# 헬스체크와 함께 재시작
restart_application 8080 "--spring.profiles.active=prod" "current.jar" "health"
```

## 2. 프로세스 검색

### find_app_process(port, jar_name)
**목적**: 포트 기반으로 프로세스 PID 찾기

**검색 패턴**:
```bash
pgrep -f "java -jar <jar_name> --server.port=<port>"
```

**반환값**:
- 성공: PID 출력 및 exit 0
- 실패: exit 1

### check_app_running(port, jar_name)
**목적**: 애플리케이션 실행 여부 확인

**반환값**:
- `running`: 프로세스 실행 중
- `stopped`: 프로세스 중지됨

### get_app_process_info(port, jar_name)
**목적**: 프로세스 상세 정보 출력

**출력 정보**:
- PID
- 실행 명령어
- 메모리 사용량 (KB)
- CPU 사용률 (%)

## 3. 명령어 구성

### build_exec_command(port, java_opts, jar_name)
**목적**: Java 실행 명령어 구성

**구성 형식**:
```bash
java -jar <jar_name> --server.port=<port> <java_opts>
```

### verify_jar_file(jar_name)
**목적**: JAR 파일 존재 확인

**동작**:
- JAR 파일이 없으면 에러 반환
- 있으면 로그 출력 및 성공 반환

### prepare_log_directory(log_dir)
**목적**: 로그 디렉터리 생성

**동작**:
- 디렉터리가 없으면 생성
- 생성된 경로 반환

## 4. 환경 설정 (run_app.env)

```bash
# JAR 파일명
export APP_JAR_NAME="current.jar"

# Java 실행 파일 경로 (기본값: java)
# 여러 Java 버전 사용 예시:
#   - Java 8:  export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-8-openjdk/bin/java"
#   - Java 11: export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-11-openjdk/bin/java"
#   - Java 17: export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-17-openjdk/bin/java"
#   - Java 21: export APP_JAVA_EXECUTABLE="/usr/lib/jvm/java-21-openjdk/bin/java"
#   - 기본값:  export APP_JAVA_EXECUTABLE="java"
export APP_JAVA_EXECUTABLE="java"

# 기본 Java 옵션
export APP_JAVA_OPTS="--spring.profiles.active=prod"

# 프로세스 종료 타임아웃 (초)
export APP_SIGTERM_TIMEOUT="10"
export APP_SIGKILL_TIMEOUT="5"

# 프로세스 시작 대기 시간 (초)
export APP_START_WAIT="2"

# 로그 디렉터리
export APP_LOG_DIR="./logs"

# 헬스체크 설정
export APP_HEALTH_CHECK_ENABLED="false"
export APP_HEALTH_CHECK_URL="http://localhost"
export APP_HEALTH_CHECK_PATH="/actuator/health"
export APP_HEALTH_CHECK_TIMEOUT="30"
export APP_HEALTH_CHECK_INTERVAL="2"
```

## 5. 배포 워크플로우에서의 사용

### 무중단 배포 시나리오
```bash
# 1. Nginx 트래픽 차단
./nginx_control.sh down 8080

# 2. 애플리케이션 중지
./run_app_control.sh stop 8080

# 3. JAR 파일 교체
ln -sf new-app.jar current.jar

# 4. 애플리케이션 시작 (헬스체크)
./run_app_control.sh start 8080 '--spring.profiles.active=prod' current.jar health

# 5. Nginx 트래픽 복구
./nginx_control.sh up 8080
```

### 롤백 시나리오
```bash
# 1. 애플리케이션 중지
./run_app_control.sh stop 8080

# 2. JAR 파일 복원
ln -sf current.jar.bak current.jar

# 3. 애플리케이션 재시작
./run_app_control.sh restart 8080
```

## 6. CLI 사용법

### run_app_control.sh - 메인 진입점

```bash
# 시작
./run_app_control.sh start 8080
./run_app_control.sh start 8080 '--spring.profiles.active=dev'
./run_app_control.sh start 8080 '--spring.profiles.active=prod' app.jar health

# 중지
./run_app_control.sh stop 8080
./run_app_control.sh stop 8080 current.jar force

# 재시작
./run_app_control.sh restart 8080
./run_app_control.sh restart 8080 '--spring.profiles.active=prod' current.jar health

# 상태 확인
./run_app_control.sh status 8080
./run_app_control.sh info 8080
./run_app_control.sh find 8080
```

## 7. 헬스체크 기능

### 설정
```bash
# run_app.env에서 활성화
export APP_HEALTH_CHECK_ENABLED="true"
export APP_HEALTH_CHECK_URL="http://localhost"
export APP_HEALTH_CHECK_PATH="/actuator/health"
export APP_HEALTH_CHECK_TIMEOUT="30"
export APP_HEALTH_CHECK_INTERVAL="2"
```

### 동작
1. 애플리케이션 시작 후 대기
2. 지정된 간격(INTERVAL)으로 헬스체크 URL 호출
3. 최대 타임아웃(TIMEOUT) 내에 성공 응답 확인
4. 실패 시 에러 반환

### 사용 예시
```bash
# 헬스체크와 함께 시작
./run_app_control.sh start 8080 '--spring.profiles.active=prod' current.jar health

# 헬스체크와 함께 재시작
./run_app_control.sh restart 8080 '--spring.profiles.active=prod' current.jar health
```

## 8. 로그 관리

### 로그 파일 위치
- 기본 디렉터리: `./logs` (run_app.env의 APP_LOG_DIR로 설정)
- 파일명 형식: `app-<port>.log`
- 예시: `logs/app-8080.log`

### 콘솔 로그 제어
애플리케이션 콘솔 출력(stdout/stderr)을 로그 파일에 저장할지 여부를 설정할 수 있습니다.

**환경 변수**:
```bash
# base.env 또는 myapp.env에서 설정
export APP_CONSOLE_LOG_ENABLED="true"   # 로그 파일에 출력 (기본값)
export APP_CONSOLE_LOG_ENABLED="false"  # /dev/null로 버림 (로그 저장 안함)
```

**동작**:
- `true`: 콘솔 출력을 `${log_dir}/app-${port}.log` 파일에 저장
- `false`: 콘솔 출력을 `/dev/null`로 리다이렉트 (디스크 공간 절약)

**사용 사례**:
- 프로덕션 환경에서 별도 로깅 시스템 사용 시 (예: ELK Stack, Logback 파일 로거)
- 디스크 I/O 최소화가 필요한 경우
- 애플리케이션 자체에서 로그 파일을 관리하는 경우

### nohup 출력
- 표준 출력(stdout)과 표준 에러(stderr)를 로그 파일 또는 /dev/null로 리다이렉트
- 백그라운드 실행 시 터미널 독립적으로 작동

## 9. 에러 처리

### 시작 실패
1. 이미 실행 중: WARN 로그 출력, 정상 종료 (exit 0)
2. JAR 파일 없음: ERROR 로그 출력, 비정상 종료 (exit 1)
3. 프로세스 시작 실패: ERROR 로그 출력, 비정상 종료 (exit 1)

### 중지 실패
1. 프로세스 없음: INFO 로그 출력, 정상 종료 (exit 0)
2. SIGKILL 후에도 종료 안됨: ERROR 로그 출력, 비정상 종료 (exit 1)

### 헬스체크 실패
1. 타임아웃 초과: ERROR 로그 출력, 비정상 종료 (exit 1)
2. 애플리케이션은 실행 중이나 헬스체크 실패 상태

## 10. 파일 구조

```
renew/run_app/
├── run_app.env              # 환경 변수 설정
├── run_app_control.sh       # 메인 CLI 스크립트
├── SPEC.md                  # 명세 문서
└── func/                    # 함수 스크립트들
    ├── find_app_process.sh      # 프로세스 검색
    ├── build_exec_command.sh    # 명령어 구성
    ├── start_application.sh     # 시작
    ├── stop_application.sh      # 중지
    └── restart_application.sh   # 재시작
```

## 11. 기존 시스템과의 차이점

### pre/runApp.sh (레거시)
- common_utils_dir 파라미터 필요
- 하드코딩된 타임아웃 값
- 헬스체크 미지원
- 로그 파일 없음 (nohup만 /dev/null로)

### renew/run_app (신규)
- 환경 변수 기반 설정 (run_app.env)
- 선택적 파라미터 지원
- 헬스체크 내장
- 구조화된 로그 관리
- 모듈형 함수 구조
- 상세한 프로세스 정보 제공

## 12. 테스트 시나리오

### 단위 테스트
```bash
# 1. 시작 테스트
./run_app_control.sh start 8080
./run_app_control.sh status 8080  # 결과: running

# 2. 중지 테스트
./run_app_control.sh stop 8080
./run_app_control.sh status 8080  # 결과: stopped

# 3. 재시작 테스트
./run_app_control.sh restart 8080
./run_app_control.sh status 8080  # 결과: running
```

### 통합 테스트
```bash
# 전체 워크플로우 테스트
export APP_JAR_NAME="test-app.jar"
export APP_JAVA_OPTS="--spring.profiles.active=test"

./run_app_control.sh start 8080
./run_app_control.sh info 8080
./run_app_control.sh stop 8080
```
