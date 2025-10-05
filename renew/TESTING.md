# Testing Guide

Auto Deploy Shell의 테스트 가이드입니다.

## 테스트 환경

### 1. Docker 테스트 (권장)

완전한 배포 시나리오를 검증할 수 있는 Docker 기반 테스트 환경입니다.

#### 빠른 시작

```bash
# Docker Desktop 시작
cd renew/docker
./run-test.sh
```

#### 제공되는 테스트

| 테스트 | 설명 |
|--------|------|
| 배포 검증 | 3개 인스턴스 배포 전 환경 검증 |
| 초기 배포 | 3개 인스턴스 배포 및 헬스 체크 |
| 상태 확인 | 배포 상태 조회 |
| 스케일 업 | 3개 → 5개 인스턴스 증가 |
| 스케일 다운 | 5개 → 3개 인스턴스 감소 |
| 롤백 | 전체 인스턴스 이전 버전 복구 |
| Nginx 제어 | 업스트림 설정 확인 |

#### Docker 환경 구성

- **OS**: Ubuntu 22.04
- **Java**: OpenJDK 17
- **웹서버**: Nginx
- **포트**: 8080-8089 (인스턴스), 80 (Nginx)
- **사용자**: deploy (uid=1000)

자세한 내용: `docker/README.md`

### 2. 로컬 테스트 (Docker 불필요)

Docker 없이도 기본 기능을 테스트할 수 있습니다.

```bash
cd renew/docker
./local-test.sh
```

#### 테스트 내용

- ✅ Mock Spring Boot JAR 빌드
- ✅ 애플리케이션 시작 및 응답 확인
- ✅ 헬스 체크 엔드포인트 검증
- ✅ 스크립트 실행 권한 설정

## Mock 애플리케이션

테스트용으로 간단한 HTTP 서버를 JAR로 제공합니다.

### 특징

- **경량**: 순수 Java HttpServer 사용 (Spring Boot 미사용)
- **포트 설정**: `--server.port` 파라미터 지원
- **헬스 체크**: `/actuator/health` 엔드포인트 제공
- **JSON 응답**: `{"status":"UP","port":8080}` 형식

### 수동 빌드 및 실행

```bash
# JAR 빌드
cd renew/docker/test-app
./build-test-app.sh

# 실행
java -jar testapp-1.0.0.jar --server.port=8080

# 테스트
curl http://localhost:8080/actuator/health
```

## 단위 테스트

각 모듈을 개별적으로 테스트할 수 있습니다.

### Nginx 제어 테스트

```bash
# Nginx 설정 파일 준비
export UPSTREAM_CONF="/tmp/test-upstream.conf"
cat > $UPSTREAM_CONF << EOF
upstream testapp {
    server 127.0.0.1:8080;
}
EOF

# DOWN 테스트
./renew/nginx/nginx_control.sh down 8080 $UPSTREAM_CONF

# UP 테스트
./renew/nginx/nginx_control.sh up 8080 $UPSTREAM_CONF

# 상태 확인
./renew/nginx/nginx_control.sh status 8080 $UPSTREAM_CONF
```

### JAR 링크 테스트

```bash
# 테스트 환경 준비
export SERVICE_NAME="testapp"
export SERVICE_BASE_DIR="/tmp/test-service"
export JAR_TRUNK_DIR="/tmp/test-jars"

mkdir -p $SERVICE_BASE_DIR/$SERVICE_NAME/instances/0
mkdir -p $JAR_TRUNK_DIR
touch $JAR_TRUNK_DIR/app-1.0.0.jar

# 링크 생성 테스트
./renew/link_jar/link_jar_control.sh link 0 test.env app-1.0.0.jar

# 결과 확인
ls -la $SERVICE_BASE_DIR/$SERVICE_NAME/instances/0/current.jar
```

### 테스트 인스턴스 검증

```bash
# Mock 앱 시작
java -jar renew/docker/test-app/testapp-1.0.0.jar --server.port=8080 &
APP_PID=$!

# Simple 테스트
./renew/test_instance/test_instance_control.sh test 8080 test.env

# Full 테스트
export TEST_MODE=full
./renew/test_instance/test_instance_control.sh test 8080 test.env

# 정리
kill $APP_PID
```

## 통합 테스트

전체 배포 플로우를 수동으로 테스트합니다.

### 사전 준비

