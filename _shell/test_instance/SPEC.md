# Test Instance Module Specification

## 1. Overview

test_instance 모듈은 배포된 애플리케이션 인스턴스의 헬스 체크 및 검증을 담당합니다. HTTP 상태 코드, TCP 연결성, 응답 시간, 커스텀 테스트 등 다양한 검증 방법을 제공하여 배포 후 인스턴스가 정상적으로 동작하는지 확인합니다.

## 2. Module Structure

```
test_instance/
├── test_instance.env              # 테스트 설정
├── test_instance_control.sh       # 메인 CLI 스크립트
├── SPEC.md                        # 본 명세서
└── func/
    ├── validate_test_params.sh    # 파라미터 검증
    ├── test_http_status.sh        # HTTP 상태 테스트
    ├── test_tcp_connection.sh     # TCP 연결 테스트
    ├── test_response_time.sh      # 응답 시간 테스트
    └── run_custom_tests.sh        # 커스텀 테스트 실행
```

## 3. Core Functions

### 3.1 validate_test_params.sh

**책임**: 테스트 파라미터 및 설정 검증

**주요 함수**:
- `validate_test_parameters()`: 포트 및 env_file 검증
- `validate_test_mode()`: 테스트 모드 검증 (simple/full/custom)
- `validate_test_configuration()`: 전체 테스트 설정 검증
- `validate_custom_test_script()`: 커스텀 테스트 스크립트 검증
- `validate_http_endpoint()`: HTTP 엔드포인트 검증
- `validate_port_accessibility()`: 포트 접근성 사전 검증

### 3.2 test_http_status.sh

**책임**: HTTP 상태 코드 검증

**주요 함수**:
- `test_http_status_with_retry()`: 재시도 포함 HTTP 테스트
- `test_http_status_single()`: 단일 HTTP 요청 테스트
- `test_http_response_body()`: 응답 본문 패턴 검증
- `test_http_headers()`: 필수 HTTP 헤더 검증
- `test_http_full()`: 통합 HTTP 테스트 (상태 + 본문 + 헤더)

**특징**:
- curl 기반 HTTP 요청
- 설정 가능한 재시도 횟수 및 딜레이
- 응답 본문 정규식 패턴 매칭
- 필수 헤더 검증
- HTTPS 지원 (자체 서명 인증서 허용)

### 3.3 test_tcp_connection.sh

**책임**: TCP 연결 검증

**주요 함수**:
- `test_tcp_connection_with_retry()`: 재시도 포함 TCP 테스트
- `test_tcp_connection_single()`: 단일 TCP 연결 테스트
- `test_tcp_with_nc()`: netcat 기반 테스트
- `test_tcp_with_dev_tcp()`: /dev/tcp 기반 테스트
- `test_tcp_with_telnet()`: telnet 기반 테스트 (폴백)
- `test_port_listening()`: 포트 LISTEN 상태 확인
- `check_port_process()`: 포트 사용 프로세스 확인
- `test_tcp_full()`: 통합 TCP 테스트

**특징**:
- 여러 도구 지원 (nc, /dev/tcp, telnet)
- 자동 도구 선택 (가용성에 따라)
- 포트 LISTEN 상태 검증 (netstat, ss, lsof)
- 프로세스 정보 확인

### 3.4 test_response_time.sh

**책임**: 응답 시간 성능 검증

**주요 함수**:
- `test_response_time_with_retry()`: 재시도 포함 응답 시간 테스트
- `test_response_time_single()`: 단일 응답 시간 측정
- `measure_response_time_curl()`: curl 기반 시간 측정
- `measure_response_time_fallback()`: 폴백 시간 측정 (time 명령)
- `test_response_time_statistics()`: 다중 측정 통계 (min/max/avg)
- `test_response_time_benchmark()`: 부하 테스트 벤치마크 (ab, wrk)

