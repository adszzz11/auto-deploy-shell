# Auto Deploy Shell (Renew) - v2.0

Spring Boot 애플리케이션의 다중 인스턴스 배포를 자동화하는 모듈형 배포 시스템입니다.

## Quick Start

### 1. 환경 설정 파일 준비

**사용자는 하나의 설정 파일만 관리합니다: `base.env`**

```bash
# 1. 템플릿 복사
cd renew/
cp base.env myapp.env

# 2. 설정 수정
vi myapp.env

# 필수 설정만 수정
export SERVICE_NAME="myapp"
export BASE_PORT="808"
export JAR_TRUNK_DIR="/home/deploy/jars"
export SERVICE_BASE_DIR="/home/service"
export UPSTREAM_CONF="/etc/nginx/conf.d/upstream.conf"

# 선택 설정 (필요 시)
export JAVA_OPTS="--spring.profiles.active=prod"
export TEST_MODE="simple"
```

**참고**: 각 모듈의 `.env` 파일(deploy.env, nginx.env 등)은 기본값만 제공합니다. `myapp.env`가 모든 설정을 오버라이드합니다.

### 2. 다중 인스턴스 배포

```bash
# 5개 인스턴스 배포
./main.sh deploy 5 myapp.env

# 배포 상태 확인
./main.sh status myapp.env

# 전체 롤백
./main.sh rollback myapp.env
```


## 주요 명령어

### main.sh 명령어 (권장)

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `deploy <count> <env_file>` | 다중 인스턴스 배포 (2-10개) | `./main.sh deploy 5 app.env` |
| `rollback <env_file>` | 전체 인스턴스 롤백 | `./main.sh rollback app.env` |
| `status <env_file>` | 배포 상태 확인 | `./main.sh status app.env` |
| `validate <count> <env_file>` | 배포 전 검증 | `./main.sh validate 5 app.env` |
| `version` | 버전 정보 | `./main.sh version` |
| `help` | 도움말 | `./main.sh help` |

### 고급 사용 (모듈 직접 호출)

단일 인스턴스 작업이나 세부 제어가 필요한 경우:

```bash
# 단일 인스턴스 배포
./multi_deploy/multi_deploy_control.sh deploy-single 0 app.env

# 단일 인스턴스 롤백
./multi_deploy/multi_deploy_control.sh rollback-single 0 app.env

# 인스턴스 헬스 체크
./test_instance/test_instance_control.sh test 8080 app.env

# Nginx 수동 제어
./nginx/nginx_control.sh up 8080 /etc/nginx/conf.d/upstream.conf
./nginx/nginx_control.sh down 8080 /etc/nginx/conf.d/upstream.conf
```

## 배포 플로우

```
1. 파라미터 검증
2. 환경 변수 로드
3. 각 인스턴스별 순차 배포:
   ├─ Nginx DOWN (트래픽 차단)
   ├─ JAR 백업 (current.jar → current.jar.bak)
   ├─ JAR 교체 (심볼릭 링크)
   ├─ runApp.sh 동기화
   ├─ 로그 디렉터리 설정
   ├─ 애플리케이션 재시작
   ├─ 헬스 체크 (test_instance 모듈)
   └─ Nginx UP (트래픽 복구)
4. 초과 인스턴스 제거 (스케일 다운)
5. 안정화 대기
```

## 시스템 아키텍처

### 포트 체계

```
BASE_PORT=808, INSTANCE_NUM=0 → PORT=8080
BASE_PORT=808, INSTANCE_NUM=1 → PORT=8081
BASE_PORT=808, INSTANCE_NUM=2 → PORT=8082
...
```

### 디렉터리 구조

```
${SERVICE_BASE_DIR}/
└── ${SERVICE_NAME}/
    └── instances/
        ├── 0/
        │   ├── current.jar         # 심볼릭 링크
        │   ├── current.jar.bak     # 백업
        │   ├── runApp.sh           # 프로세스 관리 스크립트
        │   ├── app.pid             # PID 파일
        │   └── logs/               # 로그 디렉터리 (심볼릭 링크)
        ├── 1/
        └── 2/
```

### 모듈 구조

