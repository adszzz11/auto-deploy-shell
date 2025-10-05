# Multi Deploy Control Functions Specification

## 개요

여러 애플리케이션 인스턴스를 동시에 배포/관리하는 Bash 기반 시스템입니다. 2-10개의 인스턴스를 대상으로 하며, 실패 시 자동 롤백, 스케일 인/아웃, 상태 확인 기능을 제공합니다.

## 1. 파라미터 검증

### validate_multi_deploy_parameters(target_count, env_file_raw)
**목적**: 다중 배포 파라미터 유효성 검증

**파라미터**:
- `target_count`: 배포할 인스턴스 수 (2-10)
- `env_file_raw`: 환경 설정 파일 경로 (CR 문자 포함 가능)

**검증 항목**:
1. 타겟 인스턴스 수가 숫자인지 확인
2. 인스턴스 수 범위 검증 (MIN_INSTANCES ~ MAX_INSTANCES)
3. 환경 파일에서 CR(\r) 제거
4. 환경 파일 존재 및 읽기 권한 확인

**반환값**:
- 성공: 정제된 환경 파일 경로
- 실패: ERROR 메시지 및 exit 1

**구현 예시**:
```bash
# 타겟 인스턴스 수 검증
if ! [[ "$target_count" =~ ^[0-9]+$ ]]; then
    error_exit "Target instance count must be a valid number: $target_count"
fi

# 범위 검증 (2-10)
if [ "$target_count" -lt 2 ] || [ "$target_count" -gt 10 ]; then
    error_exit "Target instance count must be between 2-10: $target_count"
fi

# CR 제거
env_file="$(echo "$env_file_raw" | tr -d '\r')"
```

### validate_required_env_vars(env_file)
**목적**: 필수 환경 변수 존재 확인

**필수 변수**:
- `SERVICE_NAME`: 서비스 이름
- `SERVICE_BASE_DIR`: 서비스 베이스 디렉터리
- `BASE_PORT`: 기본 포트 (인스턴스별로 +숫자)
- `JAR_TRUNK_DIR`: JAR 파일 소스 디렉터리
- `UPSTREAM_CONF`: Nginx 업스트림 설정 파일

**에러 케이스**:
```bash
[ERROR] Missing required environment variables: SERVICE_NAME BASE_PORT
```

### validate_instance_directories(service_base_dir, service_name)
**목적**: 인스턴스 디렉터리 구조 검증 및 생성

**디렉터리 구조**:
```
${SERVICE_BASE_DIR}/
└── ${SERVICE_NAME}/
    └── instances/
        ├── 0/
        ├── 1/
        ├── 2/
        └── ...
```

**동작**:
1. 서비스 베이스 디렉터리 존재 확인
2. 서비스 디렉터리 생성 (없는 경우)
3. 인스턴스 디렉터리 생성 (없는 경우)

## 2. 인스턴스 분석

### analyze_current_instances(service_base_dir, service_name)
**목적**: 현재 배포된 인스턴스 스캔

**동작**:
1. `${service_base_dir}/${service_name}/instances/` 디렉터리 스캔
2. 숫자로만 구성된 서브디렉터리 탐지 (예: 0, 1, 2)
3. 인스턴스 번호 리스트 반환 (정렬됨, 공백 구분)

**출력 형식**:
```
0 1 2 3
```

**구현 예시**:
```bash
for d in "$service_instances_dir"/*; do
    if [ -d "$d" ]; then
        instance_num=$(basename "$d")
        if [[ "$instance_num" =~ ^[0-9]+$ ]]; then
            current_instances+=("$instance_num")
        fi
    fi
done

printf '%s\n' "${current_instances[@]}" | sort -n | tr '\n' ' '
```

### calculate_current_instance_count(service_base_dir, service_name)
**목적**: 현재 인스턴스 수 계산

**계산 방법**:
- 최대 인스턴스 번호 + 1 = 현재 인스턴스 수
- 예: 인스턴스 [0, 1, 3] 존재 → 최대 번호 3 → 카운트 4

