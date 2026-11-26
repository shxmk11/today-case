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
    PRIMARY KEY (case_id)
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

-- 단서
CREATE TABLE clue (
    clue_id INT NOT NULL AUTO_INCREMENT,
    scene_id INT NOT NULL,
    character_id INT NULL,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),
    clue_type ENUM('물증', '증언', '기록') NOT NULL,
    PRIMARY KEY (clue_id),
    CONSTRAINT fk_clue_scene FOREIGN KEY (scene_id)
        REFERENCES scene (scene_id) ON DELETE CASCADE,
    CONSTRAINT fk_clue_character FOREIGN KEY (character_id)
        REFERENCES game_character (character_id) ON DELETE SET NULL
);

-- 힌트 (범인 역할 플레이어용)
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


/* 2. 사건 데이터 (예시 사건: 별장의 마지막 밤) */

INSERT INTO case_file (title, genre, difficulty, summary, truth) VALUES
('별장의 마지막 밤', '클로즈드 서클', '보통',
 '폭설로 고립된 별장에서 주인 한도윤이 서재에서 숨진 채 발견되었다.',
 '조카 한서진이 유산 문제로 21시 40분 서재에서 삼촌을 살해하고, 정원사의 장갑을 현장에 남겨 누명을 씌웠다.');

INSERT INTO scene (case_id, name, description) VALUES
(1, '서재', '피해자가 쓰러져 있던 2층 서재. 창문은 안에서 잠겨 있다.'),
(1, '부엌', '저녁 식사 후 설거지가 반쯤 되어 있다.'),
(1, '정원 창고', '정원 도구가 보관된 창고.');

INSERT INTO game_character (case_id, name, age, job, personality, character_type, is_culprit) VALUES
(1, '한도윤', 62, '별장 주인', '고집이 세고 돈에 엄격함', '피해자', FALSE),
(1, '한서진', 29, '대학원생', '침착하지만 거짓말에 능함', '용의자', TRUE),
(1, '박정호', 55, '정원사', '말수가 적고 성실함', '용의자', FALSE),
(1, '최유나', 34, '가정부', '눈치가 빠르고 수다스러움', '용의자', FALSE);

INSERT INTO character_relation (character_a_id, character_b_id, relation_type, description) VALUES
(2, 1, '가족', '피해자의 조카이자 유일한 상속인'),
(3, 1, '고용', '10년째 일한 정원사'),
(4, 3, '동료', '자주 함께 식사함');

INSERT INTO fact (case_id, occurred_at, place, content, is_initial) VALUES
(1, '19:00:00', '부엌', '모두 함께 저녁 식사를 했다.', TRUE),
(1, '21:40:00', '서재', '한서진이 서재에 들어가 한도윤을 살해했다.', FALSE),
(1, '21:50:00', '정원 창고', '한서진이 창고에서 정원사의 장갑을 가져갔다.', FALSE),
(1, '22:30:00', '서재', '최유나가 시신을 발견했다.', TRUE);

INSERT INTO character_fact (character_id, fact_id, is_hidden) VALUES
(2, 1, FALSE), (3, 1, FALSE), (4, 1, FALSE),
(2, 2, TRUE),
(2, 3, TRUE), (3, 3, FALSE),
(4, 4, FALSE);

INSERT INTO alibi (character_id, claimed_time, place, statement, is_false) VALUES
(2, '21:40:00', '2층 손님방', '방에서 논문을 쓰고 있었어요.', TRUE),
(3, '21:40:00', '정원 창고', '창고에서 공구를 정리하고 있었소.', FALSE),
(4, '21:40:00', '부엌', '설거지를 하고 있었어요.', FALSE);

INSERT INTO clue (scene_id, character_id, name, description, clue_type) VALUES
(1, NULL, '흙 묻은 장갑', '서재 바닥에 떨어진 정원용 장갑. 안쪽은 깨끗하다.', '물증'),
(1, NULL, '멈춘 탁상시계', '21시 40분에 멈춰 있다.', '물증'),
(3, 3, '창고 문 소리', '21시 50분쯤 창고 문 여닫는 소리를 들었다는 정원사의 증언.', '증언'),
(2, NULL, '반쯤 한 설거지', '설거지가 21시 30분쯤 멈춘 흔적.', '기록');

INSERT INTO hint (character_id, content, reveal_order) VALUES
(2, '손님방 프린터 기록을 증거로 들면 알리바이가 그럴듯해진다.', 1),
(2, '장갑 이야기가 나오면 정원사와 가정부의 사이를 언급해 의심을 돌려라.', 2);


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
