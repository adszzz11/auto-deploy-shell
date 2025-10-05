# Link JAR Control Functions Specification

## 개요

JAR 파일에 대한 심볼릭 링크를 관리하는 Bash 기반 시스템입니다. PID 파일 또는 직접 지정을 통해 JAR 파일명을 읽고, 안전하게 심볼릭 링크를 생성/제거하며, 백업 기능을 제공합니다.

## 1. JAR 이름 읽기

### read_jar_name_from_pid(jar_dir, pid_file)
**목적**: PID 파일에서 JAR 파일명 읽기

**파라미터**:
- `jar_dir`: JAR trunk 디렉터리 (필수)
- `pid_file`: PID 파일 경로 (선택, 기본값: `<jar_dir>/current_jar.pid`)

**동작**:
1. PID 파일 존재 확인
2. 파일 내용 읽기 (앞뒤 공백 제거)
3. 비어있지 않은지 확인
4. JAR 파일명 반환

**PID 파일 형식**:
```
app-v1.0.0.jar
```

**구현 예시**:
```bash
# 기본 PID 파일 사용
jar_name=$(read_jar_name_from_pid "/path/to/jar_trunk")

# 커스텀 PID 파일 사용
jar_name=$(read_jar_name_from_pid "/path/to/jar_trunk" "/custom/path/jar.pid")
```

### use_jar_name_directly(jar_name)
**목적**: JAR 파일명 직접 사용 (PID 파일 우회)

**파라미터**:
- `jar_name`: JAR 파일명 (필수)

**동작**:
- JAR 파일명이 비어있지 않은지 확인
- 그대로 반환

## 2. 검증 함수

### validate_jar_name(jar_name, validate_ext)
**목적**: JAR 파일명 유효성 검증

**파라미터**:
- `jar_name`: JAR 파일명 (필수)
- `validate_ext`: 확장자 검증 여부 (선택, 기본값: true)

**검증 항목**:
1. 비어있지 않은가?
2. `.jar` 확장자로 끝나는가? (validate_ext=true인 경우)

**에러 케이스**:
- 빈 문자열: ERROR 반환
- 잘못된 확장자: ERROR 반환 (예: `app.war`, `app.zip`)

### validate_jar_file_exists(jar_dir, jar_name)
**목적**: JAR 파일 실제 존재 확인

**파라미터**:
- `jar_dir`: JAR trunk 디렉터리
- `jar_name`: JAR 파일명

**동작**:
1. `${jar_dir}/${jar_name}` 경로 구성
2. 파일 존재 확인
3. 전체 경로 반환

**반환값**:
- 성공: JAR 파일 전체 경로
- 실패: ERROR 메시지 및 exit 1

### validate_jar_directory(jar_dir)
**목적**: JAR 디렉터리 검증

**검증 항목**:
1. 디렉터리가 존재하는가?
2. 읽기 권한이 있는가?

### validate_target_directory(target_link)
**목적**: 타겟 링크의 디렉터리 검증

**동작**:
1. `dirname` 명령으로 디렉터리 추출
2. 디렉터리 존재 확인
3. 쓰기 권한 확인

## 3. 링크 관리

### remove_existing_link(target_link, backup_enabled, backup_suffix)
**목적**: 기존 링크/파일 제거

**파라미터**:
- `target_link`: 타겟 링크 경로 (필수)
- `backup_enabled`: 백업 활성화 (선택, 기본값: true)
- `backup_suffix`: 백업 파일 접미사 (선택, 기본값: .bak)

**동작 (backup_enabled=true)**:
1. 기존 파일/링크 존재 확인
2. 백업 파일 생성: `mv $target_link ${target_link}.bak`
3. 성공 로그 출력

**동작 (backup_enabled=false)**:
1. 기존 파일/링크 존재 확인
2. 삭제: `rm -f $target_link`
3. 경고 로그 출력

**구현 예시**:
```bash
# 백업과 함께 제거
remove_existing_link "/path/to/current.jar"

# 백업 없이 제거
remove_existing_link "/path/to/current.jar" false

# 커스텀 백업 접미사
remove_existing_link "/path/to/current.jar" true ".backup"
```

### create_symbolic_link(jar_path, target_link, verify)
**목적**: 심볼릭 링크 생성

**파라미터**:
- `jar_path`: 실제 JAR 파일 경로 (필수)
- `target_link`: 생성할 링크 경로 (필수)
- `verify`: 링크 검증 여부 (선택, 기본값: true)

**동작**:
1. `ln -s $jar_path $target_link` 실행
2. 성공 로그 출력
3. (verify=true) 생성된 링크 검증

