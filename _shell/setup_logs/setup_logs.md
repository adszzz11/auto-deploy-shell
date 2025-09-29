# setup_logs.sh 명세서

## 개요
애플리케이션 인스턴스별 로그 디렉터리를 설정하고 심볼릭 링크를 생성하는 스크립트입니다.

## 주요 기능

### 로그 디렉터리 구조 생성
- 로그 베이스 디렉터리 하위에 서비스별/인스턴스별 디렉터리 생성
- 구조: `${LOG_BASE_DIR}/${SERVICE_NAME}/instances/${INSTANCE_NUM}`

### 심볼릭 링크 생성
- 인스턴스 디렉터리에서 로그 디렉터리로의 심볼릭 링크 생성
- 링크 경로: `${INSTANCE_DIR}/logs` → `${LOG_SOURCE_DIR}`

### 검증 과정
- 기존 로그 링크/파일 제거
- 새 심볼릭 링크 생성
- 생성된 링크의 정확성 검증 (`readlink` 사용)

## 사용법
```bash
./setup_logs.sh service_name 0 /path/to/instance/0 /path/to/log_base
```

## 파라미터
1. `<service_name>`: 서비스명
2. `<instance_num>`: 인스턴스 번호
3. `<instance_dir>`: 인스턴스 디렉터리 경로
4. `<log_base_dir>`: 로그 베이스 디렉터리 경로

## 생성되는 구조
```
LOG_BASE_DIR/
└── SERVICE_NAME/
    └── instances/
        └── INSTANCE_NUM/
            └── (로그 파일들)

INSTANCE_DIR/
└── logs -> LOG_BASE_DIR/SERVICE_NAME/instances/INSTANCE_NUM
```

## 의존성
- common_utils.sh
- mkdir, ln, readlink 명령어

## 호출하는 스크립트
- deploy.sh (배포 과정에서 로그 디렉터리 설정용)