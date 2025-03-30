# Shell Script Architecture Overview

## UML Diagram

```mermaid
flowchart TD
  subgraph "환경 설정"
    BASE[base.env - 환경 변수]
  end

  subgraph "공통 유틸리티"
    CU[common_utils.sh - 로그 출력, 인자 검증]
  end

  subgraph "Nginx 및 배포 관련"
    DEP[deploy.sh - 단일 인스턴스 배포]
    CTN[controll_nginx.sh - Nginx 업스트림 제어]
    LJ[link_jar.sh - jar 심볼릭 링크 생성]
    SL[setup_logs.sh - 로그 디렉터리/링크 설정]
    RA[runApp.sh - 애플리케이션 실행/중지/재시작]
  end

  subgraph "다중 배포 및 롤백"
    MD[multi_deploy.sh - 여러 인스턴스 배포]
    RB[rollback.sh - 배포 실패 시 롤백]
  end

  BASE --> DEP
  BASE --> RB
  BASE --> MD
  CU --> DEP
  CU --> CTN
  CU --> LJ
  CU --> SL
  CU --> RA
  CU --> RB
  CU --> MD

  DEP -->|nginx DOWN/up| CTN
  DEP --> LJ
  DEP --> SL
  DEP --> RA

  MD --> DEP
  MD -- 실패 시 롤백 --> RB
  RB --> RA

