# 배포 안내 (Render + TiDB Cloud)

화면과 서버를 Node 서버 하나로 묶어 Render 무료 웹 서비스에 올리고, DB는 MySQL 호환인 TiDB Cloud 무료 플랜을 씁니다.

## 1. DB 만들기 (TiDB Cloud)
1. tidbcloud.com 가입 → Starter(무료) 클러스터 생성
2. 클러스터의 Connect 화면에서 Host, Port(4000), User, Password 확인
3. MySQL Workbench에서 새 연결을 만들고 SSL을 "Require"로 설정해 접속
4. `db/schema.sql` 실행 (today_case DB가 만들어짐)

## 2. 서버 올리기 (Render)
1. render.com 가입 → New → Blueprint → GitHub 저장소 `today-case` 연결
2. `render.yaml`을 읽어 서비스가 만들어지면, 환경 변수에 입력:
   `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `GROQ_API_KEY`
3. 배포가 끝나면 `https://<서비스이름>.onrender.com` 에서 플레이

## 알아둘 점
- 무료 웹 서비스는 15분 동안 접속이 없으면 잠들고, 다음 접속 때 깨어나는 데 1분쯤 걸립니다.
- main에 머지하면 Render가 자동으로 다시 배포합니다.
- 심문(AI 호출)은 IP마다 분당 10번, 하루 200번으로 제한됩니다. `RATE_PER_MINUTE`, `RATE_PER_DAY`로 조정할 수 있습니다.
- 키와 DB 비밀번호는 Render 대시보드에만 넣고 저장소에는 올리지 않습니다.