**반환값**:
- 인스턴스 없음: `0`
- 인스턴스 있음: `max_instance + 1`

**왜 max + 1인가?**:
- 인스턴스 번호는 0부터 시작 (0-based indexing)
- 인스턴스 0, 1, 2 존재 → 총 3개 → max(2) + 1 = 3

### show_instance_status(service_base_dir, service_name, target_count)
**목적**: 현재 상태 및 필요한 액션 표시

**출력 예시**:
```
=== Instance Status Analysis ===
Service: my-service
Service Base Dir: /home/service
Target Instance Count: 5

Current Instances: 0 1 2
Current Count: 3
Action Required: Scale out - Deploy 2 additional instances
```

**액션 결정 로직**:
1. `current_count < target_count` → Scale out (배포)
2. `current_count > target_count` → Scale in (제거)
3. `current_count == target_count` → Update (업데이트)

## 3. 배포 실행

### execute_multi_deployment(target_count, env_file, script_dir)
**목적**: 다중 인스턴스 순차 배포

**배포 프로세스**:
```bash
for i in 0..(target_count-1):
    1. deploy_control.sh deploy $i env_file
    2. 성공 → successful_instances에 추가
    3. 실패 → 자동 롤백 (옵션에 따라)
    4. 다음 배포 전 대기 (WAIT_BETWEEN_DEPLOYS)
```

**자동 롤백 (MULTI_DEPLOY_AUTO_ROLLBACK=true)**:
```bash
if deployment_failed; then
    for instance in successful_instances:
        rollback_instance
    rollback_failed_instance
    exit 1
fi
```

**구현 예시**:
```bash
for (( i=0; i<target_count; i++ )); do
    echo "==================================================[ Instance $i ]=="

    if "$deploy_script" deploy "$i" "$env_file"; then
        successful_instances+=("$i")

        # 다음 배포 전 대기
        if [ "$i" -lt $((target_count - 1)) ]; then
            sleep "$wait_time"
        fi
    else
        # 롤백
        rollback_successful_instances "${successful_instances[@]}"
        exit 1
    fi
done
```

### rollback_successful_instances(instances, env_file, script_dir)
**목적**: 성공한 인스턴스들 롤백

**롤백 방법**:
1. `rollback_control.sh` 사용 (우선)
2. 폴백 방식: JAR 백업 복원 (`current.jar.bak` → `current.jar`)

**파라미터**:
- `instances`: 롤백할 인스턴스 번호 배열
- `env_file`: 환경 설정 파일
- `script_dir`: 스크립트 디렉터리

**구현 예시**:
```bash
# rollback_control.sh 사용 (권장)
rollback_script="${script_dir}/../rollback/rollback_control.sh"

if [ -x "$rollback_script" ]; then
    for instance in "${instances[@]}"; do
        "$rollback_script" rollback "$instance" "$env_file"
    done
else
    # 폴백 방식
    rollback_instances_fallback "${instances[@]}" "$env_file" "$script_dir"
fi
```

**폴백 방식** (`rollback_control.sh` 없는 경우):
```bash
for instance in "${instances[@]}"; do
    backup_jar="${instance_dir}/current.jar.bak"
    if [ -f "$backup_jar" ]; then
        mv "$backup_jar" "${instance_dir}/current.jar"
        run_app_control.sh restart "${BASE_PORT}${instance}"
    fi
done
```

### remove_excess_instances(current_count, target_count, env_file, script_dir)
**목적**: 스케일 다운 시 초과 인스턴스 제거

**제거 전략**:
- `MULTI_DEPLOY_SCALE_IN_REVERSE=true`: 큰 번호부터 제거 (예: 4, 3, 2)
- `MULTI_DEPLOY_SCALE_IN_REVERSE=false`: 작은 번호부터 제거 (예: 2, 3, 4)

