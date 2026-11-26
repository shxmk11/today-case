import { Router, type Request, type Response, type NextFunction } from "express";
import { query, one, insert } from "./db.js";
import { interrogate, formatQuestion, type Evidence } from "./llm.js";
import type { CaseRow, CharacterRow, ClueRow, FactRow } from "./types.js";

export const router = Router();

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

// async 핸들러의 에러를 Express 에러 처리로 넘긴다
const wrap =
  (fn: (req: Request, res: Response) => Promise<unknown>) =>
  (req: Request, res: Response, next: NextFunction) =>
    fn(req, res).catch(next);

/* 플레이어에게 보여도 되는 필드만 고른다 (범인 여부, 진상, 숨긴 사실은 제외) */
const publicCharacter = ({ is_culprit: _c, case_id: _id, ...rest }: CharacterRow) => rest;

async function getPlay(playId: number) {
  const play = await one<{ play_id: number; case_id: number; status: string; participant_id: number }>(
    `SELECT pl.play_id, pl.case_id, pl.status, p.participant_id
     FROM play pl JOIN participant p ON p.play_id = pl.play_id AND p.role = '탐정'
     WHERE pl.play_id = ?`,
    [playId],
  );
  if (!play) throw new HttpError(404, "플레이를 찾을 수 없어요.");
  return play;
}

function assertOngoing(play: { status: string }) {
  if (play.status !== "진행중") throw new HttpError(409, "이미 끝난 사건이에요.");
}

async function getCharacterInCase(caseId: number, characterId: number) {
  const ch = await one<CharacterRow>(
    `SELECT * FROM game_character WHERE character_id = ? AND case_id = ?`,
    [characterId, caseId],
  );
  if (!ch) throw new HttpError(404, "등장인물을 찾을 수 없어요.");
  return ch;
}

async function discoveredClues(participantId: number) {
  return query<ClueRow & { scene_name: string; found_at: string }>(
    `SELECT c.clue_id, c.scene_id, c.character_id, c.name, c.description, c.clue_type,
            s.name AS scene_name, cd.found_at
     FROM clue_discovery cd
     JOIN clue c ON c.clue_id = cd.clue_id
     JOIN scene s ON s.scene_id = c.scene_id
     WHERE cd.participant_id = ?
     ORDER BY cd.found_at, c.clue_id`,
    [participantId],
  );
}

/* 사건 목록 */
router.get(
  "/cases",
  wrap(async (_req, res) => {
    const cases = await query<Omit<CaseRow, "truth"> & { suspect_count: number }>(
      `SELECT c.case_id, c.title, c.genre, c.difficulty, c.summary,
              (SELECT COUNT(*) FROM game_character g
               WHERE g.case_id = c.case_id AND g.character_type = '용의자') AS suspect_count
       FROM case_file c ORDER BY c.case_id`,
    );
    res.json(cases);
  }),
);

/* 새 플레이 시작: 게스트 회원 + 1인 탐정 참가자 생성 */
router.post(
  "/plays",
  wrap(async (req, res) => {
    const caseId = Number(req.body?.caseId);
    const c = await one<CaseRow>(`SELECT * FROM case_file WHERE case_id = ?`, [caseId]);
    if (!c) throw new HttpError(404, "사건을 찾을 수 없어요.");

    const guestId = `guest_${Date.now().toString(36)}${Math.floor(Math.random() * 1e4)}`.slice(0, 20);
    await insert(`INSERT INTO member (member_id, password, nickname) VALUES (?, '', ?)`, [guestId, guestId]);
    const playId = await insert(`INSERT INTO play (case_id, mode) VALUES (?, '1인')`, [caseId]);
    await insert(`INSERT INTO participant (play_id, member_id, role) VALUES (?, ?, '탐정')`, [playId, guestId]);
    res.status(201).json({ playId });
  }),
);

/* 플레이 화면에 필요한 정보 한 번에 */
router.get(
  "/plays/:id",
  wrap(async (req, res) => {
    const play = await getPlay(Number(req.params.id));
    const c = await one<CaseRow>(`SELECT * FROM case_file WHERE case_id = ?`, [play.case_id]);
    const characters = await query<CharacterRow>(
      `SELECT * FROM game_character WHERE case_id = ? ORDER BY character_id`,
      [play.case_id],
    );
    const scenes = await query<{ scene_id: number; name: string; description: string | null }>(
      `SELECT scene_id, name, description FROM scene WHERE case_id = ? ORDER BY scene_id`,
      [play.case_id],
    );
    const facts = await query<FactRow>(
      `SELECT fact_id, occurred_at, place, content FROM fact
       WHERE case_id = ? AND is_initial = TRUE ORDER BY occurred_at`,
      [play.case_id],
    );
    const investigated = await query<{ scene_id: number }>(
      `SELECT DISTINCT c.scene_id FROM clue_discovery cd JOIN clue c ON c.clue_id = cd.clue_id
       WHERE cd.participant_id = ?`,
      [play.participant_id],
    );
    const chats = await query<{ character_id: number; question: string; answer: string; asked_at: string }>(
      `SELECT character_id, question, answer, asked_at FROM interrogation
       WHERE participant_id = ? ORDER BY asked_at, interrogation_id`,
      [play.participant_id],
    );

    res.json({
      playId: play.play_id,
      status: play.status,
      case: { case_id: c!.case_id, title: c!.title, genre: c!.genre, difficulty: c!.difficulty, summary: c!.summary },
      characters: characters.map(publicCharacter),
      scenes: scenes.map((s) => ({ ...s, investigated: investigated.some((i) => i.scene_id === s.scene_id) })),
      facts,
      clues: await discoveredClues(play.participant_id),
      chats,
    });
  }),
);