**검증 방법**:
- `[ -L "$target_link" ]`: 심볼릭 링크인가?
- `[ -e "$target_link" ]`: 타겟이 존재하는가?

**구현 예시**:
```bash
# 검증과 함께 생성
create_symbolic_link "/path/to/jar_trunk/app-v1.0.jar" "/path/to/current.jar"

# 검증 없이 생성
create_symbolic_link "/path/to/jar_trunk/app-v1.0.jar" "/path/to/current.jar" false
```

### get_link_info(target_link)
**목적**: 링크 정보 조회

**출력 정보**:
- 타입: Symbolic Link / Regular File / Not found
- 링크 경로
- 타겟 경로 (심볼릭 링크인 경우)
- 상태: Valid / Broken (심볼릭 링크인 경우)

**구현 예시**:
```bash
./link_jar_control.sh info /path/to/current.jar

# 출력 예시:
# Type: Symbolic Link
# Link: /path/to/current.jar
# Target: /path/to/jar_trunk/app-v1.0.jar
# Status: Valid (target exists)
```

## 4. 환경 설정 (link_jar.env)

```bash
# PID 파일명
export LINK_JAR_PID_FILE="current_jar.pid"

# 타겟 링크 파일명 (기본값)
export LINK_JAR_TARGET_NAME="current.jar"

# JAR 파일 검증 옵션
export LINK_JAR_VALIDATE_EXTENSION="true"

# 백업 옵션
export LINK_JAR_BACKUP_ENABLED="true"
export LINK_JAR_BACKUP_SUFFIX=".bak"

# 심볼릭 링크 검증 옵션
export LINK_JAR_VERIFY_LINK="true"

# 로그 레벨
export LINK_JAR_LOG_LEVEL="INFO"
```

## 5. 배포 워크플로우에서의 사용

### 무중단 배포 시나리오
```bash
# 1. 기존 JAR 백업 (자동)
./link_jar_control.sh link /path/to/jar_trunk /path/to/instances/0/current.jar

# 심볼릭 링크:
# /path/to/instances/0/current.jar -> /path/to/jar_trunk/app-v2.0.jar
# 백업:
# /path/to/instances/0/current.jar.bak -> /path/to/jar_trunk/app-v1.0.jar

# 2. 애플리케이션 재시작
./run_app_control.sh restart 8080
```

### 롤백 시나리오
```bash
# 1. 백업 파일 복원
mv /path/to/instances/0/current.jar.bak /path/to/instances/0/current.jar

# 2. 애플리케이션 재시작
./run_app_control.sh restart 8080
```

### 특정 버전 지정 배포
```bash
# PID 파일 대신 직접 JAR 이름 지정
./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar app-v1.5.0.jar
```

## 6. CLI 사용법

### link_jar_control.sh - 메인 진입점

```bash
# PID 파일에서 JAR 이름 읽어서 링크 생성
./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar

# 특정 JAR 파일로 링크 생성 (PID 파일 무시)
./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar app-v2.0.jar

# 커스텀 PID 파일 사용
./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar /custom/jar.pid

# 링크 제거 (백업 포함)
./link_jar_control.sh unlink /path/to/current.jar

# 링크 제거 (백업 없음)
./link_jar_control.sh unlink /path/to/current.jar false

# 링크 정보 조회
./link_jar_control.sh info /path/to/current.jar

# JAR 파일 검증
./link_jar_control.sh validate /path/to/jar_trunk app-v1.0.jar

# PID 파일에서 JAR 이름 읽기만
./link_jar_control.sh read-pid /path/to/jar_trunk
```

## 7. PID 파일 구조

### current_jar.pid 형식
```
app-service-v1.0.0.jar
```

**규칙**:
- 한 줄에 JAR 파일명만 기재
- 앞뒤 공백은 자동 제거됨
- `.jar` 확장자 필수 (검증 활성화 시)

### PID 파일 생성 예시
```bash
# 새 JAR 배포 시 PID 파일 업데이트
echo "app-service-v2.0.0.jar" > /path/to/jar_trunk/current_jar.pid

# 링크 생성
./link_jar_control.sh link /path/to/jar_trunk /path/to/current.jar
```

## 8. 에러 처리

### PID 파일 오류
1. **파일 없음**: `[ERROR] PID file not found at <path>`
2. **빈 파일**: `[ERROR] No jar name found in <path>`

### JAR 검증 오류
1. **잘못된 이름**: `[ERROR] JAR name is empty`
2. **잘못된 확장자**: `[ERROR] Invalid jar name '<name>'. Expected a file ending with .jar`
3. **파일 없음**: `[ERROR] JAR file not found: <path>`