**특징**:
- 밀리초 단위 정확도
- 설정 가능한 최대 응답 시간
- 통계 분석 (최소/최대/평균)
- 벤치마크 도구 지원 (Apache Bench, wrk)

### 3.5 run_custom_tests.sh

**책임**: 사용자 정의 테스트 실행

**주요 함수**:
- `run_custom_tests()`: 커스텀 테스트 오케스트레이션
- `run_custom_test_script()`: 단일 테스트 스크립트 실행
- `run_custom_test_directory()`: 디렉터리 내 모든 테스트 실행
- `run_inline_test()`: 인라인 명령 테스트
- `log_test_result()`: 테스트 결과 로깅
- `create_failure_report()`: 실패 리포트 생성

**특징**:
- 외부 스크립트 실행
- 디렉터리 기반 테스트 스위트
- 타임아웃 지원
- 결과 로깅
- 실패 리포트 자동 생성

## 4. CLI Commands

### 4.1 test - 모드별 테스트 실행

```bash
./test_instance_control.sh test <port> [env_file]
```

TEST_MODE 환경 변수에 따라 테스트 실행:
- `simple`: HTTP 상태 테스트만
- `full`: HTTP + TCP + Response Time + Custom
- `custom`: 커스텀 테스트만

**예시**:
```bash
# Simple 모드 (기본)
./test_instance_control.sh test 8080 app.env

# Full 모드
export TEST_MODE=full
./test_instance_control.sh test 8080 app.env

# Custom 모드
export TEST_MODE=custom
export TEST_CUSTOM_SCRIPT="./my_test.sh"
./test_instance_control.sh test 8080 app.env
```

### 4.2 http - HTTP 테스트

```bash
./test_instance_control.sh http <port> [env_file]
```

HTTP 상태 코드 검증만 수행.

**예시**:
```bash
# 기본 엔드포인트 (/actuator/health)
./test_instance_control.sh http 8080

# 커스텀 엔드포인트
export TEST_HTTP_ENDPOINT=/api/health
./test_instance_control.sh http 8080 app.env
```

### 4.3 tcp - TCP 연결 테스트

```bash
./test_instance_control.sh tcp <port> [env_file]
```

TCP 연결성 검증만 수행.

**예시**:
```bash
./test_instance_control.sh tcp 8080
```

### 4.4 response - 응답 시간 테스트

```bash
./test_instance_control.sh response <port> [env_file]
```

응답 시간 측정 및 검증.

**예시**:
```bash
# 기본 (1000ms 제한)
./test_instance_control.sh response 8080

# 커스텀 제한
export TEST_MAX_RESPONSE_TIME=500
./test_instance_control.sh response 8080 app.env
```

### 4.5 custom - 커스텀 테스트

```bash
./test_instance_control.sh custom <port> [service_name] [env_file]
```

사용자 정의 테스트 스크립트 실행.

**예시**:
```bash
export TEST_CUSTOM_SCRIPT="./tests/integration_test.sh"
./test_instance_control.sh custom 8080 myservice app.env
```

### 4.6 full - 전체 테스트

```bash
./test_instance_control.sh full <port> [service_name] [env_file]
```

모든 테스트 실행 (HTTP + TCP + Response Time + Custom).

**예시**:
```bash
./test_instance_control.sh full 8080 myservice app.env
```

### 4.7 quick - 빠른 테스트

```bash
./test_instance_control.sh quick <port>
```

재시도 및 warmup 없이 즉시 HTTP 테스트.

**예시**:
```bash
./test_instance_control.sh quick 8080
```

### 4.8 benchmark - 벤치마크

```bash
./test_instance_control.sh benchmark <port> [env_file]
```

응답 시간 벤치마크 실행 (ab 또는 wrk 사용).

**예시**:
```bash
./test_instance_control.sh benchmark 8080 app.env
```

### 4.9 validate - 검증

```bash
./test_instance_control.sh validate <port> [env_file]
```

테스트 실행 전 설정 및 환경 검증.

