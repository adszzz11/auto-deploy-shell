# Auto Deploy Shell - Summary

## 시스템 개요

**버전**: 2.0.0
**목적**: Spring Boot 애플리케이션의 다중 인스턴스 무중단 배포 자동화
**아키텍처**: 4계층 모듈형 구조

---

## Quick Start (30초 안에)

```bash
# 1. 환경 파일 작성 (base.env 템플릿 사용)
cd renew/
cp base.env myapp.env
vi myapp.env  # SERVICE_NAME, BASE_PORT 등 필수 설정만 수정

# 2. 배포 실행
./main.sh deploy 3 myapp.env

# 3. 상태 확인
./main.sh status myapp.env
```

**핵심**: 사용자는 `base.env`를 복사한 하나의 파일만 관리합니다.

---

## 계층 구조 (한눈에 보기)

```
┌─────────────────────────────────────┐
│ Layer 1: User Interface             │
│  main.sh                             │
│  - 4개 명령어만 제공                  │
│  - multi_deploy만 호출               │
└──────────────┬──────────────────────┘
               │
               v
┌─────────────────────────────────────┐
│ Layer 2: Orchestration              │
│  multi_deploy                        │
│  - 다중 인스턴스 오케스트레이션        │
│  - deploy, rollback 호출             │
└────────┬────────────┬────────────────┘
         │            │
         v            v
┌────────────┐  ┌────────────┐
│ Layer 3    │  │ Layer 3    │
│  deploy    │  │  rollback  │
│  12단계    │  │  10단계    │
└─────┬──────┘  └──────┬─────┘
      │                │
      └────────┬───────┘
               │
               v
┌─────────────────────────────────────┐
│ Layer 4: Support Services           │
│  nginx | link_jar | run_app | test  │
└─────────────────────────────────────┘
```

---

## 4개 명령어 (외우기)

| 명령어 | 용도 | 예시 |
|--------|------|------|
| `deploy` | 배포 | `./main.sh deploy 5 app.env` |
| `status` | 상태 | `./main.sh status app.env` |
| `rollback` | 롤백 | `./main.sh rollback app.env` |
| `validate` | 검증 | `./main.sh validate 5 app.env` |

**추가**: `version`, `help`

---

## 핵심 특징

### 1. 무중단 배포
- Nginx 업스트림 제어로 트래픽 차단/복구
- 인스턴스별 순차 배포
- 헬스 체크 통과 후 트래픽 복구

### 2. 자동 롤백
- 배포 실패 시 모든 인스턴스 자동 롤백
- 버전 일관성 보장
- `current.jar.bak` 백업 파일 사용

### 3. 스케일링
- 스케일 업: `./main.sh deploy 5` (3개 → 5개)
- 스케일 다운: `./main.sh deploy 3` (5개 → 3개)
- 자동으로 인스턴스 추가/제거

### 4. 계층 분리
- 사용자는 `main.sh`만 사용
- 내부 모듈은 자동으로 호출됨
- 계층 우회 금지로 안정성 보장

---

## 배포 프로세스 (12단계)

```
1. 파라미터 검증
2. 환경 변수 로드
3. 필수 변수 확인
4. 환경 준비 (디렉터리 생성)
5. Nginx DOWN (트래픽 차단)
6. JAR 백업 (current.jar → current.jar.bak)
7. JAR 교체 (심볼릭 링크)
8. runApp.sh 동기화
9. 로그 설정
10. 애플리케이션 재시작
11. 헬스 체크 (test_instance)
12. Nginx UP (트래픽 복구)
```

**실패 시**: 각 단계 실패 시 Nginx UP으로 복구 → 상위로 에러 전파

---

## 디렉터리 구조