/* 현장 조사: 그 현장의 물증·기록 단서를 발견 처리 (증언 단서는 심문으로 얻음) */
router.post(
  "/plays/:id/investigate",
  wrap(async (req, res) => {
    const play = await getPlay(Number(req.params.id));
    assertOngoing(play);
    const sceneId = Number(req.body?.sceneId);
    const scene = await one(`SELECT scene_id FROM scene WHERE scene_id = ? AND case_id = ?`, [sceneId, play.case_id]);
    if (!scene) throw new HttpError(404, "현장을 찾을 수 없어요.");

    await query(
      `INSERT IGNORE INTO clue_discovery (participant_id, clue_id)
       SELECT ?, clue_id FROM clue WHERE scene_id = ? AND character_id IS NULL`,
      [play.participant_id, sceneId],
    );
    res.json({ clues: await discoveredClues(play.participant_id) });
  }),
);

/* 심문: 질문을 저장하고 AI 답변을 돌려준다 */
router.post(
  "/plays/:id/interrogate",
  wrap(async (req, res) => {
    const play = await getPlay(Number(req.params.id));
    assertOngoing(play);
    const question = String(req.body?.question ?? "").trim();
    if (!question || question.length > 300) throw new HttpError(400, "질문은 1~300자로 해주세요.");

    const ch = await getCharacterInCase(play.case_id, Number(req.body?.characterId));
    if (ch.character_type === "피해자") throw new HttpError(400, "피해자는 심문할 수 없어요.");
    const c = (await one<CaseRow>(`SELECT * FROM case_file WHERE case_id = ?`, [play.case_id]))!;

    const history = await query<{ question: string; answer: string }>(
      `SELECT question, answer FROM interrogation
       WHERE participant_id = ? AND character_id = ? ORDER BY asked_at, interrogation_id`,
      [play.participant_id, ch.character_id],
    );
    // 증거 제시: 이미 발견한 단서만 낼 수 있다
    let evidence: Evidence | undefined;
    if (req.body?.clueId != null) {
      evidence = await one<Evidence>(
        `SELECT c.name, c.description FROM clue_discovery cd JOIN clue c ON c.clue_id = cd.clue_id
         WHERE cd.participant_id = ? AND cd.clue_id = ?`,
        [play.participant_id, Number(req.body.clueId)],
      );
      if (!evidence) throw new HttpError(400, "아직 찾지 못한 단서예요.");
    }

    const { answer, revealedClueIds } = await interrogate(c, ch, history.slice(-20), question, evidence);
    const storedQuestion = formatQuestion(question, evidence);
    await insert(
      `INSERT INTO interrogation (participant_id, character_id, question, answer) VALUES (?, ?, ?, ?)`,
      [play.participant_id, ch.character_id, storedQuestion, answer],
    );

    // 인물이 실제로 털어놓은 증언 단서만 발견 처리 (그 인물의 증언인지 확인)
    const before = new Set((await discoveredClues(play.participant_id)).map((x) => x.clue_id));
    if (revealedClueIds.length > 0) {
      await query(
        `INSERT IGNORE INTO clue_discovery (participant_id, clue_id)
         SELECT ?, clue_id FROM clue WHERE character_id = ? AND clue_id IN (?)`,
        [play.participant_id, ch.character_id, revealedClueIds],
      );
    }
    const clues = await discoveredClues(play.participant_id);
    const newClues = clues.filter((x) => !before.has(x.clue_id)).map((x) => x.clue_id);
    res.json({ answer, question: storedQuestion, clues, newClues });
  }),
);

/* 범인 지목: 결과와 진상 공개 */
router.post(
  "/plays/:id/accuse",
  wrap(async (req, res) => {
    const play = await getPlay(Number(req.params.id));
    assertOngoing(play);
    const accused = await getCharacterInCase(play.case_id, Number(req.body?.characterId));
    if (accused.character_type !== "용의자") throw new HttpError(400, "용의자 중에서 골라주세요.");

    await insert(`INSERT INTO accusation (participant_id, character_id) VALUES (?, ?)`, [play.participant_id, accused.character_id]);
    const result = accused.is_culprit ? "성공" : "실패";
    await query(`UPDATE play SET status = '종료', result = ?, ended_at = NOW() WHERE play_id = ?`, [result, play.play_id]);

    const c = (await one<CaseRow>(`SELECT * FROM case_file WHERE case_id = ?`, [play.case_id]))!;
    const culprit = await one<{ character_id: number; name: string }>(
      `SELECT character_id, name FROM game_character WHERE case_id = ? AND is_culprit = TRUE`,
      [play.case_id],
    );
    const timeline = await query<FactRow>(
      `SELECT fact_id, occurred_at, place, content, is_initial FROM fact WHERE case_id = ? ORDER BY occurred_at`,
      [play.case_id],
    );
    const stats = await one<{ minutes: number; questions: number; clues: number }>(
      `SELECT TIMESTAMPDIFF(MINUTE, pl.started_at, pl.ended_at) AS minutes,
              (SELECT COUNT(*) FROM interrogation i WHERE i.participant_id = ?) AS questions,
              (SELECT COUNT(*) FROM clue_discovery d WHERE d.participant_id = ?) AS clues
       FROM play pl WHERE pl.play_id = ?`,
      [play.participant_id, play.participant_id, play.play_id],
    );
    res.json({ result, accused: accused.name, culprit, truth: c.truth, timeline, stats });
  }),
);

router.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message });
    return;
  }
  console.error(err);
  res.status(500).json({ error: "서버에서 문제가 생겼어요." });
});