```bash
# 1. 테스트 환경 파일 생성
cat > test-integration.env << 'EOF'
export SERVICE_NAME="testapp"
export BASE_PORT="808"
export JAR_TRUNK_DIR="/tmp/test-jars"
export SERVICE_BASE_DIR="/tmp/test-service"
export UPSTREAM_CONF="/tmp/test-upstream.conf"
export LOG_BASE_DIR="/tmp/test-logs"
export TEST_INSTANCE_ENABLED=true
export TEST_MODE=simple
export TEST_HTTP_ENDPOINT="/actuator/health"
EOF

# 2. 디렉터리 생성
source test-integration.env
mkdir -p $JAR_TRUNK_DIR
mkdir -p $SERVICE_BASE_DIR
mkdir -p $LOG_BASE_DIR

# 3. 테스트 JAR 복사
cp renew/docker/test-app/testapp-1.0.0.jar $JAR_TRUNK_DIR/

# 4. Nginx upstream 설정 (빈 파일)
cat > $UPSTREAM_CONF << EOF
upstream testapp {
    # Auto-generated
}
EOF
```

### 배포 테스트

```bash
# 1. 검증
./renew/main.sh validate 3 test-integration.env

# 2. 배포
./renew/main.sh deploy 3 test-integration.env

# 3. 상태 확인
./renew/main.sh status test-integration.env

# 4. 헬스 체크
for port in 8080 8081 8082; do
    curl http://localhost:$port/actuator/health
done

# 5. 롤백
./renew/main.sh rollback test-integration.env
```

### 정리

```bash
# 프로세스 종료
pgrep -f "testapp-1.0.0.jar" | xargs kill 2>/dev/null

# 디렉터리 삭제
rm -rf /tmp/test-*
```

## 성능 테스트

배포 시간 및 리소스 사용량을 측정합니다.

### 배포 시간 측정

```bash
# 3개 인스턴스 배포 시간
time ./renew/main.sh deploy 3 test.env

# 10개 인스턴스 배포 시간
time ./renew/main.sh deploy 10 test.env
```

### 리소스 모니터링

```bash
# CPU 사용률
top -p $(pgrep -f "testapp" | tr '\n' ',')

# 메모리 사용량
ps aux | grep testapp | awk '{sum+=$6} END {print sum/1024 " MB"}'

# 디스크 사용량
du -sh $SERVICE_BASE_DIR/$SERVICE_NAME
```

## CI/CD 통합

### GitHub Actions 예시

```yaml
name: Auto Deploy Shell Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set up Java
        uses: actions/setup-java@v3
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Run local tests
        run: |
          cd renew/docker
          ./local-test.sh

      - name: Run Docker tests
        run: |
          cd renew/docker
          ./run-test.sh

      - name: Cleanup
        if: always()
        run: |
          cd renew/docker
          docker-compose down -v
```

## 트러블슈팅

### Docker 테스트 실패

```bash
# 로그 확인
docker-compose logs -f

# 컨테이너 재시작
docker-compose restart

# 완전 재빌드
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d
```

### 포트 충돌

```bash
# 사용 중인 포트 확인
lsof -i :8080
lsof -i :8081

# 프로세스 종료
kill $(lsof -t -i:8080)
```

### JAR 빌드 오류

```bash
# Java 버전 확인
java -version    # 1.8 이상 필요
javac -version

# 수동 빌드
cd renew/docker/test-app
javac TestApp.java
jar cfe testapp-1.0.0.jar TestApp TestApp*.class
```

## 테스트 체크리스트

배포 전 다음 사항을 확인하세요:

- [ ] 로컬 테스트 통과 (`./local-test.sh`)
- [ ] Docker 테스트 통과 (`./run-test.sh`)
- [ ] 3개 인스턴스 배포 성공
- [ ] 스케일 업/다운 동작 확인
- [ ] 롤백 정상 작동
- [ ] Nginx 업스트림 제어 확인
- [ ] 헬스 체크 통과
- [ ] 모든 스크립트 실행 권한 확인

## 참고 문서

- **Docker 테스트**: `docker/README.md`
- **시스템 아키텍처**: `ARCHITECTURE.md`
- **계층 구조**: `HIERARCHY.md`
- **사용 가이드**: `README.md`
- **요약**: `SUMMARY.md`

---

**문서 버전**: 1.0.0
**작성일**: 2025-10-04
**호환성**: Auto Deploy Shell v2.0.0