**제거 프로세스**:
1. 제거할 인스턴스 번호 결정
2. 각 인스턴스에 대해 `deploy_control.sh remove` 실행
3. 실패 시 경고 로그만 출력 (계속 진행)

**구현 예시**:
```bash
# 역순 제거 (권장)
for (( i=current_count-1; i>=target_count; i-- )); do
    deploy_control.sh remove "$i" "$env_file"
done
```

## 4. 환경 설정 (multi_deploy.env)

```bash
# 인스턴스 수 범위
export MULTI_DEPLOY_MIN_INSTANCES="2"
export MULTI_DEPLOY_MAX_INSTANCES="10"

# 배포 옵션
export MULTI_DEPLOY_PARALLEL="false"           # 병렬 배포 (미지원, 향후 확장)
export MULTI_DEPLOY_AUTO_ROLLBACK="true"       # 실패 시 자동 롤백
export MULTI_DEPLOY_CONTINUE_ON_ERROR="false"  # 에러 시 계속 진행
export MULTI_DEPLOY_DRY_RUN="false"            # Dry run 모드 (미지원)

# 배포 전략
export MULTI_DEPLOY_STRATEGY="sequential"      # sequential만 지원
export MULTI_DEPLOY_ROLLING_BATCH_SIZE="2"    # Rolling 배포 배치 크기 (미지원)

# 대기 시간
export MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS="2"  # 배포 간 대기 (초)
export MULTI_DEPLOY_STABILIZATION_WAIT="5"    # 배포 후 안정화 대기 (초)

# 검증 옵션
export MULTI_DEPLOY_VERIFY_BEFORE_DEPLOY="true"  # 배포 전 검증
export MULTI_DEPLOY_VERIFY_AFTER_DEPLOY="true"   # 배포 후 검증 (미지원)

# 스케일링 옵션
export MULTI_DEPLOY_SCALE_IN_REVERSE="true"    # 스케일 다운 역순 제거
export MULTI_DEPLOY_SCALE_GRACEFUL="true"      # Graceful 스케일링 (미지원)

# 로그 옵션
export MULTI_DEPLOY_LOG_LEVEL="INFO"
export MULTI_DEPLOY_SHOW_PROGRESS="true"
```

## 5. 배포 워크플로우

### 전체 배포 시나리오 (0 → 5 인스턴스)
```bash
./multi_deploy_control.sh deploy 5 /path/to/env.env

# 실행 과정:
# 1. 파라미터 검증 (target_count=5, env_file 존재 확인)
# 2. 환경 변수 로드 및 검증
# 3. 인스턴스 디렉터리 검증/생성
# 4. 현재 상태 분석 (현재 0개)
# 5. 상태 표시:
#    Current Count: 0
#    Target Count: 5
#    Action Required: Deploy 5 new instances
# 6. 순차 배포:
#    - Instance 0 배포 → 성공 → 2초 대기
#    - Instance 1 배포 → 성공 → 2초 대기
#    - Instance 2 배포 → 성공 → 2초 대기
#    - Instance 3 배포 → 성공 → 2초 대기
#    - Instance 4 배포 → 성공
# 7. 안정화 대기 (5초)
# 8. 완료
```

### 스케일 업 시나리오 (3 → 5 인스턴스)
```bash
./multi_deploy_control.sh deploy 5 /path/to/env.env

# 현재 상태: 인스턴스 0, 1, 2 존재
# 1. 현재 상태 분석: count=3
# 2. 상태 표시:
#    Current Instances: 0 1 2
#    Current Count: 3
#    Target Count: 5
#    Action Required: Scale out - Deploy 2 additional instances
# 3. 전체 업데이트:
#    - Instance 0 업데이트 → 성공
#    - Instance 1 업데이트 → 성공
#    - Instance 2 업데이트 → 성공
#    - Instance 3 배포 (신규) → 성공
#    - Instance 4 배포 (신규) → 성공
# 4. 완료
```

