# Module Hierarchy

## 계층 구조

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: User Interface                                 │
│                                                          │
│  main.sh                                                 │
│  - 사용자 진입점                                          │
│  - 4개 명령어: deploy, rollback, status, validate         │
│  - multi_deploy만 호출                                   │
└────────────────────┬────────────────────────────────────┘
                     │
                     v
┌─────────────────────────────────────────────────────────┐
│ Layer 2: Orchestration                                  │
│                                                          │
│  multi_deploy/                                           │
│  - 다중 인스턴스 오케스트레이션                             │
│  - deploy, rollback 모듈 호출                            │
│  - 스케일 업/다운 관리                                    │
│  - 자동 롤백 처리                                         │
└────────────┬────────────────────┬──────────────────────┘
             │                    │
             v                    v
┌────────────────────┐  ┌────────────────────┐
│ Layer 3:           │  │ Layer 3:           │
│ Core Operations    │  │ Core Operations    │
│                    │  │                    │
│  deploy/           │  │  rollback/         │
│  - 단일 배포       │  │  - 단일 롤백       │
│  - 12단계 실행     │  │  - 10단계 실행     │
└─────┬──────────────┘  └──────┬─────────────┘
      │                        │
      └────────┬───────────────┘
               │
               v
┌─────────────────────────────────────────────────────────┐
│ Layer 4: Support Services                               │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐│
│  │  nginx   │  │link_jar  │  │ run_app  │  │   test   ││
│  │          │  │          │  │          │  │ instance ││
│  │업스트림  │  │JAR 링크  │  │프로세스  │  │헬스체크  ││
│  │  제어    │  │  관리    │  │  관리    │  │         ││
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘│
└─────────────────────────────────────────────────────────┘
```

---

## 사용자 관점

### 일반 사용자 (95%)

**사용 도구**: `main.sh`만 + `base.env` 하나

```bash
# 환경 설정
cp base.env myapp.env
vi myapp.env  # 필수 설정만 수정

# 배포
./main.sh deploy 5 myapp.env

# 상태 확인
./main.sh status myapp.env

# 롤백
./main.sh rollback myapp.env
```

**특징**:
- 간단한 4개 명령어
- 하나의 설정 파일만 관리 (base.env 템플릿 사용)
- 내부 구조 몰라도 사용 가능
- 안전한 오케스트레이션

---

### 고급 사용자 (5%)

**사용 도구**: 모듈 직접 호출 (base.env 파일은 동일하게 사용)

```bash
# 단일 인스턴스 배포 (Layer 2 통해서)
./multi_deploy/multi_deploy_control.sh deploy-single 0 myapp.env

# 단일 인스턴스 롤백 (Layer 2 통해서)
./multi_deploy/multi_deploy_control.sh rollback-single 0 myapp.env

# 세부 테스트 (Layer 4 직접 호출)
./test_instance/test_instance_control.sh full 8080 myapp.env

# Nginx 수동 제어 (Layer 4 직접 호출)
./nginx/nginx_control.sh down 8080 /etc/nginx/conf.d/upstream.conf
```

**사용 시나리오**:
- 디버깅
- 부분 실패 복구
- 커스터마이징
- 자동화 스크립트 작성

---

## 호출 흐름

### 배포 흐름

```
User
  │
  └─> ./main.sh deploy 5 myapp.env
        │
        └─> multi_deploy_control.sh deploy 5 myapp.env
              │
              ├─> deploy_control.sh deploy 0 myapp.env
              │     │
              │     ├─> nginx_control.sh down 8080
              │     ├─> link_jar_control.sh link
              │     ├─> run_app_control.sh restart 8080
              │     ├─> test_instance_control.sh test 8080
              │     └─> nginx_control.sh up 8080
              │
              ├─> deploy_control.sh deploy 1 app.env
              │     └─> (동일한 흐름)
              │
              ├─> deploy_control.sh deploy 2 app.env
              │     └─> (동일한 흐름)
              │
              └─> ... (나머지 인스턴스)
```

### 롤백 흐름

```
User
  │
  └─> ./main.sh rollback app.env
        │
        └─> multi_deploy_control.sh rollback app.env
              │
              ├─> rollback_control.sh rollback 2 app.env
              │     │
              │     ├─> nginx_control.sh down 8082
              │     ├─> (JAR 복원)
              │     ├─> run_app_control.sh restart 8082
              │     └─> nginx_control.sh up 8082
              │
              ├─> rollback_control.sh rollback 1 app.env
              │     └─> (동일한 흐름)
              │
              └─> rollback_control.sh rollback 0 app.env
                    └─> (동일한 흐름)