**예시**:
```bash
./test_instance_control.sh validate 8080 app.env
```

## 5. Environment Variables

### 5.1 Test Execution Settings

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `TEST_INSTANCE_ENABLED` | `true` | 테스트 활성화 여부 |
| `TEST_MODE` | `simple` | 테스트 모드 (simple/full/custom) |
| `TEST_RETRY_COUNT` | `3` | 재시도 횟수 |
| `TEST_RETRY_DELAY` | `5` | 재시도 간 딜레이 (초) |
| `TEST_TIMEOUT` | `30` | 전체 타임아웃 (초) |
| `TEST_WARMUP_WAIT` | `5` | 테스트 전 대기 시간 (초) |

### 5.2 HTTP Test Settings

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `TEST_HTTP_ENDPOINT` | `/actuator/health` | HTTP 엔드포인트 |
| `TEST_EXPECTED_STATUS` | `200` | 예상 HTTP 상태 코드 |
| `TEST_HTTP_METHOD` | `GET` | HTTP 메소드 |
| `TEST_USE_HTTPS` | `false` | HTTPS 사용 여부 |
| `TEST_HOST` | `localhost` | 테스트 대상 호스트 |
| `TEST_HEALTH_BODY_PATTERN` | `` | 응답 본문 정규식 패턴 |
| `TEST_REQUIRED_HEADERS` | `` | 필수 헤더 (쉼표 구분) |

### 5.3 TCP Test Settings

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `TEST_TCP_ENABLED` | `false` | TCP 테스트 활성화 |
| `TEST_TCP_TIMEOUT` | `5` | TCP 연결 타임아웃 (초) |

### 5.4 Response Time Settings

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `TEST_RESPONSE_TIME_ENABLED` | `false` | 응답 시간 테스트 활성화 |
| `TEST_MAX_RESPONSE_TIME` | `1000` | 최대 응답 시간 (밀리초) |
| `TEST_RESPONSE_TIME_ENDPOINT` | `` | 응답 시간 테스트 엔드포인트 |

### 5.5 Custom Test Settings

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `TEST_CUSTOM_SCRIPT` | `` | 커스텀 테스트 스크립트 경로 |
| `TEST_CUSTOM_TIMEOUT` | `60` | 커스텀 테스트 타임아웃 (초) |
| `TEST_CUSTOM_PASS_ENV` | `true` | env_file을 커스텀 스크립트에 전달 |

### 5.6 Reporting Settings

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `TEST_VERBOSE` | `false` | 상세 출력 |
| `TEST_SHOW_RESPONSE_ON_FAIL` | `true` | 실패 시 응답 표시 |
| `TEST_LOG_RESULTS` | `false` | 결과 로깅 활성화 |
| `TEST_LOG_DIR` | `/tmp/test_instance_logs` | 로그 디렉터리 |
| `TEST_CONTINUE_ON_FAIL` | `false` | 실패 시에도 계속 진행 |
| `TEST_CREATE_FAILURE_REPORT` | `true` | 실패 리포트 생성 |
| `TEST_FAILURE_REPORT_DIR` | `/tmp/test_failures` | 실패 리포트 디렉터리 |

## 6. Test Modes

### 6.1 Simple Mode (기본)

**용도**: 배포 후 기본 헬스 체크

**실행 테스트**:
- HTTP 상태 코드 검증

**장점**:
- 빠른 실행
- 최소한의 리소스 사용
- 배포 프로세스에 적합

**설정 예시**:
```bash
export TEST_MODE=simple
export TEST_HTTP_ENDPOINT=/actuator/health
export TEST_EXPECTED_STATUS=200
```

### 6.2 Full Mode

**용도**: 종합적인 인스턴스 검증

**실행 테스트**:
- HTTP 상태 코드 검증
- TCP 연결성 검증 (활성화 시)
- 응답 시간 검증 (활성화 시)
- 커스텀 테스트 (설정 시)