### 스케일 다운 시나리오 (5 → 3 인스턴스)
```bash
./multi_deploy_control.sh deploy 3 /path/to/env.env

# 현재 상태: 인스턴스 0, 1, 2, 3, 4 존재
# 1. 현재 상태 분석: count=5
# 2. 상태 표시:
#    Current Instances: 0 1 2 3 4
#    Current Count: 5
#    Target Count: 3
#    Action Required: Scale in - Remove 2 excess instances
# 3. 대상 인스턴스 업데이트:
#    - Instance 0 업데이트 → 성공
#    - Instance 1 업데이트 → 성공
#    - Instance 2 업데이트 → 성공
# 4. 초과 인스턴스 제거 (역순):
#    - Instance 4 제거 → 성공
#    - Instance 3 제거 → 성공
# 5. 완료
```

### 롤백 시나리오 (배포 실패)
```bash
./multi_deploy_control.sh deploy 5 /path/to/env.env

# 배포 과정:
# - Instance 0 배포 → 성공 ✅
# - Instance 1 배포 → 성공 ✅
# - Instance 2 배포 → 실패 ❌

# 자동 롤백 (MULTI_DEPLOY_AUTO_ROLLBACK=true):
# 1. rollback_control.sh 확인
# 2. Instance 0 롤백:
#    - rollback_control.sh rollback 0 env.env 실행
#    - Nginx DOWN → JAR 복원 → 앱 재시작 → Nginx UP
# 3. Instance 1 롤백:
#    - rollback_control.sh rollback 1 env.env 실행
#    - Nginx DOWN → JAR 복원 → 앱 재시작 → Nginx UP
# 4. 배포 중단 및 에러 반환
```

### 전체 롤백 시나리오
```bash
./multi_deploy_control.sh rollback /path/to/env.env

# 실행 과정:
# 1. 현재 인스턴스 분석 (예: 0, 1, 2 발견)
# 2. rollback_control.sh 확인
# 3. 역순으로 롤백 실행:
#    - Instance 2 롤백 → 성공
#    - 2초 대기
#    - Instance 1 롤백 → 성공
#    - 2초 대기
#    - Instance 0 롤백 → 성공
# 4. 완료

# 출력 예시:
==================================================
Multi-Instance Rollback
Using environment file: /path/to/env.env
==================================================
[INFO] Found 3 instances to rollback: 0 1 2

==================================================[ Rollback Instance 2 ]==
[SUCCESS] Instance 2 rolled back successfully
[INFO] Waiting 2s before next rollback

==================================================[ Rollback Instance 1 ]==
[SUCCESS] Instance 1 rolled back successfully
[INFO] Waiting 2s before next rollback

==================================================[ Rollback Instance 0 ]==
[SUCCESS] Instance 0 rolled back successfully

==================================================
[SUCCESS] Multi-instance rollback completed successfully
==================================================
```

## 6. CLI 사용법

### multi_deploy_control.sh - 메인 진입점

```bash
# 5개 인스턴스 배포
./multi_deploy_control.sh deploy 5 /path/to/env.env

# 모든 인스턴스 롤백
./multi_deploy_control.sh rollback /path/to/env.env

# 현재 상태 확인
./multi_deploy_control.sh status /path/to/env.env

# 배포 전 검증
./multi_deploy_control.sh validate 5 /path/to/env.env

# 도움말
./multi_deploy_control.sh help
```

### 상태 확인 출력 예시
```
=== Multi-Deploy Status ===
Environment File: /tmp/test.env
Service: my-service
Service Base Dir: /home/service
Base Port: 808

Current Instances: 0 1 2
Current Count: 3

=== Individual Instance Status ===
Instance 0 (port 8080):
  Directory: ✅ /home/service/my-service/instances/0
  JAR Link: ✅ -> /jar_trunk/app-v1.0.jar
  Process: ✅ Running
  Backup: ✅ Available

Instance 1 (port 8081):
  Directory: ✅ /home/service/my-service/instances/1
  JAR Link: ✅ -> /jar_trunk/app-v1.0.jar
  Process: ✅ Running
  Backup: ✅ Available

Instance 2 (port 8082):
  Directory: ✅ /home/service/my-service/instances/2
  JAR Link: ✅ -> /jar_trunk/app-v1.0.jar
  Process: ❌ Not running
  Backup: ✅ Available
```

