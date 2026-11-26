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
    is_key BOOLEAN NOT NULL DEFAULT FALSE,   -- 결과 화면의 '결정적 증거/증언'
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
 '폭설로 고립된 산속 별장. 밤 10시 30분, 별장 주인 한도윤이 2층 서재에서 숨진 채 발견되었다. 진입로가 막혀 경찰은 아침에야 도착한다. 별장에 남은 네 사람 중 누군가가 범인이다.',
 '조카 한서진은 20시 30분 변호사의 서류가방에서 유언장 수정안을 몰래 읽고, 삼촌이 상속인을 자신에서 재단으로 바꾸려 한다는 걸 알았다. 21시 35분 서재에서 언쟁을 벌이다 21시 40분 청동 문진으로 삼촌을 내려쳤고, 이때 떨어진 탁상시계가 멈췄다. 21시 50분 실내화 차림으로 눈길을 지나 창고에서 정원사의 장갑 한 짝을 가져와 서재에 떨어뜨리고 문진을 닦아 제자리에 두었다. 22시 2분 논문을 출력해 계속 방에 있던 것처럼 꾸몄지만, 노트북의 마지막 저장은 21시 31분이었다.');

INSERT INTO scene (case_id, name, description) VALUES
(1, '서재', '피해자가 쓰러져 있던 2층 서재. 창문은 안에서 잠겨 있고, 책상 위가 어지럽다.'),
(1, '부엌', '저녁 식사 뒤 정리가 덜 된 1층 부엌.'),
(1, '정원 창고', '별채 옆 정원 창고. 본관 뒷문에서 눈길로 30걸음쯤 떨어져 있다.'),
(1, '서진의 방', '2층 손님방 1. 한서진이 머무는 방.'),
(1, '변호사의 방', '2층 손님방 2. 고문 변호사 윤재혁이 머무는 방.');

INSERT INTO game_character (case_id, name, age, job, personality, character_type, is_culprit) VALUES
(1, '한도윤', 62, '별장 주인, 사업가', '고집이 세고 돈에 엄격함', '피해자', FALSE),
(1, '한서진', 29, '대학원생, 피해자의 조카', '침착하고 예의 바르지만 거짓말에 능함', '용의자', TRUE),
(1, '박정호', 55, '정원사', '말수가 적고 무뚝뚝함, 자존심이 셈', '용의자', FALSE),
(1, '최유나', 34, '가정부', '눈치가 빠르고 수다스러움, 남 얘기를 좋아함', '용의자', FALSE),
(1, '윤재혁', 41, '고문 변호사', '말을 고르고 논리적이며 방어적임', '용의자', FALSE);

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

-- character_id가 있는 단서는 그 인물의 증언 (심문 중 실제로 털어놓아야 발견)
INSERT INTO clue (scene_id, character_id, name, description, clue_type) VALUES
(1, NULL, '흙 묻은 장갑', '서재 바닥에 떨어진 정원용 장갑 오른쪽 한 짝. 겉에만 흙이 묻었고 안쪽은 깨끗하다.', '물증'),
(1, NULL, '멈춘 탁상시계', '책상 아래로 떨어져 21시 40분에 멈춰 있다.', '물증'),
(1, NULL, '닦인 청동 문진', '책장 위 문진만 먼지 하나 없이 닦여 있다. 밑면 틈에 붉은 얼룩이 남아 있다.', '물증'),
(1, NULL, '빈 유언장 봉투', '책상 서랍 속 빈 봉투. 겉면에 "수정안 - 윤 변호사 지참"이라고 적혀 있다.', '기록'),
(2, NULL, '반쯤 한 설거지', '개수대 물이 완전히 식어 있다. 21시 20분쯤 설거지가 멈춘 것으로 보인다.', '기록'),
(3, NULL, '숨겨진 술병', '작업대 아래 숨겨진 빈 소주병 두 개. 아직 술 냄새가 난다.', '물증'),
(3, NULL, '눈 위의 발자국', '본관 뒷문에서 창고까지 이어진 작은 발자국. 장화가 아니라 실내화 밑창 무늬다.', '물증'),
(3, NULL, '한 짝 남은 장갑', '장갑 걸이에 왼쪽 장갑만 걸려 있다.', '물증'),
(4, NULL, '노트북 저장 기록', '논문 파일의 마지막 저장 시각은 21시 31분이다.', '기록'),
(4, NULL, '프린터 출력 기록', '22시 2분에 논문 12쪽이 출력되었다.', '기록'),
(4, NULL, '젖은 실내화', '침대 밑에 밀어 넣은 실내화. 밑창이 눈 녹은 물에 젖어 있다.', '물증'),
(5, NULL, '신탁 계좌 메모', '한도윤 필체의 메모. "윤 변호사, 신탁 계좌 전부 확인할 것."', '기록'),
(5, NULL, '화상회의 접속 기록', '노트북에 21시 30분부터 22시 5분까지 회의에 접속한 기록이 있다.', '기록'),
(3, 3, '창고 문 소리', '정원사 박정호의 증언. 21시 50분쯤 창고 문이 열렸다 닫히는 소리를 들었지만, 술에 취해 누군지는 못 봤다.', '증언'),
(1, 4, '서재의 언쟁', '가정부 최유나의 증언. 21시 35분쯤 2층 복도에서 서재 안 언쟁을 들었다. "유언장"이라는 말과 젊은 여자 목소리였다.', '증언'),
(2, 4, '정원사 해고 소문', '가정부 최유나의 증언. 저녁 무렵 주인이 정원사에게 해고를 통보하는 걸 봤다.', '증언'),
(5, 5, '유언장 수정 계획', '변호사 윤재혁의 증언. 피해자는 내일 유언장을 고쳐 상속인을 조카에서 재단으로 바꾸려 했다.', '증언');

-- 결정적 증거 3개 + 결정적 증언 1개
UPDATE clue SET is_key = TRUE WHERE name IN ('닦인 청동 문진', '멈춘 탁상시계', '흙 묻은 장갑', '서재의 언쟁');

INSERT INTO hint (character_id, content, reveal_order) VALUES
(2, '22시 2분 프린터 출력 기록을 들어 계속 방에 있었다고 주장하라.', 1),
(2, '장갑 이야기가 나오면 정원사가 오늘 해고당했다는 사실을 흘려 의심을 돌려라.', 2);


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
