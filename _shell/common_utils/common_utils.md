# common_utils.sh 명세서

## 개요
모든 배포 스크립트에서 공통으로 사용하는 유틸리티 함수들을 제공하는 라이브러리 스크립트입니다.

## 주요 기능

### 로깅 함수
- `current_timestamp()`: 현재 날짜와 시간을 "YYYY-MM-DD HH:MM:SS" 형식으로 반환
- `log_info(message)`: 정보성 메시지를 "[INFO] 타임스탬프 - 메시지" 형식으로 출력
- `log_warn(message)`: 경고 메시지를 "[WARN] 타임스탬프 - 메시지" 형식으로 출력
- `log_success(message)`: 성공 메시지를 "[SUCCESS] 타임스탬프 - 메시지" 형식으로 출력
- `error_exit(message)`: 에러 메시지를 "[ERROR] 타임스탬프 - 메시지" 형식으로 stderr에 출력 후 종료

## 사용법
```bash
source "$(dirname "$0")/common_utils.sh"

log_info "애플리케이션 시작"
log_warn "설정 파일이 없습니다"
log_success "배포 완료"
error_exit "치명적인 오류 발생"
```

## 의존성
- bash
- date 명령어

## 호출하는 스크립트
- deploy.sh
- controll_nginx.sh
- multi_deploy.sh
- 기타 모든 _shell/ 디렉터리의 스크립트들