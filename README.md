# 오늘의 사건

AI가 연기하는 용의자를 심문하고, 현장을 조사하고, 범인을 지목하는 웹 머더미스터리 게임.
DB 설계 과제에서 만든 MySQL 스키마(`db/schema.sql`)를 그대로 사용합니다.

## 구성

| 폴더 | 내용 |
|---|---|
| `client/` | React + TypeScript (Vite). 사건 선택, 심문 채팅, 현장 조사·단서 보드, 범인 지목, 결과 공개 |
| `server/` | Node + Express + TypeScript. MySQL 조회, Claude API로 용의자 대사 생성 |
| `db/schema.sql` | 17개 테이블 + 예시 사건 "별장의 마지막 밤" |

## 실행

1. MySQL Workbench(또는 `mysql` 명령)로 `db/schema.sql`을 실행해 `today_case` DB를 만듭니다.
2. 서버 환경 변수:
   ```bash
   cp server/.env.example server/.env
   # DB_PASSWORD, ANTHROPIC_API_KEY 채우기 (키가 없으면 모의 모드로 동작)
   ```
3. 설치 후 실행:
   ```bash
   npm install
   npm run dev
   ```
   브라우저에서 http://localhost:5173 을 엽니다. 서버는 3001번 포트.

## 게임 흐름과 DB

| 행동 | 쓰는 테이블 |
|---|---|
| 수사 시작 | `member`(게스트), `play`, `participant`(탐정) |
| 현장 조사 | `clue` → `clue_discovery` (그 현장의 물증·기록) |
| 심문 | `interrogation` 저장. 프롬프트는 `game_character`, `character_relation`, `character_fact`(숨긴 사실), `alibi`(거짓 여부)로 구성. 그 인물의 증언 단서도 발견 처리 |
| 범인 지목 | `accusation`, `play.result`, 진상(`case_file.truth`)과 전체 `fact` 타임라인 공개 |

범인 여부, 진상, 숨긴 사실은 지목 전까지 클라이언트로 보내지 않습니다.

## 다음 할 일

- 자동 정렬 타임라인 (`timeline_entry`)
- 1인 범인 모드: 플레이어가 범인 역, AI 탐정이 심문 (`hint` 사용)
- 사건 추가, 회원가입·전적 (`vw_Record`)
- 배포
