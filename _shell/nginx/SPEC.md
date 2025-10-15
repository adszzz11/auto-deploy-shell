# Nginx Control Functions Specification

## 개요

Spring Boot 다중 인스턴스 배포 시스템에서 Nginx 업스트림을 동적으로 제어하기 위한 기능 명세서입니다.

## 1. 서버 상태 제어

### set_server_up(port, config)
**목적**: 업스트림에서 서버를 활성화 (주석 제거 또는 신규 추가)

**동작**:
- 포트가 설정 파일에 존재하면: 주석 제거 (`# server 127.0.0.1:8080;` → `server 127.0.0.1:8080;`)
- 포트가 설정 파일에 없으면: 새 서버 라인 추가

**구현 예시**:
```bash
# 기존 주석 제거
sed -i "/^[[:space:]]*#[[:space:]]*server.*:$port/ s/^# //" "$upstream_conf"

# 새 서버 추가 (upstream 블록 } 앞에)
sed -i "/^[[:space:]]*}/ i\    server 127.0.0.1:$port;" "$upstream_conf"
```

### set_server_down(port, config)
**목적**: 업스트림에서 서버를 비활성화 (주석 처리)

**동작**:
- 해당 포트의 server 라인 앞에 `#` 추가
- 이미 주석 처리된 경우 무시

**구현 예시**:
```bash
sed -i "/^[[:space:]]*server.*:$port/ s/^/# /" "$upstream_conf"
```

### add_new_server(port, config)
**목적**: 완전히 새로운 서버를 업스트림에 추가

**동작**:
- upstream 블록의 마지막 `}` 앞에 새 서버 라인 삽입
- 기본적으로 활성 상태로 추가

## 2. 설정 검증

### test_nginx_config()
**목적**: Nginx 설정 파일의 문법 검증

**동작**:
```bash
nginx -t
```

**에러 처리**: 검증 실패 시 배포 중단 및 이전 상태로 롤백

### validate_upstream_format(config)
**목적**: upstream.conf 파일의 형식이 올바른지 검증

**검증 항목**:
- `upstream` 블록이 존재하는가?
- 중괄호 `{ }` 짝이 맞는가?
- server 지시자 형식이 올바른가? (`server IP:PORT;`)

### check_port_exists(port, config)
**목적**: 특정 포트가 설정 파일에 이미 존재하는지 확인

**구현 예시**:
```bash
grep -q "server.*:$port" "$upstream_conf"
```

## 3. Nginx 프로세스 관리

### reload_nginx()
**목적**: Nginx 설정을 재로드하여 변경사항 적용

**동작**:
```bash
nginx -s reload
```

**에러 처리**: reload 실패 시 error_exit 호출

### is_nginx_running()
**목적**: Nginx 프로세스가 실행 중인지 확인

**구현 예시**:
```bash
command -v nginx &>/dev/null || error_exit "nginx command not found"
pgrep nginx >/dev/null 2>&1
```

### backup_config(config)
**목적**: 설정 파일 변경 전 백업 생성

**동작**:
```bash
cp "$upstream_conf" "$upstream_conf.bak.$(date +%Y%m%d_%H%M%S)"
```

## 4. 업스트림 조회

### list_active_servers(config)
**목적**: 현재 활성화된 서버 목록 출력

**구현 예시**:
```bash
grep "^[[:space:]]*server" "$upstream_conf" | grep -v "^#"
```

### list_inactive_servers(config)
**목적**: 비활성화된 (주석 처리된) 서버 목록 출력

**구현 예시**:
```bash
grep "^[[:space:]]*#[[:space:]]*server" "$upstream_conf"
```

### get_server_status(port, config)
**목적**: 특정 포트의 현재 상태 조회 (active/inactive/not_found)

**반환값**:
- `active`: 주석 없이 존재
- `inactive`: 주석 처리됨
- `not_found`: 설정에 없음

## 5. 예제 upstream.conf 형식

```nginx
upstream backend {
    server 127.0.0.1:8080;
    server 127.0.0.1:8081;
    # server 127.0.0.1:8082;  # DOWN 상태 (배포 중)
    server 127.0.0.1:8083;
}
```

## 6. 배포 워크플로우에서의 사용

### 무중단 배포 시나리오
```bash
# 1. 트래픽 차단
set_server_down 8080 /etc/nginx/conf.d/upstream.conf
test_nginx_config
reload_nginx

# 2. 애플리케이션 배포
deploy_application 8080

# 3. 헬스체크
test_instance 8080

# 4. 트래픽 복구
set_server_up 8080 /etc/nginx/conf.d/upstream.conf
test_nginx_config
reload_nginx
```

### 스케일링 시나리오
```bash
# 스케일 아웃: 새 인스턴스 추가
add_new_server 8084 /etc/nginx/conf.d/upstream.conf
test_nginx_config
reload_nginx

# 스케일 인: 인스턴스 제거
set_server_down 8084 /etc/nginx/conf.d/upstream.conf
test_nginx_config
reload_nginx
```

## 7. 구현 참고

### 기존 구현 위치
`_shell/controll_nginx/` 모듈에 완성된 구현 존재:

```
_shell/controll_nginx/
├── nginx_control_main.sh       # 메인 진입점
├── set_server_up.sh            # UP 설정 구현
├── set_server_down.sh          # DOWN 설정 구현
├── test_nginx_config.sh        # 설정 검증
├── reload_nginx.sh             # 리로드 실행
├── validate_nginx_env.sh       # 환경 검증
└── validate_parameters.sh      # 파라미터 검증
```

### 사용 예시
```bash
# 직접 호출
./_shell/controll_nginx/nginx_control_main.sh 8080 /etc/nginx/conf.d/upstream.conf down

# 함수로 사용 (source 후)
source _shell/controll_nginx/nginx_control_main.sh
nginx_control_main 8080 /etc/nginx/conf.d/upstream.conf up
```

## 8. 에러 처리 전략

### 설정 변경 실패 시
1. 변경 사항 롤백 (백업에서 복원)
2. Nginx 재검증
3. 원래 상태로 리로드
4. error_exit 호출하여 배포 중단

### Nginx 리로드 실패 시
1. 설정 파일 롤백
2. 이전 설정으로 재시도
3. 실패 로그 기록
4. 배포 프로세스 중단

## 9. 보안 고려사항

### 권한 요구사항
- Nginx 설정 파일 쓰기 권한 필요
- `nginx -t`, `nginx -s reload` 실행 권한 필요 (일반적으로 sudo 필요)

### 설정 파일 보호
- 변경 전 항상 백업 생성
- 원자적 작업 보장 (sed -i 사용 시 주의)
- 검증 실패 시 즉시 롤백

## 10. 테스트 시나리오

### 단위 테스트
```bash
# 1. 서버 DOWN 테스트
./set_server_down.sh 8080 /tmp/test-upstream.conf
grep -q "^#.*server.*:8080" /tmp/test-upstream.conf && echo "PASS" || echo "FAIL"

# 2. 서버 UP 테스트
./set_server_up.sh 8080 /tmp/test-upstream.conf
grep -q "^[[:space:]]*server.*:8080" /tmp/test-upstream.conf && echo "PASS" || echo "FAIL"
```

### 통합 테스트
```bash
# 전체 워크플로우 테스트 (테스트 환경)
export UPSTREAM_CONF="/tmp/test-nginx.conf"
./multi_deploy.sh 3 test.env
```