```
renew/
├── main.sh                    # 메인 진입점 ★
├── README.md                  # 본 문서
│
├── multi_deploy/              # 다중 인스턴스 배포 오케스트레이션
│   ├── multi_deploy_control.sh
│   ├── multi_deploy.env
│   ├── SPEC.md
│   └── func/
│
├── deploy/                    # 단일 인스턴스 배포
│   ├── deploy_control.sh
│   ├── deploy.env
│   ├── SPEC.md
│   └── func/
│
├── rollback/                  # 인스턴스 롤백
│   ├── rollback_control.sh
│   ├── rollback.env
│   ├── SPEC.md
│   └── func/
│
├── test_instance/             # 헬스 체크 및 테스트
│   ├── test_instance_control.sh
│   ├── test_instance.env
│   ├── SPEC.md
│   └── func/
│
├── nginx/                     # Nginx 업스트림 제어
│   ├── nginx_control.sh
│   ├── nginx.env
│   ├── SPEC.md
│   └── func/
│
├── run_app/                   # 애플리케이션 프로세스 관리
│   ├── run_app_control.sh
│   ├── run_app.env
│   ├── SPEC.md
│   └── func/
│
└── link_jar/                  # JAR 심볼릭 링크 관리
    ├── link_jar_control.sh
    ├── link_jar.env
    ├── SPEC.md
    └── func/
```

## 환경 변수

### 설정 파일 관리

**중요**: 사용자는 `base.env` 파일 하나만 관리하면 됩니다.

```bash
# 1. 템플릿 복사
cp renew/base.env myapp.env

# 2. 필수 설정 수정
vi myapp.env
```

### 환경 변수 우선순위

1. **런타임 환경 변수** (최우선)
   ```bash
   TEST_MODE=full ./main.sh deploy 3 myapp.env
   ```

2. **사용자 설정 파일** (myapp.env, base.env 등)
   ```bash
   export SERVICE_NAME="myapp"
   export BASE_PORT="808"
   ```

3. **모듈 기본값** (deploy.env, nginx.env 등)
   - 사용자가 건드리지 않음
   - 기본값만 제공

### 필수 환경 변수 (base.env에서 설정)

```bash
# 서비스 정보
export SERVICE_NAME="myapp"              # 서비스 이름
export BASE_PORT="808"                   # 기본 포트 (인스턴스별로 +숫자)

# 디렉터리 설정
export JAR_TRUNK_DIR="/path/to/jars"     # JAR 파일 소스 디렉터리
export SERVICE_BASE_DIR="/path/to/service" # 서비스 루트 디렉터리

# Nginx 설정
export UPSTREAM_CONF="/etc/nginx/conf.d/upstream.conf"
```

### 선택적 환경 변수

#### Multi Deploy 설정

```bash
export MULTI_DEPLOY_MIN_INSTANCES=2           # 최소 인스턴스 (기본: 2)
export MULTI_DEPLOY_MAX_INSTANCES=10          # 최대 인스턴스 (기본: 10)
export MULTI_DEPLOY_AUTO_ROLLBACK=true        # 자동 롤백 (기본: true)
export MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS=2    # 배포 간 대기 시간 (초)
export MULTI_DEPLOY_STABILIZATION_WAIT=5      # 안정화 대기 시간 (초)
```

#### Test Instance 설정

```bash
export TEST_INSTANCE_ENABLED=true             # test_instance 모듈 활성화
export TEST_MODE=simple                       # simple, full, custom
export TEST_HTTP_ENDPOINT=/actuator/health    # HTTP 엔드포인트
export TEST_EXPECTED_STATUS=200               # 예상 HTTP 상태
export TEST_RETRY_COUNT=5                     # 재시도 횟수
export TEST_RETRY_DELAY=3                     # 재시도 간 딜레이 (초)
export TEST_WARMUP_WAIT=10                    # 애플리케이션 Warmup 시간 (초)
```

#### Nginx 제어 설정

```bash
export DEPLOY_NGINX_CONTROL=true              # Nginx 제어 활성화
export DEPLOY_NGINX_DOWN_ON_ERROR=true        # 에러 시 Nginx DOWN
```

#### Rollback 설정

```bash
export ROLLBACK_VERIFY_BACKUP=true            # 백업 검증
export ROLLBACK_RESTART_APP=true              # 앱 재시작
export ROLLBACK_NGINX_UP_AFTER=true           # 롤백 후 Nginx UP
```

## 사용 예시

### 시나리오 1: 신규 배포