```
renew/
├── main.sh                    # ★ 사용자 진입점
├── README.md                  # 사용 가이드
├── ARCHITECTURE.md            # 아키텍처 상세
├── HIERARCHY.md               # 계층 구조
├── SUMMARY.md                 # 본 문서
│
├── multi_deploy/              # Layer 2
│   ├── multi_deploy_control.sh
│   ├── multi_deploy.env
│   ├── SPEC.md
│   └── func/
│
├── deploy/                    # Layer 3
│   ├── deploy_control.sh
│   ├── deploy.env
│   ├── SPEC.md
│   └── func/
│
├── rollback/                  # Layer 3
│   ├── rollback_control.sh
│   ├── rollback.env
│   ├── SPEC.md
│   └── func/
│
├── test_instance/             # Layer 4
├── nginx/                     # Layer 4
├── link_jar/                  # Layer 4
└── run_app/                   # Layer 4
```

---

## 환경 변수

### 단일 설정 파일 관리

**사용자는 `base.env` 하나만 관리합니다.**

```bash
# 1. 템플릿 복사
cp renew/base.env myapp.env

# 2. 필수 설정 수정
vi myapp.env
```

### 필수 환경 변수 (myapp.env에 설정)

```bash
# 서비스 정보
export SERVICE_NAME="myapp"
export BASE_PORT="808"

# 디렉터리
export JAR_TRUNK_DIR="/home/deploy/jars"
export SERVICE_BASE_DIR="/home/service"

# Nginx
export UPSTREAM_CONF="/etc/nginx/conf.d/upstream.conf"
```

### 환경 변수 우선순위

1. **런타임 환경 변수** (최우선) - `TEST_MODE=full ./main.sh deploy 3 myapp.env`
2. **사용자 설정 파일** (myapp.env) - 사용자가 관리하는 유일한 파일
3. **모듈 기본값** (deploy.env, nginx.env 등) - 사용자가 건드리지 않음

자세한 내용은 `ENV_LOADING.md` 참조

---

## 포트 체계

```
BASE_PORT=808

Instance 0 → Port 8080
Instance 1 → Port 8081
Instance 2 → Port 8082
...
Instance 9 → Port 8089

최대 10개 인스턴스 (0-9)
```

---

## 사용 시나리오

### 시나리오 1: 최초 배포

```bash
# 환경 설정
cp base.env myapp.env
vi myapp.env  # 필수 설정 수정

# 3개 인스턴스 배포
./main.sh deploy 3 myapp.env

# 결과: 0, 1, 2 인스턴스 생성
# 포트: 8080, 8081, 8082
```

### 시나리오 2: 스케일 업

```bash
# 3개 → 5개
./main.sh deploy 5 myapp.env

# 결과: 3, 4 인스턴스 추가
# 기존 0, 1, 2는 유지
```

### 시나리오 3: 스케일 다운

```bash
# 5개 → 3개
./main.sh deploy 3 myapp.env

# 결과: 4, 3 인스턴스 제거 (역순)
# 0, 1, 2만 유지
```

### 시나리오 4: 배포 실패 시

```bash
./main.sh deploy 5 myapp.env

# 인스턴스 3 배포 중 실패
# → 0, 1, 2 자동 롤백
# → 결과: 배포 전 상태로 복구
```

### 시나리오 5: 수동 롤백

```bash
# 전체 롤백
./main.sh rollback myapp.env

# 결과: 모든 인스턴스가 이전 버전으로 복원
```

---

## 고급 사용 (직접 모듈 호출)

### 상황: 인스턴스 0만 재배포하고 싶을 때

```bash
# multi_deploy를 통해 단일 인스턴스 배포
./multi_deploy/multi_deploy_control.sh deploy-single 0 myapp.env
```

### 상황: 수동으로 Nginx 제어

```bash
# Nginx DOWN
./nginx/nginx_control.sh down 8080 /etc/nginx/conf.d/upstream.conf

# Nginx UP
./nginx/nginx_control.sh up 8080 /etc/nginx/conf.d/upstream.conf
```

### 상황: 헬스 체크만 실행

```bash
# Simple 테스트
./test_instance/test_instance_control.sh test 8080 myapp.env

# Full 테스트
export TEST_MODE=full
./test_instance/test_instance_control.sh test 8080 myapp.env
```

---

## 트러블슈팅

### 배포 실패

```bash
# 1. 상태 확인
./main.sh status myapp.env

# 2. 로그 확인
tail -f ${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/*/logs/*.log

# 3. 프로세스 확인
pgrep -f "java -jar current.jar"

# 4. Nginx 확인
sudo nginx -t
cat /etc/nginx/conf.d/upstream.conf
```