```

---

## 계층 간 통신

### 통신 방식

| 계층 | 통신 방법 | 데이터 형식 |
|------|----------|------------|
| Layer 1 → 2 | CLI 호출 | 명령어 인자 |
| Layer 2 → 3 | CLI 호출 | 명령어 인자 |
| Layer 3 → 4 | CLI 호출 | 명령어 인자 |
| 모든 계층 | 환경 변수 | `export VAR=value` |
| 모든 계층 | 파일 시스템 | 심볼릭 링크, PID 파일 |

### 반환값

- **0**: 성공
- **1**: 실패
- **124**: 타임아웃

### 출력 채널

- **stdout**: 정보, 성공 메시지
- **stderr**: 에러, 경고 메시지

---

## 의존성 규칙

### ✅ 허용

```bash
# 상위 → 하위 계층 호출
main.sh → multi_deploy
multi_deploy → deploy
multi_deploy → rollback
deploy → nginx, link_jar, run_app, test_instance
rollback → nginx, run_app
```

### ❌ 금지

```bash
# 계층 우회 금지
main.sh → deploy (X)
main.sh → nginx (X)

# 하위 → 상위 호출 금지
deploy → multi_deploy (X)
nginx → deploy (X)

# 동일 계층 간 호출 금지
deploy → rollback (X)
nginx → link_jar (X)
```

### 🔄 예외: 순환 참조 방지

```bash
# multi_deploy가 deploy 호출
# deploy 실패 시 multi_deploy가 rollback 호출
# 이는 오케스트레이션 역할로 허용됨

multi_deploy
  ├─> deploy (성공)
  └─> rollback (실패 시)
```

---

## 모듈 독립성

### 독립 실행 가능

모든 `*_control.sh`는 독립적으로 실행 가능:

```bash
# ✅ 가능
./deploy/deploy_control.sh deploy 0 app.env
./nginx/nginx_control.sh up 8080 upstream.conf
./test_instance/test_instance_control.sh test 8080

# ✅ 가능 (환경 변수로 설정 전달)
export SERVICE_NAME=myapp
export BASE_PORT=808
./run_app/run_app_control.sh start 8080
```

### 모듈 교체 가능

각 모듈은 인터페이스만 맞으면 교체 가능:

```bash
# nginx 모듈을 HAProxy로 교체 가능
# - nginx_control.sh와 동일한 인터페이스 제공
# - up, down 명령어 지원
./haproxy/haproxy_control.sh up 8080 haproxy.cfg
```

---

## 확장 포인트

### 1. 새 Layer 4 모듈 추가

```bash
# 예: 모니터링 모듈
renew/monitoring/
├── monitoring_control.sh
├── monitoring.env
└── func/
    ├── send_metric.sh
    └── send_alert.sh

# deploy에서 호출
"${script_dir}/../monitoring/monitoring_control.sh" metric deployed "$instance"
```

### 2. Layer 3 모듈 추가

```bash
# 예: 블루-그린 배포 모듈
renew/blue_green/
├── blue_green_control.sh
└── func/
    ├── switch_traffic.sh
    └── validate_deployment.sh

# multi_deploy에서 호출 가능
```

### 3. Layer 2 확장

```bash
# 예: 카나리 배포 오케스트레이터
renew/canary_deploy/
├── canary_deploy_control.sh
└── func/
    ├── gradual_rollout.sh
    └── traffic_split.sh

# main.sh에서 새 명령어 추가
case "$command" in
    canary)
        ./canary_deploy/canary_deploy_control.sh "$@"
        ;;
esac
```

---

## 설계 원칙

### 1. 단일 책임 (Single Responsibility)
- 각 모듈은 하나의 명확한 책임
- main.sh: 사용자 인터페이스
- multi_deploy: 오케스트레이션
- deploy: 배포 실행
- nginx: 업스트림 제어

### 2. 계층 분리 (Layered Architecture)
- 상위 계층은 하위 계층 호출만 가능
- 계층 우회 금지
- 명확한 책임 경계

### 3. 느슨한 결합 (Loose Coupling)
- CLI 기반 통신
- 환경 변수로 설정 공유
- 파일 시스템으로 상태 공유

### 4. 높은 응집도 (High Cohesion)
- 관련 기능을 한 모듈에 집중
- func/ 디렉터리로 세부 기능 분리

### 5. 개방-폐쇄 원칙 (Open-Closed)
- 확장에는 열려있음 (새 모듈 추가)
- 수정에는 닫혀있음 (기존 모듈 변경 최소화)

---

**Version**: 1.0
**Last Updated**: 2025-10-04
