# controll_nginx.sh 명세서

## 개요
Nginx 업스트림 설정을 동적으로 제어하여 특정 포트의 서버를 활성화(up) 또는 비활성화(down)하는 스크립트입니다.

## 주요 기능

### 업스트림 제어
- **UP 모드**: 지정된 포트의 서버를 활성화
  - 기존에 주석 처리된 서버 라인의 주석 제거
  - 해당 포트가 설정에 없으면 새로 추가
- **DOWN 모드**: 지정된 포트의 서버를 비활성화 (주석 처리)

### 안전성 검증
- Nginx 설정 파일 존재 여부 확인
- nginx 명령어 설치 여부 확인
- 설정 변경 후 문법 검증 (`nginx -t`)
- 설정 리로드 (`nginx -s reload`)

## 사용법
```bash
# 포트 8080 서버 비활성화
./controll_nginx.sh 8080 /etc/nginx/conf.d/upstream.conf down

# 포트 8080 서버 활성화
./controll_nginx.sh 8080 /etc/nginx/conf.d/upstream.conf up
```

## 파라미터
1. `<port>`: 제어할 서버의 포트 번호
2. `<upstream_conf>`: Nginx 업스트림 설정 파일 경로
3. `<up|down>`: 서버 활성화(up) 또는 비활성화(down)

## 의존성
- nginx 명령어
- sed 명령어
- common_utils.sh

## 호출하는 스크립트
- deploy.sh (배포 시 트래픽 차단/복구용)