```bash
# 1. 환경 파일 확인
cat app.env

# 2. 배포 전 검증
./main.sh validate 3 app.env

# 3. 3개 인스턴스 배포
./main.sh deploy 3 app.env

# 4. 배포 상태 확인
./main.sh status app.env

# 5. 각 인스턴스 헬스 체크 (고급 - 모듈 직접 사용)
./test_instance/test_instance_control.sh test 8080 app.env
./test_instance/test_instance_control.sh test 8081 app.env
./test_instance/test_instance_control.sh test 8082 app.env
```

### 시나리오 2: 스케일 업 (3개 → 5개)

```bash
# 기존 3개에서 5개로 증가
./main.sh deploy 5 app.env

# 새로 추가된 인스턴스 테스트 (고급 - 모듈 직접 사용)
./test_instance/test_instance_control.sh test 8083 app.env
./test_instance/test_instance_control.sh test 8084 app.env
```

### 시나리오 3: 스케일 다운 (5개 → 3개)

```bash
# 5개에서 3개로 감소 (4, 5번 인스턴스 자동 제거)
./main.sh deploy 3 app.env
```

### 시나리오 4: 롤백

```bash
# 전체 인스턴스 롤백
./main.sh rollback app.env

# 특정 인스턴스만 롤백 (고급 - 모듈 직접 사용)
./multi_deploy/multi_deploy_control.sh rollback-single 2 app.env
```

### 시나리오 5: 부분 배포 실패 후 복구

```bash
# 배포 중 인스턴스 2가 실패했다고 가정

# 1. 상태 확인
./main.sh status app.env

# 2. 실패한 인스턴스만 재배포 (고급 - 모듈 직접 사용)
./multi_deploy/multi_deploy_control.sh deploy-single 2 app.env

# 3. 테스트
./test_instance/test_instance_control.sh test 8082 app.env
```

### 시나리오 6: 커스텀 테스트 사용

```bash
# 1. 커스텀 테스트 스크립트 작성
cat > my_integration_test.sh << 'EOF'
#!/bin/bash
PORT=$1
curl -f http://localhost:$PORT/api/v1/health || exit 1
curl -f http://localhost:$PORT/api/v1/status || exit 1
EOF
chmod +x my_integration_test.sh

# 2. 환경 변수 설정
export TEST_MODE=custom
export TEST_CUSTOM_SCRIPT=./my_integration_test.sh

# 3. 배포 (커스텀 테스트 포함)
./main.sh deploy 3 app.env
```

## 트러블슈팅

### 배포 실패 시

```bash
# 1. 상세 로그 확인
./main.sh status app.env

# 2. 특정 인스턴스 테스트 (고급 - 모듈 직접 사용)
./test_instance/test_instance_control.sh test 8080 app.env

# 3. Nginx 상태 확인
sudo nginx -t
sudo systemctl status nginx

# 4. 애플리케이션 로그 확인
tail -f ${LOG_BASE_DIR}/${SERVICE_NAME}/instances/0/application.log
```

### 롤백 실패 시

```bash
# 1. 백업 파일 확인
ls -la ${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/*/current.jar.bak

# 2. 수동 롤백
cd ${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/0
mv current.jar.bak current.jar
./runApp.sh restart 8080

# 3. Nginx 수동 복구 (고급 - 모듈 직접 사용)
./nginx/nginx_control.sh up 8080 /etc/nginx/conf.d/upstream.conf
```

### 테스트 타임아웃

```bash
# Warmup 시간 증가
export TEST_WARMUP_WAIT=30
export TEST_RETRY_COUNT=10
export TEST_RETRY_DELAY=5

./main.sh deploy 3 app.env
```

## 모범 사례

### 1. 배포 전 체크리스트

- [ ] JAR 파일이 `JAR_TRUNK_DIR`에 존재
- [ ] 환경 변수 파일 검증 완료
- [ ] Nginx 설정 파일 존재 및 권한 확인
- [ ] 디스크 공간 충분 (최소 2GB)
- [ ] 네트워크 연결 정상

### 2. 프로덕션 배포 권장 설정

```bash
# 안전한 배포
export MULTI_DEPLOY_AUTO_ROLLBACK=true
export MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS=5
export MULTI_DEPLOY_STABILIZATION_WAIT=10

# 철저한 테스트
export TEST_INSTANCE_ENABLED=true
export TEST_MODE=simple
export TEST_RETRY_COUNT=5
export TEST_WARMUP_WAIT=15
```

