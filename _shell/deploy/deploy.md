# deploy.sh 명세서

## 개요
단일 인스턴스의 배포와 제거를 관리하는 핵심 스크립트입니다. 무중단 배포를 위한 전체 프로세스를 오케스트레이션합니다.

## 주요 기능

### 배포 모드 (deploy)
1. **환경 검증**: JAR 트렁크 디렉터리, 인스턴스 디렉터리 확인
2. **트래픽 차단**: Nginx 업스트림에서 해당 포트 비활성화
3. **JAR 백업**: 기존 `current.jar`를 `current.jar.bak`으로 백업
4. **JAR 교체**: 새 JAR 파일로 심볼릭 링크 업데이트
5. **runApp.sh 동기화**: 최신 버전으로 업데이트 및 실행 권한 부여
6. **로그 설정**: 로그 디렉터리 및 심볼릭 링크 구성
7. **애플리케이션 재시작**: 새 JAR로 애플리케이션 실행
8. **테스트 실행**: TEST_SCRIPT 환경변수 지정 시 헬스체크 실행
9. **트래픽 복구**: 테스트 통과 후 Nginx 업스트림 활성화

### 제거 모드 (remove)
1. **애플리케이션 중지**: runApp.sh로 프로세스 종료
2. **트래픽 차단**: Nginx 업스트림에서 포트 비활성화
3. **디렉터리 삭제**: 인스턴스 디렉터리 전체 제거

### 에러 처리
- 각 단계 실패 시 Nginx 업스트림 복구
- runApp.sh 동기화 실패 시 백업 복원
- 테스트 실패 시 배포 중단

## 사용법
```bash
# 배포
./deploy.sh 0 production.env deploy

# 제거
./deploy.sh 0 production.env remove

# 기본값은 deploy
./deploy.sh 0 production.env
```

## 파라미터
1. `<instance_number>`: 배포할 인스턴스 번호 (0-9)
2. `<env_file>`: 환경 설정 파일 경로
3. `[deploy|remove]`: 실행 모드 (기본값: deploy)

## 필수 환경 변수
- `BASE_PORT`: 기본 포트 번호
- `SERVICE_BASE_DIR`: 서비스 베이스 디렉터리
- `SERVICE_NAME`: 서비스명
- `JAR_TRUNK_DIR`: JAR 파일 소스 디렉터리
- `UPSTREAM_CONF`: Nginx 업스트림 설정 파일
- `LOG_BASE_DIR`: 로그 베이스 디렉터리
- `APP_MODE`: 애플리케이션 실행 모드
- `JAVA_OPTS`: Java 실행 옵션
- `TEST_SCRIPT`: 테스트 스크립트 경로 (선택사항)

## 의존성
- common_utils.sh
- controll_nginx.sh
- link_jar.sh
- runApp.sh
- setup_logs.sh

## 호출하는 스크립트
- multi_deploy.sh (다중 인스턴스 배포시)