### 디렉터리 오류
1. **디렉터리 없음**: `[ERROR] JAR directory not found: <path>`
2. **권한 없음**: `[ERROR] JAR directory not readable: <path>`
3. **타겟 디렉터리 없음**: `[ERROR] Target directory does not exist: <path>`
4. **쓰기 권한 없음**: `[ERROR] Target directory not writable: <path>`

### 링크 생성 오류
1. **링크 실패**: `[ERROR] Failed to create symbolic link`
2. **검증 실패**: `[ERROR] Symbolic link verification failed: <path>`
3. **백업 실패**: `[ERROR] Failed to backup existing file`

## 9. 백업 관리

### 자동 백업 (기본 동작)
```bash
# 기존 파일: /path/to/current.jar -> app-v1.0.jar
./link_jar_control.sh link /jar_trunk /path/to/current.jar app-v2.0.jar

# 결과:
# /path/to/current.jar     -> app-v2.0.jar (새 링크)
# /path/to/current.jar.bak -> app-v1.0.jar (백업)
```

### 백업 비활성화
```bash
# link_jar.env에서 설정
export LINK_JAR_BACKUP_ENABLED="false"

# 또는 unlink 시 파라미터로 지정
./link_jar_control.sh unlink /path/to/current.jar false
```

### 백업 접미사 커스터마이징
```bash
# link_jar.env에서 설정
export LINK_JAR_BACKUP_SUFFIX=".backup.$(date +%Y%m%d)"

# 결과: current.jar.backup.20241003
```

## 10. 파일 구조

```
renew/link_jar/
├── link_jar.env             # 환경 변수 설정
├── link_jar_control.sh      # 메인 CLI 스크립트
├── SPEC.md                  # 명세 문서
└── func/                    # 함수 스크립트들
    ├── read_jar_name.sh         # JAR 이름 읽기
    ├── validate_jar.sh          # JAR 검증
    └── manage_link.sh           # 링크 관리
```

## 11. 기존 시스템과의 차이점

### pre/link_jar.sh (레거시)
- 3개 필수 파라미터 (service_name, target_link, jar_trunk_dir)
- PID 파일만 지원 (직접 JAR 지정 불가)
- 백업 기능 없음
- 하드코딩된 검증 로직

### renew/link_jar (신규)
- 환경 변수 기반 설정 (link_jar.env)
- 선택적 파라미터 지원
- PID 파일 또는 직접 JAR 이름 지정 가능
- 자동 백업 기능 내장
- 구조화된 검증 함수
- 링크 정보 조회 기능
- 모듈형 함수 구조

## 12. 테스트 시나리오

### 단위 테스트
```bash
# 1. PID 파일에서 읽기 테스트
echo "test-app-v1.0.jar" > /tmp/jar_trunk/current_jar.pid
./link_jar_control.sh read-pid /tmp/jar_trunk
# 출력: test-app-v1.0.jar

# 2. JAR 검증 테스트
touch /tmp/jar_trunk/test-app-v1.0.jar
./link_jar_control.sh validate /tmp/jar_trunk test-app-v1.0.jar
# 결과: 모든 검증 통과

# 3. 링크 생성 테스트
./link_jar_control.sh link /tmp/jar_trunk /tmp/current.jar
# 결과: 심볼릭 링크 생성 성공

# 4. 링크 정보 조회
./link_jar_control.sh info /tmp/current.jar
# 출력: Type, Link, Target, Status
```

### 통합 테스트
```bash
# 전체 워크플로우 테스트
export LINK_JAR_BACKUP_ENABLED="true"

# 1. 초기 링크 생성
echo "app-v1.0.jar" > /jar_trunk/current_jar.pid
touch /jar_trunk/app-v1.0.jar
./link_jar_control.sh link /jar_trunk /instance/current.jar

# 2. 새 버전으로 업데이트
echo "app-v2.0.jar" > /jar_trunk/current_jar.pid
touch /jar_trunk/app-v2.0.jar
./link_jar_control.sh link /jar_trunk /instance/current.jar

# 3. 백업 확인
ls -la /instance/current.jar*
# 출력: current.jar -> app-v2.0.jar
#      current.jar.bak -> app-v1.0.jar
```

## 13. 보안 고려사항

### 심볼릭 링크 공격 방지
- 타겟 디렉터리 쓰기 권한 검증
- 링크 생성 전 기존 링크 확인 및 백업
- 링크 검증을 통한 broken link 방지

### 권한 관리
- JAR 디렉터리 읽기 권한 필요
- 타겟 디렉터리 쓰기 권한 필요
- PID 파일 읽기 권한 필요