**장점**:
- 완전한 검증
- 성능 확인
- 프로덕션 준비 상태 확인

**설정 예시**:
```bash
export TEST_MODE=full
export TEST_TCP_ENABLED=true
export TEST_RESPONSE_TIME_ENABLED=true
export TEST_MAX_RESPONSE_TIME=500
```

### 6.3 Custom Mode

**용도**: 애플리케이션별 특화 테스트

**실행 테스트**:
- 사용자 정의 테스트 스크립트

**장점**:
- 완전한 유연성
- 비즈니스 로직 검증 가능
- 복잡한 시나리오 테스트

**설정 예시**:
```bash
export TEST_MODE=custom
export TEST_CUSTOM_SCRIPT=/path/to/integration_tests.sh
```

**커스텀 스크립트 인터페이스**:
```bash
#!/bin/bash
# my_custom_test.sh

PORT=$1
SERVICE_NAME=$2
ENV_FILE=$3

# 테스트 로직
# ...

# 성공: exit 0
# 실패: exit 1
```

## 7. Integration with Deploy Module

### 7.1 deploy.env 설정

```bash
# test_instance 모듈 활성화
export TEST_INSTANCE_ENABLED=true

# 테스트 설정
export TEST_MODE=simple
export TEST_HTTP_ENDPOINT=/api/health
export TEST_EXPECTED_STATUS=200
export TEST_RETRY_COUNT=5
export TEST_RETRY_DELAY=3
export TEST_WARMUP_WAIT=10
```

### 7.2 execute_deployment.sh 통합

deploy 모듈의 `execute_deployment.sh`에서 test_instance 사용:

```bash
# 5단계: 테스트 실행
if [ "${TEST_INSTANCE_ENABLED:-false}" = "true" ]; then
    local test_script="${script_dir}/../test_instance/test_instance_control.sh"

    if [ -x "$test_script" ]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running instance tests..."

        if ! "$test_script" test "$port" "$env_file"; then
            echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Instance health check failed" >&2

            # Nginx UP 복구
            control_nginx_upstream "up" "$port" "$upstream_conf" "$script_dir"

            return 1
        fi

        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Instance tests passed"
    else
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - test_instance_control.sh not found, skipping tests"
    fi
fi
```

### 7.3 배포 플로우

```
1. Nginx DOWN
2. JAR 백업
3. JAR 교체 (link_jar)
4. 애플리케이션 재시작 (run_app)
5. 테스트 실행 (test_instance) ← 여기서 검증
   ├─ 성공: Nginx UP → 배포 완료
   └─ 실패: Nginx UP (복구) → 배포 실패
6. Nginx UP
```

## 8. Usage Examples

### 8.1 기본 사용법

```bash
# 1. Simple HTTP 테스트
./test_instance_control.sh test 8080 app.env

# 2. 빠른 테스트 (재시도 없음)
./test_instance_control.sh quick 8080

# 3. 전체 테스트
./test_instance_control.sh full 8080 myservice app.env
```

### 8.2 개별 테스트

```bash
# HTTP 테스트만
./test_instance_control.sh http 8080 app.env

# TCP 테스트만
./test_instance_control.sh tcp 8080

# 응답 시간 테스트만
./test_instance_control.sh response 8080 app.env
```

### 8.3 커스텀 테스트

```bash
# 커스텀 스크립트 작성
cat > my_test.sh << 'EOF'
#!/bin/bash
PORT=$1
curl -f http://localhost:$PORT/api/custom || exit 1
EOF
chmod +x my_test.sh

# 커스텀 테스트 실행
export TEST_CUSTOM_SCRIPT=./my_test.sh
./test_instance_control.sh custom 8080
```

### 8.4 벤치마크

```bash
# Apache Bench로 벤치마크
./test_instance_control.sh benchmark 8080 app.env
```

### 8.5 고급 설정

