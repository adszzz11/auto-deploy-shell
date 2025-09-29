# rollback.sh 명세서

## 개요
배포 실패 시 이전 버전의 JAR 파일로 롤백하는 스크립트입니다. 백업된 JAR 파일을 복원하고 애플리케이션을 재시작합니다.

## 주요 기능

### 롤백 프로세스
1. **백업 파일 확인**: `current.jar.bak` 파일 존재 여부 검증
2. **현재 JAR 제거**: 문제가 있는 `current.jar` 파일 삭제
3. **백업 복원**: `current.jar.bak` → `current.jar`로 이름 변경
4. **애플리케이션 재시작**: 복원된 JAR로 서비스 재시작

### 안전성 보장
- 환경 설정 파일 검증
- 백업 파일 존재 확인
- 각 단계별 에러 처리

## 사용법
```bash
./rollback.sh 0 production.env
```

## 파라미터
1. `<instance_number>`: 롤백할 인스턴스 번호
2. `<env_file>`: 환경 설정 파일 경로

## 롤백 조건
- `current.jar.bak` 백업 파일이 존재해야 함
- `runApp.sh`가 인스턴스 디렉터리에 존재해야 함 (애플리케이션 재시작용)

## 복원되는 파일
- `current.jar.bak` → `current.jar`

## 의존성
- common_utils.sh
- runApp.sh (애플리케이션 재시작용)

## 필수 환경 변수
- `BASE_PORT`: 기본 포트 번호
- `SERVICE_BASE_DIR`: 서비스 베이스 디렉터리
- `SERVICE_NAME`: 서비스명
- `APP_MODE`: 애플리케이션 실행 모드
- `JAVA_OPTS`: Java 실행 옵션

## 호출하는 스크립트
- multi_deploy.sh (배포 실패 시 자동 롤백)
- 수동 롤백 시 직접 실행

## 주의사항
- Nginx 업스트림 제어는 포함되지 않음 (호출하는 스크립트에서 처리)
- 롤백 후 수동으로 헬스체크 권장