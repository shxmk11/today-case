-- 오늘의 사건 게임 DB (DB 설계 과제 스키마 그대로 사용)
-- MySQL 8.0

SET NAMES utf8mb4;

DROP DATABASE IF EXISTS today_case;
CREATE DATABASE today_case DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE today_case;


/* 1. 테이블 생성 */

-- 회원
CREATE TABLE member (
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

-- 심문 기록
CREATE TABLE interrogation (
    interrogation_id INT NOT NULL AUTO_INCREMENT,
    participant_id INT NOT NULL,
    character_id INT NOT NULL,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    asked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (interrogation_id),
    CONSTRAINT fk_interrogation_participant FOREIGN KEY (participant_id)
        REFERENCES participant (participant_id) ON DELETE CASCADE,
    CONSTRAINT fk_interrogation_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id)
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


/* 2. 사건 데이터 */

-- 사건 1: 별장의 마지막 밤 (인물 1~5, 현장 1~5, 사실 1~14, 조사 지점·단서·추론 1~)
INSERT INTO case_file (title, genre, difficulty, summary, truth, investigation_limit) VALUES
('별장의 마지막 밤', '클로즈드 서클', '보통',
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


-- 사건 2: 여름, 너에게 (인물 6~10, 현장 6~11, 사실 15~30, 조사 지점·단서·추론 101~)
INSERT INTO case_file (title, genre, difficulty, summary, truth, investigation_limit) VALUES
('여름, 너에게', '연애 리얼리티', '보통',
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

-- 사실을 사건별, 시각 순으로 자주 조회
CREATE INDEX ix_fact_time ON fact(case_id, occurred_at);

-- 타임라인 항목을 참가자별, 시각 순으로 자주 조회
CREATE INDEX ix_timeline_time ON timeline_entry(participant_id, event_time);
