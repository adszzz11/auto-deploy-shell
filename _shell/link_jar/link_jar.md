# link_jar.sh 명세서

## 개요
JAR 트렁크 디렉터리에서 배포할 JAR 파일을 찾아 인스턴스 디렉터리에 심볼릭 링크를 생성하는 스크립트입니다.

## 주요 기능

### JAR 파일 링크 생성
- `current_jar.pid` 파일에서 배포할 JAR 파일명 읽기
- JAR 파일 존재 여부 확인
- 기존 심볼릭 링크 제거
- 새로운 심볼릭 링크 생성 (`current.jar` → 실제 JAR 파일)

### 검증 과정
- JAR 트렁크 디렉터리 존재 확인
- `current_jar.pid` 파일 존재 확인
- JAR 파일명이 `.jar` 확장자로 끝나는지 검증
- 실제 JAR 파일 존재 확인
- 타겟 디렉터리 존재 확인

## 사용법
```bash
./link_jar.sh service_name /path/to/instance/current.jar /path/to/jar_trunk
```

## 파라미터
1. `<service_name>`: 서비스명 (현재는 로깅용으로만 사용)
2. `<target_link_path>`: 생성할 심볼릭 링크의 전체 경로
3. `<jar_trunk_dir>`: JAR 파일들이 저장된 트렁크 디렉터리

## 의존성
- common_utils.sh
- sed, ln 명령어

## 관련 파일
- `current_jar.pid`: 배포할 JAR 파일명이 기록된 파일

## 호출하는 스크립트
- deploy.sh (배포 과정에서 JAR 교체용)