-- 오늘의 사건 게임 DB (DB 설계 과제 스키마 그대로 사용)
-- MySQL 8.0

SET NAMES utf8mb4;

-- 다시 실행해도 회원 계정과 로그인은 남는다 (member, login_session은 지우지 않음).
-- 사건 데이터와 플레이 기록은 지우고 새로 만든다.
CREATE DATABASE IF NOT EXISTS today_case DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE today_case;

SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW IF EXISTS vw_Suspect, vw_Record;
DROP TABLE IF EXISTS
    truth_question,
    suspect_mark,
    accusation_evidence,
    accusation,
    timeline_entry,
    memo,
    link_attempt,
    spot_search,
    clue_discovery,
    interrogation,
    evidence_answer,
    basic_answer,
    participant,
    play,
    hint,
    relation_stage,
    deduction_clue,
    deduction,
    clue,
    spot,
    alibi,
    character_fact,
    fact,
    character_relation,
    game_character,
    scene,
    autopsy,
    case_file;
SET FOREIGN_KEY_CHECKS = 1;


/* 1. 테이블 생성 */

-- 회원
CREATE TABLE IF NOT EXISTS member (
    member_id VARCHAR(20) NOT NULL,
    password VARCHAR(255) NOT NULL,
    nickname VARCHAR(30) NOT NULL,
    joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id),
    UNIQUE KEY uq_member_nickname (nickname)
);

-- 사건 (CASE는 예약어라 case_file)
CREATE TABLE case_file (
    case_id INT NOT NULL AUTO_INCREMENT,
    title VARCHAR(100) NOT NULL,
    genre VARCHAR(30) NOT NULL,
    difficulty ENUM('쉬움', '보통', '어려움') NOT NULL,
    summary TEXT NOT NULL,
    truth TEXT NOT NULL,
    investigation_limit INT NOT NULL DEFAULT 12,  -- 조사 횟수 (조사 지점을 열 때마다 1회. 단서 연결은 무료)
    map_url VARCHAR(255),                          -- 건물 단면도 그림
    PRIMARY KEY (case_id),
    CONSTRAINT chk_case_limit CHECK (investigation_limit > 0)
);

-- 검시 기록 (사건과 1:1, 게임 시작 때 모두에게 공개되는 시신 정보)
CREATE TABLE autopsy (
    case_id INT NOT NULL,
    found_time TIME NOT NULL,
    found_place VARCHAR(100) NOT NULL,  -- 발견 위치와 자세
    found_by VARCHAR(30),
    cause VARCHAR(255) NOT NULL,        -- 사인
    wound VARCHAR(255),                 -- 상처
    death_estimate VARCHAR(255),        -- 추정 사망 시각
    weapon VARCHAR(255),                -- 현장에서 흉기로 보이는 것
    note VARCHAR(255),                  -- 함께 알려진 사실
    PRIMARY KEY (case_id),
    CONSTRAINT fk_autopsy_case FOREIGN KEY (case_id)
        REFERENCES case_file (case_id) ON DELETE CASCADE
);

-- 사건 현장
CREATE TABLE scene (
    scene_id INT NOT NULL AUTO_INCREMENT,
    case_id INT NOT NULL,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),          -- 현장 그림 (조사 지점을 그 위에 찍는다)
    map_x DECIMAL(5,2),              -- 단면도에서 이 장소가 차지하는 칸 (그림 크기 대비 %)
    map_y DECIMAL(5,2),
    map_w DECIMAL(5,2),
    map_h DECIMAL(5,2),
    PRIMARY KEY (scene_id),
    CONSTRAINT fk_scene_case FOREIGN KEY (case_id)
        REFERENCES case_file (case_id) ON DELETE CASCADE
);

-- 등장인물 (CHARACTER는 예약어라 game_character)
CREATE TABLE game_character (
    character_id INT NOT NULL AUTO_INCREMENT,
    case_id INT NOT NULL,
    name VARCHAR(30) NOT NULL,
    age INT,
    gender ENUM('남', '여'),
    job VARCHAR(30),
    personality VARCHAR(100),
    backstory TEXT,  -- 숨겨진 과거와 동기 (AI만 읽음)
    cover_story TEXT,  -- 범인만: 미리 짜 둔 거짓 이야기 (AI만 읽음)
    fallback_story TEXT,  -- 범인만: 처음 이야기가 깨지면 물러설 두 번째 이야기 (AI만 읽음)
    fallback_clue_ids VARCHAR(100),  -- 이 단서들 중 하나를 범인에게 제시하면 두 번째 이야기로 넘어간다 (쉼표로 구분)
    fallback_guard TEXT,  -- 두 번째 이야기 중에 나오면 안 되는 말 (정규식, 줄마다 하나). 걸리면 답을 한 번 다시 받는다
    fallback_admit VARCHAR(255),  -- 범인이 스스로 두 번째 이야기를 꺼냈는지 알아보는 말 (정규식). 한 번 꺼내면 두 번째 이야기로 넘어간다
    image_url VARCHAR(255),  -- 얼굴 그림 (없으면 이름 글자로 표시)
    character_type ENUM('피해자', '용의자', '목격자') NOT NULL,
    is_culprit BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (character_id),
    CONSTRAINT fk_character_case FOREIGN KEY (case_id)
        REFERENCES case_file (case_id) ON DELETE CASCADE,
    CONSTRAINT chk_character_age CHECK (age IS NULL OR age >= 0)
);

-- 인물 관계 (N:M, 자기 참조)
CREATE TABLE character_relation (
    character_a_id INT NOT NULL,
    character_b_id INT NOT NULL,
    relation_type VARCHAR(20) NOT NULL,
    description VARCHAR(255),
    PRIMARY KEY (character_a_id, character_b_id),
    -- CHECK에 쓰인 열이라 CASCADE 대신 기본값(RESTRICT)
    CONSTRAINT fk_relation_a FOREIGN KEY (character_a_id)
        REFERENCES game_character (character_id),
    CONSTRAINT fk_relation_b FOREIGN KEY (character_b_id)
        REFERENCES game_character (character_id),
    CONSTRAINT chk_relation_self CHECK (character_a_id <> character_b_id)
);

-- 사실 (실제 사건 타임라인)
CREATE TABLE fact (
    fact_id INT NOT NULL AUTO_INCREMENT,
    case_id INT NOT NULL,
    occurred_at TIME NOT NULL,
    place VARCHAR(50),
    content VARCHAR(255) NOT NULL,
    is_initial BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (fact_id),
    CONSTRAINT fk_fact_case FOREIGN KEY (case_id)
        REFERENCES case_file (case_id) ON DELETE CASCADE
);

-- 앎 (등장인물 N:M 사실)
CREATE TABLE character_fact (
    character_id INT NOT NULL,
    fact_id INT NOT NULL,
    is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (character_id, fact_id),
    CONSTRAINT fk_cf_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE CASCADE,
    CONSTRAINT fk_cf_fact FOREIGN KEY (fact_id)
        REFERENCES fact (fact_id) ON DELETE CASCADE
);

-- 알리바이
CREATE TABLE alibi (
    alibi_id INT NOT NULL AUTO_INCREMENT,
    character_id INT NOT NULL,
    claimed_time TIME NOT NULL,
    place VARCHAR(50) NOT NULL,
    statement VARCHAR(255) NOT NULL,
    is_false BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (alibi_id),
    CONSTRAINT fk_alibi_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE CASCADE
);

-- 조사 지점 (장소 안에서 조사할 곳. 열 때마다 조사 1회)
CREATE TABLE spot (
    spot_id INT NOT NULL AUTO_INCREMENT,
    scene_id INT NOT NULL,
    name VARCHAR(50) NOT NULL,
    unlock_clue_id INT NULL,                 -- 2차 조사: 이 단서를 찾아야 열 수 있음
    unlock_deduction_id INT NULL,            -- 2차 조사: 이 추론을 얻어야 열 수 있음
    lock_hint VARCHAR(255) NULL,             -- 잠겨 있을 때 보여 주는 한 줄 힌트 (방향만)
    pos_x DECIMAL(5,2),                      -- 현장 그림 위 위치 (가로 %, 세로 %)
    pos_y DECIMAL(5,2),
    PRIMARY KEY (spot_id),
    CONSTRAINT fk_spot_scene FOREIGN KEY (scene_id)
        REFERENCES scene (scene_id) ON DELETE CASCADE
);

-- 단서
CREATE TABLE clue (
    clue_id INT NOT NULL AUTO_INCREMENT,
    scene_id INT NOT NULL,
    spot_id INT NULL,                        -- 물증·기록이 놓인 조사 지점 (증언은 NULL)
    character_id INT NULL,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),
    clue_type ENUM('물증', '증언', '기록') NOT NULL,
    is_key BOOLEAN NOT NULL DEFAULT FALSE,   -- 결과 화면의 '결정적 증거/증언'
    event_time TIME NULL,                    -- 단서가 가리키는 시각 (발견하면 타임라인에 올라감)
    unlock_clue_id INT NULL,                 -- 숨은 증언: 이 단서를 증거로 내밀어야만 털어놓음
    is_filler BOOLEAN NOT NULL DEFAULT FALSE, -- 별 쓸모없는 단서: 단서 탭에는 뜨지만 연결(추론)에는 쓸 수 없다
    PRIMARY KEY (clue_id),
    CONSTRAINT fk_clue_scene FOREIGN KEY (scene_id)
        REFERENCES scene (scene_id) ON DELETE CASCADE,
    CONSTRAINT fk_clue_spot FOREIGN KEY (spot_id)
        REFERENCES spot (spot_id) ON DELETE SET NULL,
    CONSTRAINT fk_clue_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE SET NULL,
    CONSTRAINT fk_clue_unlock FOREIGN KEY (unlock_clue_id)
        REFERENCES clue (clue_id) ON DELETE SET NULL
);

ALTER TABLE spot ADD CONSTRAINT fk_spot_unlock FOREIGN KEY (unlock_clue_id)
    REFERENCES clue (clue_id) ON DELETE SET NULL;

-- 추론 (단서 2개를 연결해야 얻는 사실)
CREATE TABLE deduction (
    deduction_id INT NOT NULL AUTO_INCREMENT,
    case_id INT NOT NULL,
    name VARCHAR(50) NOT NULL,
    description VARCHAR(500) NOT NULL,
    proof_role ENUM('알리바이', '연결') NULL,  -- 범인 지목 근거: 알리바이를 깨는 추론 / 범인과 범행을 잇는 추론
    proof_note VARCHAR(255) NULL,            -- 결과 화면에서 이 추론이 근거로 왜 맞는지·부족한지 설명
    reveal_clue_id INT NULL,                 -- 이 추론을 얻으면 바로 손에 들어오는 단서 (잠긴 노트북을 열면 나오는 기록 등)
    PRIMARY KEY (deduction_id),
    CONSTRAINT fk_deduction_case FOREIGN KEY (case_id)
        REFERENCES case_file (case_id) ON DELETE CASCADE,
    CONSTRAINT fk_deduction_reveal FOREIGN KEY (reveal_clue_id)
        REFERENCES clue (clue_id) ON DELETE SET NULL
);

ALTER TABLE spot ADD CONSTRAINT fk_spot_unlock_deduction FOREIGN KEY (unlock_deduction_id)
    REFERENCES deduction (deduction_id) ON DELETE SET NULL;

-- 추론 재료 (추론 N:M 단서)
CREATE TABLE deduction_clue (
    deduction_id INT NOT NULL,
    clue_id INT NOT NULL,
    PRIMARY KEY (deduction_id, clue_id),
    CONSTRAINT fk_dc_deduction FOREIGN KEY (deduction_id)
        REFERENCES deduction (deduction_id) ON DELETE CASCADE,
    CONSTRAINT fk_dc_clue FOREIGN KEY (clue_id)
        REFERENCES clue (clue_id) ON DELETE CASCADE
);

-- 인물 관계도의 단계 (인물 관계 1:N). 어떤 단서나 추론을 찾으면 관계도 선이 생기거나 바뀐다
CREATE TABLE relation_stage (
    stage_id INT NOT NULL AUTO_INCREMENT,
    character_a_id INT NOT NULL,
    character_b_id INT NOT NULL,
    stage_order INT NOT NULL,                -- 클수록 나중 단계 (찾은 것 중 가장 큰 단계를 그린다)
    label VARCHAR(40) NOT NULL,              -- 선 위에 쓰는 짧은 말
    tone ENUM('관계', '갈등', '불확실') NOT NULL,  -- 흰 선 / 빨간 선 / 점선
    clue_id INT NULL,                        -- 이 단서를 찾으면 보인다
    deduction_id INT NULL,                   -- 이 추론을 얻으면 보인다 (둘 다 NULL이면 처음부터)
    PRIMARY KEY (stage_id),
    UNIQUE KEY uq_relation_stage (character_a_id, character_b_id, stage_order),
    CONSTRAINT fk_rs_relation FOREIGN KEY (character_a_id, character_b_id)
        REFERENCES character_relation (character_a_id, character_b_id) ON DELETE CASCADE,
    CONSTRAINT fk_rs_clue FOREIGN KEY (clue_id)
        REFERENCES clue (clue_id) ON DELETE CASCADE,
    CONSTRAINT fk_rs_deduction FOREIGN KEY (deduction_id)
        REFERENCES deduction (deduction_id) ON DELETE CASCADE
);

-- 힌트 (범인 역할 플레이어용 / AI 범인의 변명 계획)
CREATE TABLE hint (
    hint_id INT NOT NULL AUTO_INCREMENT,
    character_id INT NOT NULL,
    content VARCHAR(255) NOT NULL,
    reveal_order INT NOT NULL,
    PRIMARY KEY (hint_id),
    UNIQUE KEY uq_hint_order (character_id, reveal_order),
    CONSTRAINT fk_hint_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE CASCADE
);

-- 플레이 (한 판)
CREATE TABLE play (
    play_id INT NOT NULL AUTO_INCREMENT,
    case_id INT NOT NULL,
    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at DATETIME NULL,
    mode ENUM('1인', '멀티') NOT NULL,
    status ENUM('진행중', '종료') NOT NULL DEFAULT '진행중',
    result ENUM('성공', '실패') NULL,
    PRIMARY KEY (play_id),
    CONSTRAINT fk_play_case FOREIGN KEY (case_id)
        REFERENCES case_file (case_id),
    CONSTRAINT chk_play_time CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- 참가자 (member_id가 NULL이면 AI)
CREATE TABLE participant (
    participant_id INT NOT NULL AUTO_INCREMENT,
    play_id INT NOT NULL,
    member_id VARCHAR(20) NULL,
    character_id INT NULL,
    role ENUM('탐정', '용의자') NOT NULL,
    unlimited BOOLEAN NOT NULL DEFAULT FALSE,  -- 조사 횟수를 다 쓴 뒤 「조사 무제한」을 켰는지
    PRIMARY KEY (participant_id),
    CONSTRAINT fk_participant_play FOREIGN KEY (play_id)
        REFERENCES play (play_id) ON DELETE CASCADE,
    CONSTRAINT fk_participant_member FOREIGN KEY (member_id)
        REFERENCES member (member_id) ON DELETE SET NULL,
    CONSTRAINT fk_participant_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id)
);

-- 기본 질문의 정해진 답 (AI를 부르지 않는다. 범인은 물러선 이야기로 넘어가면 '물러섬' 답을 쓴다)
CREATE TABLE basic_answer (
    character_id INT NOT NULL,
    topic ENUM('알리바이', '관계', '목격') NOT NULL,  -- 그 시간에 어디 있었는지 / 피해자와의 관계 / 이상한 걸 봤는지
    stage ENUM('처음', '물러섬') NOT NULL DEFAULT '처음',
    answer TEXT NOT NULL,
    clue_ids VARCHAR(100) NULL,                    -- 이 답에서 털어놓는 증언 (쉼표로 구분)
    PRIMARY KEY (character_id, topic, stage),
    CONSTRAINT fk_basic_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE CASCADE
);

-- 증거 제시 답 저장 (인물 × 증거 × 그 인물의 지금 단계). 단계가 같으면 AI를 다시 부르지 않고 같은 답을 쓴다
CREATE TABLE evidence_answer (
    answer_id INT NOT NULL AUTO_INCREMENT,
    character_id INT NOT NULL,
    evidence_key VARCHAR(20) NOT NULL,             -- 단서 c12, 추론 d3
    stage VARCHAR(100) NOT NULL,                   -- 범인: 처음/물러섬, 범인 아님: 이미 털어놓은 숨은 증언
    answer TEXT NOT NULL,
    clue_ids VARCHAR(100) NULL,                    -- 이 답에서 털어놓는 증언
    stated_alibi BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (answer_id),
    UNIQUE KEY uq_evidence_answer (character_id, evidence_key, stage),
    CONSTRAINT fk_ea_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE CASCADE
);

-- 심문 기록
CREATE TABLE interrogation (
    interrogation_id INT NOT NULL AUTO_INCREMENT,
    participant_id INT NOT NULL,
    character_id INT NOT NULL,
    kind ENUM('기본', '증거', '자유') NOT NULL DEFAULT '자유',  -- 자유 질문만 인물당 횟수 제한
    answer_id INT NULL,                                       -- 증거 제시면 쓴 저장 답
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    asked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (interrogation_id),
    CONSTRAINT fk_interrogation_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_interrogation_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id),
    CONSTRAINT fk_interrogation_answer FOREIGN KEY (answer_id)
        REFERENCES evidence_answer (answer_id) ON DELETE SET NULL
);

-- 단서 발견 (참가자 N:M 단서)
CREATE TABLE clue_discovery (
    participant_id INT NOT NULL,
    clue_id INT NOT NULL,
    found_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (participant_id, clue_id),
    CONSTRAINT fk_discovery_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_discovery_clue FOREIGN KEY (clue_id)
        REFERENCES clue (clue_id)
);

-- 조사 지점 조사 기록 (참가자 N:M 조사 지점)
CREATE TABLE spot_search (
    participant_id INT NOT NULL,
    spot_id INT NOT NULL,
    searched_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (participant_id, spot_id),
    CONSTRAINT fk_search_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_search_spot FOREIGN KEY (spot_id)
        REFERENCES spot (spot_id) ON DELETE CASCADE
);

-- 단서 연결 시도 (deduction_id가 NULL이면 틀린 연결. 연결은 조사 횟수를 쓰지 않는다)
CREATE TABLE link_attempt (
    attempt_id INT NOT NULL AUTO_INCREMENT,
    participant_id INT NOT NULL,
    clue_key VARCHAR(60) NOT NULL,           -- 고른 단서 id를 정렬해 이은 값 (같은 조합 중복 방지)
    deduction_id INT NULL,
    attempted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (attempt_id),
    UNIQUE KEY uq_attempt (participant_id, clue_key),
    CONSTRAINT fk_attempt_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_attempt_deduction FOREIGN KEY (deduction_id)
        REFERENCES deduction (deduction_id) ON DELETE CASCADE
);

-- 메모
CREATE TABLE memo (
    memo_id INT NOT NULL AUTO_INCREMENT,
    participant_id INT NOT NULL,
    content TEXT NOT NULL,
    written_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_auto BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (memo_id),
    CONSTRAINT fk_memo_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE
);

-- 타임라인 항목 (단서 발견, 심문 시 자동 추가)
CREATE TABLE timeline_entry (
    entry_id INT NOT NULL AUTO_INCREMENT,
    participant_id INT NOT NULL,
    clue_id INT NULL,
    interrogation_id INT NULL,
    fact_id INT NULL,
    event_time TIME NOT NULL,
    content VARCHAR(255) NOT NULL,
    PRIMARY KEY (entry_id),
    CONSTRAINT fk_timeline_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_timeline_clue FOREIGN KEY (clue_id)
        REFERENCES clue (clue_id) ON DELETE SET NULL,
    CONSTRAINT fk_timeline_interrogation FOREIGN KEY (interrogation_id)
        REFERENCES interrogation (interrogation_id) ON DELETE SET NULL,
    CONSTRAINT fk_timeline_fact FOREIGN KEY (fact_id)
        REFERENCES fact (fact_id) ON DELETE SET NULL
);

-- 지목
CREATE TABLE accusation (
    accusation_id INT NOT NULL AUTO_INCREMENT,
    participant_id INT NOT NULL,
    character_id INT NOT NULL,
    accused_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (accusation_id),
    CONSTRAINT fk_accusation_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_accusation_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id)
);

-- 지목 근거 (지목할 때 고른 추론 2개, N:M)
CREATE TABLE accusation_evidence (
    accusation_id INT NOT NULL,
    deduction_id INT NOT NULL,
    slot ENUM('알리바이', '연결') NOT NULL,   -- 플레이어가 어떤 근거로 냈는지
    PRIMARY KEY (accusation_id, slot),
    CONSTRAINT fk_accev_accusation FOREIGN KEY (accusation_id)
        REFERENCES accusation (accusation_id) ON DELETE CASCADE,
    CONSTRAINT fk_accev_deduction FOREIGN KEY (deduction_id)
        REFERENCES deduction (deduction_id)
);

-- 로그인 세션 (게스트도 브라우저마다 게스트 회원 + 세션을 하나 받는다)
CREATE TABLE IF NOT EXISTS login_session (
    token CHAR(64) NOT NULL,
    member_id VARCHAR(20) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (token),
    CONSTRAINT fk_session_member FOREIGN KEY (member_id)
        REFERENCES member (member_id) ON DELETE CASCADE
);

-- 용의선상 제외 표시 (플레이어 메모용. 판정에는 영향 없음)
CREATE TABLE suspect_mark (
    participant_id INT NOT NULL,
    character_id INT NOT NULL,
    marked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (participant_id, character_id),
    CONSTRAINT fk_mark_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_mark_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE CASCADE
);

-- 진상 공개 뒤 AI에게 한 질문 (한 판에 10번까지)
CREATE TABLE truth_question (
    question_id INT NOT NULL AUTO_INCREMENT,
    participant_id INT NOT NULL,
    question VARCHAR(300) NOT NULL,
    answer TEXT NOT NULL,
    asked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (question_id),
    CONSTRAINT fk_tq_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE
);


/* 2. 사건 데이터 */

-- 사건 1: 겨울 별장 (인물 1~5, 현장 1~5, 사실 1~14, 조사 지점·단서·추론 1~)
INSERT INTO case_file (title, genre, difficulty, summary, truth, investigation_limit) VALUES
('겨울 별장', '클로즈드 서클', '보통',
 '폭설로 고립된 산속 별장. 밤 10시 30분, 별장 주인 한도윤이 2층 서재에서 숨진 채 발견되었다. 진입로가 막혀 경찰은 아침에야 도착한다. 별장에 남은 네 사람 중 누군가가 범인이다.',
 '조카 한서진은 19시 50분 변호사의 귀띔으로 삼촌이 유언장을 고친다는 걸 알고, 20시 30분 서류가방 속 수정안에서 상속인이 자신에서 재단으로 바뀐 걸 확인했다. 21시 35분 서재로 따지러 갔다가 "너는 한씨 집안 사람이 아니다"라는 말을 듣고, 21시 40분 책상 앞에서 청동 문진으로 삼촌의 뒷머리를 내려쳤다. 그 뒤 알리바이를 만들기 위해 시한장치를 꾸몄다. 21시 50분 실내화 차림으로 창고에 가 정원사의 장갑 한 짝을 챙기고, 창고 앞 눈 더미에서 눈을 뭉쳐 왔다. 21시 55분 시신을 책장 앞으로 끌어 옮기고, 4kg짜리 청동 흉상을 책장 맨 윗칸 끝에 걸친 뒤 눈덩이로 괴어 두었다. 난방기를 30도로 올려 눈이 빨리 녹고 시신도 덜 식게 했고, 장갑을 떨어뜨린 뒤 문진을 닦아 책장에 돌려놓았다. 22시 부엌에 내려가 가정부 최유나와 함께 있는 동안, 22시 10분 눈이 녹아 흉상이 떨어지며 "쿵" 소리가 났다. 모두 그때 범행이 일어났다고 믿었지만, 상처는 둥근 흉상이 아니라 각진 문진의 모양이었고, 책장 윗칸은 녹은 눈에 젖어 있었다.', 16);

INSERT INTO scene (case_id, name, description) VALUES
(1, '서재', '피해자가 쓰러져 있던 2층 서재. 창문은 안에서 잠겨 있고, 책상 위가 어지럽다.'),
(1, '부엌', '저녁 식사 뒤 정리가 덜 된 1층 부엌.'),
(1, '정원 창고', '별채 옆 정원 창고. 본관 뒷문에서 눈길로 30걸음쯤 떨어져 있다.'),
(1, '서진의 방', '2층 손님방 1. 한서진이 머무는 방.'),
(1, '변호사의 방', '2층 손님방 2. 고문 변호사 윤재혁이 머무는 방.');

INSERT INTO game_character (case_id, name, age, gender, job, personality, character_type, is_culprit) VALUES
(1, '한도윤', 62, '남', '별장 주인, 사업가', '고집이 세고 돈에 엄격함', '피해자', FALSE),
(1, '한서진', 29, '여', '대학원생, 피해자의 조카', '침착하고 예의 바르지만 거짓말에 능함', '용의자', TRUE),
(1, '박정호', 55, '남', '정원사', '말수가 적고 무뚝뚝함, 자존심이 셈', '용의자', FALSE),
(1, '최유나', 34, '여', '가정부', '눈치가 빠르고 수다스러움, 남 얘기를 좋아함', '용의자', FALSE),
(1, '윤재혁', 41, '남', '고문 변호사', '말을 고르고 논리적이며 방어적임', '용의자', FALSE);

INSERT INTO character_relation (character_a_id, character_b_id, relation_type, description) VALUES
(2, 1, '가족', '피해자의 조카. 지금 유언장으로는 유일한 상속인'),
(3, 1, '고용', '10년째 일한 정원사'),
(4, 1, '고용', '3년째 일한 가정부'),
(5, 1, '업무', '고문 변호사. 피해자의 신탁 계좌를 관리'),
(4, 3, '동료', '자주 함께 식사함');

INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(1, '18:00:00', '진입로', '폭설로 별장 진입로가 막혔다.', TRUE),
(1, '18:30:00', '정원', '한도윤이 박정호에게 이달까지만 일하라고 해고를 통보했다.', FALSE),
(1, '19:00:00', '식당', '다섯 사람이 함께 저녁 식사를 했다.', TRUE),
(1, '19:40:00', '서재', '한도윤이 윤재혁에게 내일 유언장을 고치겠다고 말했다.', FALSE),
(1, '20:00:00', '서재', '한도윤이 윤재혁에게 신탁 계좌를 전부 감사하겠다고 말했다.', FALSE),
(1, '20:30:00', '변호사의 방', '한서진이 윤재혁의 서류가방에서 유언장 수정안을 몰래 읽었다. 상속인이 재단으로 바뀌어 있었다.', FALSE),
(1, '21:00:00', '정원 창고', '박정호가 창고에서 혼자 술을 마시기 시작했다.', FALSE),
(1, '21:20:00', '2층 복도', '최유나가 설거지를 멈추고 2층 복도에서 몰래 개인 통화를 했다.', FALSE),
(1, '21:35:00', '서재', '한서진과 한도윤이 유언장 문제로 크게 다퉜다.', FALSE),
(1, '21:40:00', '서재', '한서진이 책상 앞에서 청동 문진으로 한도윤의 뒷머리를 내려쳤다. 한도윤은 책상 옆에 쓰러져 숨졌다.', FALSE),
(1, '21:50:00', '정원 창고', '한서진이 실내화 차림으로 창고에 가 정원사 장갑 한 짝을 챙기고, 창고 앞 눈 더미에서 눈을 단단히 뭉쳐 왔다.', FALSE),
(1, '21:55:00', '서재', '한서진이 시신을 책장 앞으로 끌어 옮기고, 청동 흉상을 책장 맨 윗칸 끝에 걸쳐 눈덩이로 괴어 두었다. 난방기를 30도로 올리고, 장갑을 떨어뜨린 뒤 문진을 닦아 책장에 돌려놓았다.', FALSE),
(1, '22:00:00', '부엌', '한서진이 부엌에 내려와 최유나에게 차를 부탁하고 20분 동안 머물렀다.', FALSE),
(1, '22:30:00', '서재', '최유나가 시신을 발견했다.', TRUE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(2, 1, FALSE), (3, 1, FALSE), (4, 1, FALSE), (5, 1, FALSE),
(2, 3, FALSE), (3, 3, FALSE), (4, 3, FALSE), (5, 3, FALSE),
(2, 14, FALSE), (3, 14, FALSE), (4, 14, FALSE), (5, 14, FALSE),
(2, 6, TRUE), (2, 9, TRUE), (2, 10, TRUE), (2, 11, TRUE), (2, 12, TRUE), (2, 13, TRUE),
(3, 2, TRUE), (3, 7, TRUE),
(4, 2, FALSE), (4, 8, TRUE), (4, 9, TRUE), (4, 13, FALSE),
(5, 4, FALSE), (5, 5, TRUE);

-- 거짓 알리바이(is_false = TRUE)는 범인만 가진다. 범인이 아닌 인물은 말을 아낄 수는 있어도 거짓말은 하지 않는다.
INSERT INTO alibi (character_id, claimed_time, place, statement, is_false) VALUES
(2, '21:40:00', '서진의 방', '9시 반 넘어서는 방에서 논문 자료를 읽다가 10시에 부엌에 내려갔어요. 쿵 소리가 났을 땐 유나 씨랑 같이 있었고요.', TRUE),
(3, '22:10:00', '정원 창고', '9시부터 창고에 계속 있었소. 혼자였으니 증명해 줄 사람은 없소.', FALSE),
(4, '22:10:00', '부엌', '10시부터 부엌에서 서진 아가씨랑 같이 있었어요. 쿵 소리도 같이 들었고요. 그 전엔 잠깐 2층에서 개인적인 통화를 했어요.', FALSE),
(5, '22:10:00', '변호사의 방', '방에서 화상회의를 하다 10시 5분에 끝내고 서류를 보고 있었습니다. 쿵 소리는 들었지만 주인이 또 뭘 떨어뜨렸겠거니 했습니다.', FALSE);

-- 조사 지점: 장소마다 3~5곳. 한 곳 열 때마다 조사 1회 (빈 곳도 있음)
INSERT INTO spot (spot_id, scene_id, name) VALUES
(1, 1, '책상 위'), (2, 1, '책상 아래'), (3, 1, '책장'), (4, 1, '바닥'), (5, 1, '창문'),
(6, 2, '개수대'), (7, 2, '충전기'), (8, 2, '칼꽂이'),
(9, 3, '작업대 아래'), (10, 3, '문 앞 눈길'), (11, 3, '장갑 걸이'),
(12, 4, '노트북'), (14, 4, '침대 밑'), (15, 4, '휴지통'), (16, 4, '옷장'),
(17, 5, '책상'), (18, 5, '노트북'), (19, 5, '서류가방');

-- 단서 문구는 사실만 적는다. 하나만으로는 누구도 확정되지 않고, 추론(조합)을 거쳐야 의미가 생긴다.
-- character_id가 있는 단서는 그 인물의 증언 (심문 중 실제로 털어놓아야 발견)
INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(1, 1, 4, NULL, '흙 묻은 장갑', '서재 바닥에 떨어진 정원용 장갑 오른쪽 한 짝. 겉에만 흙이 묻었고 안쪽은 깨끗하다.', '물증', FALSE, NULL),
(2, 1, 2, NULL, '책상 아래 슬리퍼', '책상 아래에 남자용 실내 슬리퍼 한 짝이 떨어져 있다. 시신은 왼발에만 같은 슬리퍼를 신고 있다. 카펫 결이 책상 옆에서 책장 쪽으로 두 줄 길게 눌려 있다.', '물증', FALSE, NULL),
(3, 1, 3, NULL, '닦인 청동 문진', '책장 가운데 칸의 직육면체 청동 문진. 모서리가 각져 있다. 둘레 물건엔 먼지가 앉았는데 문진만 닦여 있고, 밑면 모서리 틈에 붉은 얼룩이 남아 있다.', '물증', FALSE, NULL),
(4, 1, 1, NULL, '빈 유언장 봉투', '책상 위의 빈 봉투. 겉면에 "수정안 - 윤 변호사 지참"이라고 적혀 있다.', '기록', FALSE, NULL),
(5, 1, 5, NULL, '잠긴 창문', '서재 창문은 안쪽 걸쇠가 걸려 있다. 바깥 창틀에 쌓인 눈에는 아무 자국이 없고, 창 아래 바닥은 말라 있다.', '물증', FALSE, NULL),
(6, 2, 6, NULL, '반쯤 한 설거지', '개수대 물이 완전히 식어 있다. 21시 20분쯤 설거지가 멈춘 것으로 보인다.', '기록', FALSE, '21:20:00'),
(7, 2, 7, NULL, '가정부 휴대폰 통화 기록', '부엌 충전기에 꽂힌 최유나의 휴대폰. 21시 20분부터 26분 동안 통화한 기록이 있다. 상대는 저장되지 않은 번호다.', '기록', FALSE, NULL),
(8, 3, 9, NULL, '숨겨진 술병', '작업대 아래 숨겨진 빈 소주병 두 개. 아직 술 냄새가 난다.', '물증', FALSE, NULL),
(9, 3, 10, NULL, '눈 위의 발자국', '본관 뒷문에서 창고까지 갔다가 돌아온 작은 발자국. 밑창 무늬 없이 납작하고, 가운데에 작은 별 모양이 찍혀 있다. 창고 문 옆 눈 더미 한쪽이 손으로 퍼낸 듯 움푹 파여 있다.', '물증', FALSE, NULL),
(10, 3, 11, NULL, '한 짝 남은 장갑', '장갑 걸이에 왼쪽 장갑만 걸려 있다. 오른쪽 고리는 비어 있고, 고리 아래에 눈 녹은 물이 떨어져 있다.', '물증', FALSE, NULL),
(11, 4, 12, NULL, '노트북 저장 기록', '서진의 노트북. 논문 파일의 마지막 저장 시각은 21시 31분이다.', '기록', TRUE, '21:31:00'),
(13, 4, 14, NULL, '젖은 실내화', '침대 밑에 밀어 넣은 실내화. 밑창이 무늬 없이 납작하고 가운데에 별 모양 장식이 박혀 있다. 밑창이 아직 축축하다.', '물증', TRUE, NULL),
(14, 4, 15, NULL, '구겨진 메모', '휴지통 속 구겨진 메모지. 서진의 필체로 "상속인 → 재단?", "내일 서명"이라고 적혀 있다.', '기록', FALSE, NULL),
(15, 5, 17, NULL, '신탁 계좌 메모', '한도윤 필체의 메모. "윤 변호사, 신탁 계좌 전부 확인할 것."', '기록', FALSE, NULL),
(16, 5, 18, NULL, '화상회의 접속 기록', '노트북에 21시 30분부터 22시 5분까지 회의에 접속한 기록이 있다. 21시 38분부터는 카메라와 마이크가 꺼져 있다.', '기록', FALSE, '21:30:00'),
(17, 5, 19, NULL, '고쳐 쓴 장부', '서류가방 속 신탁 계좌 장부. 몇 군데 숫자가 새로 덧쓰여 있고, 잉크가 아직 번진다.', '물증', FALSE, NULL),
(18, 3, NULL, 3, '창고 문 소리', '정원사 박정호의 증언. 21시부터 창고 안에서 혼자 술을 마셨다. 21시 50분쯤 창고 문이 열렸다 닫히고, 문밖에서 눈을 긁어모으는 소리가 났다. 취해서 누군지는 못 봤다.', '증언', FALSE, '21:50:00'),
(19, 1, NULL, 4, '서재의 언쟁', '가정부 최유나의 증언. 21시 35분쯤 2층 복도에서 서재 안 언쟁을 들었다. 말소리가 섞여 누군지는 모르겠지만 "유언장"이라는 말은 똑똑히 들었다.', '증언', TRUE, '21:35:00'),
(20, 2, NULL, 4, '정원사 해고 소문', '가정부 최유나의 증언. 저녁 무렵 주인이 정원사에게 해고를 통보하는 걸 봤다.', '증언', FALSE, '18:30:00'),
(21, 5, NULL, 5, '유언장 수정 계획', '변호사 윤재혁의 증언. 피해자는 내일 유언장을 고쳐 상속인을 조카에서 재단으로 바꾸려 했다. 수정안은 서류가방에 넣어 두었다.', '증언', FALSE, NULL);

-- 2차 조사: 이 단서를 찾아야 열리는 곳
UPDATE spot SET unlock_clue_id = 4 WHERE spot_id = 19;   -- 서류가방 ← 빈 유언장 봉투 ("윤 변호사 지참")
UPDATE spot SET lock_hint = '가방 주인이 무엇을 들고 왔는지 알려 주는 기록을 먼저 찾아보세요.' WHERE spot_id = 19;
-- 숨은 증언: 관련 증거를 내밀어야만 털어놓는다
UPDATE clue SET unlock_clue_id = 6 WHERE clue_id = 19;   -- 서재의 언쟁 ← 반쯤 한 설거지

-- 추론: 단서 2개를 연결해야 얻는 사실. 범인 지목 근거로는 추론만 낼 수 있다.
INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(1, 1, '녹은 눈 시한장치', '책장 맨 윗칸 끝은 물에 젖어 부풀었고 그 위엔 아무것도 없다. 머리맡의 청동 흉상은 4kg짜리로 받침이 둥글다. 평소 꺼 두던 서재 난방기는 30도로 맞춰져 있었다.', '알리바이',
 '흉상은 맨 윗칸 끝에 눈덩이로 괴어 둔 것이 난방에 녹으면서 22시 10분에 저절로 떨어졌어요. "쿵" 소리는 범행 시각이 아니에요. 그 시각 부엌에 있었다는 서진의 알리바이는 아무것도 증명하지 못해요.'),
(2, 1, '별 무늬 발자국', '창고 눈길의 납작한 발자국에 찍힌 별 모양과 서진 방 실내화 밑창의 별 장식이 같다. 그 실내화는 아직 젖어 있다. 발자국이 끝나는 창고 문 옆 눈 더미는 손으로 퍼낸 듯 파여 있다.', '연결',
 '창고까지 눈길을 오가며 정원사 장갑과 눈덩이를 가져온 건 서진의 실내화예요. 정원사에게 누명을 씌우고 시한장치를 만든 사람이 서진이라는 뜻이에요.'),
(3, 1, '유언장 다툼', '피해자는 내일 상속인을 조카에서 재단으로 바꾸려 했고, 서진의 메모에는 그 내용이 적혀 있다. 21시 35분 서재에서는 "유언장" 얘기로 언쟁이 있었다.', '연결',
 '유언장이 바뀌면 잃는 사람은 서진뿐이고, 서진은 그걸 미리 알고 있었어요. 범행 5분 전 서재 언쟁과 이어져요.'),
(4, 1, '옮겨진 장갑', '서재의 오른쪽 장갑은 창고 걸이에 남은 왼쪽 장갑의 짝이다. 걸이 아래에는 눈 녹은 물이 떨어져 있고, 서재 장갑은 안쪽이 깨끗하다.', NULL,
 '누군가 창고에서 장갑을 가져와 정원사가 한 것처럼 꾸몄다는 뜻이에요. 누가 가져왔는지는 다른 추론과 엮어야 해요.'),
(5, 1, '창고의 정원사', '정원사는 21시부터 창고 안에서 술을 마셨고, 21시 50분쯤 창고 문이 열렸다 닫히는 소리를 들었다.', NULL,
 '정원사가 그 시각 창고에 있었다는 것뿐, 서재의 범행과 이어지는 흔적은 없어요.'),
(6, 1, '감추고 싶은 장부', '피해자는 신탁 계좌 감사를 예고했다. 변호사의 회의 카메라와 마이크는 21시 38분부터 꺼져 있었고, 변호사의 장부에는 잉크가 번진 새 숫자가 덧쓰여 있다.', NULL,
 '변호사가 화면을 끄고 감추려던 건 장부 조작이에요. 살인과 이어지는 흔적은 없어요.'),
(7, 1, '가정부의 26분', '유나는 21시 20분쯤 설거지를 멈췄고, 같은 시각부터 26분 동안 통화했다.', NULL,
 '유나가 자리를 비운 이유를 보여주지만, 범행과는 이어지지 않아요.'),
(8, 1, '진짜 흉기', '뒷머리 상처는 길이 3cm의 곧은 일자로 패어 있다. 머리맡 흉상의 받침은 둥글다. 책장의 직육면체 문진은 모서리가 각졌고, 혼자 닦여 있으며 틈에 붉은 얼룩이 남았다.', NULL,
 '둥근 흉상으로는 곧은 상처가 날 수 없어요. 진짜 흉기는 닦인 문진이고, 흉상은 나중에 꾸민 거예요. 누가 했는지는 아직 몰라요.'),
(13, 1, '옮겨진 시신', '시신은 책장 앞 흉상 곁에 엎드려 있다. 그런데 피해자의 슬리퍼 한 짝은 책상 아래에 있고, 카펫은 책상 옆에서 책장 쪽으로 두 줄 눌려 있다.', NULL,
 '피해자는 책상 앞에서 쓰러졌고, 누군가 책장 앞으로 끌어 옮겼어요. 흉상이 떨어진 자리에 시신을 맞춘 거예요.'),
(14, 1, '30분의 공백', '서진의 논문은 21시 31분에 마지막으로 저장됐다. 서진은 22시에야 부엌에 나타났다.', NULL,
 '"계속 논문을 썼다"던 말과 달리 21시 31분부터 30분 가까이 기록이 없어요. 다만 범행이 정말 22시 10분이었다면 서진은 부엌에 있었으니, 이것만으로는 알리바이가 깨지지 않아요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(2, 9), (2, 13),
(3, 14), (3, 19), (3, 21),
(4, 1), (4, 10),
(5, 8), (5, 18),
(6, 15), (6, 16), (6, 17),
(7, 6), (7, 7);

-- 범인의 변명 계획 (AI 범인이 증거마다 그럴듯한 설명을 대도록)
-- 범인의 변명 계획 (AI 범인이 증거마다 그럴듯한 설명을 대도록)
INSERT INTO hint (character_id, content, reveal_order) VALUES
(2, '알리바이: 9시 반 넘어서는 방에서 논문 자료를 읽었고, 10시부터는 부엌에서 유나와 함께 있었다고 한다. "쿵 소리가 났을 때 유나 씨랑 같이 있었어요. 유나 씨한테 물어보세요"를 가장 강한 무기로 쓴다.', 1),
(2, '노트북 마지막 저장이 21시 31분이라는 걸 들이밀면: 처음부터 자료를 읽었다고 했다며 말을 바꾸지 않는다. 종이 자료라 저장할 게 없었다고 한다. 그래도 쿵 소리 때는 부엌에 있었다고 되돌린다.', 2),
(2, '언쟁 소리 얘기가 나오면: 9시 반쯤 서재에 들러 유언장 얘기로 언성을 높인 건 인정하되, 금방 나왔고 그때 삼촌은 멀쩡했다고 한다.', 3),
(2, '젖은 실내화나 별 모양 발자국 얘기가 나오면: 10시 조금 전에 머리 식히러 뒷문 밖에 잠깐 나갔었다고 한다. 창고까지 이어진 발자국과 파인 눈 더미를 들이밀면 대답을 피한다.', 4),
(2, '장갑 얘기가 나오면: 정원사가 오늘 해고 통보를 받았다는 걸 흘려 의심을 돌린다. 정원사는 쿵 소리가 난 22시 10분에 혼자 있었다는 점을 짚는다.', 5),
(2, '젖은 책장 윗칸 얘기가 나오면: 창문 틈으로 눈이 들이친 거라고 한다. 창문이 안에서 잠겼고 창 아래가 말라 있다는 걸 들이밀면 "그럼 화분 물이라도 쏟았겠죠"라며 흐린다.', 6),
(2, '30도로 켜진 난방기 얘기가 나오면: 삼촌이 요즘 추위를 많이 탔다고 한다. 유나가 삼촌은 늘 난방을 꺼 두었다고 증언하면 대답을 피한다.', 7),
(2, '상처 모양이나 문진 얘기가 나오면: 자기는 시신을 제대로 보지도 못했다며 흉기는 경찰이 밝힐 일이라고 한다. 흉상이 머리맡에 떨어져 있었으니 그게 흉기 아니냐고 되묻는다.', 8),
(2, '유언장 수정안을 몰래 읽은 건 끝까지 숨긴다. 들키면 궁금해서 봤을 뿐 그걸로 삼촌을 해칠 이유는 없다고 한다.', 9),
(2, '구겨진 메모 얘기가 나오면: 저녁 식사 때 삼촌이 "재단에 남기겠다"는 말을 흘려서 적어둔 거라고 한다.', 10);


-- 사건 2: 마지막 여름 (인물 6~10, 현장 6~11, 사실 15~30, 조사 지점·단서·추론 101~)
INSERT INTO case_file (title, genre, difficulty, summary, truth, investigation_limit) VALUES
('마지막 여름', '연애 리얼리티', '보통',
 '최종 선택을 하루 앞둔 연애 리얼리티 「여름, 너에게」의 제주 촬영 숙소. 밤 10시 50분, 출연자 윤시우가 수영장에 떠 있는 채 발견되었다. 태풍으로 길이 막혀 경찰은 새벽에야 도착한다. 숙소에 남은 네 사람 중 누군가가 범인이다.',
 '출연자 한지아는 언니 한지영의 투자금 1억 2천만 원을 날리게 한 윤시우에게 다가가려고 방송에 지원했다. 21시 40분 시우가 "10시에 수영장에서 보자"고 메시지를 보내자, 지아는 그 자리에서 죽이기로 마음먹었다. 알리바이를 위해 21시 20분부터 찍던 30분짜리 브이로그를 21시 50분에 끝내고, 21시 57분 채널에 올려 22시 최초 공개로 걸어 두었다. 그리고 입원한 언니에게 처방된 수면제 4알을 녹인 샴페인을 들고 22시 수영장으로 갔다. 시우는 두 잔을 마시고 비틀거렸고, 22시 10분 지아는 돈 이야기로 다투다 시우를 밀쳤다. 시우는 데크 모서리에 뒷머리를 부딪치고 물에 빠졌고, 지아는 물에 들어가 시우의 양 어깨를 눌러 떠오르지 못하게 했다(스마트워치 심박 22시 11분 끊김). 이때 왼쪽 귀걸이가 빠져 필터로 흘러갔다. 수영장 카메라는 22시 5분 배터리가 떨어져 꺼져 있었다. 지아는 자기 잔을 수영장 물에 헹궈 두어 술에 취한 사고처럼 보이게 하고, 맨발로 방에 돌아와 젖은 원피스를 벗고 머리를 말렸다. 22시 30분 라이브를 켜 "계속 방에 있었다"고 말했지만, 라이브 속 지아에게는 왼쪽 귀걸이가 없었다.', 17);

INSERT INTO scene (case_id, name, description) VALUES
(2, '수영장 데크', '숙소 뒤편 야외 수영장. 대리석 데크와 선베드가 있고, 촬영용 카메라가 한 대 달려 있다.'),
(2, '시우의 방', '2층 남자 출연자 방 중 하나. 윤시우가 혼자 쓰던 방.'),
(2, '지아의 방', '2층 여자 출연자 방. 한지아가 쓰는 방으로, 브이로그용 삼각대가 세워져 있다.'),
(2, '작가실', '1층 제작진 작가실. 원고와 촬영 일정표가 벽에 붙어 있다.'),
(2, '장비실', '1층 촬영 장비실. 배터리 충전기와 모니터가 늘어서 있다.'),
(2, '거실', '출연자들이 모여 이야기하던 1층 거실.');

INSERT INTO game_character (case_id, name, age, gender, job, personality, character_type, is_culprit) VALUES
(2, '윤시우', 31, '남', '출연자, 스타트업 대표', '자신만만하고 말이 번지르르함', '피해자', FALSE),
(2, '한지아', 27, '여', '출연자, 플로리스트', '상냥하고 차분하지만 속을 잘 드러내지 않음', '용의자', TRUE),
(2, '백도현', 31, '남', '출연자, 소방관', '다혈질이지만 솔직하고 정이 많음', '용의자', FALSE),
(2, '이채원', 29, '여', '프로그램 작가', '예민하고 말을 돌려 하며 눈치를 많이 봄', '용의자', FALSE),
(2, '주경민', 44, '남', '촬영감독', '느긋하고 투덜거리며 술을 좋아함', '용의자', FALSE);

INSERT INTO character_relation (character_a_id, character_b_id, relation_type, description) VALUES
(7, 6, '출연자', '방송에서는 시우와 러브라인. 사실 언니의 투자금을 날리게 한 사람이라 원한이 있다'),
(8, 6, '출연자', '지아를 두고 경쟁하는 사이. 시우를 싫어함'),
(9, 6, '제작', '담당 작가. 방송 중 몰래 사귀어 왔다 (제작진·출연자 연애 금지)'),
(10, 6, '제작', '촬영감독'),
(8, 7, '출연자', '도현이 지아에게 호감이 있다');

INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(2, '18:00:00', '숙소', '최종 선택을 하루 앞두고 마지막 촬영이 시작됐다.', TRUE),
(2, '19:00:00', '다이닝룸', '출연자와 제작진이 함께 마지막 만찬을 했다.', TRUE),
(2, '20:30:00', '시우의 방', '윤시우가 이채원 작가와 몰래 만나 "방송 끝나면 공개하자"고 말했다.', FALSE),
(2, '21:00:00', '장비실', '주경민이 혼자 맥주를 마시기 시작했고, 수영장 카메라 배터리 교체를 미뤘다.', FALSE),
(2, '21:30:00', '거실', '백도현과 윤시우가 거실에서 몸싸움을 벌였다. 시우는 넘어졌다가 웃으며 일어났다.', FALSE),
(2, '21:40:00', '지아의 방', '윤시우가 한지아에게 "10시에 수영장에서 보자"는 메시지를 보냈다.', FALSE),
(2, '21:57:00', '지아의 방', '한지아가 미리 찍어 둔 브이로그를 채널에 올려 22시 최초 공개로 걸어 두고, 언니의 수면제 4알을 녹인 샴페인을 챙겨 방을 나섰다.', FALSE),
(2, '22:00:00', '시우의 방', '이채원이 시우의 방에 몰래 들어가 둘이 주고받은 메시지를 지웠다. 이때 목에 걸고 있던 자기 출입증을 시우의 침대 밑에 떨어뜨렸다.', FALSE),
(2, '22:05:00', '수영장 데크', '수영장 카메라가 배터리 방전으로 녹화를 멈췄다.', FALSE),
(2, '22:10:00', '수영장 데크', '한지아가 비틀거리는 윤시우와 언니 돈 문제로 다투다 밀쳤다. 시우는 데크 모서리에 뒷머리를 부딪치고 물에 빠졌고, 지아는 물에 들어가 시우의 양 어깨를 눌러 떠오르지 못하게 했다. 이때 왼쪽 귀걸이가 빠졌다.', FALSE),
(2, '22:12:00', '작가실', '이채원이 작가실 창문 너머로 수영장 쪽 여자 목소리를 들었다.', FALSE),
(2, '22:15:00', '장비실', '주경민이 창밖으로 맨발로 뛰어가는 작은 그림자를 봤다.', FALSE),
(2, '22:20:00', '지아의 방', '한지아가 젖은 원피스를 벗어 욕실 바구니에 넣고 머리를 말렸다.', FALSE),
(2, '22:25:00', '2층 복도', '이채원이 복도에서 머리가 젖은 한지아와 마주쳤다.', FALSE),
(2, '22:30:00', '지아의 방', '한지아가 라이브를 켜고 시청자에게 "10시부터 계속 방에 있었다"며 마무리 인사를 했다. 왼쪽 귀걸이가 없다.', FALSE),
(2, '22:50:00', '수영장 데크', '백도현이 수영장에 떠 있는 윤시우를 발견했다.', TRUE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(7, 15, FALSE), (8, 15, FALSE), (9, 15, FALSE), (10, 15, FALSE),
(7, 16, FALSE), (8, 16, FALSE), (9, 16, FALSE), (10, 16, FALSE),
(7, 30, FALSE), (8, 30, FALSE), (9, 30, FALSE), (10, 30, FALSE),
(7, 20, TRUE), (7, 21, TRUE), (7, 24, TRUE), (7, 27, TRUE), (7, 28, TRUE), (7, 29, TRUE),
(8, 19, TRUE),
(9, 17, TRUE), (9, 22, TRUE), (9, 25, FALSE), (9, 28, FALSE),
(10, 18, TRUE), (10, 23, FALSE), (10, 26, FALSE);

INSERT INTO alibi (character_id, claimed_time, place, statement, is_false) VALUES
(7, '22:10:00', '지아의 방', '10시엔 방에 있었어요. 제 브이로그가 10시에 최초 공개라서 방에서 같이 보면서 댓글 달고 있었어요.', TRUE),
(8, '22:10:00', '헬스장', '지하 헬스장에서 혼자 운동하고 있었어요.', FALSE),
(9, '22:10:00', '작가실', '작가실에서 내일 원고를 정리하고 있었어요.', FALSE),
(10, '22:10:00', '장비실', '장비실에서 배터리 충전하고 장비 정리했소.', FALSE);

INSERT INTO spot (spot_id, scene_id, name) VALUES
(101, 6, '수영장 필터'), (102, 6, '데크 바닥'), (103, 6, '데크 모서리'), (104, 6, '흡연 구역'), (105, 6, '시신 곁'),
(106, 7, '휴대폰'), (107, 7, '노트북'), (108, 7, '침대'),
(109, 8, '삼각대 휴대폰'), (110, 8, '노트북'), (111, 8, '욕실 바구니'), (112, 8, '화장대'), (113, 8, '옷장'),
(114, 9, '창문'), (115, 9, '책상'), (116, 9, '원고 더미'),
(117, 10, '녹화기'), (118, 10, '화이트보드'), (119, 10, '구석'), (120, 10, '출입 태그 모니터'),
(121, 11, '바닥'), (122, 11, '쓰레기통'), (123, 11, '소파');

INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(101, 6, 101, NULL, '꽃 모양 귀걸이', '수영장 필터망에 걸려 있던 작은 생화 모양 귀걸이 한 짝. 왼쪽 귀에 다는 고리다.', '물증', TRUE, NULL),
(102, 6, 102, NULL, '데크의 맨발 자국', '데크에서 본관 뒷문 쪽으로 이어진 젖은 맨발 자국. 발이 작다(230~240mm쯤).', '물증', FALSE, NULL),
(103, 6, 103, NULL, '데크 모서리 혈흔', '수영장 쪽 대리석 모서리의 핏자국. 시우의 머리 상처 높이와 맞는다.', '물증', FALSE, NULL),
(104, 6, 104, NULL, '데크 옆 담배꽁초', '흡연 구역 재떨이의 갓 피운 꽁초 하나. 옆에 소방서 로고가 찍힌 라이터가 떨어져 있다.', '물증', FALSE, NULL),
(105, 6, 105, NULL, '스마트워치 기록', '시우 손목의 스마트워치. 심박 신호가 22시 11분에 끊겼다.', '기록', TRUE, '22:11:00'),
(106, 7, 106, NULL, '비워진 대화방', '시우 휴대폰의 대화방 하나가 22시에 통째로 삭제되었다.', '기록', FALSE, '22:00:00'),
(107, 7, 107, NULL, '환불 요청자 명단', '시우 노트북의 엑셀 파일 "환불 요청자". 투자자 이름과 금액이 수십 줄 적혀 있고, 맨 위는 "한지영 - 1억 2천"이다.', '기록', FALSE, NULL),
(108, 7, 108, NULL, '떨어진 출입증', '침대 밑에 떨어진 제작진 출입증. 이름 칸에 "작가 이채원"이라고 적혀 있다.', '물증', FALSE, NULL),
(109, 8, 109, NULL, '휴대폰 촬영 기록', '삼각대에 꽂힌 지아 휴대폰의 앨범. 오늘 밤 영상은 두 개다. 하나는 21시 20분에 시작해 21시 50분에 끝난 30분짜리로, 지아는 머리를 풀었고 꽃 모양 귀걸이를 양쪽에 하고 있다. 하나는 22시 30분부터 8분 동안 찍힌 라이브 녹화본으로, 지아는 머리를 하나로 묶었고 귀걸이는 오른쪽에만 있다.', '기록', TRUE, '21:50:00'),
(110, 8, NULL, NULL, '채널 업로드 기록', '지아 노트북의 채널 관리 화면. 영상 「제주 마지막 밤」은 21시 57분에 업로드가 끝났고, 22시에 최초 공개되었다. 길이는 30분이다. 영상 속 지아는 머리를 풀었고 꽃 모양 귀걸이를 양쪽에 하고 있다.', '기록', TRUE, '21:57:00'),
(111, 8, 111, NULL, '젖은 원피스', '욕실 바구니 속 원피스. 아직 물기가 뚝뚝 떨어지고, 수영장 소독약 냄새가 난다.', '물증', FALSE, NULL),
(112, 8, 112, NULL, '가족 사진', '화장대 거울에 끼운 사진. 지아가 닮은 얼굴의 여자와 어깨동무를 하고 있다. 뒷면에 "지영 언니랑, 2024 봄"이라고 적혀 있다.', '물증', FALSE, NULL),
(113, 9, 114, NULL, '작가실 창문', '작가실 창문을 열면 수영장 데크가 바로 내려다보인다.', '물증', FALSE, NULL),
(114, 9, 115, NULL, '연애 금지 서약서', '제작진과 출연자의 연애를 금지하는 서약서. 이채원의 서명이 있다.', '기록', FALSE, NULL),
(115, 10, 117, NULL, '수영장 카메라 기록', '수영장 카메라 녹화가 22시 5분에 배터리 방전으로 끊겼다.', '기록', FALSE, '22:05:00'),
(116, 10, 118, NULL, '꺼진 카메라 메모', '장비실 화이트보드에 "수영장 캠 배터리 → 내일 아침 교체" 메모. 오늘 날짜다.', '기록', FALSE, NULL),
(117, 10, 119, NULL, '빈 맥주캔', '장비실 구석에 빈 맥주캔 다섯 개가 쌓여 있다.', '물증', FALSE, NULL),
(118, 10, 120, NULL, '헬스장 출입 기록', '장비실 모니터의 출입 태그 기록. 지하 헬스장에 백도현이 21시 45분에 들어가 22시 18분에 나왔다.', '기록', FALSE, '22:18:00'),
(119, 11, 121, NULL, '깨진 액자', '거실 바닥에 떨어져 깨진 출연자 단체 사진 액자. 누군가 세게 부딪힌 흔적이다.', '물증', FALSE, NULL),
(120, 11, 122, NULL, '피 묻은 휴지', '거실 쓰레기통 속 피 묻은 휴지 뭉치.', '물증', FALSE, NULL),
(121, 9, NULL, 9, '수영장의 여자 목소리', '작가 이채원의 증언. 22시 12분쯤 작가실 창문 너머 수영장 쪽에서 언성이 높아진 여자 목소리와 물 튀는 소리를 들었다. "돈"이라는 말이 들린 것 같다.', '증언', TRUE, '22:12:00'),
(122, 8, NULL, 9, '복도의 젖은 머리', '작가 이채원의 증언. 22시 25분쯤 2층 복도에서 머리가 젖은 한지아와 마주쳤다. 지아는 샤워했다고 했다.', '증언', FALSE, '22:25:00'),
(123, 11, NULL, 8, '거실 몸싸움', '출연자 백도현의 증언. 21시 30분 거실에서 시우의 멱살을 잡고 밀쳤다. 시우는 일어나며 "나한테 원한 있는 사람이 여기 또 있다"고 비웃었다.', '증언', FALSE, '21:30:00'),
(124, 10, NULL, 10, '맨발의 그림자', '촬영감독 주경민의 증언. 22시 15분쯤 장비실 창밖으로 맨발로 본관 쪽에 뛰어가는 작은 그림자를 봤다. 술에 취해 누군지는 모른다.', '증언', FALSE, '22:15:00');

UPDATE clue SET unlock_clue_id = 113 WHERE clue_id = 121;  -- 수영장의 여자 목소리 ← 작가실 창문
UPDATE clue SET unlock_clue_id = 119 WHERE clue_id = 123;  -- 거실 몸싸움 ← 깨진 액자

INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(101, 2, '미리 찍은 영상', '22시에 공개된 30분짜리 영상은 21시 57분에 이미 업로드가 끝나 있었다. 지아 휴대폰에서 그 영상은 21시 20분부터 21시 50분까지 찍혔다.', '알리바이',
 '10시에 공개된 영상은 21시 50분에 이미 다 찍혀 있었어요. 영상이 공개되는 동안 지아가 방에 있었다는 건 지아 본인의 말뿐이고, 사망 시각 22시 11분의 알리바이를 받쳐 주는 건 아무것도 없어요.'),
(102, 2, '사라진 왼쪽 귀걸이', '21시 50분까지 찍은 영상 속 지아는 꽃 모양 귀걸이를 양쪽에 하고 있다. 22시 30분 라이브에서는 오른쪽에만 있다. 수영장 필터에서는 같은 모양의 왼쪽 귀걸이가 나왔다.', '연결',
 '21시 50분과 22시 30분 사이에 지아의 왼쪽 귀걸이가 수영장 필터로 갔어요. 지아가 그때 수영장 물에 들어갔다는 증거예요.'),
(103, 2, '젖은 채 돌아온 사람', '22시 25분 지아는 머리가 젖은 채 2층 복도에 있었다. 지아 방 욕실 바구니에는 물기가 떨어지고 수영장 소독약 냄새가 나는 원피스가 있다.', '연결',
 '샤워를 했다면 원피스가 수영장 물에 젖을 이유가 없어요. 지아가 범행 직후 수영장에서 돌아왔다는 흔적이에요.'),
(104, 2, '돈 이야기', '22시 12분 수영장 쪽에서 "돈"이라는 말이 섞인 언쟁과 물소리가 들렸다. 시우의 환불 요청자 명단 맨 위는 "한지영 - 1억 2천"이고, 지아의 사진 뒷면에는 "지영 언니"라고 적혀 있다.', '연결',
 '시우에게 1억 2천을 떼인 한지영은 지아의 언니예요. 사망 직후 수영장에서 들린 "돈" 다툼과 이어져요.'),
(105, 2, '지워진 대화', '시우 휴대폰의 대화방 하나가 22시에 지워졌고, 시우 방 침대 밑에서 이채원의 출입증이 나왔다. 채원은 출연자와의 연애 금지 서약서에 서명했다.', NULL,
 '채원이 시우와의 관계를 숨기려 한 흔적이에요. 22시 10분 범행과는 이어지지 않아요.'),
(106, 2, '헬스장 이후', '도현은 21시 45분부터 22시 18분까지 지하 헬스장에 있었다. 흡연 구역에는 갓 피운 꽁초와 소방서 로고 라이터가 있다.', NULL,
 '도현의 라이터는 22시 18분 이후 담배를 피운 흔적이에요. 범행 시각엔 헬스장에 있었어요.'),
(107, 2, '꺼진 카메라', '수영장 카메라는 22시 5분 배터리 방전으로 꺼졌다. 장비실 화이트보드에는 배터리 교체를 내일 아침으로 미룬 메모가 있고, 구석엔 빈 맥주캔이 쌓여 있다.', NULL,
 '카메라는 촬영감독이 배터리 교체를 미뤄서 꺼졌어요. 누가 노린 건 아니에요.'),
(108, 2, '사고가 아니다', '데크 모서리의 핏자국 높이는 시우의 머리 상처와 맞는다. 그런데 시우의 양 어깨 앞쪽에는 손가락 모양 멍이 네 개씩 있다. 데크의 샴페인 잔 하나는 물로 헹군 듯 물기만 있다.', NULL,
 '미끄러져 빠진 사고라면 어깨를 움켜쥐고 누른 멍이 생길 수 없어요. 누군가 시우를 물속에 눌렀고, 자기가 마신 잔을 헹궈 흔적을 지웠어요. 누가 했는지는 아직 몰라요.'),
(109, 2, '맨발의 사람', '22시 15분쯤 맨발로 본관 쪽에 뛰어가는 작은 그림자가 있었다. 데크에서 본관 뒷문 쪽으로 230~240mm쯤의 젖은 맨발 자국이 이어진다.', NULL,
 '발이 작은 사람이 수영장에서 본관으로 갔다는 것까지만 알려줘요.'),
(110, 2, '거실의 몸싸움', '21시 30분 거실에서 도현과 시우가 몸싸움을 했고, 거실에는 깨진 액자와 피 묻은 휴지가 있다.', NULL,
 '도현과 시우가 싸운 흔적이지만, 범행보다 40분 전 일이에요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(101, 109), (101, 110),
(102, 101), (102, 109),
(103, 111), (103, 122),
(104, 121), (104, 107), (104, 112),
(105, 106), (105, 108), (105, 114),
(106, 118), (106, 104),
(107, 115), (107, 116), (107, 117),
(109, 102), (109, 124),
(110, 119), (110, 120), (110, 123);

INSERT INTO hint (character_id, content, reveal_order) VALUES
(7, '알리바이를 물으면: 10시엔 방에서 자기 영상 최초 공개를 보며 댓글을 달았다고 한다. 영상을 언제 찍었는지 물으면 9시 20분부터 50분까지 찍어 57분에 올렸다고 처음부터 사실대로 말한다.', 1),
(7, '촬영·업로드 기록을 들이밀면: 이미 말한 그대로라며 말을 바꾸지 않는다. 미리 찍어 최초 공개로 거는 건 늘 쓰는 방식이라고 한다. 영상이 알리바이가 못 된다고 하면 "혼자 방에 있었으니 증명할 사람이 없는 건 어쩔 수 없죠"라고 한다.', 2),
(7, '젖은 머리 얘기가 나오면: 샤워하고 물 가지러 복도에 나갔다가 작가님을 마주쳤다고 한다. 수영장에 간 걸 인정한 뒤라면, 수영장에서 돌아와 샤워한 거라고 한다.', 3),
(7, '젖은 원피스 얘기가 나오면: 아직 물이 떨어지는 옷이라 낮에 젖었다는 말은 통하지 않으니 처음부터 꺼내지 않는다. 잠깐 말을 멈춘 뒤 바로 [물러선 이야기]만 말한다: "사실… 10시쯤 수영장에 잠깐 나갔어요." 시우가 장난으로 물을 끼얹어 젖었고, 22시 5분쯤 화가 나서 먼저 들어왔으며 그때 시우는 멀쩡했다. 의심받을까 봐 무서워서 숨겼다고 한다.', 4),
(7, '귀걸이 얘기가 나오면: 샤워하려고 뺐는데 한 짝이 안 보인다고 한다. 필터에서 나왔다면 낮 촬영 때 빠졌을 거라고 한다. 21시 50분까지 영상에 양쪽이 다 있다는 걸 들이밀면, 물에는 들어가지 않았으니 모르겠다며 말이 막혀 입을 다문다.', 5),
(7, '샴페인 잔이나 수면제 얘기가 나오면: 언니 약은 입원한 언니 짐을 챙기다 가져온 것이고 요즘 잠이 안 와서 자기가 먹었다고 한다. 잔의 가루를 들이밀면 대답을 피한다.', 6),
(7, '어깨의 멍 얘기가 나오면: 시우가 저녁에 도현과 거실에서 몸싸움을 했다는 걸 짚는다. 도현은 멱살만 잡았다는 말이 나오면 말을 돌린다.', 7),
(7, '맨발 자국 얘기가 나오면: 아직 수영장에 간 걸 인정하기 전이면 여기서 [물러선 이야기]로 물러선다. 22시 12분 여자 목소리나 22시 15분 맨발 그림자 얘기가 나오면: 자기는 22시 5분에 들어왔다며 지키는 선을 지키고, 이채원 작가와 시우가 몰래 가까웠다는 걸 흘려 의심을 돌린다.', 8),
(7, '술에 취한 사고 아니냐는 말이 나오면: "시우 씨 원래 술 좋아했어요"라며 사고 쪽으로 슬쩍 거든다.', 9),
(7, '가족 사진이나 환불 명단의 한지영 얘기가 나오면: 언니인 건 인정한다. 수영장에 간 걸 인정하기 전이면 방송 끝나고 따로 얘기하려 했다고만 한다. 인정한 뒤라면 수영장에서 언니 돈 얘기를 꺼냈다가 비웃음만 샀다고 한다.', 10);


-- 범인이 아닌 사람들의 수상한 정황 (사실 31~33)
INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(1, '21:38:00', '변호사의 방', '윤재혁이 화상회의 카메라와 마이크를 끄고, 신탁 계좌 장부의 숫자를 몰래 고쳤다.', FALSE),
(1, '21:46:00', '2층 복도', '최유나가 26분 동안의 통화를 마치고 부엌으로 내려왔다. 통화 상대는 연예 잡지 기자였다.', FALSE),
(2, '22:20:00', '수영장 데크', '백도현이 헬스장에서 나와 수영장 옆 흡연 구역에서 몰래 담배를 피웠다. 어두워서 수영장 안은 보지 못했다.', FALSE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(5, 31, TRUE), (4, 32, TRUE), (8, 33, TRUE);


-- 인물 서사 보강: 모든 용의자에게 피해자와 얽힌 과거와 동기가 있고, 그날 밤 한 번씩 피해자를 만났다

-- 사건 1 인물의 과거 (AI만 읽음)
UPDATE game_character SET backstory = '사업으로 크게 성공했지만, 20년 전 동업자 박정호의 지분을 빼돌려 회사를 차지했다. 옛 비서가 임신하자 버렸다. 사람을 잘 믿지 않고 돈과 서열로 사람을 다룬다.' WHERE character_id = 1;
UPDATE game_character SET backstory = '12살에 교통사고로 부모를 잃고 삼촌 손에 자랐다. 삼촌은 학비를 다 대줬지만 늘 "한씨 집안 사람답게"를 강요했다. 회사를 물려받으라는 말을 거절하고 해외 박사과정에 합격했는데, 그 뒤로 삼촌이 차갑게 변했다. 유학 준비로 진 빚이 있고, 유산이 유일한 기댈 곳이었다. 어릴 때 정원에서 자기를 돌봐준 박정호를 좋아했다. 윤재혁이 자기에게 호감이 있다는 걸 알고 적당히 이용해 왔다.' WHERE character_id = 2;
UPDATE game_character SET backstory = '20년 전 한도윤과 함께 회사를 차린 공동 창업자다. 한도윤이 지분을 빼돌려 회사에서 쫓겨났고, 파산하고 이혼했다. 10년 전 한도윤이 사과 대신 정원사 자리를 내밀었고, 자존심을 접고 받아들였다. 오늘 해고 통보를 받고 "두 번 버려졌다"는 생각에 분이 풀리지 않는다. 최유나가 한도윤의 딸이라는 걸 유나에게 직접 들어 알고 있고, 유나를 딸처럼 감싼다. 이 일은 남의 비밀이라 쉽게 말하지 않는다.' WHERE character_id = 3;
UPDATE game_character SET backstory = '사실 한도윤의 혼외 딸이다. 엄마는 한도윤의 옛 비서로, 임신하자 버려졌다. 엄마가 병으로 쓰러지자 3년 전 정체를 숨기고 가정부로 들어왔고, 몰래 친자 검사를 해 결과를 받았다. 오늘 저녁 결과지를 내밀었지만 한도윤은 수표를 써 주며 조용히 나가라고 했다. 그래서 연예 잡지 기자에게 한도윤의 과거를 제보하기로 했다. 박정호에게만 이 사실을 털어놓았다. 한서진이 사촌이라는 건 알지만 서진은 모른다.' WHERE character_id = 4;
UPDATE game_character SET backstory = '15년째 한도윤의 고문 변호사다. 주식으로 큰돈을 잃고, 메우려고 신탁 계좌에서 2억 원을 몰래 빼 썼다. 내일 아침 감사가 열리면 변호사 자격도, 인생도 끝난다. 한서진에게 오래 호감을 품어 왔고, 그래서 저녁에 유언장 이야기를 서진에게 귀띔했다. 그게 서진을 서류가방으로 이끈 것 같아 마음에 걸려 숨기고 싶어 한다.' WHERE character_id = 5;

-- 사건 2 인물의 과거
UPDATE game_character SET backstory = '투자금을 돌려막는 스타트업 대표다. 환불 요구가 쌓이자 방송으로 이미지를 세탁하고 새 투자자를 모으려고 출연했다. 2년 전 자기 회사 사무실 화재 때 비상구를 잠가 둔 책임을 피했다. 작가 이채원과 몰래 사귀며 편집을 유리하게 받았지만, 방송이 끝나면 한지아에게 갈아탈 생각이었다. 남의 약점을 쥐고 비웃는 버릇이 있다.' WHERE character_id = 6;
UPDATE game_character SET backstory = '언니 한지영이 결혼 자금과 대출을 합친 1억 2천만 원을 윤시우의 회사에 넣었다가 날렸고, 충격으로 쓰러져 입원해 있다. 지아는 정체를 숨기고 방송에 지원해 시우에게 다가갔다. 처음부터 해칠 생각은 아니었다. 언니에게 사과하고 돈을 돌려주겠다는 약속을 받아내려 했다. 백도현이 자기를 좋아한다는 걸 알고 있다.' WHERE character_id = 7;
UPDATE game_character SET backstory = '2년 전 윤시우 회사 사무실 화재에 출동했다. 비상구가 잠겨 있어 함께 들어간 동료 소방관이 크게 다쳤고 지금도 재활 중이다. 시우는 책임을 끝까지 피했다. 그 일을 세상에 알리고 싶어 방송에 나왔고, 지갑에 그 기사를 오려 넣고 다닌다. 촬영 중 한지아에게 진심으로 마음이 생겼다. 주경민과는 저녁마다 술을 마시며 시우 뒷담화를 한 사이다.' WHERE character_id = 8;
UPDATE game_character SET backstory = '방송 중 윤시우와 몰래 사귀어 왔다. 시우가 좋게 나오도록 몰래 편집본을 바꿔 주기도 했다. 제작진과 출연자의 연애를 금지하는 서약서에 서명했기 때문에 들키면 작가 일을 잃는다. 오늘 밤 시우의 휴대폰에서 시우가 한지아를 따로 부른 메시지를 보고 배신감을 느꼈다. 휴대폰을 몰래 만진 게 들킬까 봐 그 이야기를 꺼내기 싫어한다.' WHERE character_id = 9;
UPDATE game_character SET backstory = '아내 몰래 퇴직금 5천만 원을 윤시우 회사에 넣었다가 돌려받지 못했다. 돈을 받아내려고 이 방송 촬영을 맡았지만 시우는 만날 때마다 비웃기만 한다. 술로 버티는 중이고, 수영장 카메라 배터리 교체를 미룬 게 자기 탓이라 마음이 무겁다. 이채원과 시우가 사귄다는 걸 눈치챘다.' WHERE character_id = 10;

-- 피해자와의 관계, 용의자끼리의 관계를 다시 정리
DELETE FROM character_relation WHERE character_a_id BETWEEN 1 AND 10;
INSERT INTO character_relation (character_a_id, character_b_id, relation_type, description) VALUES
(2, 1, '가족', '피해자의 조카. 부모를 잃고 피해자 손에 자랐다. 지금 유언장으로는 유일한 상속인'),
(3, 1, '고용', '10년째 일한 정원사. 사실 20년 전 피해자에게 회사를 빼앗긴 옛 동업자'),
(4, 1, '고용', '3년째 일한 가정부. 사실 피해자의 혼외 딸'),
(5, 1, '업무', '15년째 고문 변호사. 피해자의 신탁 계좌를 관리하며 몰래 돈을 빼 썼다'),
(4, 3, '동료', '자주 함께 식사함. 유나는 정호에게만 자기가 피해자의 딸이라는 걸 털어놓았다'),
(5, 2, '지인', '재혁이 서진에게 호감이 있다. 저녁에 유언장 이야기를 서진에게 귀띔했다'),
(3, 2, '지인', '서진이 어릴 때 정원에서 돌봐준 사이'),
(4, 2, '가족', '유나에게 서진은 사촌. 서진은 이 사실을 모른다'),
(7, 6, '출연자', '방송에서는 시우와 러브라인. 사실 언니의 투자금을 날리게 한 사람이라 원한이 있다'),
(8, 6, '출연자', '시우 회사 화재 때 동료 소방관이 크게 다쳤다. 지아를 두고도 경쟁하는 사이'),
(9, 6, '제작', '담당 작가. 방송 중 몰래 사귀어 왔다 (제작진·출연자 연애 금지)'),
(10, 6, '제작', '촬영감독. 시우 회사에 퇴직금 5천만 원을 넣었다가 떼였다'),
(8, 7, '출연자', '도현이 지아에게 진심으로 호감이 있다'),
(10, 8, '동료', '저녁마다 같이 술을 마시며 시우 뒷담화를 한 사이'),
(10, 9, '제작', '경민은 채원과 시우가 사귄다는 걸 눈치챘다'),
(9, 7, '제작', '채원은 시우가 지아를 따로 불러낸 걸 알고 있다');

-- 사건 1: 저녁에 저마다 피해자를 찾아간 일 (사실 34~37)
INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(1, '19:20:00', '서재', '최유나가 차를 들고 서재에 가 한도윤에게 친자 검사 결과를 내밀었다. 한도윤은 5천만 원 수표를 써 주며 조용히 나가라고 했고, 유나는 수표를 찢어 버렸다.', FALSE),
(1, '19:50:00', '2층 복도', '윤재혁이 한서진에게 "삼촌이 내일 유언장을 고치신대"라고 귀띔했다.', FALSE),
(1, '20:15:00', '서재', '박정호가 서재로 찾아가 해고를 따지며 "20년 전에 나한테 한 짓"을 꺼냈다. 한도윤은 문을 닫아 버렸다.', FALSE),
(1, '21:10:00', '서재', '윤재혁이 서재로 찾아가 감사를 일주일만 미뤄 달라고 빌었지만 한도윤은 거절했다.', FALSE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(4, 34, TRUE),
(2, 35, TRUE), (5, 35, TRUE),
(3, 36, TRUE), (4, 36, FALSE),
(5, 37, TRUE);

-- 사건 1: 새 조사 지점과 단서
INSERT INTO spot (spot_id, scene_id, name) VALUES
(20, 3, '작업대 서랍'), (21, 2, '앞치마'), (22, 1, '휴지통'), (23, 1, '탁상 달력');

INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(22, 3, 20, NULL, '오래된 개업 사진', '작업대 서랍 속 빛바랜 사진. 젊은 한도윤과 박정호가 간판 앞에 나란히 서 있다. 뒷면에 "도윤·정호 공동대표, 1호점 2006"이라고 적혀 있다.', '물증', FALSE, NULL),
(23, 2, 21, NULL, '유전자 검사 결과지', '가정부 앞치마 주머니에 접힌 종이. "검사 대상: 최유나 / 한도윤, 친자 관계 확률 99.9%".', '기록', FALSE, NULL),
(24, 1, 22, NULL, '찢긴 수표', '서재 휴지통 속 반으로 찢긴 5천만 원짜리 수표. 받는 사람 칸은 비어 있고, 한도윤의 서명이 있다.', '물증', FALSE, NULL),
(25, 1, 23, NULL, '탁상 달력 메모', '한도윤 필체로 오늘 날짜 칸에 "21:10 윤 — 연기 불가. 내일 9시 감사"라고 적혀 있다.', '기록', FALSE, '21:10:00'),
(26, 1, NULL, 4, '서재의 고함', '가정부 최유나의 증언. 20시 15분쯤 서재에서 정원사가 "20년 전에 나한테 한 짓"이라며 소리치는 걸 들었다. 주인은 문을 닫아 버렸다.', '증언', FALSE, '20:15:00'),
(27, 5, NULL, 5, '조카에게 한 귀띔', '변호사 윤재혁의 증언. 19시 50분쯤 2층 복도에서 서진에게 "삼촌이 내일 유언장을 고치신대"라고 말해 줬다. 수정안이 서류가방에 있다는 말도 했다.', '증언', FALSE, '19:50:00'),
(28, 3, NULL, 3, '유나의 비밀', '정원사 박정호의 증언. 유나가 주인의 딸이라는 걸 유나에게 직접 들었다. 오늘 저녁 유나가 서재에서 울면서 나오는 걸 봤다.', '증언', FALSE, NULL);

-- 숨은 증언: 관련 증거를 내밀어야 털어놓는다
UPDATE clue SET unlock_clue_id = 14 WHERE clue_id = 27;   -- 조카에게 한 귀띔 ← 구겨진 메모 ("상속인 → 재단?")
UPDATE clue SET unlock_clue_id = 23 WHERE clue_id = 28;   -- 유나의 비밀 ← 유전자 검사 결과지

INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(9, 1, '버려진 동업자', '정원사 박정호는 20년 전 한도윤과 회사를 함께 차린 공동대표였다. 오늘 해고 통보를 받았고, 20시 15분 서재에서 "20년 전 일"로 소리쳤다.', NULL,
 '정호에게는 20년 묵은 원한이 있어요. 하지만 21시부터 창고에서 술을 마셨고, 서재의 범행과 이어지는 흔적은 없어요.'),
(10, 1, '숨겨진 딸', '최유나와 한도윤은 친자 관계다. 서재 휴지통에는 한도윤이 서명한 5천만 원 수표가 찢겨 있다.', NULL,
 '유나는 피해자의 딸인데 인정받지 못하고 돈으로 내쫓기려 했어요. 동기는 있지만 범행 시각엔 26분 동안 통화 중이었어요.'),
(11, 1, '거절당한 부탁', '피해자는 신탁 계좌 감사를 예고했고, 21시 10분 "윤 — 연기 불가"라고 적었다. 변호사의 장부에는 새로 덧쓴 숫자가 있다.', NULL,
 '재혁은 감사를 미뤄 달라고 빌었다가 거절당했어요. 그래서 장부를 고쳤을 뿐, 범행과 이어지는 흔적은 없어요.'),
(12, 1, '미리 알았던 조카', '19시 50분 재혁은 서진에게 유언장이 바뀐다고 귀띔하며 수정안이 서류가방에 있다고 말했다. 서진의 메모에는 "상속인 → 재단?"이라고 적혀 있다.', '연결',
 '서진은 범행 전에 이미 유언장이 바뀐다는 걸 알았어요. "몰랐다"는 말과 달리 삼촌을 막을 이유가 있었어요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(9, 20), (9, 22), (9, 26),
(10, 23), (10, 24),
(11, 17), (11, 25),
(12, 14), (12, 27);

-- 범인의 변명 계획 추가: 다른 사람들의 동기를 이용해 의심을 돌린다
INSERT INTO hint (character_id, content, reveal_order) VALUES
(2, '유나나 정호, 재혁의 속사정이 드러나면: 놀란 척하며 "그럼 그 사람도 삼촌을 미워할 이유가 있었네요"라고 의심을 그쪽으로 몬다. 정호 얘기를 할 때는 미안한 기색을 감춘다.', 11),
(2, '재혁의 귀띔을 들이밀면: 들은 건 맞지만 그냥 걱정돼서 메모해 둔 것뿐이고, 서류가방은 열어 보지 않았다고 한다.', 12);


-- 사건 2: 저녁에 저마다 피해자와 얽힌 일 (사실 38~39)
INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(2, '21:10:00', '장비실', '윤시우가 장비실에 들러 주경민에게 "감독님 돈은 방송 잘 나오면 돌려드리죠"라며 비웃고 나갔다.', FALSE),
(2, '22:01:00', '시우의 방', '이채원이 대화방을 지우다가, 시우가 21시 40분 한지아에게 보낸 "10시에 수영장에서 보자" 메시지를 봤다.', FALSE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(10, 38, TRUE), (9, 39, TRUE);

-- 환불 요청자 명단에 촬영감독 이름도 있다 (한지영만 눈에 띄지 않게)
UPDATE clue SET description = '시우 노트북의 엑셀 파일 "환불 요청자". 투자자 이름과 금액이 수십 줄 적혀 있다. 금액 순으로 위에서부터 "한지영 - 1억 2천", "박○○ - 8천", "주경민 - 5천"이다.' WHERE clue_id = 107;

INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(125, 11, 123, NULL, '지갑 속 기사', '소파 틈에 끼어 있던 백도현의 지갑. 오려 둔 2년 전 기사가 들어 있다. "스타트업 사무실 화재, 비상구 잠겨… 소방관 1명 중상". 기사 속 회사는 윤시우의 회사다.', '기록', FALSE, NULL),
(126, 9, 116, NULL, '편집 지시서', '원고 더미 속 편집 지시서. "21:30 거실 장면 전체 삭제, 윤시우 화내는 컷 빼기 — 이채원". 오늘 날짜다.', '기록', FALSE, NULL),
(127, 10, NULL, 10, '장비실의 조롱', '촬영감독 주경민의 증언. 21시 10분쯤 시우가 장비실에 와서 "감독님 돈은 방송 잘 나오면 돌려드리죠"라며 비웃고 갔다. 시우 회사에 퇴직금 5천만 원을 넣었다.', '증언', FALSE, '21:10:00'),
(128, 7, NULL, 9, '10시의 메시지', '작가 이채원의 증언. 22시쯤 시우의 휴대폰에서 시우가 21시 40분 한지아에게 보낸 "10시에 수영장에서 보자"라는 메시지를 봤다.', '증언', TRUE, '21:40:00');

UPDATE clue SET unlock_clue_id = 107 WHERE clue_id = 127;  -- 장비실의 조롱 ← 환불 요청자 명단 (주경민 이름)
UPDATE clue SET unlock_clue_id = 108 WHERE clue_id = 128;  -- 10시의 메시지 ← 떨어진 출입증 (시우 방에 들어간 걸 들킴)

INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(111, 2, '잠긴 비상구', '도현의 지갑에는 시우 회사 화재로 소방관이 다친 기사가 있다. 21시 30분 도현과 시우는 거실에서 몸싸움을 했고, 시우는 "원한 있는 사람이 또 있다"고 비웃었다.', NULL,
 '도현에게는 다친 동료 때문에 생긴 원한이 있어요. 하지만 범행 시각엔 헬스장에 있었어요.'),
(112, 2, '바뀐 편집본', '채원은 시우가 화내는 거실 장면을 통째로 빼라고 지시했다. 채원은 출연자와의 연애 금지 서약서에 서명했다.', NULL,
 '채원은 연애 금지를 어기고 시우를 감싸 줬어요. 들키면 일을 잃으니 동기는 되지만, 범행과 이어지는 흔적은 없어요.'),
(113, 2, '떼인 퇴직금', '환불 요청자 명단에 "주경민 - 5천"이 있다. 21시 10분 시우는 장비실에서 경민의 돈 얘기로 비웃었다.', NULL,
 '경민은 시우에게 퇴직금을 떼였어요. 동기는 있지만 카메라가 꺼진 건 배터리를 미룬 탓이고, 범행 시각엔 장비실에 있었어요.'),
(114, 2, '10시의 약속', '시우는 21시 40분 지아에게 "10시에 수영장에서 보자"고 보냈다. 지아의 30분짜리 영상은 21시 50분에 촬영이 끝났다.', '연결',
 '사망 직전 시우가 수영장으로 부른 사람은 지아였고, 지아는 약속 시각 전에 미리 영상을 다 찍어 두었어요.'),
(115, 2, '언니의 수면제', '지아의 옷장 속 약 봉투는 "환자: 한지영" 앞으로 처방된 수면제이고 4정이 비었다. 데크의 샴페인 잔 하나에는 하얀 가루 찌꺼기가 가라앉아 있다. 지아의 사진 뒷면에는 "지영 언니"라고 적혀 있다.', '연결',
 '시우가 마신 샴페인에는 지아 언니 앞으로 처방된 수면제가 들어 있었어요. 지아는 처음부터 준비해서 수영장에 간 거예요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(111, 123), (111, 125),
(112, 114), (112, 126),
(113, 107), (113, 127),
(114, 109), (114, 128);

INSERT INTO hint (character_id, content, reveal_order) VALUES
(7, '"10시에 수영장에서 보자" 메시지를 들이밀면: 받은 건 인정한다. 이것만 나왔을 때는 답장은 안 했다고만 하고 나갔는지는 말을 아낀다. 젖은 원피스나 맨발 자국까지 함께 나오면 [물러선 이야기]로 수영장에 간 걸 인정한다.', 11),
(7, '도현이나 경민, 채원의 속사정이 드러나면: "그 사람들이 시우 씨를 더 미워했을 거예요"라며 의심을 그쪽으로 돌린다.', 12);



/* 살인 트릭 강화: 범인이 꾸민 가짜 진상과 그것을 깨는 단서 */

-- 사건 1: 녹는 눈 시한장치 (사실 40~41)
INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(1, '22:10:00', '서재', '서재 쪽에서 "쿵" 하는 큰 소리가 났다. 부엌의 최유나와 한서진, 방에 있던 윤재혁이 들었다.', TRUE),
(1, '22:10:00', '서재', '눈덩이가 녹으면서 책장 맨 윗칸 끝의 청동 흉상이 시신 머리맡으로 떨어졌다.', FALSE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(2, 40, FALSE), (4, 40, FALSE), (5, 40, FALSE), (2, 41, TRUE);

INSERT INTO spot (spot_id, scene_id, name) VALUES
(24, 1, '시신 곁'), (25, 1, '난방기'), (26, 1, '책장 맨 윗칸');

INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(29, 1, 24, NULL, '머리맡의 청동 흉상', '시신 머리맡에 떨어진 청동 흉상. 무게는 4kg쯤이고 받침은 지름 12cm의 둥근 원판이다. 받침 가장자리에 피가 묻어 있다. 흉상이 떨어진 바닥 판자가 움푹 패었다.', '물증', TRUE, NULL),
(30, 1, 25, NULL, '30도의 난방기', '서재 난방기가 최고 온도 30도로 맞춰져 있다. 방 안이 후끈하다.', '물증', TRUE, NULL),
(31, 1, 24, NULL, '뒷머리 상처', '시신의 뒷머리 상처는 길이 3cm쯤의 곧은 일자 모양으로 패어 있다. 상처 둘레에 둥근 자국은 없다.', '물증', FALSE, NULL),
(32, 1, 26, NULL, '젖은 맨 윗칸', '책장 맨 윗칸 끝의 나무가 물에 젖어 부풀었다. 윗칸 끝에는 아무것도 놓여 있지 않고, 바로 아래 카펫도 축축하다.', '물증', TRUE, NULL),
(33, 2, NULL, 4, '부엌에 온 서진', '가정부 최유나의 증언. 22시쯤 평소 부엌에 오지 않던 서진이 내려와 차를 부탁하고 20분 동안 이것저것 물었다. 22시 10분 서재 쪽에서 쿵 소리가 나자 서진은 "삼촌이 또 책을 떨어뜨리셨나 봐요"라며 올라가지 말자고 했다.', '증언', FALSE, '22:00:00'),
(34, 1, NULL, 4, '늘 꺼 두던 난방', '가정부 최유나의 증언. 주인은 더위를 많이 타서 서재 난방을 늘 꺼 두었다. 19시 20분 차를 갖다 드릴 때도 서재 난방은 꺼져 있었다.', '증언', FALSE, '19:20:00');

-- 범인이 꾸민 시한장치·흉기·시신 이동을 밝히는 추론의 재료 (추론 1·8·13·14)
INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(1, 29), (1, 30), (1, 32),
(8, 3), (8, 29), (8, 31),
(13, 2), (13, 29),
(14, 11), (14, 33);

UPDATE clue SET unlock_clue_id = 30 WHERE clue_id = 34;   -- 늘 꺼 두던 난방 ← 30도의 난방기
UPDATE case_file SET investigation_limit = 16 WHERE case_id = 1;


-- 사건 2: 미리 찍은 영상과 언니의 수면제 (사실 42~45)
INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(2, '21:20:00', '지아의 방', '한지아가 30분짜리 브이로그를 찍기 시작해 21시 50분에 끝냈다.', FALSE),
(2, '22:00:00', '수영장 데크', '한지아가 샴페인을 들고 수영장에서 윤시우를 만났다. 시우는 두 잔을 마시고 어지러워했다.', FALSE),
(2, '22:00:00', '지아의 채널', '한지아의 채널에 브이로그 「제주 마지막 밤」이 최초 공개되었다.', FALSE),
(2, '22:15:00', '수영장 데크', '한지아가 자기 잔을 수영장 물에 헹궈 두고 맨발로 본관에 돌아갔다.', FALSE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(7, 42, TRUE), (7, 43, TRUE), (7, 44, FALSE), (7, 45, TRUE);

INSERT INTO spot (spot_id, scene_id, name) VALUES
(124, 6, '선베드 테이블');

INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(131, 6, 124, NULL, '샴페인 잔 두 개', '선베드 테이블 위의 샴페인 병과 잔 두 개. 한 잔에는 샴페인이 조금 남았고 바닥에 하얀 가루 찌꺼기가 가라앉아 있다. 다른 잔은 물로 헹군 듯 물기만 있다.', '물증', TRUE, NULL),
(132, 8, 113, NULL, '수면제 약 봉투', '옷장 속 파우치의 약 봉투. "환자: 한지영 (1996.04.12) / 수면제 10mg, 14정"이라고 적혀 있고, 4정이 비어 있다.', '물증', TRUE, NULL),
(133, 6, 105, NULL, '어깨의 멍', '시우의 양쪽 어깨 앞쪽에 손가락 모양 멍이 네 개씩 나란히 있다. 멍은 아직 붉다.', '물증', FALSE, NULL),
(134, 8, 110, NULL, '잠긴 노트북', '책상 위 지아의 노트북. 잠금 화면에 비밀번호 6자리를 넣는 칸이 있고, 힌트에 "언니 생일"이라고 적혀 있다.', '물증', FALSE, NULL);

-- 잠긴 노트북은 추론으로 연다: 잠금 힌트 + 약 봉투의 생년월일 → 노트북 속 채널 업로드 기록이 바로 손에 들어온다
INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note, reveal_clue_id) VALUES
(116, 2, '언니 생일', '노트북 비밀번호 힌트는 "언니 생일"이다. 약 봉투의 환자 한지영은 1996년 4월 12일생이다. 960412를 넣자 지아의 노트북이 열렸다.', NULL,
 '지아의 노트북을 여는 열쇠예요. 범행과 바로 이어지지는 않아요.', 110);

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(108, 103), (108, 131), (108, 133),
(115, 112), (115, 131), (115, 132),
(116, 132), (116, 134);

UPDATE case_file SET investigation_limit = 17 WHERE case_id = 2;

-- 단서 연결은 모두 2개로 통일: 재료가 3개였던 추론에서 하나씩 뺀다 (뺀 단서의 내용은 남은 단서나 추론 설명에 녹인다)
DELETE FROM deduction_clue WHERE (deduction_id, clue_id) IN (
  (1, 29), (3, 14), (6, 15), (8, 29), (9, 20),
  (104, 121), (105, 114), (107, 117), (108, 131), (110, 120), (115, 112)
);
UPDATE clue SET description = '책장 맨 윗칸 끝의 나무가 물에 젖어 부풀었다. 윗칸 끝에는 아무것도 놓여 있지 않고, 바로 아래 카펫도 축축하다. 그 바로 아래 바닥에 청동 흉상이 떨어져 있다.' WHERE clue_id = 32;
UPDATE deduction SET description = '책장 맨 윗칸 끝은 물에 젖어 부풀었고 그 위엔 아무것도 없다. 바로 아래에 청동 흉상이 떨어져 있다. 평소 꺼 두던 서재 난방기는 30도로 맞춰져 있었다.' WHERE deduction_id = 1;
UPDATE deduction SET description = '피해자는 내일 유언장을 고쳐 상속인을 조카에서 재단으로 바꾸려 했다. 21시 35분 서재에서는 "유언장" 얘기로 언쟁이 있었다.' WHERE deduction_id = 3;
UPDATE deduction SET description = '변호사의 회의 카메라와 마이크는 21시 38분부터 꺼져 있었고, 변호사의 신탁 계좌 장부에는 잉크가 아직 번지는 새 숫자가 덧쓰여 있다.' WHERE deduction_id = 6;
UPDATE deduction SET description = '뒷머리 상처는 길이 3cm의 곧은 일자로 패어 있고 둥근 자국은 없다. 책장의 직육면체 문진은 모서리가 각졌고, 혼자 닦여 있으며 틈에 붉은 얼룩이 남았다.' WHERE deduction_id = 8;
UPDATE deduction SET description = '정원사 박정호는 20년 전 한도윤과 회사를 함께 차린 공동대표였다. 오늘 20시 15분 서재에서 "20년 전에 나한테 한 짓"이라며 소리쳤다.' WHERE deduction_id = 9;
UPDATE deduction SET name = '언니의 돈', description = '시우의 환불 요청자 명단 맨 위는 "한지영 - 1억 2천"이다. 지아의 사진 뒷면에는 "지영 언니"라고 적혀 있다.',
  proof_note = '시우에게 1억 2천을 떼인 한지영은 지아의 언니예요. 지아에게는 시우를 미워할 이유가 있었어요.' WHERE deduction_id = 104;
UPDATE deduction SET description = '시우 휴대폰의 대화방 하나가 22시에 지워졌고, 시우 방 침대 밑에서 이채원의 출입증이 나왔다.' WHERE deduction_id = 105;
UPDATE deduction SET description = '수영장 카메라는 22시 5분 배터리 방전으로 꺼졌다. 장비실 화이트보드에는 배터리 교체를 내일 아침으로 미룬 메모가 있다.' WHERE deduction_id = 107;
UPDATE deduction SET description = '데크 모서리의 핏자국 높이는 시우의 머리 상처와 맞는다. 그런데 시우의 양 어깨 앞쪽에는 손가락 모양 멍이 네 개씩 있다.',
  proof_note = '미끄러져 빠진 사고라면 어깨를 움켜쥐고 누른 멍이 생길 수 없어요. 누군가 시우를 물속에 눌렀어요. 누가 했는지는 아직 몰라요.' WHERE deduction_id = 108;
UPDATE deduction SET description = '21시 30분 거실에서 도현과 시우가 몸싸움을 했고, 거실 바닥에는 세게 부딪혀 깨진 액자가 있다.' WHERE deduction_id = 110;
UPDATE deduction SET description = '지아의 옷장 속 약 봉투는 "환자: 한지영" 앞으로 처방된 수면제이고 4정이 비었다. 데크의 샴페인 잔 하나에는 하얀 가루 찌꺼기가 가라앉아 있다.' WHERE deduction_id = 115;

-- 인물 관계도: 플레이어 화면에 그리는 선. 단서·추론을 찾을 때마다 선이 생기거나 바뀐다
-- 짝마다 찾은 단계 중 stage_order가 가장 큰 것을 그린다. clue_id·deduction_id가 둘 다 NULL이면 처음부터 보인다
-- (character_relation.description은 AI만 읽는 진짜 관계, 여기 label은 플레이어가 지금까지 알아낸 만큼)
INSERT INTO relation_stage (character_a_id, character_b_id, stage_order, label, tone, clue_id, deduction_id) VALUES
-- 사건 1
(2, 1, 0, '조카', '관계', NULL, NULL),
(2, 1, 1, '상속인 → 재단?', '불확실', 14, NULL),
(2, 1, 2, '유언장에서 빠질 처지', '갈등', NULL, 3),
(3, 1, 0, '정원사', '관계', NULL, NULL),
(3, 1, 1, '옛 공동대표', '관계', 22, NULL),
(3, 1, 2, '20년 전 일로 고함', '갈등', 26, NULL),
(3, 1, 3, '회사를 빼앗긴 동업자', '갈등', NULL, 9),
(4, 1, 0, '가정부', '관계', NULL, NULL),
(4, 1, 1, '친자 99.9%', '관계', 23, NULL),
(4, 1, 2, '인정받지 못한 딸', '갈등', NULL, 10),
(5, 1, 0, '고문 변호사', '관계', NULL, NULL),
(5, 1, 1, '신탁 계좌 확인?', '불확실', 15, NULL),
(5, 1, 2, '감사 연기 거절', '갈등', 25, NULL),
(5, 1, 3, '감추려던 장부', '갈등', NULL, 11),
(4, 3, 0, '동료', '관계', NULL, NULL),
(4, 3, 1, '비밀을 아는 사이', '관계', 28, NULL),
(5, 2, 1, '유언장 귀띔', '관계', 27, NULL),
(4, 2, 1, '사촌', '관계', NULL, 10),
-- 사건 2
(7, 6, 0, '러브라인', '관계', NULL, NULL),
(7, 6, 1, '10시 수영장 약속', '불확실', 128, NULL),
(7, 6, 2, '언니 돈 1억 2천', '갈등', NULL, 104),
(8, 6, 0, '출연자', '관계', NULL, NULL),
(8, 6, 1, '거실 몸싸움', '갈등', 123, NULL),
(8, 6, 2, '동료가 다친 화재', '갈등', 125, NULL),
(9, 6, 0, '담당 작가', '관계', NULL, NULL),
(9, 6, 1, '몰래 연애?', '불확실', 108, NULL),
(9, 6, 2, '숨긴 연애', '갈등', NULL, 112),
(10, 6, 0, '촬영감독', '관계', NULL, NULL),
(10, 6, 1, '5천만 원 떼임', '갈등', 107, NULL),
(10, 6, 2, '돈 얘기로 조롱', '갈등', 127, NULL),
(8, 7, 0, '도현의 호감', '관계', NULL, NULL),
(10, 8, 1, '술친구?', '불확실', 117, NULL),
(9, 7, 1, '시우의 메시지를 봄', '관계', 128, NULL);

-- 검시 기록: 범인이 꾸민 겉모습 그대로 적는다 (사실만, 결론은 없음)
INSERT INTO autopsy (case_id, found_time, found_place, found_by, cause, wound, death_estimate, weapon, note) VALUES
(1, '22:30:00', '2층 서재 책장 앞, 엎드린 채', '최유나', '뒷머리 둔기 타격에 의한 두개골 골절',
 '뒷머리 오른쪽 한 곳, 길이 3cm', '21:30~22:30 · 시신이 아직 따뜻하다', '머리맡에 떨어진 청동 흉상(약 4kg), 피가 묻어 있다',
 '22:10 서재 쪽에서 "쿵" 하는 큰 소리가 났다'),
(2, '22:50:00', '수영장, 엎드린 채 물에 떠 있음', '백도현', '익사',
 '뒷머리 가운데 한 곳, 길이 4cm · 데크 모서리에 핏자국', '22:11 · 스마트워치 심박이 끊긴 시각', '뚜렷한 흉기 없음',
 '입에서 술 냄새가 난다');

-- 범인의 거짓 각본: 범인이 미리 짜 둔 단 하나의 이야기 (AI만 읽음)
-- 「지키는 선」은 끝까지 지키고, 나머지는 증거가 나오면 [변명 계획]대로 한 걸음씩 물러선다
UPDATE game_character SET cover_story = '거짓말은 단 하나: 21시 30분쯤 서재에서 삼촌과 언성을 높이고 나온 뒤로 서재에 다시 가지 않았고 삼촌은 멀쩡했다. 22시 10분 쿵 소리 때 부엌에서 유나와 함께 있었다는 건 사실이고, 이걸 가장 강한 무기로 쓴다. 나머지는 사실대로 말하거나 먼저 꺼내지 않는다.
- 19시 다섯 사람이 함께 저녁을 먹고 방으로 올라갔다.
- 21시 30분쯤 서재에 들러 유언장 얘기로 삼촌과 언성을 높였다. 금방 나왔고 그때 삼촌은 멀쩡했다. (언쟁 소리 얘기가 나오기 전에는 먼저 꺼내지 않는다)
- 그 뒤 방에서 노트북을 끄고 종이 논문 자료를 읽었다. (거짓)
- 10시 조금 전에 머리 식히러 뒷문 밖에 잠깐 나갔다가 들어왔다. (나간 건 사실, 창고에 간 건 숨긴다. 젖은 실내화나 발자국 얘기가 나오기 전에는 먼저 꺼내지 않는다)
- 22시에 부엌에 내려가 유나에게 차를 부탁하고 22시 20분까지 같이 있었다. 22시 10분 쿵 소리를 유나와 같이 들었다.
- 22시 30분 유나가 서재에서 삼촌을 발견했다는 걸 알고 서재로 갔다.' WHERE character_id = 2;
UPDATE game_character SET cover_story = '거짓말은 단 하나: 21시 57분 영상을 올린 뒤 22시 30분 라이브까지 방에서 나가지 않았다. 나머지는 사실대로 말하고, 기록으로 확인될 수 있는 시각은 처음부터 정확히 말한다.
- 저녁을 먹고 21시쯤 방에 올라왔다. (사실)
- 21시 20분~50분 방에서 브이로그 「제주 마지막 밤」을 찍었다. (사실)
- 21시 40분쯤 촬영 중에 시우에게 "10시에 수영장에서 보자"는 메시지를 받았다. (사실. 먼저 꺼내지 않고, 시우와 연락했냐고 물어도 부정하지 말고 말을 피한다. 메시지를 들이밀면 받은 건 인정하고, 나갔는지는 말을 아낀다)
- 21시 57분 영상을 올려 22시 최초 공개로 걸었다. (사실)
- 22시부터 방에서 최초 공개를 보며 댓글을 달았고, 22시 10분쯤부터 샤워를 했다. (거짓)
- 22시 25분쯤 머리가 젖은 채 물을 가지러 복도에 나갔다가 이채원 작가와 마주쳤다. (사실)
- 22시 30분 방에서 라이브를 켜고 마무리 인사를 했다. (사실)',
fallback_story = '수영장에 간 건 인정한다. "방에만 있었다"는 의심받을까 봐 무서워서 한 말이라고 한다. 이제부터 이 이야기만 말한다.
- 21시 40분쯤 시우에게 "10시에 수영장에서 보자"는 메시지를 받았다. (사실)
- 21시 57분 영상을 올려 22시 최초 공개로 걸고, 22시쯤 시우를 만나러 수영장에 잠깐 나갔다. (사실)
- 시우는 데크에서 샴페인을 마시고 있었다. 샴페인은 시우가 마시던 것이고 자기는 마시지 않았다. (거짓)
- 언니 돈 얘기를 꺼냈더니 시우가 비웃으며 장난으로 수영장 물을 잔뜩 끼얹어 원피스가 젖었다. 물에는 들어가지 않았다. (거짓. 원피스가 젖은 것만 사실)
- 22시 5분쯤 화가 나서 혼자 방으로 돌아왔다. 그때 시우는 데크에서 혼자 술을 마시며 멀쩡했다. 그 뒤로 수영장에 다시 가지 않았다. (거짓)
- 방에 와서 젖은 원피스를 바구니에 넣고 샤워했다.
- 22시 25분쯤 머리가 젖은 채 물을 가지러 복도에 나갔다가 이채원 작가와 마주쳤다. (사실)
- 22시 30분 방에서 라이브를 켜고 마무리 인사를 했다. (사실)
굳힌 진술 (몰아붙여도 바꾸지 않는다): 22시 5분에 수영장을 떠났다. 그 뒤 22시 12분 수영장의 여자 목소리, 22시 15분 맨발 그림자는 자기가 아니다. 누구였는지는 모른다. 이걸 깨는 증거가 나오면 "…저는 5분에 들어왔어요"라고만 하거나 말이 막혀 입을 다문다. 그 시각 수영장에 있었다고 인정하지 않는다.',
fallback_clue_ids = '111,102',
fallback_guard = '방에만 있었
(10시|22시)(엔|에는|에)? ?(계속 )?방에 있었
방에서 (한 번도 )?나가지 않
수영장에 (안 갔|간 적 없)
제 목소리
(그때|그 시각|12분).{0,15}수영장에 있었
22시 ?1[0-9]분.{0,15}(헤어|떠나|들어)' WHERE character_id = 7;


-- 사건 2: 한지아가 스스로 수영장에 갔다고 말하면 물러선 이야기로 넘어간다
UPDATE game_character SET fallback_admit = '수영장에\\s*(잠깐\\s*)?(나갔|갔)' WHERE character_id = 7;


-- ---------------------------------------------------------------
-- 사건 3: 가장 완벽한 결혼식 (인물 11~15, 현장 12~16, 사실 201~, 조사 지점·단서·추론 201~)
-- ---------------------------------------------------------------
INSERT INTO case_file (case_id, title, genre, difficulty, summary, truth, investigation_limit) VALUES
(3, '가장 완벽한 결혼식', '블랙코미디', '어려움',
 '11월 27일 저녁, 라비앙 로즈 웨딩홀. 본식이 끝나고 피로연이 한창이다. 20시 50분 신랑 강도훈이 무대에서 짧게 인사했고, 20시 53분 신랑 대기실로 들어가는 모습이 보였다. 21시 12분, 케이크 커팅을 위해 신랑을 부르러 간 플래너가 대기실 바닥에 쓰러진 신랑을 발견했다. 하객이 다 떠나기 전에 범인을 찾아야 한다.',
 '범인은 신랑의 사촌으로 알려진 강도준이다. 도준은 사실 도훈의 일란성 쌍둥이 동생으로, 7살 때 큰아버지 댁에 입양돼 서류상 사촌이 되었다. 도훈은 평생 동생을 행사·방송 대역으로 써 왔고, 3년 전에는 자기 음주 사고를 동생에게 뒤집어씌워 동생의 연극 주연을 날렸다. 오늘은 1억 원을 받고 12월에 출국해 다시는 같은 얼굴로 활동하지 말라는 계약서까지 내밀었다. 도준은 19시 40분 2부 대역용으로 받아 둔 턱시도 2번과 출입 카드 2번을 가지고 20시 36분 대기실 뒷문으로 들어갔다. 20시 37분 계약서를 두고 다투다 20시 39분 진열대의 황동 이중 반지 트로피로 형의 오른쪽 옆머리를 내려쳤다. 형과 똑같은 턱시도 2번으로 갈아입고 시신의 흰 장미 장식을 떼어 단 뒤, 불을 끄고 20시 47분 뒷문으로 나가 20시 50분 어두운 조명 아래에서 신랑 대신 무대 인사를 했다. 20시 53분 일부러 정문으로 대기실에 들어가는 모습을 보인 뒤 뒷문으로 빠져나와, 20시 56분 트로피를 정장 커버 안에 넣고 턱시도 2번을 반납했다. 그 뒤 로비에서 하객들과 어울렸다. 하객 모두가 20시 50분에 신랑을 봤기 때문에 사망 시각이 20시 53분 이후로 밀렸고, 그 시간대에 혼자였던 신부와 사진작가, 플래너가 의심을 받았다. 그러나 태규가 찍은 무대 사진 속 신랑의 커프스와 장식, 오른쪽 눈썹 끝 흉터는 시신과 달랐다.', 18);

INSERT INTO autopsy (case_id, found_time, found_place, found_by, cause, wound, death_estimate, weapon, note) VALUES
(3, '21:12:00', '신랑 대기실 화장대 옆 바닥, 옆으로 쓰러진 채', '장미라', '머리 타격에 의한 뇌출혈',
 '오른쪽 옆머리 한 곳 · 왼쪽 팔꿈치에 멍', '20:30~21:10 · 대기실 불이 꺼져 있었다', '현장에서 흉기로 보이는 것 없음',
 '20:50 신랑이 무대에서 인사했고, 20:53 대기실로 들어가는 신랑을 직원이 봤다');

INSERT INTO scene (scene_id, case_id, name, description) VALUES
(12, 3, '신랑 대기실', '1층 신랑 대기실. 전구 거울 화장대와 소파, 트로피 진열대가 있다. 복도 쪽 정문과 서비스 복도 쪽 뒷문이 있다.'),
(13, 3, '피로연장', '하객 원탁이 놓인 큰 홀. 무대 위에 알루미늄 트러스와 조명이 달려 있다.'),
(14, 3, '신부 대기실', '2층 신부 대기실. 둥근 거울 화장대와 2부 드레스를 건 행거가 있다.'),
(15, 3, '서비스 복도·의상실', '직원용 복도와 의상 대여 데스크. 신랑 대기실 뒷문이 이 복도로 나 있다.'),
(16, 3, '조정실', '2층 조명·음향 조정실. 창 너머로 피로연장이 내려다보인다.');

INSERT INTO game_character (character_id, case_id, name, age, gender, job, personality, character_type, is_culprit) VALUES
(11, 3, '강도훈', 34, '남', '웨딩 영상 회사 대표, 신랑', '매끄럽고 자신만만하며 남을 쓰는 데 익숙함', '피해자', FALSE),
(12, 3, '백서린', 31, '여', '화장품 회사 마케팅 이사, 신부', '빈틈없고 예의 바르지만 신경이 곤두서 있음', '용의자', FALSE),
(13, 3, '윤태규', 33, '남', '사진작가', '조용하고 감정을 꾹꾹 누르며 말을 고름', '용의자', FALSE),
(14, 3, '장미라', 38, '여', '웨딩홀 총괄 플래너', '일 처리가 정확하고 냉소적이며 말이 짧음', '용의자', FALSE),
(15, 3, '강도준', 34, '남', '무명 연극배우, 신랑의 사촌', '차분하고 예의 바르며 표정을 잘 감춤', '용의자', TRUE);

UPDATE game_character SET backstory = '웨딩 영상 회사 로즈필름 대표. 일란성 쌍둥이 동생 도준을 사촌이라 부르며 행사와 방송에 대역으로 써 왔다. 3년 전 자기 음주 사고를 동생이 대신 뒤집어썼다. 오늘 동생에게 출국 계약서를 내밀었다. 남의 약점을 쥐고 사람을 움직인다.' WHERE character_id = 11;
UPDATE game_character SET backstory = '도훈이 회사의 광고 수치 조작 자료를 쥐고 결혼을 밀어붙였다. 20시 2분 도훈에게서 "광고 수치 자료 내일 이사회에 넘긴다"는 문자를 받았다. 20시 1분 휴대폰 메모에 "잠들면 휴대폰. 자료 폴더만 지우면 끝"이라고 적었다. 20시 5분~10분 신랑 대기실에 들러, 도훈이 화장실에 간 사이 신랑 잔에 자기 처방 진정제를 탔다. 20시 30분~50분 신부 대기실에서 헤어 실장과 2부 드레스로 갈아입었고, 20시 55분~21시 8분은 혼자 신부 대기실에 있었다. 21시 도훈에게 "자?"라고 문자했지만 답이 없었다.
숨기는 것: 진정제를 탄 것, 자료를 지우려던 목적. 약병이나 신랑 잔의 진정제를 들이밀면 진정제를 탔다고 인정한다. 메모나 도훈의 문자를 들이밀면 자료를 지우려 했다고 인정한다. 도훈이 잔을 마시지 않았다는 걸 알게 되면 "그 사람이 안 마셨다니…"라며 허탈해한다. 사촌 도준과는 결혼 준비하며 몇 번 본 사이다.' WHERE character_id = 12;
UPDATE game_character SET backstory = '도훈의 대학 친구이자 4년 동안 남몰래 사귄 연인이다. 도훈은 결혼하면서 태규를 버렸고, 오늘 스냅 촬영까지 맡겼다. 20시 18분 "오늘 끝내자. 지금 갈게"라고 문자하고, 20시 20분 TG가 새겨진 자기 레터 오프너를 들고 정문으로 대기실에 갔다. 오프너로 위협했다가 손목을 잡혀 오프너를 떨어뜨렸고(소파 틈으로 들어갔다), 20시 24분 나왔다. 20시 28분부터 21시까지 피로연장에서 1~2분 간격으로 사진을 찍었다. 20시 50분 신랑 무대 인사도 찍었다. 21시 2분~9분 조정실 장비 테이블에서 메모리 카드를 백업했고, 장미라도 같은 방에 있었다.
숨기는 것: 오프너로 위협한 것, 연인 관계. 오프너나 20시 18분 문자를 들이밀면 위협했다가 손목을 잡혀 떨어뜨렸다고 인정한다. 바닷가 사진이나 문자를 들이밀면 연인이었다고 인정한다. 무대 인사 사진은 직접 찍었지만, 어두워서 신랑 얼굴을 자세히 보지는 못했다.' WHERE character_id = 13;
UPDATE game_character SET backstory = '로즈필름 공동 창업자였다. 2년 전 도훈이 미라의 기획안을 회사 소유로 돌리고 지분 30%를 0%로 만들었다. 지금은 웨딩홀 플래너로 일하며 도훈의 결혼식을 맡았다. 20시 12분 리허설 핑계로 신랑 인사 자리 위 무대 트러스의 조명 나사를 자기 4mm 렌치로 풀었다. 20시 28분 시설팀이 나사를 다시 조였다. 20시 31분부터 21시 7분까지 조정실 콘솔에서 큐를 직접 돌렸고, 21시 2분~9분에는 윤태규도 같은 방에 있었다. 21시 12분 케이크 커팅 때문에 신랑을 부르러 갔다가 시신을 발견했다. 2부 큐시트에 "20:50 신랑 무대 인사(조명 어둡게)"를 넣은 건 도훈의 요청이었다.
숨기는 것: 조명 나사를 푼 것, 지분 문제. 지분표를 들이밀면 원한을 인정한다. 렌치나 나사 자국을 들이밀면 나사를 풀었다고 인정한다. 나사가 다시 조여졌다는 얘기에는 "결국 떨어지지도 않았잖아요"라고 한다.' WHERE character_id = 14;
UPDATE game_character SET backstory = '사실 도훈의 일란성 쌍둥이 동생이다. 7살 때 큰아버지 댁에 입양돼 서류상 사촌이 되었다. 평생 형의 행사·방송 대역으로 쓰였고, 3년 전 형의 음주 사고를 대신 뒤집어써서 연극 주연이 취소됐다. 오른쪽 눈썹 끝에 흉터가 있다(형에게는 없다). 오늘 형은 1억 원을 받고 12월에 출국해 다시는 같은 얼굴로 공개 활동을 하지 말라는 계약서를 내밀었다. 서명은 하지 않았다. 웨딩홀에서는 "신랑 측 대역"으로 2부 테이블 인사를 맡기로 되어 있었다.' WHERE character_id = 15;

INSERT INTO character_relation (character_a_id, character_b_id, relation_type, description) VALUES
(12, 11, '약혼', '신부. 사실 도훈이 회사 광고 수치 조작 자료를 쥐고 결혼을 밀어붙였다'),
(13, 11, '친구', '대학 친구이자 오늘 스냅 작가. 사실 4년 동안 비밀 연인이었고 도훈의 결혼으로 버려졌다'),
(14, 11, '업무', '오늘의 총괄 플래너. 사실 로즈필름 공동 창업자로, 도훈에게 지분 30%를 빼앗겼다'),
(15, 11, '가족', '사촌으로 알려졌지만 사실 일란성 쌍둥이 동생. 평생 대역으로 쓰였고 오늘 출국 계약을 강요받았다'),
(13, 14, '동료', '오늘 같은 현장에서 일함. 21시 2분~9분 조정실에 함께 있었다'),
(12, 15, '지인', '결혼 준비하며 몇 번 본 신랑의 사촌');

-- 사실 (실제 타임라인)
INSERT INTO fact (fact_id, case_id, occurred_at, place, content, is_initial) VALUES
(201, 3, '19:00:00', '의상실', '강도훈이 신랑 턱시도 1번을 받았다.', FALSE),
(202, 3, '19:20:00', '신랑 대기실', '강도훈이 카드 1번으로 대기실 뒷문에 들어갔다.', FALSE),
(203, 3, '19:30:00', '예식홀', '본식이 끝났다.', TRUE),
(204, 3, '19:40:00', '의상실', '강도준이 2부 대역용 턱시도 2번과 카드 2번을 받았다.', FALSE),
(205, 3, '20:00:00', '피로연장', '피로연이 시작됐다.', TRUE),
(206, 3, '20:02:00', '신랑 대기실', '강도훈이 백서린에게 "광고 수치 자료 내일 이사회에 넘긴다"고 문자했다.', FALSE),
(207, 3, '20:05:00', '신랑 대기실', '백서린이 대기실에 들러, 도훈이 화장실에 간 사이 신랑 잔에 자기 처방 진정제를 탔다.', FALSE),
(208, 3, '20:12:00', '피로연장', '장미라가 리허설 핑계로 무대 트러스의 조명 나사를 4mm 렌치로 풀었다.', FALSE),
(209, 3, '20:18:00', '피로연장', '윤태규가 강도훈에게 "오늘 끝내자. 지금 갈게"라고 문자했다.', FALSE),
(210, 3, '20:20:00', '신랑 대기실', '윤태규가 정문으로 대기실에 가 레터 오프너로 위협했다가 손목을 잡혀 떨어뜨렸다. 20시 24분 나왔다.', FALSE),
(211, 3, '20:28:00', '피로연장', '시설팀이 풀린 나사를 발견해 다시 조였다. 윤태규가 피로연장 촬영을 시작했다(21시까지).', FALSE),
(212, 3, '20:30:00', '신부 대기실', '백서린이 헤어 실장과 2부 드레스로 갈아입었다(20시 50분까지).', FALSE),
(213, 3, '20:31:00', '조정실', '장미라가 조정실 콘솔에서 큐를 직접 돌리기 시작했다(21시 7분까지).', FALSE),
(214, 3, '20:36:00', '신랑 대기실', '강도준이 정장 가방을 들고 카드 2번으로 대기실 뒷문에 들어갔다.', FALSE),
(215, 3, '20:37:00', '신랑 대기실', '강도훈이 출국 계약서를 내밀며 "넌 원래 없는 사람이야"라고 했다.', FALSE),
(216, 3, '20:39:00', '신랑 대기실', '강도준이 진열대의 황동 트로피로 강도훈의 오른쪽 옆머리를 내려쳤다. 도훈은 쓰러지며 왼쪽 팔꿈치를 화장대에 부딪혔다.', FALSE),
(217, 3, '20:40:00', '신랑 대기실', '강도준이 턱시도 2번으로 갈아입고 시신의 흰 장미 장식을 떼어 달았다. 트로피를 가방에 넣고 불을 껐다.', FALSE),
(218, 3, '20:47:00', '서비스 복도', '강도준이 뒷문으로 나가 무대 뒤로 갔다.', FALSE),
(219, 3, '20:50:00', '피로연장', '신랑이 무대에 올라 하객에게 짧게 인사했다.', TRUE),
(220, 3, '20:53:00', '신랑 대기실', '직원이 신랑이 정문으로 대기실에 들어가는 걸 봤다.', TRUE),
(221, 3, '20:54:00', '서비스 복도', '강도준이 가방을 들고 뒷문으로 나갔다.', FALSE),
(222, 3, '20:56:00', '의상실', '강도준이 트로피를 정장 커버 안에 넣고 턱시도 2번을 반납했다.', FALSE),
(223, 3, '20:58:00', '로비', '강도준이 로비에서 하객들과 이야기했다(21시 12분까지).', FALSE),
(224, 3, '21:00:00', '신부 대기실', '혼자 있던 백서린이 강도훈에게 "자?"라고 문자했다.', FALSE),
(225, 3, '21:02:00', '조정실', '윤태규가 조정실 장비 테이블에서 메모리 카드를 백업했다(21시 9분까지). 장미라도 같은 방에 있었다.', FALSE),
(226, 3, '21:12:00', '신랑 대기실', '장미라가 대기실 화장대 옆 바닥에서 강도훈을 발견했다.', TRUE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(12, 203, FALSE), (13, 203, FALSE), (14, 203, FALSE), (15, 203, FALSE),
(12, 205, FALSE), (13, 205, FALSE), (14, 205, FALSE), (15, 205, FALSE),
(12, 219, FALSE), (13, 219, FALSE), (14, 219, FALSE), (15, 219, FALSE),
(12, 220, FALSE), (13, 220, FALSE), (14, 220, FALSE), (15, 220, FALSE),
(12, 226, FALSE), (13, 226, FALSE), (14, 226, FALSE), (15, 226, FALSE),
(12, 206, TRUE), (12, 207, TRUE), (12, 212, FALSE), (12, 224, FALSE),
(13, 209, TRUE), (13, 210, TRUE), (13, 211, FALSE), (13, 225, FALSE),
(14, 208, TRUE), (14, 211, FALSE), (14, 213, FALSE), (14, 225, FALSE),
(15, 204, FALSE), (15, 214, TRUE), (15, 215, TRUE), (15, 216, TRUE), (15, 217, TRUE), (15, 218, TRUE), (15, 221, TRUE), (15, 222, FALSE), (15, 223, FALSE);

-- 거짓 알리바이는 범인만. 다른 사람은 말을 아낄 뿐 사실대로 말한다
INSERT INTO alibi (character_id, claimed_time, place, statement, is_false) VALUES
(12, '20:40:00', '신부 대기실', '8시 반부터 8시 50분까지 신부 대기실에서 헤어 실장님이랑 2부 드레스로 갈아입었어요.', FALSE),
(12, '21:00:00', '신부 대기실', '그 뒤엔 혼자 신부 대기실에서 화장을 고치고 있었어요.', FALSE),
(13, '20:40:00', '피로연장', '8시 28분부터 9시까지 계속 피로연장에서 사진 찍었어요.', FALSE),
(13, '21:05:00', '조정실', '9시 넘어서는 조정실에서 메모리 카드 백업했어요. 장 실장님도 계셨고요.', FALSE),
(14, '20:40:00', '조정실', '8시 반부터 계속 조정실에서 큐를 돌렸어요.', FALSE),
(15, '20:40:00', '흡연 구역', '8시 반 넘어서부터 9시 조금 전까지 건물 뒤 흡연 구역에 혼자 있었어요.', TRUE),
(15, '21:00:00', '로비', '9시쯤부터는 로비에서 하객분들이랑 있었어요.', FALSE);

-- 조사 지점 (빈 곳도 있다). 반납 턱시도 걸이는 추론 「두 번째 신랑」을 얻어야 열린다
INSERT INTO spot (spot_id, scene_id, name, pos_x, pos_y) VALUES
(201, 12, '시신', 30.25, 90.33), (202, 12, '탁자', 84.56, 69.87), (203, 12, '진열대', 92.41, 36.20),
(204, 12, '소파', 11.10, 66.92), (205, 12, '개인 서랍', 62.38, 56.56), (206, 12, '화장대', 31.62, 44.68),
(207, 13, '무대 조명', 50.00, 14.22), (208, 13, '태규의 카메라', 82.50, 55.11), (209, 13, '하객 테이블', 32.06, 68.04),
(210, 14, '화장대 파우치', 48.67, 45.69), (211, 14, '휴대폰', 85.34, 66.04), (212, 14, '드레스 행거', 15.12, 46.33), (213, 14, '창가', 70.00, 28.89),
(214, 15, '뒷문 출입 기록기', 30.88, 41.11), (215, 15, '카드 발급 대장', 43.58, 55.51), (216, 15, '의상 대여 데스크', 60.50, 46.89),
(217, 15, '반납 턱시도 걸이', 83.75, 34.17), (218, 15, '코트 걸이', 9.00, 37.56),
(219, 16, '콘솔', 32.17, 48.67), (220, 16, '공구 서랍', 23.60, 68.61), (221, 16, '편집 PC', 56.88, 38.00),
(222, 16, '장비 테이블', 72.20, 44.00), (223, 16, '큐시트', 90.60, 34.80), (224, 16, '모니터', 28.00, 38.67);

-- 단서 문구는 사실만. 하나만으로는 누구도 확정되지 않는다
INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(201, 12, 201, NULL, '머리 상처', '오른쪽 옆머리에 둥근 곡선 압흔 두 개가 겹쳐 있다. 주변에서 황동 가루가 나왔다.', '물증', FALSE, NULL),
(202, 12, 201, NULL, '시신의 차림', '소매에 DH 이니셜이 새겨진 은색 커프스. 옷깃에 핀 구멍만 있고 장식은 없다. 오른쪽 눈썹에 흉터가 없다.', '물증', TRUE, NULL),
(203, 12, 201, NULL, '혈액 검사', '진정제·수면제 성분이 나오지 않았다. 혈중 알코올이 낮다.', '기록', FALSE, NULL),
(204, 12, 202, NULL, '신랑 잔', '"신랑"이 새겨진 샴페인 잔이 가득 찬 채 놓여 있다. 잔 속에서 진정제 성분이 나왔다.', '물증', FALSE, NULL),
(205, 12, 203, NULL, '빈 진열대', '받침대 위에 먼지 없는 둥근 자국이 있다. 안내판: "로즈필름 2025 올해의 웨딩필름상, 황동 이중 반지 트로피, 3.2kg".', '물증', FALSE, NULL),
(206, 12, 204, NULL, '레터 오프너', 'TG가 새겨진 은색 레터 오프너가 소파 틈에 끼어 있다. 날에 혈흔이 없다.', '물증', FALSE, NULL),
(207, 12, 205, NULL, '출국 계약서', '"갑 강도훈, 을 강도준. 을은 12월에 출국하며 이후 국내에서 갑과 같은 얼굴로 공개 활동을 하지 않는다. 대가 1억 원." 을의 서명란은 비어 있고, 종이가 구겨져 있다.', '기록', FALSE, NULL),
(208, 12, 205, NULL, '도훈의 휴대폰 1', '20:02 도훈→서린 "광고 수치 자료 내일 이사회에 넘긴다". 21:00 서린→도훈 "자?" (읽지 않음).', '기록', FALSE, '20:02:00'),
(209, 12, 205, NULL, '도훈의 휴대폰 2', '20:18 태규→도훈 "오늘 끝내자. 지금 갈게".', '기록', FALSE, '20:18:00'),
(210, 12, 205, NULL, '바닷가 사진', '도훈과 태규가 바닷가에서 손을 잡고 있는 사진. 뒷면에 "4주년"이라고 적혀 있다.', '물증', FALSE, NULL),
(211, 12, 205, NULL, '지분표', '로즈필름 지분표. 장미라의 지분 30%가 2년 전 0%로 바뀌었다. 비고: "기획안 저작권 회사 귀속".', '기록', FALSE, NULL),
(212, 13, 207, NULL, '조명 나사', '신랑 인사 자리 바로 위 알루미늄 트러스의 4mm 육각 나사에 새 공구 자국이 있다.', '물증', FALSE, NULL),
(213, 13, 207, NULL, '시설 점검표', '"20:28 무대 트러스 나사 풀림 발견, 재조임 완료. 시설팀 오민수".', '기록', FALSE, '20:28:00'),
(214, 13, 208, NULL, '촬영 기록', '태규의 카메라에 20:28~21:00 사진 214장이 있다. 1~2분 간격이고 모두 피로연장에서 찍혔다.', '기록', FALSE, '20:28:00'),
(215, 13, 208, NULL, '무대 인사 사진', '20:50:12 촬영. 무대의 신랑은 검은 원형 커프스와 흰 장미 장식을 달았다. 확대하면 오른쪽 눈썹 끝에 작은 흉터가 보인다.', '기록', TRUE, '20:50:00'),
(216, 14, 210, NULL, '진정제 약병', '처방자 "백서린"의 진정제 병. 절반이 비어 있다.', '물증', FALSE, NULL),
(217, 14, 211, NULL, '서린의 메모', '휴대폰 메모(20:01): "잠들면 휴대폰. 자료 폴더만 지우면 끝".', '기록', FALSE, '20:01:00'),
(218, 14, 212, NULL, '환복 기록', '헤어 실장 일지: "20:30~20:50 신부 2부 드레스 환복, 신부 대기실".', '기록', FALSE, '20:30:00'),
(219, 15, 214, NULL, '뒷문 출입 기록', '신랑 대기실 뒷문은 밖에서 들어올 때만 기록된다. 19:00~21:12 기록: 19:20 카드 1번, 20:36 카드 2번.', '기록', TRUE, '20:36:00'),
(220, 15, 215, NULL, '카드 발급 대장', '카드 1번: 강도훈. 카드 2번: "신랑 측 대역용", 수령 강도준 19:40.', '기록', FALSE, '19:40:00'),
(221, 15, 216, NULL, '의상 대여 기록', '같은 디자인의 신랑 턱시도 2벌. 1번: 강도훈 19:00 수령. 2번: 강도준 19:40 수령, 20:56 반납 스캔.', '기록', TRUE, '20:56:00'),
(222, 15, 217, NULL, '반납된 턱시도 2번', '정장 커버 안에 황동 이중 반지 트로피가 들어 있다. 한쪽 고리에 혈흔. 턱시도 오른쪽 소맷부리 안쪽에도 혈흔이 있다. 검은 원형 커프스가 달려 있다.', '물증', TRUE, NULL),
(223, 15, 218, NULL, '도준의 연극 전단', '코트 주머니 속 연극 전단. 출연자 강도준의 프로필 사진에 오른쪽 눈썹 끝 흉터가 있다.', '물증', TRUE, NULL),
(224, 16, 219, NULL, '콘솔 큐 기록', '로그인 장미라. 20:31~21:07 수동 실행 12건, 간격은 모두 6분 이하.', '기록', FALSE, '20:31:00'),
(225, 16, 220, NULL, '공구 서랍', '"장미라" 이름표가 붙은 육각 렌치 세트. 4mm 자리가 비어 있고, 4mm 렌치는 서랍 안쪽에 따로 굴러다닌다.', '물증', FALSE, NULL),
(226, 16, 221, NULL, '삭제된 사진', '성장 영상 원본 폴더. 최종본에서 빠진 사진 1장: 똑같이 생긴 아기 둘, 뒷면에 "도훈·도준 첫돌". 편집 메모: "신랑 요청으로 삭제".', '기록', FALSE, NULL),
(227, 16, 222, NULL, '백업 기록', '장비 테이블 노트북. 로그인 윤태규, 메모리 카드 백업 21:02~21:09.', '기록', FALSE, '21:02:00'),
(228, 16, 223, NULL, '2부 큐시트', '"20:50 신랑 무대 인사(조명 어둡게)", "21:30 2부 테이블 인사: 신랑(대역 가능)".', '기록', FALSE, '20:50:00');

-- 추론: 단서 2개를 이어야 얻는다. 지목 근거로는 추론만 낼 수 있다
INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(201, 3, '마시지 않은 잔', '신랑 잔에서는 진정제가 나왔지만 잔은 가득 찬 채였고, 도훈의 혈액에서는 진정제가 나오지 않았다.', NULL,
 '진정제는 도훈의 죽음과 상관없어요. 잔을 마시지 않았어요.'),
(202, 3, '서린의 약', '신랑 잔의 진정제는 백서린 앞으로 처방된 진정제와 같다. 서린의 약병은 절반이 비어 있다.', NULL,
 '서린이 신랑 잔에 약을 탄 흔적이에요. 하지만 도훈은 머리를 맞아 죽었어요.'),
(203, 3, '서린의 목적', '도훈은 서린 회사의 광고 수치 자료를 내일 이사회에 넘기려 했다. 서린은 "잠들면 휴대폰. 자료 폴더만 지우면 끝"이라고 메모했다.', NULL,
 '서린은 도훈을 재워 자료를 지우려 했어요. 죽이려던 게 아니에요.'),
(204, 3, '태규의 방문', '20:18 태규는 "지금 갈게"라고 문자했고, 대기실 소파 틈에서 TG가 새겨진 레터 오프너가 나왔다. 날에 혈흔은 없다.', NULL,
 '태규가 오프너를 들고 대기실에 왔던 흔적이에요. 오프너에는 피가 없고, 사인은 둔기예요.'),
(205, 3, '숨긴 연인', '태규는 "오늘 끝내자"라고 문자했고, 도훈과 태규가 손을 잡은 사진 뒷면에는 "4주년"이라고 적혀 있다.', NULL,
 '두 사람은 4년 된 연인이었어요. 동기는 되지만 범행 증거는 아니에요.'),
(206, 3, '태규의 동선', '태규의 카메라에는 20:28~21:00 피로연장에서 1~2분 간격으로 찍은 사진이 있고, 21:02~21:09에는 조정실에서 메모리 카드를 백업했다.', NULL,
 '태규는 20:28부터 21:09까지 혼자 대기실에 갈 틈이 없었어요.'),
(207, 3, '미라의 렌치', '트러스 나사의 새 공구 자국은 4mm 육각 렌치 자국이다. 장미라의 렌치 세트에서 4mm만 빠져 서랍 안쪽에 따로 있다.', NULL,
 '미라가 조명 나사를 풀었어요. 하지만 도훈은 대기실에서 둔기에 맞았어요.'),
(208, 3, '떨어지지 않은 조명', '풀린 나사는 20:28 시설팀이 다시 조였다. 트러스는 알루미늄이다.', NULL,
 '조명은 떨어지지 않았고, 상처에서 나온 건 황동 가루예요. 미라의 시도는 범행과 이어지지 않아요.'),
(209, 3, '조정실의 두 사람', '콘솔은 20:31~21:07 장미라 로그인으로 6분 이하 간격마다 수동 실행됐다. 21:02~21:09 같은 방에서 윤태규가 백업을 했다.', NULL,
 '미라는 조정실을 오래 비울 수 없었고, 9시 넘어서는 태규와 함께 있었어요.'),
(210, 3, '흉기', '머리 상처에는 둥근 곡선 압흔 두 개가 겹쳐 있고 황동 가루가 나왔다. 진열대에서 3.2kg 황동 이중 반지 트로피가 사라졌다.', NULL,
 '흉기는 사라진 트로피예요. 누가 썼는지는 아직 몰라요.'),
(211, 3, '서린의 환복', '헤어 실장 일지에 따르면 서린은 20:30~20:50 신부 대기실에서 2부 드레스로 갈아입었다. 그 사이 신랑 대기실 뒷문에 찍힌 건 20:36 카드 2번뿐이다.', NULL,
 '서린은 20:30~20:50 헤어 실장과 함께 있었어요.'),
(212, 3, '두 번째 신랑', '20:50 무대의 신랑은 검은 원형 커프스와 흰 장미 장식을 달았고 오른쪽 눈썹 끝에 흉터가 있다. 시신은 은색 DH 커프스에 장식이 없고, 눈썹에 흉터가 없다.', NULL,
 '20:50 무대의 신랑은 시신과 다른 사람이에요. 그게 누구인지는 이것만으로 알 수 없어요.'),
(213, 3, '쌍둥이', '도훈은 도준에게 "같은 얼굴로" 활동하지 말라는 계약서를 내밀었다. 삭제된 성장 영상 사진에는 똑같이 생긴 아기 둘과 "도훈·도준 첫돌"이 적혀 있다.', NULL,
 '도훈과 도준은 쌍둥이예요. 도준에게 동기가 있고, 형 행세를 할 수 있었어요. 하지만 범행을 증명하지는 않아요.'),
(214, 3, '무대에 선 사람', '20:50 무대 신랑의 오른쪽 눈썹 끝 흉터는 강도준의 연극 전단 프로필 사진 속 흉터와 같은 자리다.', '알리바이',
 '20:50에 무대에 선 신랑은 도준이에요. "20:50까지 신랑이 살아 있었다"는 전제가 무너지고, 흡연 구역에 혼자 있었다는 도준의 말도 거짓이에요.'),
(215, 3, '대역 카드', '대기실 뒷문에는 20:36 카드 2번이 찍혔다. 카드 2번은 "신랑 측 대역용"으로 강도준이 19:40에 받았다.', '연결',
 '도준의 카드로 20:36에 대기실 뒷문을 열었어요. 범행 시각에 도준이 현장에 들어갔다는 증거예요.'),
(216, 3, '무너진 알리바이', '20:50 무대의 신랑은 검은 원형 커프스를 달았다. 반납된 턱시도 2번에도 같은 검은 원형 커프스가 달려 있다.', '알리바이',
 '20:50의 신랑은 도훈의 턱시도 1번이 아니라 대역용 턱시도 2번을 입고 있었어요. 그 인사는 도훈이 살아 있었다는 증거가 아니에요.'),
(217, 3, '숨긴 흉기', '강도준이 19:40에 받은 턱시도 2번은 20:56 반납 스캔됐다. 그 정장 커버 안에 피 묻은 황동 트로피가 있고, 소맷부리 안쪽에도 피가 묻어 있다.', '연결',
 '흉기는 도준이 반납한 턱시도 커버 속에 있었고, 그 턱시도 소매에도 피가 묻었어요. 도준과 범행을 직접 잇는 증거예요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(201, 203), (201, 204),
(202, 204), (202, 216),
(203, 208), (203, 217),
(204, 206), (204, 209),
(205, 209), (205, 210),
(206, 214), (206, 227),
(207, 212), (207, 225),
(208, 212), (208, 213),
(209, 224), (209, 227),
(210, 201), (210, 205),
(211, 218), (211, 219),
(212, 202), (212, 215),
(213, 207), (213, 226),
(214, 215), (214, 223),
(215, 219), (215, 220),
(216, 215), (216, 222),
(217, 221), (217, 222);

UPDATE spot SET unlock_deduction_id = 212 WHERE spot_id = 217;   -- 반납 턱시도 걸이 ← 두 번째 신랑
UPDATE spot SET lock_hint = '신랑의 차림을 꼼꼼히 비교해 보세요.' WHERE spot_id = 217;

-- 인물 관계도
INSERT INTO relation_stage (character_a_id, character_b_id, stage_order, label, tone, clue_id, deduction_id) VALUES
(12, 11, 0, '신부', '관계', NULL, NULL),
(12, 11, 1, '이사회 자료?', '불확실', 208, NULL),
(12, 11, 2, '약점 잡힌 결혼', '갈등', NULL, 203),
(13, 11, 0, '대학 친구 · 스냅 작가', '관계', NULL, NULL),
(13, 11, 1, '"오늘 끝내자"', '불확실', 209, NULL),
(13, 11, 2, '4년 연인', '갈등', NULL, 205),
(14, 11, 0, '플래너 · 전 동업자', '관계', NULL, NULL),
(14, 11, 1, '빼앗긴 지분 30%', '갈등', 211, NULL),
(15, 11, 0, '사촌', '관계', NULL, NULL),
(15, 11, 1, '출국 계약 강요', '갈등', 207, NULL),
(15, 11, 2, '쌍둥이', '갈등', NULL, 213),
(13, 14, 1, '조정실에 함께', '관계', NULL, 209);

-- 범인의 거짓 각본: 거짓말은 혼자 있던 20:36~20:57 하나뿐. 기록으로 확인되는 건 처음부터 사실대로
UPDATE game_character SET cover_story = '거짓말은 단 하나: 20시 30분 넘어서부터 9시 조금 전까지 건물 뒤 흡연 구역에 혼자 있었다. 나머지는 사실대로 말하거나 먼저 꺼내지 않는다.
지키는 선: 20시 39분에 형이 살아 있었는지, 그 뒤 대기실에서 무슨 일이 있었는지는 끝까지 모른다. 트로피는 본 적도 없다.
- 형이랑은 사촌이다. (서류상 사실. 쌍둥이라는 건 먼저 꺼내지 않는다. 출국 계약서나 첫돌 사진이 나오면 "서류상 사촌, 실은 쌍둥이예요"라고 인정한다)
- 19시 40분 의상실에서 2부 대역용 턱시도 2번과 출입 카드 2번을 받았다. 2부 테이블 인사를 대신 서기로 되어 있었다. (사실)
- 20시 30분 넘어서부터 9시 조금 전까지 건물 뒤 흡연 구역에 혼자 있었다. (거짓)
- 9시 조금 전, 들어오는 길에 턱시도 2번을 반납했다. 형이 오늘은 대역 필요 없다고 했다. (반납은 사실. 형의 말은 거짓. 대여 기록이 나오기 전엔 먼저 꺼내지 않는다)
- 9시쯤부터 로비에서 하객들과 있었다. (사실)
- 8시 50분에 형이 무대에서 인사하는 건 다들 봤다. (자기가 봤다고는 하지 않는다. "다들 보셨잖아요"라고만 한다)
- 출국 계약서 얘기가 나오면: 받았지만 서명은 안 했다고 인정한다. 언제 받았는지는 먼저 말하지 않는다.',
fallback_story = '20시 36분 형 방에 들어간 건 인정한다. 흡연 구역에만 있었다는 말은 "형이랑 다툰 게 창피해서" 한 말이라고 한다. 이제부터 이 이야기만 말한다.
- 19시 40분 대역용 턱시도 2번과 카드 2번을 받았다. (사실)
- 20시 36분 카드 2번으로 대기실 뒷문으로 들어갔다. 2부 대역 얘기를 하러 갔다. (사실)
- 형이 출국 계약서를 내밀어 다퉜다. 서명은 안 했다. (사실)
- 몇 분 만에 뒷문으로 나왔다. 그때 형은 멀쩡했다. 그 뒤 흡연 구역에 있었다. (거짓)
- 무대 얘기(무대 사진의 흉터·커프스, 턱시도 2번)가 나오기 전에는 먼저 꺼내지 않는다. 나오면 이렇게 인정한다: 다툰 끝에 형이 "술 마셔서 얼굴 빨개, 8시 50분 인사 네가 서"라고 했다. 늘 하던 일이라 턱시도 2번을 입고 형의 장미 장식을 빌려 달고 20시 47분 무대 뒤로 가서 인사했다. (거짓. 형이 시켰다는 것, 장식을 빌렸다는 것이 거짓)
- 20시 53분 정문으로 대기실에 갔더니 불이 꺼져 있고 형은 누워 있었다. 자는 줄 알고 깨우지 않았다. 가방을 챙겨 뒷문으로 나왔다. (거짓. 대기실에 간 것만 사실)
- 20시 56분 턱시도 2번을 반납했다. (사실)
- 9시쯤부터 로비에서 하객들과 있었다. (사실)
굳힌 진술 (몰아붙여도 바꾸지 않는다): 내가 나올 때 형은 살아 있었다. 트로피는 본 적 없고, 턱시도 커버에 누가 넣었는지 모른다. 이걸 깨는 증거가 나오면 "…저는 반납만 했어요"라고만 하거나 말이 막혀 입을 다문다.',
fallback_clue_ids = '219,220',
fallback_admit = '(형|신랑) ?(방|대기실)에 (잠깐 )?(들렀|갔었|들어갔)',
fallback_guard = '흡연 구역에 (계속|쭉|내내)
(8시 ?반|20시 ?30분).{0,20}(계속|쭉) ?흡연
(형|신랑) ?(방|대기실)에 (안 갔|간 적 없|들르지 않|가지 않았)
트로피를 (들|쥐|휘두|넣었)' WHERE character_id = 15;

INSERT INTO hint (character_id, content, reveal_order) VALUES
(15, '알리바이를 물으면: 8시 반 넘어서부터 9시 조금 전까지 흡연 구역에 혼자 있었고, 그 뒤엔 로비에 있었다고 한다. 혼자라 증명할 사람은 없다고 담담하게 말한다.', 1),
(15, '카드 발급 대장이나 뒷문 출입 기록이 나오면: [물러선 이야기]로 물러선다. 20시 36분 형 방에 대역 얘기를 하러 들렀고, 계약서로 다투고 몇 분 만에 나왔다고 한다. 다툰 게 창피해서 말을 안 했다고 한다.', 2),
(15, '무대 인사 사진의 흉터나 커프스, 연극 전단, 턱시도 2번 얘기가 나오면: 무대엔 자기가 섰다고 인정한다. 형이 술 핑계로 대신 서라고 했고 늘 하던 일이라고 한다. 끝나고 20시 53분 방에 가 보니 형은 불 끄고 누워 있어서 깨우지 않았다고 한다.', 3),
(15, '쌍둥이 얘기(계약서, 첫돌 사진)가 나오면: 서류상 사촌, 실은 쌍둥이라고 인정한다. 7살 때 큰아버지 댁에 입양됐다고 한다. 평생 대역이었다는 말에는 씁쓸하게 웃는다.', 4),
(15, '출국 계약서 얘기가 나오면: 받았고 서명은 안 했다고 인정한다. 서명 안 한 게 무슨 잘못이냐고 한다.', 5),
(15, '머리 상처나 진열대의 트로피 얘기가 나오면: 그런 트로피가 있었는지 몰랐다고 한다. 다른 사람들도 그 방에 드나들었다며, 레터 오프너나 신랑 잔 얘기를 들었다면 그쪽으로 의심을 돌린다.', 6),
(15, '반납된 턱시도 속 트로피와 소매의 피가 나오면: 반납만 했지 커버 안은 보지 않았다고 한다. 소매의 피를 들이밀면 말이 막혀 입을 다문다. 새 이야기를 지어내지 않고, 자백하지도 않는다.', 7),
(15, '"왜 신랑인 척했냐", "왜 20시 53분에 대기실에 들어갔냐"고 몰아붙이면: 형이 2부 전에 잠깐 쉬겠다고 해서 가방을 챙기러 갔을 뿐이라고 같은 말을 되풀이한다.', 8);


-- ---------------------------------------------------------------
-- 사건 4: 동기끼리 왜 이래 (인물 16~20, 현장 17~21, 사실 301~, 조사 지점·단서·추론 301~)
-- ---------------------------------------------------------------
INSERT INTO case_file (case_id, title, genre, difficulty, summary, truth, investigation_limit) VALUES
(4, '동기끼리 왜 이래', '블랙코미디', '보통',
 '11월 27일 저녁, 대학가 상가 건물 2층 파티룸 「파티로그」. 졸업 후 6개월 만에 대학 동기 다섯 명이 모였다. 반가움도 잠시, 저녁 내내 묘한 신경전이 오가던 밤, 21시 5분 단톡방에 민규가 "나 바람 좀 쐬고 옴 찾지 마 ㅋ"라고 남겼다. 21시 50분, 답이 없는 민규를 찾던 하린이 창고 선반 아래에서 쓰러진 민규를 발견했다. 파티룸 대여 시간이 끝나기 전에 범인을 찾아야 한다.',
 '범인은 노유찬이다. 유찬은 민규가 처음 만든 팀 졸업 작품 「길냥이」를 자기 개인 프로젝트로 포트폴리오에 넣어 IT 회사에 취업했다. 민규는 19시 52분 "내일 너네 회사 인사팀에 원본이랑 작업 기록 보낸다"고 통보했다. 유찬은 20시 32분 민규를 창고로 불렀고, 20시 35분 바 카운터 꽂이에서 장식 꼬치를 빼 갔다. 20시 42분 창고에서 다투다 꼬치로 민규의 복부를 찔렀고, 민규는 유찬의 오른쪽 소매를 움켜쥐었다. 유찬은 뒷문 계단 화장실에서 꼬치와 소매를 헹군 뒤 20시 49분 꼬치를 냅킨에 싸 뒷문 밖 재활용 수거함에 버렸고, 20시 52분 메인 홀로 돌아왔다. 21시 3분~6분, 노래를 고르는 척 노트북 앞에 서서 그 노트북에 로그인돼 있던 민규의 메신저로 단톡방에 메시지를 보내 민규가 21시 5분까지 살아 있던 것처럼 꾸몄다. 하린은 계단에서 민규를 밀쳤고, 준혁은 킥보드 브레이크 선을 잘랐고, 소정은 땅콩버터를 잔에 타고 에피펜을 빼돌렸지만, 모두 사인과는 상관없고 실제 범행 시각에는 각자 다른 곳에 있었다.',
 16);

INSERT INTO autopsy (case_id, found_time, found_place, found_by, cause, wound, death_estimate, weapon, note) VALUES
(4, '21:50:00', '파티룸 창고 선반 아래, 엎드린 채', '정하린', '복부 자창에 의한 과다출혈',
 '명치 아래 좁고 깊은 자창 한 곳 · 왼쪽 손바닥 찰과상', '20:30~21:40', '현장에서 흉기로 보이는 것 없음',
 '21:05 민규 이름으로 단톡방에 "나 바람 좀 쐬고 옴 찾지 마 ㅋ"가 올라왔다');

INSERT INTO scene (scene_id, case_id, name, description) VALUES
(17, 4, '메인 홀', '파티룸의 큰 방. TV와 노트북, 노래방 기기, 긴 소파와 단체 테이블, 옷걸이가 있다.'),
(18, 4, '창고', '메인 홀 안쪽 복도 끝의 창고. 접이식 의자와 소품 상자가 쌓인 철제 선반이 있다.'),
(19, 4, '바·주방', '메인 홀 옆 바 카운터와 작은 주방. 칵테일 도구와 음료 제조대가 있다.'),
(20, 4, '뒷문·계단', '파티룸 뒷문으로 나가면 1층으로 내려가는 계단과 화장실, 건물 뒤 흡연 구역과 재활용 수거함이 있다.'),
(21, 4, '건물 앞·편의점', '건물 1층 출입구와 경비실, 화단, 옆 골목. 길 건너에 편의점이 있다.');

INSERT INTO game_character (character_id, case_id, name, age, gender, job, personality, character_type, is_culprit) VALUES
(16, 4, '차민규', 25, '남', '취업 준비생', '장난스럽고 말이 많으며 남의 약점을 잘 기억함', '피해자', FALSE),
(17, 4, '정하린', 25, '여', '갤러리 계약직', '차분하지만 화가 나면 말이 날카로움', '용의자', FALSE),
(18, 4, '서준혁', 25, '남', '스타트업 신입 개발자', '무뚝뚝하고 짧게 말하며 눈을 잘 안 마주침', '용의자', FALSE),
(19, 4, '정소정', 24, '여', '간호사', '밝고 싹싹하지만 속이 상하면 웃으며 비꼼', '용의자', FALSE),
(20, 4, '노유찬', 25, '남', 'IT 회사 신입 UX 디자이너', '말이 많고 친근하며 분위기를 잘 띄움', '용의자', TRUE);

UPDATE game_character SET backstory = '모임을 연 과대표. 남의 약점을 모아 두었다가 쓰는 사람이다. 하린과 사귈 때 하린 명의로 800만 원을 대출받았다. 준혁의 졸업 논문 대필을 알고 1년째 매달 50만 원을 받아 냈다. 하린의 동생 소정과 사귀면서 하린에게 다시 만나자고 연락했다. 유찬이 팀 졸업 작품을 자기 개인 프로젝트로 올려 취업한 걸 알고, 오늘 원본 하드를 들고 와 폭로하겠다고 했다.' WHERE character_id = 16;
UPDATE game_character SET backstory = '민규의 전 여자친구. 사귈 때 민규가 하린 명의로 800만 원을 대출받았고, 헤어진 뒤 하린 혼자 갚고 있다. 민규는 동생 소정과 사귀면서 하린에게 다시 만나자고 연락해 왔다. 20시 5분 대출 문제로 민규와 크게 다퉜다(다들 봤다). 20시 22분 뒷문 계단에서 민규를 확 밀쳤다. 민규는 왼손으로 난간을 잡아 버텼고, 그때 하린의 큐빅 나비 머리핀 하나가 계단 아래로 떨어졌다. 20시 35분쯤 유찬이 바 쪽으로 가는 걸 봤다. 20시 36분부터 51분까지 노래방에서 혼자 세 곡을 불렀다(노래 고르느라 그동안 누가 드나드는지는 못 봤다). 21시 10분~35분 머리를 식히러 혼자 건물 밖에 있었다. 21시 50분 창고에서 민규를 발견했다.
숨기는 것: 계단에서 민 것, 대출. 독촉장을 들이밀면 대출을 인정한다. 계단의 머리핀을 들이밀면 "계단에서 확 밀었어요. 걔가 난간 잡고 버텨서 아무 일도 없었어요"라고 인정한다. 민규 왼손 상처가 그때 생긴 거라는 얘기에는 "그게 그때 다친 거예요…"라고 한다.' WHERE character_id = 17;
UPDATE game_character SET backstory = '민규의 대학 절친이자 졸업 작품 팀원. 졸업 논문을 대필로 냈는데, 민규가 그걸 알고 1년째 매달 25일 50만 원을 받아 갔다. 20시 15분 민규에게 "이번이 마지막이야. 더는 못 줘"라고 보냈다. 20시 28분 건물 옆 골목에서 자기 니퍼로 민규 전동 킥보드의 앞 브레이크 선을 자르고 20시 31분 돌아왔다. 귀갓길에 넘어지기라도 하라는 마음이었다. 20시 34분~56분 건물 앞 화단에서 팀장과 통화했고, 20시 40분 경비원이 담배를 끄라고 해서 "팀장님 전화예요"라고 했다. 21시 15분~30분 뒷문 계단 화장실에 있었다.
숨기는 것: 논문 대필과 송금, 브레이크 선. 송금 내역을 들이밀면 대필 약점으로 돈을 줬다고 인정한다. 니퍼나 킥보드를 들이밀면 "집에 가다 넘어지기라도 하라고… 바보 같은 짓이었어요"라고 인정한다. 유찬이 졸작을 자기 것으로 올린 건 어렴풋이 알았지만 먼저 꺼내지 않는다.' WHERE character_id = 18;
UPDATE game_character SET backstory = '민규의 여자친구이자 하린의 동생. 간호사라 민규의 땅콩 알레르기와 에피펜을 잘 안다. 19시 40분 민규 휴대폰에서 언니에게 보낸 "우리 다시 만날래"를 봤다. 20시 25분 민규의 잔에 자기 다이어트 간식인 땅콩버터를 녹여 넣고, 민규 가방에서 에피펜을 빼 자기 코트 주머니에 넣었다. 민규는 그 잔을 마시지 않았다. 20시 36분 얼음을 사러 건물을 나가 20시 38분~57분 편의점에 있었고, 20시 57분 얼음과 숙취해소제를 결제한 뒤 20시 59분 돌아왔다. 21시 4분 메인 홀에서 휴대폰으로 동영상을 찍었다. 21시 20분~40분 주방에서 혼자 정리했다. 21시 30분 단톡방에 "어디야?"라고 보냈다.
숨기는 것: 땅콩버터, 에피펜, 언니에게 간 메시지를 본 것. 땅콩버터 병이나 민규의 잔을 들이밀면 탔다고 인정한다. 에피펜을 들이밀면 빼 뒀다고 인정한다. 민규가 잔을 마시지 않았다는 걸 알게 되면 "안 마셨구나… 다행인지 뭔지 모르겠어요"라고 한다.' WHERE character_id = 19;
UPDATE game_character SET backstory = '민규와 졸업 작품을 같이 한 동기. 민규가 처음 만든 팀 졸업 작품 「길냥이」를 자기 개인 프로젝트로 포트폴리오에 넣어 IT 회사에 취업했다. 들키면 입사 취소다. 19시 52분 민규에게서 "내일 너네 회사 인사팀에 원본이랑 작업 기록 보낸다"는 메시지를 받았다. 오늘 짙은 남색 울 재킷을 입었다. 담배는 들고 다니지만 거의 피우지 않는다. 18시 40분 민규가 메인 홀 노트북에 자기 메신저를 로그인해 둔 걸 봤다.' WHERE character_id = 20;

INSERT INTO character_relation (character_a_id, character_b_id, relation_type, description) VALUES
(17, 16, '연인', '전 여자친구. 사실 민규가 하린 명의로 800만 원을 대출받았고, 헤어진 뒤 하린이 혼자 갚고 있다'),
(18, 16, '친구', '대학 절친이자 졸작 팀원. 사실 논문 대필 약점을 잡혀 매달 50만 원을 뜯겼다'),
(19, 16, '연인', '현 여자친구. 오늘 민규가 언니에게 다시 만나자고 보낸 메시지를 봤다'),
(20, 16, '동기', '졸작 팀원. 사실 민규가 만든 졸업 작품을 자기 개인 프로젝트로 올려 취업했다'),
(17, 19, '가족', '친자매. 하린이 언니');

-- 사실 (실제 타임라인)
INSERT INTO fact (fact_id, case_id, occurred_at, place, content, is_initial) VALUES
(301, 4, '18:30:00', '파티룸', '다섯 명이 파티룸에 도착했다.', TRUE),
(302, 4, '18:40:00', '메인 홀', '민규가 메인 홀 노트북에 자기 메신저를 로그인하고 대학 사진 슬라이드쇼를 TV에 띄웠다.', TRUE),
(303, 4, '19:00:00', '메인 홀', '저녁을 먹기 시작했다. 유찬이 회사 굿즈를 나눠 줬다.', TRUE),
(304, 4, '19:10:00', '메인 홀', '민규가 유찬 회사 홈페이지의 신입 소개 화면을 캡처했다.', FALSE),
(305, 4, '19:20:00', '메인 홀', '민규가 슬라이드쇼에 졸업 작품 화면을 띄우고 "이거 누가 만들었더라?" 하며 웃었다.', TRUE),
(306, 4, '19:40:00', '메인 홀', '소정이 민규 휴대폰에서 민규가 하린에게 보낸 "우리 다시 만날래"를 봤다.', FALSE),
(307, 4, '19:52:00', '메인 홀', '민규가 유찬에게 "내일 너네 회사 인사팀에 원본이랑 작업 기록 보낸다"고 보냈다.', FALSE),
(308, 4, '20:05:00', '메인 홀', '하린과 민규가 대출 문제로 크게 다퉜다.', TRUE),
(309, 4, '20:15:00', '메인 홀', '준혁이 민규에게 "이번이 마지막이야. 더는 못 줘"라고 보냈다.', FALSE),
(310, 4, '20:22:00', '뒷문 계단', '하린이 뒷문 계단에서 민규를 밀쳤다. 민규는 왼손으로 난간을 잡아 버텼고, 하린의 머리핀 하나가 떨어졌다.', FALSE),
(311, 4, '20:25:00', '바·주방', '소정이 민규의 잔에 땅콩버터를 녹여 넣고, 민규 가방의 에피펜을 빼 자기 코트에 넣었다.', FALSE),
(312, 4, '20:28:00', '건물 옆 골목', '준혁이 니퍼로 민규 킥보드의 앞 브레이크 선을 잘랐다. 20시 31분 돌아왔다.', FALSE),
(313, 4, '20:32:00', '메인 홀', '유찬이 민규에게 "창고에서 잠깐 얘기 좀. 둘이서만"이라고 보냈다.', FALSE),
(314, 4, '20:34:00', '건물 앞', '준혁이 화단에서 팀장과 통화했다(20시 56분까지). 20시 40분 경비원이 담배를 끄라고 했다.', FALSE),
(315, 4, '20:35:00', '바·주방', '유찬이 바 카운터 꽂이에서 장식 꼬치 하나를 빼 소매에 숨겼다.', FALSE),
(316, 4, '20:36:00', '메인 홀', '하린이 노래방에서 혼자 세 곡을 불렀다(20시 51분까지).', FALSE),
(317, 4, '20:36:00', '건물 앞', '소정이 얼음을 사러 건물을 나섰다. 20시 38분~57분 편의점에 있었다.', FALSE),
(318, 4, '20:37:00', '창고', '민규가 유찬에게 "ㅇㅋ"라고 답했다. 민규 휴대폰의 마지막 잠금 해제였다.', FALSE),
(319, 4, '20:38:00', '창고', '민규와 유찬이 창고에서 만났다.', FALSE),
(320, 4, '20:42:00', '창고', '유찬이 장식 꼬치로 민규의 복부를 찔렀다. 민규가 유찬의 오른쪽 소매를 움켜쥐었다.', FALSE),
(321, 4, '20:47:00', '뒷문 계단', '유찬이 창고에서 나와 뒷문 계단 화장실에서 꼬치와 소매를 헹궜다.', FALSE),
(322, 4, '20:49:00', '흡연 구역', '유찬이 꼬치를 냅킨에 싸 뒷문 밖 재활용 수거함에 넣었다.', FALSE),
(323, 4, '20:52:00', '메인 홀', '유찬이 메인 홀로 돌아와 재킷을 옷걸이에 걸었다.', FALSE),
(324, 4, '20:59:00', '메인 홀', '소정이 돌아왔다. 이후 네 사람이 메인 홀에 있었다.', FALSE),
(325, 4, '21:03:00', '메인 홀', '유찬이 노래를 고르는 척 노트북 앞에 서서 민규 계정으로 단톡방 메시지를 보냈다(21시 6분까지).', FALSE),
(326, 4, '21:05:00', '메인 홀', '단톡방에 민규 이름으로 "나 바람 좀 쐬고 옴 찾지 마 ㅋ"가 올라왔다.', TRUE),
(327, 4, '21:10:00', '건물 앞', '하린이 혼자 건물 밖에 나가 있었다(21시 35분까지).', FALSE),
(328, 4, '21:15:00', '뒷문 계단', '준혁이 뒷문 계단 화장실에 있었다(21시 30분까지).', FALSE),
(329, 4, '21:20:00', '바·주방', '소정이 주방에서 혼자 정리했다(21시 40분까지). 21시 30분 단톡방에 "어디야?"라고 보냈다.', FALSE),
(330, 4, '21:50:00', '창고', '하린이 창고 선반 아래에서 민규를 발견했다.', TRUE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(17, 301, FALSE), (18, 301, FALSE), (19, 301, FALSE), (20, 301, FALSE),
(17, 302, FALSE), (18, 302, FALSE), (19, 302, FALSE), (20, 302, FALSE),
(17, 303, FALSE), (18, 303, FALSE), (19, 303, FALSE), (20, 303, FALSE),
(17, 305, FALSE), (18, 305, FALSE), (19, 305, FALSE), (20, 305, FALSE),
(17, 308, FALSE), (18, 308, FALSE), (19, 308, FALSE), (20, 308, FALSE),
(17, 326, FALSE), (18, 326, FALSE), (19, 326, FALSE), (20, 326, FALSE),
(17, 330, FALSE), (18, 330, FALSE), (19, 330, FALSE), (20, 330, FALSE),
(17, 310, TRUE), (17, 316, FALSE), (17, 327, FALSE),
(18, 309, TRUE), (18, 312, TRUE), (18, 314, FALSE), (18, 328, FALSE),
(19, 306, TRUE), (19, 311, TRUE), (19, 317, FALSE), (19, 324, FALSE), (19, 329, FALSE),
(20, 307, FALSE), (20, 313, TRUE), (20, 315, TRUE), (20, 318, TRUE), (20, 319, TRUE), (20, 320, TRUE), (20, 321, TRUE), (20, 322, TRUE), (20, 323, FALSE), (20, 325, TRUE);

-- 거짓 알리바이는 범인만. 다른 사람은 말을 아낄 뿐 사실대로 말한다
INSERT INTO alibi (character_id, claimed_time, place, statement, is_false) VALUES
(17, '20:40:00', '메인 홀', '8시 반 넘어서는 메인 홀 노래방에서 노래했어요. 세 곡 연달아요.', FALSE),
(17, '21:20:00', '건물 앞', '9시 넘어서는 머리 식히러 혼자 밖에 나갔다 왔어요.', FALSE),
(18, '20:40:00', '건물 앞', '8시 반쯤부터 건물 앞에서 팀장님이랑 통화했어요.', FALSE),
(18, '21:20:00', '뒷문 계단', '9시 넘어서는 뒷문 쪽 화장실에 좀 오래 있었어요.', FALSE),
(19, '20:40:00', '편의점', '8시 반 넘어 얼음 사러 편의점에 갔다가 9시쯤 왔어요.', FALSE),
(19, '21:30:00', '바·주방', '9시 넘어서는 주방에서 혼자 치웠어요.', FALSE),
(20, '20:40:00', '흡연 구역', '8시 반쯤부터 50분 조금 넘어서까지 건물 뒤 흡연 구역에서 혼자 바람 쐬었어요.', TRUE),
(20, '21:05:00', '메인 홀', '그다음부턴 쭉 메인 홀에 있었어요. 9시쯤엔 제가 노트북으로 노래 틀었고요.', FALSE);

-- 조사 지점 (빈 곳도 있다). 노트북은 추론 「멈춘 휴대폰」, 재활용 수거함은 단서 「뒷문 카메라」를 얻어야 열린다
INSERT INTO spot (spot_id, scene_id, name) VALUES
(301, 17, '노트북'), (302, 17, '노래방 기기'), (303, 17, '소정의 휴대폰'), (304, 17, '단체 테이블'), (305, 17, '옷걸이'), (306, 17, '가방 선반'),
(307, 18, '시신'), (308, 18, '민규의 휴대폰'), (309, 18, '선반'), (310, 18, '바닥'),
(311, 19, '장식 꼬치 꽂이'), (312, 19, '음료 제조대'), (313, 19, '싱크대'),
(314, 20, '뒷문 카메라'), (315, 20, '재활용 수거함'), (316, 20, '계단'), (317, 20, '흡연 구역'),
(318, 21, '출입구 카메라'), (319, 21, '경비실'), (320, 21, '편의점'), (321, 21, '골목 킥보드');

-- 단서 문구는 사실만. 하나만으로는 누구도 확정되지 않는다
INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(301, 17, 301, NULL, '노트북 메신저', '메신저 로그인 계정 차민규(18:40). 이 노트북에서 21:05 동기 단톡방으로 "나 바람 좀 쐬고 옴 찾지 마 ㅋ"가 전송됐다. 음악 앱 선곡 변경 21:03, 21:06.', '기록', TRUE, '21:05:00'),
(302, 17, 302, NULL, '노래방 점수 기록', '20:36 「다시 사랑한다 말할까」 92점, 20:41 「헤어지자 말해요」 88점, 20:46 「잘 지내자, 우리」 95점. 마이크 1번, 예약자 정하린.', '기록', FALSE, '20:36:00'),
(303, 17, 302, NULL, '노래방 녹음', '자동 녹음 20:36~20:51. 같은 여자 목소리가 쉬지 않고 세 곡을 부른다. 두 번째 곡 간주에 "이 노래 민규가 제일 싫어하던 거" 하는 말이 들어 있다.', '기록', FALSE, NULL),
(304, 17, 303, NULL, '21시 4분 영상', '소정의 휴대폰 동영상 21:04:10~21:04:40. 하린이 노래하고, 준혁이 소파에 앉아 있다. 노유찬이 TV 옆 노트북 앞에 서서 키보드를 치고 있다.', '기록', TRUE, '21:04:00'),
(305, 17, 303, NULL, '단톡방', '동기 단톡방. 21:05 차민규 "나 바람 좀 쐬고 옴 찾지 마 ㅋ". 21:30 정소정 "어디야?" (안 읽음 1).', '기록', FALSE, '21:30:00'),
(306, 17, 304, NULL, '민규의 잔', '"민규" 이름표 컵이 가득 찬 채 놓여 있다. 바닥에 갈색 앙금이 가라앉아 있고 땅콩 성분이 나왔다.', '물증', FALSE, NULL),
(307, 17, 305, NULL, '유찬의 재킷', '짙은 남색 울 재킷. 오른쪽 소맷부리 안쪽이 젖어 있고 혈흔 반응이 나왔다. 소매 단추 옆 올이 뜯겨 있다.', '물증', TRUE, NULL),
(308, 17, 305, NULL, '유찬의 담배', '재킷 주머니 속 담배 한 갑. 비닐이 뜯기지 않았다. 라이터는 없다.', '물증', FALSE, NULL),
(309, 17, 305, NULL, '민규의 가방', '지갑에 "땅콩 알레르기 – 에피펜 소지" 카드가 있다. 에피펜 케이스가 비어 있다.', '물증', FALSE, NULL),
(310, 17, 305, NULL, '소정의 코트', '베이지 코트 주머니에 에피펜 한 개. 라벨의 이름은 차민규.', '물증', FALSE, NULL),
(311, 17, 306, NULL, '준혁의 가방', '작은 니퍼 한 개. 날에 구리 가루와 검은 피복 조각이 묻어 있다. 혈흔 반응은 없다.', '물증', FALSE, NULL),
(312, 17, 306, NULL, '하린의 머리핀', '하린의 가방 앞주머니에 큐빅 나비 머리핀 한 개. 짝이 없다.', '물증', FALSE, NULL),
(313, 17, 306, NULL, '대출 독촉장', '하린의 가방 속 독촉장. "차용인 정하린, 2024년 3월 대출 800만 원". 여백에 펜으로 "민규가 받은 돈"이라고 적혀 있다.', '기록', FALSE, NULL),
(314, 18, 307, NULL, '복부 상처', '명치 아래 깊고 좁은 자창 1개. 단면은 지름 약 4mm 원형이다.', '물증', FALSE, NULL),
(315, 18, 307, NULL, '손톱 밑', '오른손 손톱 밑에서 짙은 남색 울 섬유가 나왔다.', '물증', FALSE, NULL),
(316, 18, 307, NULL, '왼손 찰과상', '왼쪽 손바닥에 가로로 긴 찰과상. 딱지가 앉기 시작했다(사망 20분 이상 전에 생김).', '물증', FALSE, NULL),
(317, 18, 307, NULL, '혈액·위 검사', '땅콩 성분이 나오지 않았다. 알레르기 반응 흔적이 없다. 혈중 알코올이 낮다.', '기록', FALSE, NULL),
(318, 18, 308, NULL, '민규의 메시지', '19:52 민규→유찬 "내일 너네 회사 인사팀에 원본이랑 작업 기록 보낸다". 20:32 유찬→민규 "창고에서 잠깐 얘기 좀. 둘이서만". 20:37 민규→유찬 "ㅇㅋ".', '기록', FALSE, '20:32:00'),
(319, 18, 308, NULL, '화면 사용 기록', '마지막 잠금 해제 20:37. 그 뒤로 잠금 해제 기록이 없다.', '기록', TRUE, '20:37:00'),
(320, 18, 308, NULL, '회사 소개 캡처', '19:10 저장. "○○소프트 신입 UX 디자이너 노유찬 – 대표 작업: 캠퍼스 길찾기 앱 「길냥이」(개인 프로젝트)".', '기록', FALSE, '19:10:00'),
(321, 18, 308, NULL, '송금 내역', '매달 25일 서준혁→차민규 50만 원, 12번, 메모 "논문". 20:15 준혁→민규 "이번이 마지막이야. 더는 못 줘".', '기록', FALSE, '20:15:00'),
(322, 18, 309, NULL, '졸작 원본', '선반 위 민규의 외장 하드. 폴더 「졸작_길냥이_원본」. 디자인 파일 최초 작성자 chaminq, 2025년 3월. 팀원: 차민규, 노유찬, 서준혁.', '기록', FALSE, NULL),
(323, 19, 311, NULL, '빈 꽂이', '스테인리스 장식 꼬치 꽂이 여섯 칸 중 한 칸이 비어 있다. 꼬치는 지름 4mm, 길이 20cm, 끝이 뾰족하다.', '물증', FALSE, NULL),
(324, 19, 312, NULL, '땅콩버터 병', '음료 제조대 아래 뚜껑 열린 땅콩버터 병과 숟가락. 병에 "소정 다이어트 간식" 스티커가 붙어 있다.', '물증', FALSE, NULL),
(325, 20, 314, NULL, '뒷문 카메라', '뒷문 밖 카메라(흡연 구역과 재활용 수거함이 보인다). 20:30~21:00 흡연 구역에 사람이 없다. 20:49 화면 오른쪽 끝에서 짙은 남색 소매의 팔이 수거함에 흰 냅킨 뭉치를 넣는다. 얼굴은 화면 밖이다.', '기록', TRUE, '20:49:00'),
(326, 20, 315, NULL, '수거함 속 꼬치', '파티룸 로고 냅킨 뭉치 안에 스테인리스 장식 꼬치. 지름 4mm, 길이 20cm. 끝에서 혈흔 반응이 나왔다.', '물증', TRUE, NULL),
(327, 20, 316, NULL, '계단 난간', '뒷문 계단 중간 난간에 가로로 문질린 피부 자국과 작은 혈흔. 계단 아래에 큐빅 나비 머리핀 한 개.', '물증', FALSE, NULL),
(328, 21, 318, NULL, '출입구 카메라', '20:28 서준혁이 건물 옆 골목으로 가고 20:31 돌아온다. 20:34~20:56 서준혁이 화단에서 통화한다. 20:36 정소정이 건물을 나서고 20:59 돌아온다.', '기록', FALSE, '20:34:00'),
(329, 21, 319, NULL, '경비 일지', '"20:40 화단에서 통화 중인 남자에게 담배 끄라고 함. ''팀장님 전화예요''라고 함".', '기록', FALSE, '20:40:00'),
(330, 21, 320, NULL, '편의점 기록', '편의점 카메라 20:38~20:57 정소정이 안에 있다. 20:57 결제: 얼음 2봉, 숙취해소제 5개, 카드 정소정.', '기록', FALSE, '20:38:00'),
(331, 21, 321, NULL, '킥보드 브레이크', '골목에 세워진 민규의 전동 킥보드. 앞 브레이크 선이 깔끔하게 잘려 있다. 단면에 구리선이 드러나 있다.', '물증', FALSE, NULL);

-- 추론: 단서 2개를 이어야 얻는다. 지목 근거로는 추론만 낼 수 있다
INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(301, 4, '흉기', '상처 단면은 지름 4mm 원형이고, 바 카운터 꽂이에서 지름 4mm 장식 꼬치 한 개가 사라졌다.', NULL,
 '흉기는 사라진 장식 꼬치예요. 누가 썼는지는 아직 몰라요.'),
(302, 4, '버려진 꼬치', '바에서 사라진 것과 같은 지름 4mm, 길이 20cm 꼬치가 피 묻은 채 뒷문 밖 재활용 수거함에서 나왔다.', NULL,
 '흉기가 수거함에 버려졌어요. 누가 버렸는지는 이것만으로 알 수 없어요.'),
(303, 4, '마시지 않은 잔', '민규의 잔에서는 땅콩 성분이 나왔지만 잔은 가득 찬 채였고, 민규의 위와 혈액에서는 땅콩 성분이 나오지 않았다.', NULL,
 '땅콩버터는 민규의 죽음과 상관없어요. 잔을 마시지 않았어요.'),
(304, 4, '빼돌린 에피펜', '민규 가방의 에피펜 케이스는 비어 있고, 민규 이름의 에피펜은 소정의 코트 주머니에 있었다.', NULL,
 '소정이 민규를 해치려 한 흔적이에요. 하지만 민규는 찔려서 죽었어요.'),
(305, 4, '소정의 동선', '소정은 20:36 건물을 나가 20:38~20:57 편의점에 있었고 20:59 돌아왔다.', NULL,
 '소정은 실제 범행 시간대에 편의점에 있었어요.'),
(306, 4, '잘린 브레이크', '민규 킥보드의 앞 브레이크 선이 잘렸고, 준혁의 니퍼에 구리 가루와 피복 조각이 묻어 있다.', NULL,
 '준혁이 브레이크 선을 자른 흔적이에요. 하지만 민규는 창고에서 찔려 죽었어요.'),
(307, 4, '준혁의 동선', '준혁은 20:34~20:56 건물 앞 화단에서 통화했고, 20:40 경비원과 말을 나눴다.', NULL,
 '준혁은 실제 범행 시간대에 건물 앞에 있었어요.'),
(308, 4, '계단의 머리핀', '뒷문 계단 아래의 큐빅 나비 머리핀은 하린의 가방 속 짝 없는 머리핀과 같은 것이다.', NULL,
 '하린이 계단에 있었던 흔적이에요. 사인은 복부 자창이에요.'),
(309, 4, '계단의 상처', '민규의 왼손 찰과상은 계단 난간에 문질린 자국과 맞고, 사망 20분 이상 전에 생겼다.', NULL,
 '왼손 상처는 계단에서 생긴 거예요. 사인과는 상관없어요.'),
(310, 4, '하린의 노래', '20:36~20:51 노래방 마이크 1번으로 하린 혼자 쉬지 않고 세 곡을 불렀다.', NULL,
 '하린은 실제 범행 시간대에 메인 홀에서 노래하고 있었어요.'),
(311, 4, '훔친 졸업 작품', '유찬이 "개인 프로젝트"로 올린 「길냥이」는 민규가 2025년 3월 처음 만든 팀 졸업 작품이다.', NULL,
 '유찬의 동기예요. 하지만 범행을 증명하지는 않아요.'),
(312, 4, '폭로 예고', '민규는 졸작 원본 하드를 들고 왔고, 19:52 유찬에게 내일 회사 인사팀에 원본을 보내겠다고 했다. 20:32 유찬이 민규를 창고로 불렀다.', NULL,
 '유찬에게 동기와 기회가 있었어요. 그래도 그것만으로 범인이라 할 수는 없어요.'),
(313, 4, '멈춘 휴대폰', '21:05 민규 이름의 단톡방 메시지가 왔지만, 민규의 휴대폰은 20:37 이후 잠금이 풀린 적이 없다.', NULL,
 '21:05 메시지는 민규 휴대폰에서 나가지 않았어요. 어디서 보냈는지는 아직 몰라요.'),
(314, 4, '무너진 알리바이', '21:05 메시지는 민규 계정이 로그인된 메인 홀 노트북에서 나갔고, 그때 노트북 앞에서 키보드를 친 사람은 노유찬이다.', '알리바이',
 '21:05의 민규는 유찬이었어요. "21:05까지 민규가 살아 있었다"는 전제가 무너지고, 유찬의 9시 이후 알리바이는 의미가 없어져요.'),
(315, 4, '흡연 구역의 빈자리', '뒷문 카메라에 20:30~21:00 흡연 구역의 사람은 없고, 유찬의 담배는 비닐도 뜯기지 않았다.', '알리바이',
 '흡연 구역에 혼자 있었다는 유찬의 말은 거짓이에요. 하지만 그 시간에 어디 있었는지는 이것만으로 몰라요.'),
(316, 4, '버린 사람', '20:49 수거함에 냅킨 뭉치를 넣은 팔은 짙은 남색 소매다. 유찬의 남색 재킷 오른쪽 소맷부리 안쪽에서 혈흔 반응이 나왔다.', '연결',
 '피 묻은 꼬치를 버린 팔은 유찬의 재킷 소매이고, 그 소매에서 피가 나왔어요. 유찬과 범행을 직접 잇는 증거예요.'),
(317, 4, '움켜쥔 소매', '민규의 손톱 밑 남색 울 섬유는 유찬의 재킷 소매와 같은 색·소재이고, 그 소매의 올이 뜯겨 있다.', '연결',
 '민규가 죽기 전에 유찬의 소매를 움켜쥐었어요. 범행 때 유찬이 민규 바로 앞에 있었다는 증거예요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(301, 314), (301, 323),
(302, 323), (302, 326),
(303, 306), (303, 317),
(304, 309), (304, 310),
(305, 328), (305, 330),
(306, 311), (306, 331),
(307, 328), (307, 329),
(308, 312), (308, 327),
(309, 316), (309, 327),
(310, 302), (310, 303),
(311, 320), (311, 322),
(312, 318), (312, 322),
(313, 305), (313, 319),
(314, 301), (314, 304),
(315, 308), (315, 325),
(316, 307), (316, 325),
(317, 307), (317, 315);

UPDATE spot SET unlock_deduction_id = 313, lock_hint = '민규의 휴대폰이 마지막으로 쓰인 때를 따져 보세요.' WHERE spot_id = 301;   -- 노트북 ← 멈춘 휴대폰
UPDATE spot SET unlock_clue_id = 325, lock_hint = '건물 뒤를 비추는 카메라가 있어요.' WHERE spot_id = 315;               -- 수거함 ← 뒷문 카메라

-- 인물 관계도
INSERT INTO relation_stage (character_a_id, character_b_id, stage_order, label, tone, clue_id, deduction_id) VALUES
(17, 16, 0, '전 연인', '관계', NULL, NULL),
(17, 16, 1, '명의 도용 대출', '갈등', 313, NULL),
(18, 16, 0, '대학 절친 · 졸작 팀원', '관계', NULL, NULL),
(18, 16, 1, '대필 약점 · 매달 50만 원', '갈등', 321, NULL),
(19, 16, 0, '연인', '관계', NULL, NULL),
(19, 16, 1, '빼돌린 에피펜', '갈등', NULL, 304),
(20, 16, 0, '졸작 팀원', '관계', NULL, NULL),
(20, 16, 1, '훔친 졸업 작품', '갈등', NULL, 311),
(20, 16, 2, '폭로 예고', '갈등', NULL, 312),
(17, 19, 0, '자매', '관계', NULL, NULL);

-- 범인의 거짓 각본: 거짓말은 혼자 있던 20:35~20:52 하나뿐. 기록으로 확인되는 건 처음부터 사실대로
UPDATE game_character SET cover_story = '거짓말은 단 하나: 8시 반쯤부터 50분 조금 넘어서까지 건물 뒤 흡연 구역에서 혼자 바람을 쐬었다. 나머지는 사실대로 말하거나 먼저 꺼내지 않는다.
지키는 선: 창고에 간 적은 먼저 말하지 않는다. 장식 꼬치는 본 적도 없다. 21시 5분 메시지는 민규가 보낸 거라고 여기는 척한다(직접 "민규가 보냈다"고 단언하지는 않고 "다들 봤잖아요"라고만 한다).
- 민규랑은 졸업 작품을 같이 한 사이다. (사실. 졸작을 자기 개인 프로젝트로 올린 건 먼저 꺼내지 않는다. 회사 소개 캡처나 원본 하드가 나오면 "팀 작업이라 제 몫도 있어요"라고 하다가, 최초 작성자가 민규라는 걸 들이밀면 인정한다)
- 19시 52분 민규에게서 회사에 원본을 보내겠다는 메시지를 받았다. (사실. 먼저 꺼내지 않고, 나오면 받았다고 인정한다)
- 8시 반쯤부터 50분 조금 넘어서까지 건물 뒤 흡연 구역에서 혼자 바람을 쐬었다. (거짓)
- 8시 52분쯤 메인 홀로 돌아왔고, 그다음부턴 쭉 메인 홀에 있었다. (사실)
- 9시쯤 노트북으로 노래를 틀었다. (사실. 메시지를 보낸 건 말하지 않는다)
- 9시 5분 민규가 바람 쐬러 간다고 단톡방에 올린 건 다들 봤다.',
fallback_story = '흡연 구역은 거짓말이었다고 인정한다. 8시 32분에 민규를 창고로 불러 졸작 얘기로 다퉜다고 한다. "다툰 게 창피해서" 흡연 구역이라고 했다고 한다. 이제부터 이 이야기만 말한다.
- 19시 52분 민규에게서 회사에 원본을 보내겠다는 메시지를 받았다. (사실)
- 20시 32분 "창고에서 잠깐 얘기 좀"이라고 보냈다. 20시 38분쯤 창고에서 만나 졸작 얘기로 다퉜다. (사실)
- 몇 분 만에 창고에서 나왔다. 그때 민규는 멀쩡했다. 뒷문 밖에 나가 바람을 쐬다 8시 52분쯤 메인 홀로 돌아왔다. (거짓. 메인 홀로 돌아온 것만 사실)
- 21시 5분 메시지 얘기(노트북 기록, 21시 4분 영상)가 나오기 전에는 먼저 꺼내지 않는다. 나오면 이렇게 인정한다: 창고에서 민규가 "혼자 있고 싶다, 애들이 찾으면 바람 쐬러 갔다고 해 줘"라고 했다. 노트북에 민규 계정이 켜져 있길래 9시 5분에 대신 쳐서 보냈다. (보낸 건 사실. 민규의 부탁은 거짓)
- 그다음부턴 쭉 메인 홀에 있었다. (사실)
굳힌 진술 (몰아붙여도 바꾸지 않는다): 내가 창고를 나올 때 민규는 살아 있었다. 꼬치는 본 적 없고, 수거함에 뭘 버린 적 없다. 소매의 얼룩은 모르겠다. 이걸 깨는 증거가 나오면 "…저는 얘기만 했어요"라고만 하거나 말이 막혀 입을 다문다.',
fallback_clue_ids = '318,325,308',
fallback_admit = '(창고|민규).{0,12}(불렀|만났|얘기했|다퉜|갔었|들어갔)',
fallback_guard = '흡연 구역에 (계속|쭉|내내)
(8시 ?반|20시 ?30분).{0,20}(계속|쭉) ?흡연
창고에 (안 갔|간 적 없|가지 않았)
꼬치를 (들|쥐|찔렀|버렸|넣었)' WHERE character_id = 20;

INSERT INTO hint (character_id, content, reveal_order) VALUES
(20, '알리바이를 물으면: 8시 반쯤부터 50분 조금 넘어서까지 건물 뒤 흡연 구역에서 혼자 바람 쐬었고, 그 뒤엔 쭉 메인 홀에 있었다고 한다. 9시 넘어서는 다들 같이 있었다고 웃으며 말한다.', 1),
(20, '20시 32분 메시지나 뒷문 카메라, 뜯지 않은 담배가 나오면: [물러선 이야기]로 물러선다. 민규를 창고로 불러 졸작 얘기로 다투고 몇 분 만에 나왔다고 한다. 다툰 게 창피해서 말을 안 했다고 한다.', 2),
(20, '노트북 메신저 기록이나 21시 4분 영상이 나오면: 9시 5분 메시지는 자기가 쳤다고 인정한다. 창고에서 민규가 혼자 있고 싶다며 애들이 찾으면 바람 쐬러 갔다고 해 달라고 했다고 한다. 노트북에 민규 계정이 켜져 있었다고 한다.', 3),
(20, '졸작 얘기(회사 소개 캡처, 원본 하드)가 나오면: 처음엔 팀 작업이라 자기 몫도 있다고 한다. 최초 작성자가 민규라는 걸 들이밀면 개인 프로젝트로 올린 건 잘못이라고 인정한다. 그래서 창고에서 얘기하려 했다고 한다.', 4),
(20, '흉기 얘기(빈 꽂이, 수거함 속 꼬치)가 나오면: 바 쪽에 그런 꼬치가 있었는지 몰랐다고 한다. 하린이 계단에 있었다거나 준혁이 밖에 오래 있었다는 얘기를 들었다면 그쪽으로 의심을 돌린다.', 5),
(20, '민규의 잔이나 에피펜 얘기가 나오면: 소정이 요즘 민규랑 사이가 안 좋았다고 슬쩍 말한다. 거짓은 보태지 않는다.', 6),
(20, '재킷 소매의 혈흔이나 손톱 밑 섬유가 나오면: 창고에서 다툴 때 민규가 소매를 잡았던 것 같다고 한다. 혈흔과 수거함에 버리는 팔을 함께 들이밀면 말이 막혀 입을 다문다. 새 이야기를 지어내지 않고, 자백하지도 않는다.', 7),
(20, '"왜 민규인 척 메시지를 보냈냐"고 몰아붙이면: 민규가 부탁했다는 같은 말을 되풀이한다.', 8);


-- ---------------------------------------------------------------
-- 기본 질문 답 (AI 없이 바로 답한다). 범인이 아닌 인물은 거짓말 없이 말을 아낄 뿐이다
-- ---------------------------------------------------------------
INSERT INTO basic_answer (character_id, topic, stage, answer, clue_ids) VALUES
-- 사건 1
(2, '알리바이', '처음', '9시 반 넘어서는 방에서 논문 자료를 읽었어요. 10시에 부엌에 내려가서 유나 씨한테 차를 부탁했고, 쿵 소리가 났을 땐 유나 씨랑 같이 있었어요.', NULL),
(2, '관계', '처음', '삼촌이에요. 열두 살에 부모님을 잃고 삼촌 손에 자랐어요. *잠시 눈을 내리깐다* 엄하셨지만… 은혜가 큰 분이에요.', NULL),
(2, '목격', '처음', '10시 10분쯤 부엌에서 쿵 소리를 들은 게 다예요. 그땐 삼촌이 또 책을 떨어뜨리셨나 했어요.', NULL),
(3, '알리바이', '처음', '9시부터 창고에 계속 있었소. 혼자였으니 증명해 줄 사람은 없소.', NULL),
(3, '관계', '처음', '10년째 이 집 정원을 돌봤소. *짧게 숨을 내쉰다* 그 이상은 지금 할 말 없소.', NULL),
(3, '목격', '처음', '창고에서 혼자 한잔하고 있었는데, 9시 50분쯤 창고 문이 열렸다 닫혔소. 문밖에서 누가 눈을 긁어모으는 소리도 났고. 취해서 누군지는 못 봤소.', '18'),
(4, '알리바이', '처음', '10시 전엔 잠깐 2층에서 개인적인 통화를 했고, 10시부터는 부엌에 있었어요. 근데 평소엔 부엌에 오지도 않던 서진 아가씨가 그때 내려와서 차를 부탁하더니, 20분 동안 이것저것 묻더라고요. 10시 10분에 서재 쪽에서 쿵 소리가 났는데, 아가씨가 "삼촌이 또 책을 떨어뜨리셨나 봐요" 하면서 올라가지 말자고 했어요.', '33'),
(4, '관계', '처음', '3년째 이 집 살림을 맡고 있어요. *앞치마를 만지작거린다* 그 이상은… 지금 말씀드리기 좀 그래요.', NULL),
(4, '목격', '처음', '저녁 무렵에 주인어른이 정원사 아저씨한테 해고 통보하시는 걸 봤어요. 8시 15분쯤엔 서재에서 아저씨가 "20년 전에 나한테 한 짓"이라면서 소리치는 것도 들었고요. 주인어른은 그냥 문을 닫아 버리셨어요.', '20,26'),
(5, '알리바이', '처음', '방에서 화상회의를 하다 10시 5분에 끝내고 서류를 보고 있었습니다. 쿵 소리는 들었지만 주인이 또 뭘 떨어뜨렸겠거니 했습니다.', NULL),
(5, '관계', '처음', '15년째 고문 변호사로 일했습니다. 신탁 계좌 관리도 제 일이었고요. 그리고 이건 말씀드려야겠군요. 회장님은 내일 유언장을 고쳐 상속인을 조카분에서 재단으로 바꾸실 생각이었습니다. 수정안은 제 서류가방에 넣어 두었고요.', '21'),
(5, '목격', '처음', '회의 중이라 방에만 있었습니다. 10시 10분쯤 쿵 소리를 들은 것 말고는 특별히 본 게 없습니다.', NULL),
-- 사건 2
(7, '알리바이', '처음', '10시엔 방에 있었어요. 제 브이로그가 10시에 최초 공개라서, 방에서 같이 보면서 댓글 달고 있었어요.', NULL),
(7, '알리바이', '물러섬', '*작게 한숨 쉰다* 아까는 의심받을까 봐 무서워서 방에만 있었다고 했어요. 10시쯤 수영장에 잠깐 나갔다가, 5분쯤 혼자 방으로 돌아왔어요. 그때 시우 씨는 데크에서 혼자 술 마시고 있었고요.', NULL),
(7, '관계', '처음', '방송에서는 다들 아시다시피 시우 씨랑 러브라인이었죠. *잠시 웃음을 거둔다* 그 이상은 개인적인 일이라서요.', NULL),
(7, '목격', '처음', '10시 25분쯤 물 가지러 복도에 나갔다가 채원 작가님이랑 마주친 것 말고는, 특별한 건 없었어요.', NULL),
(8, '알리바이', '처음', '지하 헬스장에서 혼자 운동하고 있었어요.', NULL),
(8, '관계', '처음', '같은 출연자요. *주먹을 쥐었다 편다* 솔직히 좋아하진 않았어요. 지아 씨 두고 경쟁하는 사이이기도 했고요. 나머진… 나중에 얘기해요.', NULL),
(8, '목격', '처음', '운동하느라 딴 건 못 봤어요. 10시 50분쯤 수영장에 갔다가 시우가 물에 떠 있는 걸 처음 본 게 저예요.', NULL),
(9, '알리바이', '처음', '작가실에서 내일 원고를 정리하고 있었어요.', NULL),
(9, '관계', '처음', '담당 작가였어요. *시선을 피한다* 그 이상은… 지금 말씀드리기 좀 어려워요.', NULL),
(9, '목격', '처음', '10시 25분쯤 2층 복도에서 지아 씨랑 마주쳤어요. 머리가 젖어 있어서 물어봤더니 샤워했다고 하더라고요.', '122'),
(10, '알리바이', '처음', '장비실에서 배터리 충전하고 장비 정리했소.', NULL),
(10, '관계', '처음', '촬영감독이오. 이 방송 찍으러 온 거지. *맥주캔을 만지작거린다* 사적으로 얽힌 건… 굳이 지금 말할 건 아니고.', NULL),
(10, '목격', '처음', '10시 15분쯤이었나, 장비실 창밖으로 맨발로 본관 쪽에 뛰어가는 작은 그림자를 봤소. 술이 좀 들어가서 누군지는 모르겠고.', '124'),
-- 사건 3
(12, '알리바이', '처음', '8시 반부터 8시 50분까지 신부 대기실에서 헤어 실장님이랑 2부 드레스로 갈아입었어요. 그 뒤엔 혼자 신부 대기실에서 화장을 고치고 있었어요.', NULL),
(12, '관계', '처음', '오늘 결혼식을 올린 신랑이에요. *반지를 만지며 말을 고른다* 그 이상은… 사건이랑 상관있는 얘긴가요?', NULL),
(12, '목격', '처음', '대기실에만 있어서 특별한 건 못 봤어요. 9시쯤 그 사람한테 "자?"라고 문자했는데 답이 없었어요.', NULL),
(13, '알리바이', '처음', '8시 28분부터 9시까지 계속 피로연장에서 사진 찍었어요. 9시 넘어서는 조정실에서 메모리 카드를 백업했고요. 장 실장님도 계셨어요.', NULL),
(13, '관계', '처음', '대학 친구예요. 오늘은 스냅 작가로 왔고요. *카메라 끈을 꽉 쥔다* …그 이상은 말하고 싶지 않아요.', NULL),
(13, '목격', '처음', '8시 50분 신랑 무대 인사도 제가 찍었어요. 조명이 어두워서 얼굴을 자세히 보진 못했지만요.', NULL),
(14, '알리바이', '처음', '8시 반부터 계속 조정실에서 큐 돌렸어요. 9시 넘어서는 태규 씨도 같은 방에 있었고요.', NULL),
(14, '관계', '처음', '오늘 결혼식 총괄 플래너요. 일로 엮인 사이예요. *짧게 웃는다* 그 이상은 나중에요.', NULL),
(14, '목격', '처음', '8시 28분에 시설팀이 무대 조명 나사가 풀린 걸 발견해서 다시 조였어요. 그리고 9시 12분에 케이크 커팅 때문에 신랑 부르러 갔다가… 제가 발견했어요.', NULL),
(15, '알리바이', '처음', '8시 반 넘어서부터 9시 조금 전까지 건물 뒤 흡연 구역에 혼자 있었어요. 9시쯤부터는 로비에서 하객분들이랑 있었고요.', NULL),
(15, '알리바이', '물러섬', '*시선을 떨군다* 흡연 구역에만 있었다는 건, 형이랑 다툰 게 창피해서 한 말이에요. 8시 36분에 대역 얘기를 하러 대기실 뒷문으로 들어갔다가 몇 분 만에 나왔어요. 그때 형은 멀쩡했고, 그 뒤엔 흡연 구역에 있었어요. 9시쯤부터는 로비에 있었고요.', NULL),
(15, '관계', '처음', '사촌이에요. 오늘은 신랑 측 대역으로 2부 테이블 인사를 맡기로 했었고요.', NULL),
(15, '목격', '처음', '8시 50분에 형이 무대에서 인사하는 건 다들 보셨잖아요. 저는 그 밖엔 특별히 본 게 없어요.', NULL),
-- 사건 4
(17, '알리바이', '처음', '8시 반 넘어서는 메인 홀 노래방에서 노래했어요. 세 곡 연달아요. 9시 넘어서는 머리 식히러 혼자 밖에 나갔다 왔고요.', NULL),
(17, '관계', '처음', '전 남자친구예요. *입술을 깨문다* 8시쯤 다투는 거 다들 보셨죠? 왜 다퉜는지는 제 개인적인 일이에요.', NULL),
(17, '목격', '처음', '8시 35분쯤 유찬이가 바 쪽으로 가는 걸 봤어요. 그다음엔 노래 고르느라 누가 드나드는지 못 봤고요.', NULL),
(18, '알리바이', '처음', '8시 반쯤부터 건물 앞에서 팀장님이랑 통화했어요. 9시 넘어서는 뒷문 쪽 화장실에 좀 오래 있었고요.', NULL),
(18, '관계', '처음', '대학 친구요. 졸작 팀원이었고. *눈을 피한다* …지금은 더 할 말 없어요.', NULL),
(18, '목격', '처음', '통화하느라 딴 건 못 봤어요. 8시 40분쯤 경비원이 담배 끄라고 한 거 정도요.', NULL),
(19, '알리바이', '처음', '8시 반 넘어 얼음 사러 편의점에 갔다가 9시쯤 왔어요. 9시 넘어서는 주방에서 혼자 치웠고요.', NULL),
(19, '관계', '처음', '제 남자친구예요. *웃는데 눈은 웃지 않는다* 언니 전 남자친구이기도 하고요. 재밌죠?', NULL),
(19, '목격', '처음', '9시 5분에 바람 쐬러 간다는 메시지가 올라와서 그런가 보다 했어요. 9시 반쯤엔 하도 안 보여서 단톡방에 "어디야?" 보냈고요.', NULL),
(20, '알리바이', '처음', '8시 반쯤부터 50분 조금 넘어서까지 건물 뒤 흡연 구역에서 혼자 바람 쐬었어요. 그다음부턴 쭉 메인 홀에 있었고, 9시쯤엔 제가 노트북으로 노래 틀었어요.', NULL),
(20, '알리바이', '물러섬', '*머리를 긁적인다* 흡연 구역은… 거짓말이었어요. 다툰 게 창피해서요. 8시 32분에 민규를 창고로 불러서 졸작 얘기로 좀 다퉜어요. 몇 분 만에 나왔고, 그때 민규는 멀쩡했어요. 뒷문 밖에서 바람 쐬다가 8시 52분쯤 메인 홀로 돌아왔고, 그다음부턴 쭉 메인 홀에 있었어요.', NULL),
(20, '관계', '처음', '졸업 작품 같이 한 동기예요! *밝게 웃는다* 민규 없었으면 졸작 못 끝냈죠, 진짜.', NULL),
(20, '목격', '처음', '9시 5분에 민규가 바람 쐬러 간다고 단톡방에 올린 건 다들 봤잖아요. 저는 그거 말고는 잘 모르겠어요.', NULL);


-- ---------------------------------------------------------------
-- 빈 조사 지점의 별 쓸모없는 단서 (단서 탭에는 뜨고, 연결에는 쓸 수 없다)
-- ---------------------------------------------------------------
INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time, is_filler) VALUES
(9001, 2, 8, NULL, '칼꽂이', '부엌 칼 다섯 자루가 모두 제자리에 꽂혀 있다.', '물증', FALSE, NULL, TRUE),
(9002, 4, 16, NULL, '옷장', '외투 한 벌과 셔츠 몇 벌이 걸려 있다. 아래 칸에 여행 가방이 있다.', '물증', FALSE, NULL, TRUE),
(9003, 12, 206, NULL, '화장대 위', '헤어 스프레이, 빗, 물티슈가 놓여 있다.', '물증', FALSE, NULL, TRUE),
(9004, 13, 209, NULL, '하객 테이블', '원탁마다 다 먹은 접시와 답례품 상자가 놓여 있다.', '물증', FALSE, NULL, TRUE),
(9005, 14, 213, NULL, '창가의 꽃바구니', '하객들이 보낸 꽃바구니와 축하 카드가 놓여 있다.', '물증', FALSE, NULL, TRUE),
(9006, 16, 224, NULL, '무대 모니터', '피로연장 무대가 비친다. 지금은 아무도 없다.', '물증', FALSE, NULL, TRUE),
(9007, 18, 310, NULL, '창고 바닥', '맥주 상자와 빈 페트병 몇 개가 굴러다닌다.', '물증', FALSE, NULL, TRUE),
(9008, 19, 313, NULL, '싱크대', '음식물 거름망과 고무장갑이 걸려 있다.', '물증', FALSE, NULL, TRUE),
(9009, 20, 317, NULL, '흡연 구역', '철제 재떨이 하나와 플라스틱 의자 두 개가 놓여 있다.', '물증', FALSE, NULL, TRUE);

/* 3. 뷰 */


-- 용의자 목록 (범인 여부는 빼고 보여줌)
CREATE VIEW vw_Suspect
AS
SELECT case_id, name, age, job, personality
FROM game_character
WHERE character_type = '용의자';


-- 회원별 전적
CREATE OR REPLACE VIEW vw_Record (member_id, play_count, success_count)
AS
SELECT p.member_id, COUNT(*), SUM(IF(pl.result = '성공', 1, 0))
FROM participant p, play pl
WHERE p.play_id = pl.play_id AND p.member_id IS NOT NULL
GROUP BY p.member_id;



/* 4. 인덱스 */


-- ---------------------------------------------------------------
-- 현장 그림, 단면도 지도, 얼굴 그림 (client/public 아래 파일)
-- 좌표는 그림 크기 대비 % 라서 화면 크기가 바뀌어도 같은 자리에 찍힌다
-- ---------------------------------------------------------------
UPDATE case_file SET map_url = CONCAT('/maps/case-', case_id, '.svg');
UPDATE scene SET image_url = CONCAT('/scenes/', scene_id, '.svg');
UPDATE game_character SET image_url = CONCAT('/faces/', character_id, '.png');

UPDATE scene SET map_x = 5.00, map_y = 32.38, map_w = 17.50, map_h = 26.67 WHERE scene_id = 1;
UPDATE scene SET map_x = 40.50, map_y = 60.48, map_w = 29.50, map_h = 29.52 WHERE scene_id = 2;
UPDATE scene SET map_x = 81.50, map_y = 71.43, map_w = 13.25, map_h = 18.10 WHERE scene_id = 3;
UPDATE scene SET map_x = 40.50, map_y = 32.38, map_w = 14.50, map_h = 26.67 WHERE scene_id = 4;
UPDATE scene SET map_x = 55.50, map_y = 32.38, map_w = 14.50, map_h = 26.67 WHERE scene_id = 5;
UPDATE scene SET map_x = 71.50, map_y = 59.52, map_w = 27.50, map_h = 39.52 WHERE scene_id = 6;
UPDATE scene SET map_x = 33.00, map_y = 32.38, map_w = 17.50, map_h = 26.67 WHERE scene_id = 7;
UPDATE scene SET map_x = 51.00, map_y = 32.38, map_w = 18.00, map_h = 26.67 WHERE scene_id = 8;
UPDATE scene SET map_x = 43.50, map_y = 60.48, map_w = 12.50, map_h = 29.52 WHERE scene_id = 9;
UPDATE scene SET map_x = 56.50, map_y = 60.48, map_w = 12.50, map_h = 29.52 WHERE scene_id = 10;
UPDATE scene SET map_x = 18.00, map_y = 60.48, map_w = 25.00, map_h = 29.52 WHERE scene_id = 11;
UPDATE scene SET map_x = 20.50, map_y = 60.48, map_w = 17.00, map_h = 29.52 WHERE scene_id = 12;
UPDATE scene SET map_x = 55.50, map_y = 32.38, map_w = 39.50, map_h = 57.62 WHERE scene_id = 13;
UPDATE scene SET map_x = 15.50, map_y = 32.38, map_w = 22.00, map_h = 26.67 WHERE scene_id = 14;
UPDATE scene SET map_x = 38.00, map_y = 60.48, map_w = 17.00, map_h = 29.52 WHERE scene_id = 15;
UPDATE scene SET map_x = 38.00, map_y = 32.38, map_w = 17.00, map_h = 26.67 WHERE scene_id = 16;
UPDATE scene SET map_x = 15.50, map_y = 32.38, map_w = 40.00, map_h = 26.67 WHERE scene_id = 17;
UPDATE scene SET map_x = 75.50, map_y = 32.38, map_w = 19.50, map_h = 26.67 WHERE scene_id = 18;
UPDATE scene SET map_x = 56.00, map_y = 32.38, map_w = 19.00, map_h = 26.67 WHERE scene_id = 19;
UPDATE scene SET map_x = 75.50, map_y = 60.48, map_w = 19.50, map_h = 29.52 WHERE scene_id = 20;
UPDATE scene SET map_x = 5.00, map_y = 60.48, map_w = 70.00, map_h = 29.52 WHERE scene_id = 21;

UPDATE spot SET pos_x = 46.60, pos_y = 56.90 WHERE spot_id = 1;  -- 책상 위
UPDATE spot SET pos_x = 52.40, pos_y = 77.30 WHERE spot_id = 2;  -- 책상 아래
UPDATE spot SET pos_x = 75.60, pos_y = 36.90 WHERE spot_id = 3;  -- 책장
UPDATE spot SET pos_x = 43.30, pos_y = 91.10 WHERE spot_id = 4;  -- 바닥
UPDATE spot SET pos_x = 25.00, pos_y = 26.70 WHERE spot_id = 5;  -- 창문
UPDATE spot SET pos_x = 31.45, pos_y = 53.84 WHERE spot_id = 6;  -- 개수대
UPDATE spot SET pos_x = 72.35, pos_y = 53.18 WHERE spot_id = 7;  -- 충전기
UPDATE spot SET pos_x = 54.55, pos_y = 47.48 WHERE spot_id = 8;  -- 칼꽂이
UPDATE spot SET pos_x = 36.73, pos_y = 74.49 WHERE spot_id = 9;  -- 작업대 아래
UPDATE spot SET pos_x = 71.00, pos_y = 65.78 WHERE spot_id = 10;  -- 문 앞 눈길
UPDATE spot SET pos_x = 55.00, pos_y = 30.67 WHERE spot_id = 11;  -- 장갑 걸이
UPDATE spot SET pos_x = 46.06, pos_y = 47.53 WHERE spot_id = 12;  -- 노트북
UPDATE spot SET pos_x = 75.03, pos_y = 82.91 WHERE spot_id = 14;  -- 침대 밑
UPDATE spot SET pos_x = 64.75, pos_y = 68.28 WHERE spot_id = 15;  -- 휴지통
UPDATE spot SET pos_x = 14.38, pos_y = 35.87 WHERE spot_id = 16;  -- 옷장
UPDATE spot SET pos_x = 41.26, pos_y = 53.35 WHERE spot_id = 17;  -- 책상
UPDATE spot SET pos_x = 51.99, pos_y = 46.15 WHERE spot_id = 18;  -- 노트북
UPDATE spot SET pos_x = 86.83, pos_y = 77.24 WHERE spot_id = 19;  -- 서류가방
UPDATE spot SET pos_x = 21.74, pos_y = 64.60 WHERE spot_id = 20;  -- 작업대 서랍
UPDATE spot SET pos_x = 17.12, pos_y = 33.33 WHERE spot_id = 21;  -- 앞치마
UPDATE spot SET pos_x = 25.75, pos_y = 76.00 WHERE spot_id = 22;  -- 휴지통
UPDATE spot SET pos_x = 57.50, pos_y = 55.60 WHERE spot_id = 23;  -- 탁상 달력
UPDATE spot SET pos_x = 81.25, pos_y = 87.10 WHERE spot_id = 24;  -- 시신 곁
UPDATE spot SET pos_x = 25.10, pos_y = 56.20 WHERE spot_id = 25;  -- 난방기
UPDATE spot SET pos_x = 82.00, pos_y = 21.30 WHERE spot_id = 26;  -- 책장 맨 윗칸
UPDATE spot SET pos_x = 31.27, pos_y = 60.61 WHERE spot_id = 101;  -- 수영장 필터
UPDATE spot SET pos_x = 41.88, pos_y = 41.96 WHERE spot_id = 102;  -- 데크 바닥
UPDATE spot SET pos_x = 87.89, pos_y = 84.76 WHERE spot_id = 103;  -- 데크 모서리
UPDATE spot SET pos_x = 86.25, pos_y = 43.72 WHERE spot_id = 104;  -- 흡연 구역
UPDATE spot SET pos_x = 56.11, pos_y = 62.28 WHERE spot_id = 105;  -- 시신 곁
UPDATE spot SET pos_x = 65.14, pos_y = 52.80 WHERE spot_id = 106;  -- 휴대폰
UPDATE spot SET pos_x = 21.26, pos_y = 47.53 WHERE spot_id = 107;  -- 노트북
UPDATE spot SET pos_x = 77.50, pos_y = 87.67 WHERE spot_id = 108;  -- 침대
UPDATE spot SET pos_x = 44.75, pos_y = 32.00 WHERE spot_id = 109;  -- 삼각대 휴대폰
UPDATE spot SET pos_x = 69.95, pos_y = 64.62 WHERE spot_id = 110;  -- 노트북
UPDATE spot SET pos_x = 5.60, pos_y = 79.73 WHERE spot_id = 111;  -- 욕실 바구니
UPDATE spot SET pos_x = 95.68, pos_y = 41.80 WHERE spot_id = 112;  -- 화장대
UPDATE spot SET pos_x = 27.04, pos_y = 30.84 WHERE spot_id = 113;  -- 옷장
UPDATE spot SET pos_x = 26.25, pos_y = 26.67 WHERE spot_id = 114;  -- 창문
UPDATE spot SET pos_x = 46.70, pos_y = 53.40 WHERE spot_id = 115;  -- 책상
UPDATE spot SET pos_x = 86.63, pos_y = 73.23 WHERE spot_id = 116;  -- 원고 더미
UPDATE spot SET pos_x = 18.03, pos_y = 35.98 WHERE spot_id = 117;  -- 녹화기
UPDATE spot SET pos_x = 51.25, pos_y = 26.22 WHERE spot_id = 118;  -- 화이트보드
UPDATE spot SET pos_x = 86.75, pos_y = 76.00 WHERE spot_id = 119;  -- 구석
UPDATE spot SET pos_x = 69.00, pos_y = 32.22 WHERE spot_id = 120;  -- 출입 태그 모니터
UPDATE spot SET pos_x = 82.43, pos_y = 89.76 WHERE spot_id = 121;  -- 바닥
UPDATE spot SET pos_x = 92.25, pos_y = 70.13 WHERE spot_id = 122;  -- 쓰레기통
UPDATE spot SET pos_x = 57.00, pos_y = 62.31 WHERE spot_id = 123;  -- 소파
UPDATE spot SET pos_x = 18.95, pos_y = 62.78 WHERE spot_id = 124;  -- 선베드 테이블

-- 사건 4 조사 지점
UPDATE spot SET pos_x = 70.40, pos_y = 43.82 WHERE spot_id = 301;
UPDATE spot SET pos_x = 28.00, pos_y = 59.38 WHERE spot_id = 302;
UPDATE spot SET pos_x = 57.80, pos_y = 74.22 WHERE spot_id = 303;
UPDATE spot SET pos_x = 37.31, pos_y = 68.78 WHERE spot_id = 304;
UPDATE spot SET pos_x = 95.94, pos_y = 32.56 WHERE spot_id = 305;
UPDATE spot SET pos_x = 19.50, pos_y = 30.67 WHERE spot_id = 306;
UPDATE spot SET pos_x = 38.06, pos_y = 86.11 WHERE spot_id = 307;
UPDATE spot SET pos_x = 62.25, pos_y = 83.56 WHERE spot_id = 308;
UPDATE spot SET pos_x = 34.38, pos_y = 45.11 WHERE spot_id = 309;
UPDATE spot SET pos_x = 16.00, pos_y = 92.00 WHERE spot_id = 310;
UPDATE spot SET pos_x = 36.70, pos_y = 49.78 WHERE spot_id = 311;
UPDATE spot SET pos_x = 92.88, pos_y = 79.56 WHERE spot_id = 312;
UPDATE spot SET pos_x = 68.20, pos_y = 47.20 WHERE spot_id = 313;
UPDATE spot SET pos_x = 61.25, pos_y = 22.22 WHERE spot_id = 314;
UPDATE spot SET pos_x = 85.88, pos_y = 60.00 WHERE spot_id = 315;
UPDATE spot SET pos_x = 22.50, pos_y = 53.33 WHERE spot_id = 316;
UPDATE spot SET pos_x = 68.00, pos_y = 58.67 WHERE spot_id = 317;
UPDATE spot SET pos_x = 31.50, pos_y = 44.89 WHERE spot_id = 318;
UPDATE spot SET pos_x = 11.75, pos_y = 54.22 WHERE spot_id = 319;
UPDATE spot SET pos_x = 65.00, pos_y = 47.56 WHERE spot_id = 320;
UPDATE spot SET pos_x = 47.75, pos_y = 60.44 WHERE spot_id = 321;

-- 사실을 사건별, 시각 순으로 자주 조회
CREATE INDEX ix_fact_time ON fact(case_id, occurred_at);

-- 타임라인 항목을 참가자별, 시각 순으로 자주 조회
CREATE INDEX ix_timeline_time ON timeline_entry(participant_id, event_time);
