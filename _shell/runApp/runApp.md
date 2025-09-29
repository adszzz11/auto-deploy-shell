# runApp.sh 명세서

## 개요
Spring Boot 애플리케이션의 프로세스를 관리하는 스크립트입니다. 지정된 포트에서 실행되는 애플리케이션을 시작, 중지, 재시작할 수 있습니다.

## 주요 기능

### 애플리케이션 제어
- **start**: 애플리케이션 시작 (백그라운드 실행)
- **stop**: 애플리케이션 중지 (Graceful Shutdown)
- **restart**: 애플리케이션 재시작

### Graceful Shutdown
1. **SIGTERM(15) 전송**: 애플리케이션에 정상 종료 신호
2. **10초 대기**: 애플리케이션의 정상 종료 대기
3. **SIGKILL(9) 전송**: 강제 종료 (필요시)
4. **5초 대기**: 강제 종료 완료 확인

### 프로세스 식별
- 포트 기반 프로세스 검색: `pgrep -f "java -jar current.jar --server.port=${PORT}"`
- 정확한 패턴 매칭으로 다른 인스턴스와 구분

## 사용법
```bash
# 애플리케이션 시작
./runApp.sh 8080 start "--spring.profiles.active=prod" /path/to/common_utils_dir

# 애플리케이션 중지
./runApp.sh 8080 stop "" /path/to/common_utils_dir

# 애플리케이션 재시작
./runApp.sh 8080 restart "--spring.profiles.active=prod" /path/to/common_utils_dir
```

## 파라미터
1. `<port>`: 애플리케이션이 실행될 포트 번호
2. `[stop|start|restart]`: 실행 모드
3. `[JAVA_OPTS]`: Java 실행 옵션 (Spring Boot 프로파일 등)
4. `<common_utils_dir>`: common_utils.sh가 위치한 디렉터리 경로

## 실행 명령어
```bash
java -jar current.jar --server.port=${PORT} ${JAVA_OPTS}
```

## 의존성
- common_utils.sh
- current.jar (심볼릭 링크)
- pgrep, kill, nohup 명령어

## 호출하는 스크립트
- deploy.sh (배포 과정에서 애플리케이션 재시작용)