### 3. 스테이징 배포 권장 설정

```bash
# 빠른 배포
export MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS=2
export MULTI_DEPLOY_STABILIZATION_WAIT=5

# 완전한 테스트
export TEST_MODE=full
export TEST_TCP_ENABLED=true
export TEST_RESPONSE_TIME_ENABLED=true
```

### 4. 롤백 전략

- 배포 실패 시 자동 롤백: `MULTI_DEPLOY_AUTO_ROLLBACK=true`
- 수동 롤백이 필요한 경우: `./main.sh rollback app.env`
- 부분 롤백: `./main.sh rollback-single <instance> app.env`

## 성능 고려사항

### 배포 시간

- **Simple 모드**: ~10-20초/인스턴스
- **Full 모드**: ~30-60초/인스턴스

### 리소스 사용

- **메모리**: 인스턴스당 ~512MB-2GB (애플리케이션 크기에 따라)
- **디스크**: JAR 백업 포함 인스턴스당 ~200MB-1GB

## 보안 고려사항

### 1. 파일 권한

```bash
# 스크립트 실행 권한
chmod +x renew/main.sh
chmod +x renew/*/\*_control.sh

# 환경 파일 보호
chmod 600 app.env
```

### 2. Nginx 설정 접근

```bash
# Nginx 설정 파일 권한
sudo chown root:deploy /etc/nginx/conf.d/upstream.conf
sudo chmod 664 /etc/nginx/conf.d/upstream.conf

# sudoers 설정 (필요 시)
echo "deploy ALL=(ALL) NOPASSWD: /usr/sbin/nginx -s reload" | sudo tee /etc/sudoers.d/nginx-reload
```

## FAQ

**Q: 인스턴스 개수를 동적으로 변경할 수 있나요?**
A: 네, `./main.sh deploy <새로운_개수> app.env`로 자동으로 스케일 업/다운됩니다.

**Q: 배포 중 실패하면 어떻게 되나요?**
A: `MULTI_DEPLOY_AUTO_ROLLBACK=true`인 경우 자동으로 성공한 인스턴스들도 롤백됩니다.

**Q: 특정 인스턴스만 재배포할 수 있나요?**
A: 네, 고급 사용법으로 `./multi_deploy/multi_deploy_control.sh deploy-single <instance_num> app.env`를 사용하세요.

**Q: 무중단 배포가 보장되나요?**
A: 네, Nginx 업스트림 제어로 각 인스턴스 배포 시 트래픽을 차단합니다.

**Q: JAR 파일은 어디에 있어야 하나요?**
A: `JAR_TRUNK_DIR`에 `app.pid` 파일에 명시된 JAR 파일이 있어야 합니다.

## Docker 테스트

Docker를 이용한 완전한 테스트 환경이 제공됩니다.

### 빠른 테스트 (Docker 불필요)

```bash
cd renew/docker
./local-test.sh
```

**테스트 내용**:
- Mock Spring Boot JAR 빌드 및 실행
- 헬스 체크 엔드포인트 검증
- 스크립트 권한 설정

### 전체 배포 테스트 (Docker 필요)

```bash
# Docker Desktop 시작 후
cd renew/docker
./run-test.sh
```

**테스트 시나리오**:
1. ✅ 3개 인스턴스 배포
2. ✅ 배포 상태 확인
3. ✅ 헬스 체크 검증
4. ✅ 5개로 스케일 업
5. ✅ 3개로 스케일 다운
6. ✅ 전체 롤백

자세한 내용은 `docker/README.md` 참조

## 버전 정보

**Current Version**: 2.0.0

### 주요 변경사항 (v2.0)

- 모듈형 아키텍처로 전환
- `main.sh` 단일 진입점 추가
- `test_instance` 모듈 추가 (헬스 체크)
- 각 모듈별 독립적인 `.env` 설정
- 상세한 `SPEC.md` 문서화
- 함수 기반 구조로 재사용성 향상
- Docker 테스트 환경 제공

## 지원

- **문서**: 각 모듈의 `SPEC.md` 참조
- **이슈**: GitHub Issues
- **라이센스**: MIT

---

**마지막 업데이트**: 2025-10-04
**작성자**: Auto Deploy Shell Team