```bash
# HTTPS + 커스텀 헤더 검증
export TEST_USE_HTTPS=true
export TEST_HTTP_ENDPOINT=/secure/health
export TEST_REQUIRED_HEADERS="X-Custom-Header:value1,Authorization:Bearer"
./test_instance_control.sh http 8443 app.env

# 응답 본문 패턴 매칭
export TEST_HEALTH_BODY_PATTERN='"status":"UP"'
./test_instance_control.sh http 8080 app.env

# 통계 분석
export TEST_RESPONSE_TIME_ENABLED=true
export TEST_MAX_RESPONSE_TIME=200
./test_instance_control.sh response 8080 app.env
```

## 9. Error Handling

### 9.1 재시도 메커니즘

모든 테스트는 `TEST_RETRY_COUNT` 만큼 재시도:

```bash
# 3회 재시도, 5초 딜레이
export TEST_RETRY_COUNT=3
export TEST_RETRY_DELAY=5
```

**재시도 로직**:
1. 첫 번째 시도
2. 실패 시 `TEST_RETRY_DELAY` 대기
3. 재시도
4. `TEST_RETRY_COUNT` 만큼 반복
5. 모두 실패 시 에러 반환

### 9.2 타임아웃 처리

각 테스트는 타임아웃 설정 가능:

```bash
export TEST_TIMEOUT=30              # HTTP/TCP 타임아웃
export TEST_CUSTOM_TIMEOUT=60       # 커스텀 테스트 타임아웃
```

타임아웃 발생 시:
- HTTP: curl의 `--max-time` 초과
- TCP: `timeout` 명령 사용
- Custom: `timeout` 명령으로 스크립트 종료

### 9.3 실패 처리 전략

**Continue on Fail**:
```bash
export TEST_CONTINUE_ON_FAIL=true
```

활성화 시 일부 테스트 실패해도 계속 진행 (full 모드에서 유용).

**Failure Report**:
```bash
export TEST_CREATE_FAILURE_REPORT=true
export TEST_FAILURE_REPORT_DIR=/var/log/test_failures
```

실패 시 상세 리포트 자동 생성:
- 타임스탬프
- 포트 및 테스트 정보
- 에러 출력
- 환경 변수
- 시스템 정보

### 9.4 에러 코드

| Exit Code | 의미 |
|-----------|------|
| 0 | 성공 |
| 1 | 일반 실패 (테스트 실패, 검증 오류 등) |
| 124 | 타임아웃 |

## 10. Best Practices

### 10.1 배포 시 권장 설정

**프로덕션 배포**:
```bash
export TEST_MODE=simple
export TEST_RETRY_COUNT=5
export TEST_RETRY_DELAY=5
export TEST_WARMUP_WAIT=15
export TEST_HTTP_ENDPOINT=/actuator/health
```

**스테이징 배포**:
```bash
export TEST_MODE=full
export TEST_TCP_ENABLED=true
export TEST_RESPONSE_TIME_ENABLED=true
export TEST_MAX_RESPONSE_TIME=1000
```

### 10.2 Warmup 시간 설정

애플리케이션 시작 시간을 고려:

```bash
# Spring Boot 애플리케이션 (일반적으로 10-30초)
export TEST_WARMUP_WAIT=15

# 대규모 애플리케이션 (30초 이상)
export TEST_WARMUP_WAIT=30
```

### 10.3 재시도 설정

네트워크 지연 및 일시적 오류 고려:

```bash
# 안정적인 환경
export TEST_RETRY_COUNT=3
export TEST_RETRY_DELAY=3

# 불안정한 환경
export TEST_RETRY_COUNT=5
export TEST_RETRY_DELAY=5
```

### 10.4 로깅 및 모니터링

```bash
# 프로덕션: 실패만 로깅
export TEST_LOG_RESULTS=true
export TEST_CREATE_FAILURE_REPORT=true
export TEST_VERBOSE=false

# 디버깅: 모든 정보 로깅
export TEST_VERBOSE=true
export TEST_SHOW_RESPONSE_ON_FAIL=true
```

