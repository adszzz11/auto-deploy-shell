# test_instance.sh 명세서

## 개요
배포된 인스턴스의 정상 동작 여부를 검증하는 헬스체크 스크립트입니다. HTTP 응답 상태를 확인하여 배포 성공 여부를 판단합니다.

## 주요 기능

### HTTP 헬스체크
- 지정된 포트의 애플리케이션에 HTTP 요청 전송
- 응답 상태 코드 검증 (200 OK 기대)
- 커스터마이즈 가능한 엔드포인트 검증

### 테스트 결과 판정
- 모든 테스트 통과: exit code 0
- 하나라도 실패: exit code 1

### 현재 구현된 테스트
- **API 엔드포인트 테스트**: `/api/v1/global/commoncode/TX_DVCD/WDL`
- **HTTP 상태 코드 검증**: 200 OK 응답 확인

## 사용법
```bash
# 포트 8080에서 실행 중인 인스턴스 테스트
./test_instance.sh 8080

# 다른 포트의 인스턴스 테스트
./test_instance.sh 8081
```

## 파라미터
1. `<port>`: 테스트할 인스턴스의 포트 번호

## 테스트 커스터마이징
스크립트 내부의 `#===============================================================` 구간에서 테스트를 수정할 수 있습니다:

```bash
# 예시: 다른 엔드포인트 테스트
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/health")

# 예시: TCP 연결 테스트 추가
if nc -z localhost "$PORT"; then
  echo "TCP connection test passed"
else
  echo "TCP connection test failed"
  FAIL=1
fi
```

## 실패 처리
- `FAIL` 변수를 1로 설정하여 테스트 실패 표시
- 최종 exit code로 성공/실패 상태 반환

## 의존성
- curl 명령어
- 선택사항: nc (netcat) - TCP 연결 테스트용

## 호출하는 스크립트
- deploy.sh (TEST_SCRIPT 환경변수로 지정된 경우)
- 수동 헬스체크 시 직접 실행

## 테스트 대상
- Spring Boot 애플리케이션의 REST API 엔드포인트
- HTTP 응답 상태 코드
- 확장 가능: TCP 연결, 응답 시간, 콘텐츠 검증 등

## 로깅
- 각 테스트의 성공/실패 상태 출력
- 최종 결과 요약 출력

## 주의사항
- 애플리케이션 시작 후 초기화 시간을 고려하여 충분한 대기 후 실행
- 네트워크 방화벽 설정에 따라 localhost 접근 가능 여부 확인 필요