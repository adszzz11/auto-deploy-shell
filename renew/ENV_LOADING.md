# Environment Variable Loading Strategy

## 원칙

**사용자는 `base.env` 하나만 관리**

- 각 모듈의 `*.env` 파일: 기본값 제공 (개발자용)
- 사용자의 `base.env`: 모든 설정 오버라이드 (운영자용)

## 로딩 순서

```bash
1. 모듈 기본값 로드: ${MODULE}.env (있으면)
2. 사용자 설정 로드: 사용자가 제공한 .env 파일 (base.env 등)
   → 1번을 오버라이드
3. 런타임 환경 변수: export로 직접 설정한 값
   → 1, 2번을 오버라이드
```

**우선순위**: `런타임 환경 변수` > `사용자 .env` > `모듈 기본 .env`

## 구현 패턴

### 각 모듈의 *_control.sh

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")") && pwd)"

# 1. 모듈 기본값 로드 (선택적)
if [ -f "${SCRIPT_DIR}/${MODULE}.env" ]; then
    source "${SCRIPT_DIR}/${MODULE}.env"
fi

# ... 함수들 source ...

# 2. 사용자 환경 파일 로드 (main 함수 내에서)
load_environment() {
    local env_file="${1:-}"

    if [ -n "$env_file" ]; then
        if [ ! -f "$env_file" ]; then
            echo "[ERROR] Environment file not found: $env_file"
            return 1
        fi
        source "$env_file"  # 사용자 설정으로 오버라이드
    fi
}
```

## 예시

### deploy_control.sh

```bash
# 1. deploy.env 로드 (기본값)
source "${SCRIPT_DIR}/deploy.env"
# DEPLOY_BACKUP_JAR=true (기본값)

# 2. 사용자 base.env 로드
source "$user_env_file"  # base.env
# DEPLOY_BACKUP_JAR=false (사용자가 설정한 경우 오버라이드)

# 3. 런타임 환경 변수
export DEPLOY_BACKUP_JAR=true  # 최종 우선
```

## 사용자 관점

### 설정 파일 하나만 관리

```bash
# 1. base.env 복사
cp renew/base.env myapp.env

# 2. 필요한 설정만 수정
vi myapp.env
# export SERVICE_NAME="myapp"
# export BASE_PORT="808"
# ...

# 3. 배포
./main.sh deploy 3 myapp.env
```

### 일시적 설정 변경

```bash
# 환경 변수로 즉시 오버라이드
export TEST_MODE=full
./main.sh deploy 3 myapp.env

# 또는
TEST_MODE=full ./main.sh deploy 3 myapp.env
```

## 모듈별 기본 .env 파일 역할

각 모듈의 `.env` 파일은:
- **개발자용**: 모듈 개발 시 참고용 기본값
- **문서화**: 사용 가능한 환경 변수 목록
- **폴백**: 사용자가 설정하지 않은 값의 기본값

**사용자는 건드리지 않음** - `base.env`만 사용

## 현재 상태

모든 `*_control.sh`는 이미 이 패턴을 따름:

```bash
# 모듈 기본값 로드
if [ -f "${SCRIPT_DIR}/${MODULE}.env" ]; then
    source "${SCRIPT_DIR}/${MODULE}.env"
fi

# 사용자 환경 로드 (execute 함수 내)
load_environment() {
    source "$env_file"  # 사용자 파일로 오버라이드
}
```

## 검증

```bash
# 1. 모듈 기본값 확인
cat renew/deploy/deploy.env

# 2. 사용자 설정 확인
cat base.env

# 3. 실제 값 확인 (배포 중)
echo $DEPLOY_BACKUP_JAR
```

---

**핵심**: 사용자는 `base.env` 하나만 관리하면 됩니다!