## 11. Troubleshooting

### 11.1 일반적인 문제

**문제: HTTP 테스트가 계속 실패**
```bash
# 원인 확인
./test_instance_control.sh validate 8080 app.env

# 포트 접근성 확인
./test_instance_control.sh tcp 8080

# 상세 출력 활성화
export TEST_VERBOSE=true
./test_instance_control.sh http 8080 app.env
```

**문제: 타임아웃 발생**
```bash
# Warmup 시간 증가
export TEST_WARMUP_WAIT=30

# 타임아웃 증가
export TEST_TIMEOUT=60

# 재시도
./test_instance_control.sh test 8080 app.env
```

**문제: 커스텀 테스트 스크립트 실행 안됨**
```bash
# 실행 권한 확인
ls -l /path/to/test.sh

# 권한 부여
chmod +x /path/to/test.sh

# 검증
./test_instance_control.sh validate 8080 app.env
```

### 11.2 디버깅 도구

**curl을 직접 사용**:
```bash
curl -v http://localhost:8080/actuator/health
```

**TCP 연결 직접 확인**:
```bash
nc -zv localhost 8080
# 또는
telnet localhost 8080
```

**프로세스 확인**:
```bash
lsof -i :8080
netstat -an | grep 8080
```

## 12. Performance Considerations

### 12.1 테스트 속도

**Simple 모드**:
- 실행 시간: ~5-10초 (재시도 포함)
- 리소스: 최소

**Full 모드**:
- 실행 시간: ~20-40초 (모든 테스트 포함)
- 리소스: 중간

**Custom 모드**:
- 실행 시간: 스크립트에 따라 다름
- 리소스: 스크립트에 따라 다름

### 12.2 최적화

**빠른 배포를 위한 설정**:
```bash
export TEST_MODE=quick                # 재시도 없음
export TEST_WARMUP_WAIT=0             # 즉시 테스트
```

**안정성을 위한 설정**:
```bash
export TEST_MODE=full
export TEST_RETRY_COUNT=5
export TEST_WARMUP_WAIT=15
export TEST_TCP_ENABLED=true
export TEST_RESPONSE_TIME_ENABLED=true
```

## 13. Security Considerations

### 13.1 HTTPS 지원

```bash
export TEST_USE_HTTPS=true
export TEST_HTTP_ENDPOINT=/actuator/health
```

자체 서명 인증서는 `-k` 플래그로 허용됨.

### 13.2 인증

헤더 기반 인증:
```bash
export TEST_REQUIRED_HEADERS="Authorization:Bearer token123"
```

### 13.3 커스텀 테스트 보안

커스텀 스크립트는 신뢰할 수 있는 소스만 사용:
- 실행 전 스크립트 검증
- 제한된 권한으로 실행
- 타임아웃 설정 필수

## 14. Future Enhancements

### 14.1 계획된 기능

- WebSocket 연결 테스트
- gRPC 헬스 체크
- 메트릭 기반 검증 (Prometheus, Micrometer)
- 데이터베이스 연결 테스트
- 캐시 연결 테스트 (Redis 등)
- 메시지 큐 연결 테스트 (Kafka, RabbitMQ 등)

### 14.2 향후 개선 사항

- 병렬 테스트 실행
- 테스트 결과 집계 및 리포팅
- 대시보드 통합
- 알림 연동 (Slack, Email 등)

## 15. Changelog

### Version 1.0.0 (2025-10-04)

**Initial Release**:
- HTTP 상태 코드 테스트
- TCP 연결 테스트
- 응답 시간 테스트
- 커스텀 테스트 지원
- Simple/Full/Custom 모드
- 재시도 메커니즘
- 실패 리포트 생성
- deploy 모듈 통합

---

**Document Version**: 1.0
**Last Updated**: 2025-10-04
**Module Version**: 1.0.0