### 검증 출력 예시
```
=== Multi-Deploy Validation ===
✅ Parameters validated
✅ Environment variables validated
✅ Instance directories validated
✅ deploy_control.sh found and executable
✅ nginx/nginx_control.sh found and executable
✅ link_jar/link_jar_control.sh found and executable
✅ run_app/run_app_control.sh found and executable

✅ All validations passed
```

## 7. 에러 처리

### 파라미터 오류
1. **잘못된 인스턴스 수**: `[ERROR] Target instance count must be a valid number: abc`
2. **범위 초과**: `[ERROR] Target instance count must be between 2-10: 15`
3. **환경 파일 없음**: `[ERROR] Environment file not found: /path/to/env.env`

### 환경 변수 오류
1. **필수 변수 누락**: `[ERROR] Missing required environment variables: SERVICE_NAME BASE_PORT`

### 배포 오류
1. **인스턴스 배포 실패**:
   ```
   [ERROR] Deployment failed for instance 2
   [WARN] Initiating rollback for all successfully deployed instances
   [INFO] Rolling back instance 0
   [INFO] Rolling back instance 1
   ```

2. **스크립트 없음**: `[ERROR] deploy_control.sh not found or not executable: /path/to/deploy_control.sh`

### 롤백 오류
1. **백업 없음**: `[WARN] No backup found for instance 0`
2. **재시작 실패**: `[WARN] Failed to restart instance 0 after rollback`

## 8. 의존 스크립트

### 필수 스크립트 (renew/ 디렉터리)
```
renew/
├── deploy/deploy_control.sh         # 개별 인스턴스 배포/제거
├── rollback/rollback_control.sh     # 개별 인스턴스 롤백
├── nginx/nginx_control.sh           # Nginx 업스트림 제어
├── link_jar/link_jar_control.sh     # JAR 심볼릭 링크 관리
└── run_app/run_app_control.sh       # 애플리케이션 프로세스 관리
```

### 사용 방식
```bash
# 개별 인스턴스 배포
deploy_control.sh deploy <instance_num> <env_file>

# 개별 인스턴스 제거
deploy_control.sh remove <instance_num> <env_file>

# 개별 인스턴스 롤백
rollback_control.sh rollback <instance_num> <env_file>

# 애플리케이션 재시작
run_app_control.sh restart <port>
```

## 9. 파일 구조

```
renew/multi_deploy/
├── multi_deploy.env              # 환경 변수 설정
├── multi_deploy_control.sh       # 메인 CLI 스크립트
├── SPEC.md                       # 명세 문서
└── func/                         # 함수 스크립트들
    ├── validate_parameters.sh       # 파라미터 검증
    ├── analyze_instances.sh         # 인스턴스 분석
    └── execute_deployment.sh        # 배포 실행 및 롤백
```

## 10. 레거시 시스템과의 차이점

### pre/multi_deploy.sh (레거시)
- 단일 파일 모놀리식 구조
- `_shell/deploy.sh`, `_shell/rollback.sh` 호출 (존재하지 않음)
- 하드코딩된 설정 (2-10 인스턴스)
- 제한된 에러 처리

### renew/multi_deploy (신규)
- 환경 변수 기반 설정 (multi_deploy.env)
- 모듈형 함수 구조 (func/ 디렉터리)
- renew/ 모듈 통합 (deploy, nginx, link_jar, run_app)
- 상태 확인 및 검증 기능
- 세밀한 롤백 제어
- CLI 인터페이스 개선

## 11. 테스트 시나리오