### 롤백 실패

```bash
# 백업 파일 확인
ls -la ${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/*/current.jar.bak

# 수동 롤백
cd ${SERVICE_BASE_DIR}/${SERVICE_NAME}/instances/0
mv current.jar.bak current.jar
./runApp.sh restart 8080
```

### 테스트 타임아웃

```bash
# Warmup 시간 증가
export TEST_WARMUP_WAIT=30
export TEST_RETRY_COUNT=10

./main.sh deploy 3 myapp.env
```

---

## 성능 지표

### 배포 시간

| 작업 | Simple Mode | Full Mode |
|------|-------------|-----------|
| 1개 인스턴스 | ~10-20초 | ~30-60초 |
| 5개 인스턴스 | ~1-2분 | ~3-5분 |
| 10개 인스턴스 | ~2-4분 | ~6-10분 |

### 리소스

- **디스크**: 인스턴스당 ~200MB (백업 포함)
- **메모리**: 인스턴스당 ~512MB-2GB
- **CPU**: 배포 중 ~5-10% (스크립트 오버헤드)

---

## 설계 원칙

### 1. 단일 진입점
- 사용자는 `main.sh`만 사용
- 복잡도 숨김

### 2. 계층 분리
- 상위 → 하위만 호출
- 계층 우회 금지
- 책임 명확화

### 3. Fail-Safe
- 각 단계마다 검증
- 실패 시 안전한 복구
- 자동 롤백

### 4. 모듈 독립성
- 각 모듈은 독립 실행 가능
- CLI 기반 통신
- 느슨한 결합

### 5. 무중단 배포
- Nginx 트래픽 제어
- 헬스 체크 통과 확인
- 순차적 배포

---

## 문서 가이드

| 문서 | 대상 | 내용 |
|------|------|------|
| `README.md` | 모든 사용자 | 사용법, 예시, FAQ |
| `SUMMARY.md` | 모든 사용자 | 빠른 참조 (본 문서) |
| `HIERARCHY.md` | 개발자 | 계층 구조, 의존성 규칙 |
| `ARCHITECTURE.md` | 개발자 | 상세 아키텍처, 플로우 |
| `*/SPEC.md` | 개발자 | 모듈별 상세 명세 |

---

## 버전 히스토리

### v2.0.0 (2025-10-04) - Current

**Major Refactoring**:
- 모듈형 4계층 구조로 재설계
- `main.sh` 단일 진입점 도입
- `test_instance` 모듈 추가
- 계층별 책임 명확화
- 모든 모듈에 레이어 정보 주석 추가

**Migration from v1.x**:
- `multi_deploy.sh` → `./main.sh deploy`
- `test_instance.sh` → `./test_instance/test_instance_control.sh`

---

## 다음 단계

### 학습 경로

1. **입문** (5분)
   - 본 문서 읽기
   - Quick Start 실행

2. **기본** (30분)
   - `README.md` 정독
   - 시나리오별 실습

3. **중급** (2시간)
   - `HIERARCHY.md` 학습
   - 고급 사용법 실습

4. **고급** (1일)
   - `ARCHITECTURE.md` 학습
   - 모듈별 `SPEC.md` 학습
   - 커스터마이징

### 실습 권장 순서

```bash
# 1. 환경 설정
cp base.env my-app.env
vi my-app.env

# 2. 검증
./main.sh validate 3 my-app.env

# 3. 배포
./main.sh deploy 3 my-app.env

# 4. 상태 확인
./main.sh status my-app.env

# 5. 스케일 업
./main.sh deploy 5 my-app.env

# 6. 스케일 다운
./main.sh deploy 3 my-app.env

# 7. 롤백
./main.sh rollback my-app.env
```

---

## 지원

- **문서**: 이 디렉터리의 모든 `.md` 파일
- **도움말**: `./main.sh help`
- **버전**: `./main.sh version`

---

**마지막 업데이트**: 2025-10-04
**버전**: 2.0.0
**작성자**: Auto Deploy Shell Team
