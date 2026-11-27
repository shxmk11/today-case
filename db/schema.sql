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
    investigation_limit INT NOT NULL DEFAULT 12,  -- 조사 횟수 (조사 지점 열기 + 틀린 연결이 1회씩 씀)
    PRIMARY KEY (case_id),
    CONSTRAINT chk_case_limit CHECK (investigation_limit > 0)
);

-- 사건 현장
CREATE TABLE scene (
    scene_id INT NOT NULL AUTO_INCREMENT,
    case_id INT NOT NULL,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),
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

-- 추론 (단서 2~3개를 연결해야 얻는 사실)
CREATE TABLE deduction (
    deduction_id INT NOT NULL AUTO_INCREMENT,
    case_id INT NOT NULL,
    name VARCHAR(50) NOT NULL,
    description VARCHAR(500) NOT NULL,
    proof_role ENUM('알리바이', '연결') NULL,  -- 범인 지목 근거: 알리바이를 깨는 추론 / 범인과 범행을 잇는 추론
    proof_note VARCHAR(255) NULL,            -- 결과 화면에서 이 추론이 근거로 왜 맞는지·부족한지 설명
    PRIMARY KEY (deduction_id),
    CONSTRAINT fk_deduction_case FOREIGN KEY (case_id)
        REFERENCES case_file (case_id) ON DELETE CASCADE
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

-- 단서 연결 시도 (deduction_id가 NULL이면 틀린 연결 = 조사 1회 차감)
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
 '조카 한서진은 20시 30분 변호사의 서류가방에서 유언장 수정안을 몰래 읽고, 삼촌이 상속인을 자신에서 재단으로 바꾸려 한다는 걸 알았다. 21시 35분 서재에서 언쟁을 벌이다 21시 40분 청동 문진으로 삼촌을 내려쳤고, 이때 떨어진 탁상시계가 멈췄다. 21시 50분 실내화 차림으로 눈길을 지나 창고에서 정원사의 장갑 한 짝을 가져와 서재에 떨어뜨리고 문진을 닦아 제자리에 두었다. 22시 2분 논문을 출력해 계속 방에 있던 것처럼 꾸몄지만, 노트북의 마지막 저장은 21시 31분이었다.', 12);

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
(1, '21:40:00', '서재', '한서진이 청동 문진으로 한도윤을 내려쳤다. 떨어진 탁상시계가 멈췄다.', FALSE),
(1, '21:50:00', '정원 창고', '한서진이 실내화 차림으로 창고에 가 정원사 장갑 한 짝을 가져갔다.', FALSE),
(1, '21:55:00', '서재', '한서진이 장갑을 서재 바닥에 떨어뜨리고 문진을 닦아 제자리에 두었다.', FALSE),
(1, '22:02:00', '서진의 방', '한서진이 논문을 출력해 방에 계속 있었던 것처럼 꾸몄다.', FALSE),
(1, '22:30:00', '서재', '최유나가 시신을 발견했다.', TRUE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(2, 1, FALSE), (3, 1, FALSE), (4, 1, FALSE), (5, 1, FALSE),
(2, 3, FALSE), (3, 3, FALSE), (4, 3, FALSE), (5, 3, FALSE),
(2, 14, FALSE), (3, 14, FALSE), (4, 14, FALSE), (5, 14, FALSE),
(2, 6, TRUE), (2, 9, TRUE), (2, 10, TRUE), (2, 11, TRUE), (2, 12, TRUE), (2, 13, TRUE),
(3, 2, TRUE), (3, 7, TRUE),
(4, 2, FALSE), (4, 8, TRUE), (4, 9, TRUE),
(5, 4, FALSE), (5, 5, TRUE);

-- 거짓 알리바이(is_false = TRUE)는 범인만 가진다. 범인이 아닌 인물은 말을 아낄 수는 있어도 거짓말은 하지 않는다.
INSERT INTO alibi (character_id, claimed_time, place, statement, is_false) VALUES
(2, '21:40:00', '서진의 방', '방에서 계속 논문을 쓰고 있었어요. 10시쯤엔 출력도 했고요.', TRUE),
(3, '21:40:00', '정원 창고', '창고에서 공구를 정리하고 있었소.', FALSE),
(4, '21:40:00', '2층 복도', '설거지하다가 21시 20분쯤 2층에 잠깐 올라갔어요. 개인적인 일이라 더는 말하기 곤란해요.', FALSE),
(5, '21:40:00', '변호사의 방', '방에서 화상회의 중이었습니다. 접속 기록이 남아 있을 겁니다.', FALSE);

-- 조사 지점: 장소마다 3~5곳. 한 곳 열 때마다 조사 1회 (빈 곳도 있음)
INSERT INTO spot (spot_id, scene_id, name) VALUES
(1, 1, '책상 위'), (2, 1, '책상 아래'), (3, 1, '책장'), (4, 1, '바닥'), (5, 1, '창문'),
(6, 2, '개수대'), (7, 2, '충전기'), (8, 2, '칼꽂이'),
(9, 3, '작업대 아래'), (10, 3, '문 앞 눈길'), (11, 3, '장갑 걸이'),
(12, 4, '노트북'), (13, 4, '프린터'), (14, 4, '침대 밑'), (15, 4, '휴지통'), (16, 4, '옷장'),
(17, 5, '책상'), (18, 5, '노트북'), (19, 5, '서류가방');

-- 단서 문구는 사실만 적는다. 하나만으로는 누구도 확정되지 않고, 추론(조합)을 거쳐야 의미가 생긴다.
-- character_id가 있는 단서는 그 인물의 증언 (심문 중 실제로 털어놓아야 발견)
INSERT INTO clue (clue_id, scene_id, spot_id, character_id, name, description, clue_type, is_key, event_time) VALUES
(1, 1, 4, NULL, '흙 묻은 장갑', '서재 바닥에 떨어진 정원용 장갑 오른쪽 한 짝. 겉에만 흙이 묻었고 안쪽은 깨끗하다.', '물증', FALSE, NULL),
(2, 1, 2, NULL, '멈춘 탁상시계', '책상 아래로 떨어져 21시 40분에 멈춰 있다. 유리에 금이 갔다.', '물증', TRUE, '21:40:00'),
(3, 1, 3, NULL, '닦인 청동 문진', '책장 위 문진만 먼지 하나 없이 닦여 있다. 밑면 틈에 붉은 얼룩이 남아 있다.', '물증', FALSE, NULL),
(4, 1, 1, NULL, '빈 유언장 봉투', '책상 위의 빈 봉투. 겉면에 "수정안 - 윤 변호사 지참"이라고 적혀 있다.', '기록', FALSE, NULL),
(5, 1, 5, NULL, '잠긴 창문', '서재 창문은 안쪽 걸쇠가 걸려 있다. 바깥 창틀에 쌓인 눈에는 아무 자국이 없다.', '물증', FALSE, NULL),
(6, 2, 6, NULL, '반쯤 한 설거지', '개수대 물이 완전히 식어 있다. 21시 20분쯤 설거지가 멈춘 것으로 보인다.', '기록', FALSE, '21:20:00'),
(7, 2, 7, NULL, '가정부 휴대폰 통화 기록', '부엌 충전기에 꽂힌 최유나의 휴대폰. 21시 20분부터 26분 동안 통화한 기록이 있다. 상대는 저장되지 않은 번호다.', '기록', FALSE, NULL),
(8, 3, 9, NULL, '숨겨진 술병', '작업대 아래 숨겨진 빈 소주병 두 개. 아직 술 냄새가 난다.', '물증', FALSE, NULL),
(9, 3, 10, NULL, '눈 위의 발자국', '본관 뒷문에서 창고까지 갔다가 돌아온 작은 발자국. 밑창 무늬 없이 납작하고, 가운데에 작은 별 모양이 찍혀 있다.', '물증', FALSE, NULL),
(10, 3, 11, NULL, '한 짝 남은 장갑', '장갑 걸이에 왼쪽 장갑만 걸려 있다. 오른쪽 고리는 비어 있고, 고리 아래에 눈 녹은 물이 떨어져 있다.', '물증', FALSE, NULL),
(11, 4, 12, NULL, '노트북 저장 기록', '서진의 노트북. 논문 파일의 마지막 저장 시각은 21시 31분이다.', '기록', TRUE, '21:31:00'),
(12, 4, 13, NULL, '프린터 출력 기록', '22시 2분에 논문 12쪽이 출력되었다. 오늘 그 전에 출력한 기록은 없다.', '기록', FALSE, '22:02:00'),
(13, 4, 14, NULL, '젖은 실내화', '침대 밑에 밀어 넣은 실내화. 밑창이 무늬 없이 납작하고 가운데에 별 모양 장식이 박혀 있다. 밑창이 아직 축축하다.', '물증', TRUE, NULL),
(14, 4, 15, NULL, '구겨진 메모', '휴지통 속 구겨진 메모지. 서진의 필체로 "상속인 → 재단?", "내일 서명"이라고 적혀 있다.', '기록', FALSE, NULL),
(15, 5, 17, NULL, '신탁 계좌 메모', '한도윤 필체의 메모. "윤 변호사, 신탁 계좌 전부 확인할 것."', '기록', FALSE, NULL),
(16, 5, 18, NULL, '화상회의 접속 기록', '노트북에 21시 30분부터 22시 5분까지 회의에 접속한 기록이 있다. 21시 38분부터는 카메라와 마이크가 꺼져 있다.', '기록', FALSE, '21:30:00'),
(17, 5, 19, NULL, '고쳐 쓴 장부', '서류가방 속 신탁 계좌 장부. 몇 군데 숫자가 새로 덧쓰여 있고, 잉크가 아직 번진다.', '물증', FALSE, NULL),
(18, 3, NULL, 3, '창고 문 소리', '정원사 박정호의 증언. 21시부터 창고 안에서 혼자 술을 마셨다. 21시 50분쯤 창고 문이 열렸다 닫히는 소리를 들었지만, 취해서 누군지는 못 봤다.', '증언', FALSE, '21:50:00'),
(19, 1, NULL, 4, '서재의 언쟁', '가정부 최유나의 증언. 21시 35분쯤 2층 복도에서 서재 안 언쟁을 들었다. 말소리가 섞여 누군지는 모르겠지만 "유언장"이라는 말은 똑똑히 들었다.', '증언', TRUE, '21:35:00'),
(20, 2, NULL, 4, '정원사 해고 소문', '가정부 최유나의 증언. 저녁 무렵 주인이 정원사에게 해고를 통보하는 걸 봤다.', '증언', FALSE, '18:30:00'),
(21, 5, NULL, 5, '유언장 수정 계획', '변호사 윤재혁의 증언. 피해자는 내일 유언장을 고쳐 상속인을 조카에서 재단으로 바꾸려 했다. 수정안은 서류가방에 넣어 두었다.', '증언', FALSE, NULL);

-- 2차 조사: 이 단서를 찾아야 열리는 곳
UPDATE spot SET unlock_clue_id = 4 WHERE spot_id = 19;   -- 서류가방 ← 빈 유언장 봉투 ("윤 변호사 지참")
-- 숨은 증언: 관련 증거를 내밀어야만 털어놓는다
UPDATE clue SET unlock_clue_id = 6 WHERE clue_id = 19;   -- 서재의 언쟁 ← 반쯤 한 설거지

-- 추론: 단서 2~3개를 연결해야 얻는 사실. 범인 지목 근거로는 추론만 낼 수 있다.
INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(1, 1, '31분의 공백', '서진의 논문은 21시 31분에 마지막으로 저장됐고, 다음 기록은 22시 2분 출력이다. 그 사이 31분 동안 노트북과 프린터에는 아무 기록이 없다.', '알리바이',
 '"계속 논문을 썼다"던 서진의 말과 달리, 범행 시각 21시 40분을 낀 31분 동안 작업 기록이 없어요. 22시 2분 출력은 범행 뒤에 만든 알리바이예요.'),
(2, 1, '별 무늬 발자국', '창고 눈길의 납작한 발자국에 찍힌 별 모양과 서진 방 실내화 밑창의 별 장식이 같다. 그 실내화는 아직 젖어 있다.', '연결',
 '창고까지 눈길을 오간 건 서진의 실내화예요. 서재에 떨어진 정원사 장갑을 창고에서 가져온 사람이 서진이라는 뜻이에요.'),
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
(8, 1, '21시 40분의 서재', '탁상시계는 21시 40분에 떨어져 멈췄다. 서재에서는 문진만 닦여 있고, 밑면 틈에 붉은 얼룩이 남아 있다.', NULL,
 '범행 시각과 흉기를 알려주지만, 누가 했는지는 몰라요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(1, 11), (1, 12),
(2, 9), (2, 13),
(3, 14), (3, 19), (3, 21),
(4, 1), (4, 10),
(5, 8), (5, 18),
(6, 15), (6, 16), (6, 17),
(7, 6), (7, 7),
(8, 2), (8, 3);

-- 범인의 변명 계획 (AI 범인이 증거마다 그럴듯한 설명을 대도록)
-- 범인의 변명 계획 (AI 범인이 증거마다 그럴듯한 설명을 대도록)
INSERT INTO hint (character_id, content, reveal_order) VALUES
(2, '알리바이: 방에서 논문을 썼고, 22시 2분 프린터 출력 기록이 그 증거라고 말한다.', 1),
(2, '노트북 마지막 저장이 21시 31분이라는 걸 들이밀면: 그때부터는 출력본을 종이로 교정 보고 있어서 저장할 게 없었다고 한다.', 2),
(2, '언쟁 소리나 멈춘 시계 얘기가 나오면: 9시 반쯤 서재에 들러 유언장 얘기로 언성을 높인 건 인정하되, 금방 나왔고 그때 삼촌은 멀쩡했다고 한다.', 3),
(2, '젖은 실내화나 실내화 발자국 얘기가 나오면: 저녁 먹고 답답해서 뒷문 밖에 잠깐 바람 쐬러 나갔었다고 한다. 시간은 정확히 기억 안 난다고 흐린다.', 4),
(2, '장갑 얘기가 나오면: 정원사가 오늘 해고 통보를 받았다는 걸 흘려 의심을 돌린다.', 5),
(2, '유언장 수정안을 몰래 읽은 건 끝까지 숨긴다. 들키면 궁금해서 봤을 뿐 그걸로 삼촌을 해칠 이유는 없다고 한다.', 6),
(2, '구겨진 메모 얘기가 나오면: 저녁 식사 때 삼촌이 "재단에 남기겠다"는 말을 흘려서 적어둔 거라고 한다. 수정안을 직접 본 건 끝까지 부인한다.', 7),
(2, '별 모양 발자국과 실내화를 엮으면: 뒷문 밖에 잠깐 나간 건 맞지만 창고까지는 안 갔다고 한다. 발자국이 창고까지 이어진 걸 들이밀면 대답을 피한다.', 8);


-- 사건 2: 여름, 너에게 (인물 6~10, 현장 6~11, 사실 15~30, 조사 지점·단서·추론 101~)
INSERT INTO case_file (title, genre, difficulty, summary, truth, investigation_limit) VALUES
('여름, 너에게', '연애 리얼리티', '보통',
 '최종 선택을 하루 앞둔 연애 리얼리티 「여름, 너에게」의 제주 촬영 숙소. 밤 10시 50분, 출연자 윤시우가 수영장에 떠 있는 채 발견되었다. 태풍으로 길이 막혀 경찰은 새벽에야 도착한다. 숙소에 남은 네 사람 중 누군가가 범인이다.',
 '출연자 한지아는 언니 한지영의 투자금 1억 2천만 원을 날리게 한 윤시우에게 다가가려고 방송에 지원했다. 21시 40분 시우가 "10시에 수영장에서 보자"고 메시지를 보내자, 지아는 21시 58분 브이로그 촬영을 멈추고 수영장으로 갔다. 22시 10분 언니 돈 문제로 다투다 시우를 밀쳤고, 시우는 데크 모서리에 머리를 부딪친 채 물에 빠졌다(스마트워치 심박 22시 11분 끊김). 수영장 카메라는 22시 5분 배터리가 떨어져 꺼져 있었다. 지아는 맨발로 방에 돌아와 젖은 원피스를 벗고 머리를 말린 뒤, 22시 27분 브이로그를 다시 찍어 계속 방에 있었던 것처럼 꾸몄다. 하지만 다툼 중에 떨어진 왼쪽 귀걸이가 수영장 필터에 걸렸고, 다시 찍은 영상에는 그 귀걸이가 없었다.', 13);

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
(2, '21:58:00', '지아의 방', '한지아가 브이로그 촬영을 멈추고 방을 나섰다.', FALSE),
(2, '22:00:00', '시우의 방', '이채원이 시우의 방에 몰래 들어가 둘이 주고받은 메시지를 지웠다.', FALSE),
(2, '22:05:00', '수영장 데크', '수영장 카메라가 배터리 방전으로 녹화를 멈췄다.', FALSE),
(2, '22:10:00', '수영장 데크', '한지아가 언니 돈 문제로 윤시우와 다투다 밀쳤다. 시우는 데크 모서리에 머리를 부딪치고 물에 빠졌다.', FALSE),
(2, '22:12:00', '작가실', '이채원이 작가실 창문 너머로 수영장 쪽 여자 목소리를 들었다.', FALSE),
(2, '22:15:00', '장비실', '주경민이 창밖으로 맨발로 뛰어가는 작은 그림자를 봤다.', FALSE),
(2, '22:20:00', '지아의 방', '한지아가 젖은 원피스를 벗어 욕실 바구니에 넣고 머리를 말렸다.', FALSE),
(2, '22:25:00', '2층 복도', '이채원이 복도에서 머리가 젖은 한지아와 마주쳤다.', FALSE),
(2, '22:27:00', '지아의 방', '한지아가 브이로그 촬영을 다시 시작했다. 왼쪽 귀걸이가 없다.', FALSE),
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
(7, '22:10:00', '지아의 방', '10시 전부터 방에서 브이로그 찍고 있었어요. 영상 시간 보시면 알아요.', TRUE),
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
(109, 8, 109, NULL, '브이로그 촬영 기록', '지아 휴대폰의 촬영 기록. 21시 58분에 촬영이 끝나고, 22시 27분에 다시 시작된다. 앞 영상 속 지아는 꽃 모양 귀걸이를 양쪽에 하고 있다.', '기록', TRUE, '21:58:00'),
(110, 8, 110, NULL, '다시 찍은 영상', '노트북 자동 백업 폴더의 영상. 22시 27분부터 찍혔다. 지아는 머리를 하나로 묶었고, 귀걸이는 오른쪽에만 하고 있다.', '기록', TRUE, '22:27:00'),
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
(123, 11, NULL, 8, '거실 몸싸움', '출연자 백도현의 증언. 21시 30분 거실에서 시우와 몸싸움을 했다. 시우는 일어나며 "나한테 원한 있는 사람이 여기 또 있다"고 비웃었다.', '증언', FALSE, '21:30:00'),
(124, 10, NULL, 10, '맨발의 그림자', '촬영감독 주경민의 증언. 22시 15분쯤 장비실 창밖으로 맨발로 본관 쪽에 뛰어가는 작은 그림자를 봤다. 술에 취해 누군지는 모른다.', '증언', FALSE, '22:15:00');

UPDATE spot SET unlock_clue_id = 109 WHERE spot_id = 110;  -- 지아 노트북 백업 ← 브이로그 촬영 기록 (다시 찍은 영상이 있다는 걸 알게 됨)
UPDATE clue SET unlock_clue_id = 113 WHERE clue_id = 121;  -- 수영장의 여자 목소리 ← 작가실 창문
UPDATE clue SET unlock_clue_id = 119 WHERE clue_id = 123;  -- 거실 몸싸움 ← 깨진 액자

INSERT INTO deduction (deduction_id, case_id, name, description, proof_role, proof_note) VALUES
(101, 2, '29분의 공백', '지아의 브이로그는 21시 58분에 끊겼다가 22시 27분에 다시 시작된다. 시우의 심박은 그 사이인 22시 11분에 끊겼다.', '알리바이',
 '"10시 전부터 계속 방에서 찍었다"던 지아의 말과 달리, 사망 시각을 낀 29분 동안 촬영이 비어 있어요.'),
(102, 2, '사라진 왼쪽 귀걸이', '21시 58분 영상 속 지아는 꽃 모양 귀걸이를 양쪽에 하고 있다. 22시 27분 영상에서는 오른쪽에만 있다. 수영장 필터에서는 같은 모양의 왼쪽 귀걸이가 나왔다.', '연결',
 '촬영이 빈 29분 사이에 지아의 왼쪽 귀걸이가 수영장 필터로 갔어요. 지아가 그때 수영장에 있었다는 증거예요.'),
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
(108, 2, '22시 11분의 데크', '데크 모서리의 핏자국 높이는 시우의 머리 상처와 맞고, 시우의 심박은 22시 11분에 끊겼다.', NULL,
 '어떻게, 언제 죽었는지는 알려주지만 누가 밀었는지는 몰라요.'),
(109, 2, '맨발의 사람', '22시 15분쯤 맨발로 본관 쪽에 뛰어가는 작은 그림자가 있었다. 데크에서 본관 뒷문 쪽으로 230~240mm쯤의 젖은 맨발 자국이 이어진다.', NULL,
 '발이 작은 사람이 수영장에서 본관으로 갔다는 것까지만 알려줘요.'),
(110, 2, '거실의 몸싸움', '21시 30분 거실에서 도현과 시우가 몸싸움을 했고, 거실에는 깨진 액자와 피 묻은 휴지가 있다.', NULL,
 '도현과 시우가 싸운 흔적이지만, 범행보다 40분 전 일이에요.');

INSERT INTO deduction_clue (deduction_id, clue_id) VALUES
(101, 109), (101, 105),
(102, 101), (102, 109), (102, 110),
(103, 111), (103, 122),
(104, 121), (104, 107), (104, 112),
(105, 106), (105, 108), (105, 114),
(106, 118), (106, 104),
(107, 115), (107, 116), (107, 117),
(108, 103), (108, 105),
(109, 102), (109, 124),
(110, 119), (110, 120), (110, 123);

INSERT INTO hint (character_id, content, reveal_order) VALUES
(7, '알리바이: 10시 전부터 방에서 브이로그를 찍었고 촬영 기록이 있다고 말한다.', 1),
(7, '촬영 기록의 21시 58분~22시 27분 공백을 들이밀면: 촬영을 끊고 샤워를 했다고 한다. 그래서 머리가 젖어 있었다고 한다.', 2),
(7, '젖은 원피스 얘기가 나오면: 낮에 수영장 촬영 때 입었던 옷을 그냥 바구니에 넣어둔 거라고 한다.', 3),
(7, '귀걸이 얘기가 나오면: 낮 수영장 촬영 때 한 짝을 잃어버렸다고 한다. 21시 58분 영상에 양쪽이 다 있다는 걸 들이밀면 샤워하려고 빼뒀는데 어디 갔는지 모르겠다며 흔들린다.', 4),
(7, '환불 요청자 명단의 한지영 얘기가 나오면: 언니인 건 인정한다. 방송 끝나고 따로 얘기하려 했을 뿐 그날 밤 시우를 만나진 않았다고 한다.', 5),
(7, '맨발 자국이나 여자 목소리 얘기가 나오면: 여자는 자기만 있는 게 아니라며, 이채원 작가와 시우가 몰래 가까웠다는 걸 흘려 의심을 돌린다.', 6),
(7, '몸싸움 얘기가 나오면: 도현이 시우를 많이 미워했다는 걸 흘린다.', 7),
(7, '가족 사진 얘기가 나오면: 언니와 찍은 사진인 건 인정한다. 언니 일은 방송과 상관없다고 선을 긋는다.', 8);


-- 범인이 아닌 사람들의 수상한 정황 (사실 31~33)
INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(1, '21:38:00', '변호사의 방', '윤재혁이 화상회의 카메라와 마이크를 끄고, 신탁 계좌 장부의 숫자를 몰래 고쳤다.', FALSE),
(1, '21:46:00', '2층 복도', '최유나가 26분 동안의 통화를 마치고 부엌으로 내려왔다. 통화 상대는 연예 잡지 기자였다.', FALSE),
(2, '22:20:00', '수영장 데크', '백도현이 헬스장에서 나와 수영장 옆 흡연 구역에서 몰래 담배를 피웠다. 어두워서 수영장 안은 보지 못했다.', FALSE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(5, 31, TRUE), (4, 32, TRUE), (8, 33, TRUE);


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

-- 사실을 사건별, 시각 순으로 자주 조회
CREATE INDEX ix_fact_time ON fact(case_id, occurred_at);

-- 타임라인 항목을 참가자별, 시각 순으로 자주 조회
CREATE INDEX ix_timeline_time ON timeline_entry(participant_id, event_time);