### 단위 테스트
```bash
# 1. 파라미터 검증
./func/validate_parameters.sh params 5 /tmp/test.env
# 출력: /tmp/test.env (정제된 경로)

# 2. 인스턴스 분석
./func/analyze_instances.sh list /tmp/service my-service
# 출력: 0 1 2

# 3. 인스턴스 수 계산
./func/analyze_instances.sh count /tmp/service my-service
# 출력: 3
```

### 통합 테스트
```bash
# 전체 배포 워크플로우
export MULTI_DEPLOY_AUTO_ROLLBACK="true"
export MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS="1"

# 1. 초기 배포 (3개 인스턴스)
./multi_deploy_control.sh deploy 3 /tmp/test.env

# 2. 상태 확인
./multi_deploy_control.sh status /tmp/test.env

# 3. 스케일 업 (5개 인스턴스)
./multi_deploy_control.sh deploy 5 /tmp/test.env

# 4. 스케일 다운 (2개 인스턴스)
./multi_deploy_control.sh deploy 2 /tmp/test.env
```

### 에러 처리 테스트
```bash
# 1. 잘못된 타겟 수
./multi_deploy_control.sh deploy 15 /tmp/test.env
# 출력: [ERROR] Target instance count must be between 2-10: 15

# 2. 환경 파일 없음
./multi_deploy_control.sh deploy 5 /invalid/path.env
# 출력: [ERROR] Environment file not found: /invalid/path.env

# 3. 롤백 시나리오 (수동 실패 주입)
# deploy_control.sh를 임시로 실패하도록 수정
./multi_deploy_control.sh deploy 5 /tmp/test.env
# 출력:
#   [ERROR] Deployment failed for instance 2
#   [WARN] Initiating rollback for all successfully deployed instances
#   [INFO] Rolling back instance 0
#   [INFO] Rolling back instance 1
```

## 12. 모범 사례

### 배포 전
1. **검증 실행**: `./multi_deploy_control.sh validate 5 /path/to/env.env`
2. **상태 확인**: `./multi_deploy_control.sh status /path/to/env.env`
3. **백업 확인**: 각 인스턴스의 `.bak` 파일 존재 여부 확인

### 배포 중
1. **로그 모니터링**: 배포 로그 실시간 확인
2. **진행 상황 추적**: 각 인스턴스 배포 성공/실패 확인
3. **대기 시간 조정**: `MULTI_DEPLOY_WAIT_BETWEEN_DEPLOYS` 설정

### 배포 후
1. **상태 재확인**: `./multi_deploy_control.sh status /path/to/env.env`
2. **헬스체크**: 각 인스턴스 헬스체크 엔드포인트 확인
3. **로그 검증**: 애플리케이션 로그에서 에러 확인

### 트러블슈팅
```bash
# 개별 인스턴스 재배포
cd ../deploy
./deploy_control.sh deploy 2 /path/to/env.env

# 개별 인스턴스 상태 확인
./deploy_control.sh status 2 /path/to/env.env

# 수동 롤백 (백업에서 복원)
mv /instances/2/current.jar.bak /instances/2/current.jar
cd ../run_app
./run_app_control.sh restart 8082
```

## 13. 향후 확장 가능성

### 병렬 배포 (MULTI_DEPLOY_PARALLEL)
```bash
# 2개씩 병렬 배포
for (( i=0; i<target_count; i+=2 )); do
    deploy_instance $i &
    deploy_instance $((i+1)) &
    wait
done
```

### Rolling 배포 (MULTI_DEPLOY_STRATEGY=rolling)
```bash
# 2개씩 롤링 배포
for (( i=0; i<target_count; i+=2 )); do
    deploy_batch "$i" "$((i+1))"
    verify_batch "$i" "$((i+1))"
done
```

### Blue-Green 배포
```bash
# 전체 인스턴스 배포 → 테스트 → Nginx 전환
deploy_all_instances
verify_all_instances
switch_nginx_upstream
```
