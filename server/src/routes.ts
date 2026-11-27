import { Router, type Request, type Response, type NextFunction } from "express";
import { query, one, insert } from "./db.js";
import { interrogate, formatQuestion, LlmBusyError, type Evidence } from "./llm.js";
import type { AutopsyRow, CaseRow, CharacterRow, ClueRow, FactRow } from "./types.js";

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
const publicCharacter = ({ is_culprit: _c, case_id: _id, backstory: _b, ...rest }: CharacterRow) => rest;

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

/** 남은 조사 횟수 = 사건의 조사 횟수 - 연 조사 지점 수 - 틀린 연결 수 */
async function investigationsLeft(participantId: number, caseId: number) {
  const r = await one<{ n: number }>(
    `SELECT c.investigation_limit
            - (SELECT COUNT(*) FROM spot_search ss WHERE ss.participant_id = ?)
            - (SELECT COUNT(*) FROM link_attempt la WHERE la.participant_id = ? AND la.deduction_id IS NULL) AS n
     FROM case_file c WHERE c.case_id = ?`,
    [participantId, participantId, caseId],
  );
  return Math.max(0, Number(r?.n ?? 0));
}

/** 장소별 조사 지점: 조사했는지, 아직 잠겼는지 (잠금을 여는 단서는 알려주지 않음) */
async function sceneSpots(participantId: number, caseId: number) {
  const scenes = await query<{
    scene_id: number; name: string; description: string | null; image_url: string | null;
    map_x: string | null; map_y: string | null; map_w: string | null; map_h: string | null;
  }>(
    `SELECT scene_id, name, description, image_url, map_x, map_y, map_w, map_h FROM scene WHERE case_id = ? ORDER BY scene_id`,
    [caseId],
  );
  const spots = await query<{
    spot_id: number; scene_id: number; name: string; searched: number; locked: number; pos_x: string | null; pos_y: string | null;
  }>(
    `SELECT sp.spot_id, sp.scene_id, sp.name, sp.pos_x, sp.pos_y,
            EXISTS (SELECT 1 FROM spot_search ss WHERE ss.participant_id = ? AND ss.spot_id = sp.spot_id) AS searched,
            (sp.unlock_clue_id IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM clue_discovery cd WHERE cd.participant_id = ? AND cd.clue_id = sp.unlock_clue_id)) AS locked
     FROM spot sp JOIN scene s ON s.scene_id = sp.scene_id
     WHERE s.case_id = ? ORDER BY sp.spot_id`,
    [participantId, participantId, caseId],
  );
  // DECIMAL 은 문자열로 오므로 숫자로 바꾼다
  const num = (v: string | null) => (v == null ? null : Number(v));
  return scenes.map(({ map_x, map_y, map_w, map_h, ...sc }) => {
    const own = spots
      .filter((x) => x.scene_id === sc.scene_id)
      .map((x) => ({
        spot_id: x.spot_id, name: x.name, searched: !!x.searched, locked: !!x.locked,
        x: num(x.pos_x), y: num(x.pos_y),
      }));
    const map = map_x == null ? null : { x: num(map_x)!, y: num(map_y)!, w: num(map_w)!, h: num(map_h)! };
    return { ...sc, map, spots: own, investigated: own.length > 0 && own.every((x) => x.searched) };
  });
}

/** 찾은 추론 (재료 단서 id 포함) */
async function foundDeductions(participantId: number) {
  const rows = await query<{ deduction_id: number; name: string; description: string; clue_id: number; found_at: string }>(
    `SELECT d.deduction_id, d.name, d.description, dc.clue_id, la.attempted_at AS found_at
     FROM link_attempt la
     JOIN deduction d ON d.deduction_id = la.deduction_id
     JOIN deduction_clue dc ON dc.deduction_id = d.deduction_id
     WHERE la.participant_id = ?
     ORDER BY la.attempted_at, la.attempt_id, dc.clue_id`,
    [participantId],
  );
  const out: { deduction_id: number; name: string; description: string; clue_ids: number[] }[] = [];
  for (const r of rows) {
    let d = out.find((x) => x.deduction_id === r.deduction_id);
    if (!d) out.push((d = { deduction_id: r.deduction_id, name: r.name, description: r.description, clue_ids: [] }));
    d.clue_ids.push(r.clue_id);
  }
  return out;
}

async function deductionTotal(caseId: number) {
  return (await one<{ n: number }>(`SELECT COUNT(*) AS n FROM deduction WHERE case_id = ?`, [caseId]))!.n;
}

/**
 * 플레이어 타임라인 = 처음부터 공개된 사실 + 플레이 중 자동으로 쌓인 timeline_entry.
 * 시각순 자동 정렬 (플레이어가 직접 배치하지 않음)
 */
export interface TimelineItem {
  key: string;
  time: string;
  place: string | null;
  kind: "사실" | "물증" | "기록" | "증언" | "주장";
  text: string;
}

async function playerTimeline(participantId: number, caseId: number): Promise<TimelineItem[]> {
  return query<TimelineItem>(
    `SELECT CONCAT('f', f.fact_id) AS \`key\`, f.occurred_at AS time, f.place, '사실' AS kind, f.content AS text
     FROM fact f WHERE f.case_id = ? AND f.is_initial = TRUE
     UNION ALL
     SELECT CONCAT('t', t.entry_id), t.event_time, COALESCE(s.name, a.place),
            IF(t.clue_id IS NULL, '주장', c.clue_type), t.content
     FROM timeline_entry t
     LEFT JOIN clue c ON c.clue_id = t.clue_id
     LEFT JOIN scene s ON s.scene_id = c.scene_id
     LEFT JOIN interrogation i ON i.interrogation_id = t.interrogation_id
     LEFT JOIN alibi a ON a.character_id = i.character_id AND a.claimed_time = t.event_time
     WHERE t.participant_id = ?
     ORDER BY time, \`key\``,
    [caseId, participantId],
  );
}

/** 발견한 단서 중 시각이 있는 것을 타임라인에 올린다 (이미 올라간 것은 건너뜀) */
async function addClueEntries(participantId: number) {
  await query(
    `INSERT INTO timeline_entry (participant_id, clue_id, event_time, content)
     SELECT cd.participant_id, c.clue_id, c.event_time, LEFT(CONCAT(c.name, ' · ', COALESCE(c.description, '')), 255)
     FROM clue_discovery cd JOIN clue c ON c.clue_id = cd.clue_id
     WHERE cd.participant_id = ? AND c.event_time IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM timeline_entry t WHERE t.participant_id = cd.participant_id AND t.clue_id = c.clue_id)`,
    [participantId],
  );
}

/** 인물이 알리바이를 말하면 그 주장을 타임라인에 '주장'으로 올린다 */
async function addAlibiEntries(participantId: number, interrogationId: number, ch: CharacterRow) {
  await query(
    `INSERT INTO timeline_entry (participant_id, interrogation_id, event_time, content)
     SELECT ?, ?, a.claimed_time, LEFT(CONCAT(?, ' 주장 · ', a.statement), 255)
     FROM alibi a
     WHERE a.character_id = ?
       AND NOT EXISTS (
         SELECT 1 FROM timeline_entry t JOIN interrogation i ON i.interrogation_id = t.interrogation_id
         WHERE t.participant_id = ? AND i.character_id = a.character_id AND t.event_time = a.claimed_time)`,
    [participantId, interrogationId, ch.name, ch.character_id, participantId],
  );
}

/* 사건 목록 */
router.get(
  "/cases",
  wrap(async (_req, res) => {
    const cases = await query<Omit<CaseRow, "truth"> & { suspect_count: number; scene_count: number; clue_count: number; solve_rate: string | null }>(
      `SELECT c.case_id, c.title, c.genre, c.difficulty, c.summary,
              (SELECT COUNT(*) FROM game_character g
               WHERE g.case_id = c.case_id AND g.character_type = '용의자') AS suspect_count,
              (SELECT COUNT(*) FROM scene s WHERE s.case_id = c.case_id) AS scene_count,
              (SELECT COUNT(*) FROM clue k JOIN scene s ON s.scene_id = k.scene_id WHERE s.case_id = c.case_id) AS clue_count,
              (SELECT ROUND(100 * AVG(p.result = '성공')) FROM play p
               WHERE p.case_id = c.case_id AND p.status = '종료') AS solve_rate
       FROM case_file c ORDER BY c.case_id`,
    );
    const suspects = await query<{ case_id: number; name: string; job: string | null; gender: string | null; image_url: string | null }>(
      `SELECT case_id, name, job, gender, image_url FROM game_character WHERE character_type = '용의자' ORDER BY character_id`,
    );
    res.json(
      cases.map((c) => ({
        ...c,
        solve_rate: c.solve_rate == null ? null : Number(c.solve_rate),
        suspects: suspects.filter((s) => s.case_id === c.case_id).map(({ name, job, gender, image_url }) => ({ name, job, gender, image_url })),
      })),
    );
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
    const facts = await query<FactRow>(
      `SELECT fact_id, occurred_at, place, content FROM fact
       WHERE case_id = ? AND is_initial = TRUE ORDER BY occurred_at`,
      [play.case_id],
    );
    const chats = await query<{ character_id: number; question: string; answer: string; asked_at: string }>(
      `SELECT character_id, question, answer, asked_at FROM interrogation
       WHERE participant_id = ? ORDER BY asked_at, interrogation_id`,
      [play.participant_id],
    );

    res.json({
      playId: play.play_id,
      status: play.status,
      case: { case_id: c!.case_id, title: c!.title, genre: c!.genre, difficulty: c!.difficulty, summary: c!.summary, map_url: c!.map_url },
      autopsy: await one<AutopsyRow>(
        `SELECT found_time, found_place, found_by, cause, wound, death_estimate, weapon, note FROM autopsy WHERE case_id = ?`,
        [play.case_id],
      ),
      characters: characters.map(publicCharacter),
      scenes: await sceneSpots(play.participant_id, play.case_id),
      investigationLimit: c!.investigation_limit,
      investigationsLeft: await investigationsLeft(play.participant_id, play.case_id),
      deductions: await foundDeductions(play.participant_id),
      deductionTotal: await deductionTotal(play.case_id),
      facts,
      timeline: await playerTimeline(play.participant_id, play.case_id),
      clues: await discoveredClues(play.participant_id),
      clueTotal: (await one<{ n: number }>(
        `SELECT COUNT(*) AS n FROM clue k JOIN scene s ON s.scene_id = k.scene_id WHERE s.case_id = ?`,
        [play.case_id],
      ))!.n,
      chats,
    });
  }),
);

/* 현장 조사: 조사 지점 한 곳을 열어 그곳의 물증·기록 단서를 발견 처리 (조사 1회. 증언 단서는 심문으로 얻음) */
router.post(
  "/plays/:id/investigate",
  wrap(async (req, res) => {
    const play = await getPlay(Number(req.params.id));
    assertOngoing(play);
    const spotId = Number(req.body?.spotId);
    const spot = await one<{ spot_id: number; name: string; unlock_clue_id: number | null }>(
      `SELECT sp.spot_id, sp.name, sp.unlock_clue_id FROM spot sp JOIN scene s ON s.scene_id = sp.scene_id
       WHERE sp.spot_id = ? AND s.case_id = ?`,
      [spotId, play.case_id],
    );
    if (!spot) throw new HttpError(404, "조사할 곳을 찾을 수 없어요.");
    if (await one(`SELECT 1 FROM spot_search WHERE participant_id = ? AND spot_id = ?`, [play.participant_id, spotId])) {
      throw new HttpError(409, "이미 조사한 곳이에요.");
    }
    if (spot.unlock_clue_id != null &&
        !(await one(`SELECT 1 FROM clue_discovery WHERE participant_id = ? AND clue_id = ?`, [play.participant_id, spot.unlock_clue_id]))) {
      throw new HttpError(409, "아직 열 수 없어요. 다른 단서가 필요해요.");
    }
    if ((await investigationsLeft(play.participant_id, play.case_id)) <= 0) {
      throw new HttpError(409, "조사 횟수를 다 썼어요. 심문과 연결로 추리해보세요.");
    }

    await query(`INSERT INTO spot_search (participant_id, spot_id) VALUES (?, ?)`, [play.participant_id, spotId]);
    await query(
      `INSERT IGNORE INTO clue_discovery (participant_id, clue_id)
       SELECT ?, clue_id FROM clue WHERE spot_id = ? AND character_id IS NULL`,
      [play.participant_id, spotId],
    );
    await addClueEntries(play.participant_id);
    res.json({
      clues: await discoveredClues(play.participant_id),
      timeline: await playerTimeline(play.participant_id, play.case_id),
      scenes: await sceneSpots(play.participant_id, play.case_id),
      investigationsLeft: await investigationsLeft(play.participant_id, play.case_id),
    });
  }),
);

/* 단서 연결: 찾은 단서 2~3개가 어떤 추론의 재료와 정확히 같으면 추론을 얻는다. 틀리면 조사 1회 차감 */
router.post(
  "/plays/:id/link",
  wrap(async (req, res) => {
    const play = await getPlay(Number(req.params.id));
    assertOngoing(play);
    const raw: unknown[] = Array.isArray(req.body?.clueIds) ? req.body.clueIds : [];
    const ids = [...new Set(raw.map(Number))]
      .filter((n) => Number.isInteger(n) && n > 0)
      .sort((x, y) => x - y);
    if (ids.length < 2 || ids.length > 3) throw new HttpError(400, "단서를 2~3개 골라주세요.");
    const found = await query<{ clue_id: number }>(
      `SELECT clue_id FROM clue_discovery WHERE participant_id = ? AND clue_id IN (?)`,
      [play.participant_id, ids],
    );
    if (found.length !== ids.length) throw new HttpError(400, "찾은 단서만 연결할 수 있어요.");

    const key = ids.join(",");
    const tried = await one<{ deduction_id: number | null }>(
      `SELECT deduction_id FROM link_attempt WHERE participant_id = ? AND clue_key = ?`,
      [play.participant_id, key],
    );
    if (tried) throw new HttpError(409, tried.deduction_id ? "이미 찾은 추론이에요." : "이미 해본 조합이에요. 이어지는 게 없었어요.");

    // 사건의 추론마다 재료 단서 목록을 이어 붙여 고른 조합과 비교
    const recipes = await query<{ deduction_id: number; clue_key: string }>(
      `SELECT d.deduction_id, GROUP_CONCAT(dc.clue_id ORDER BY dc.clue_id SEPARATOR ',') AS clue_key
       FROM deduction d JOIN deduction_clue dc ON dc.deduction_id = d.deduction_id
       WHERE d.case_id = ? GROUP BY d.deduction_id`,
      [play.case_id],
    );
    const match = recipes.find((r) => r.clue_key === key);
    if (match) {
      if (await one(`SELECT 1 FROM link_attempt WHERE participant_id = ? AND deduction_id = ?`, [play.participant_id, match.deduction_id])) {
        throw new HttpError(409, "이미 찾은 추론이에요.");
      }
    } else if ((await investigationsLeft(play.participant_id, play.case_id)) <= 0) {
      throw new HttpError(409, "조사 횟수를 다 써서 더 연결해볼 수 없어요.");
    }
    await query(`INSERT INTO link_attempt (participant_id, clue_key, deduction_id) VALUES (?, ?, ?)`, [
      play.participant_id,
      key,
      match?.deduction_id ?? null,
    ]);
    const deductions = await foundDeductions(play.participant_id);
    res.json({
      ok: !!match,
      deduction: match ? deductions.find((d) => d.deduction_id === match.deduction_id) : null,
      deductions,
      investigationsLeft: await investigationsLeft(play.participant_id, play.case_id),
    });
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
        `SELECT c.clue_id, c.name, c.description FROM clue_discovery cd JOIN clue c ON c.clue_id = cd.clue_id
         WHERE cd.participant_id = ? AND cd.clue_id = ?`,
        [play.participant_id, Number(req.body.clueId)],
      );
      if (!evidence) throw new HttpError(400, "아직 찾지 못한 단서예요.");
    }

    const discoveredIds = (await discoveredClues(play.participant_id)).map((x) => x.clue_id);
    const { answer, revealedClueIds, statedAlibi } = await interrogate(c, ch, history.slice(-20), question, evidence, discoveredIds);
    const storedQuestion = formatQuestion(question, evidence);
    const interrogationId = await insert(
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
    await addClueEntries(play.participant_id);
    if (statedAlibi) await addAlibiEntries(play.participant_id, interrogationId, ch);
    const clues = await discoveredClues(play.participant_id);
    const newClues = clues.filter((x) => !before.has(x.clue_id)).map((x) => x.clue_id);
    const timeline = await playerTimeline(play.participant_id, play.case_id);
    res.json({ answer, question: storedQuestion, clues, newClues, timeline });
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

    // 근거 2개: 알리바이를 깨는 추론 1개 + 범인과 범행을 잇는 추론 1개 (플레이어가 연결해서 얻은 추론 중에서)
    const slots = [
      { slot: "알리바이" as const, id: Number(req.body?.alibiDeductionId) },
      { slot: "연결" as const, id: Number(req.body?.linkDeductionId) },
    ];
    if (slots.some((s) => !s.id) || slots[0].id === slots[1].id) {
      throw new HttpError(400, "근거가 될 추론을 칸마다 하나씩 골라주세요.");
    }
    const found = await query<{ deduction_id: number; name: string; proof_role: string | null; proof_note: string | null }>(
      `SELECT d.deduction_id, d.name, d.proof_role, d.proof_note FROM link_attempt la JOIN deduction d ON d.deduction_id = la.deduction_id
       WHERE la.participant_id = ? AND d.deduction_id IN (?)`,
      [play.participant_id, slots.map((s) => s.id)],
    );
    if (found.length !== 2) throw new HttpError(400, "찾은 추론 중에서 골라주세요.");
    const picked = slots.map((s) => {
      const c = found.find((f) => f.deduction_id === s.id)!;
      return { ...s, name: c.name, ok: !!accused.is_culprit && c.proof_role === s.slot, note: c.proof_note, role: c.proof_role };
    });

    const accusationId = await insert(
      `INSERT INTO accusation (participant_id, character_id) VALUES (?, ?)`,
      [play.participant_id, accused.character_id],
    );
    await query(`INSERT INTO accusation_evidence (accusation_id, deduction_id, slot) VALUES ?`, [
      picked.map((p) => [accusationId, p.id, p.slot]),
    ]);
    // 범인을 맞히고, 두 근거가 각각 맞는 역할이어야 해결
    const result = picked.every((p) => p.ok) ? "성공" : "실패";
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
    const stats = await one<{ minutes: number; questions: number; clues: number; clueTotal: number; deductions: number; deductionTotal: number }>(
      `SELECT TIMESTAMPDIFF(MINUTE, pl.started_at, pl.ended_at) AS minutes,
              (SELECT COUNT(*) FROM interrogation i WHERE i.participant_id = ?) AS questions,
              (SELECT COUNT(*) FROM clue_discovery d WHERE d.participant_id = ?) AS clues,
              (SELECT COUNT(*) FROM clue k JOIN scene s ON s.scene_id = k.scene_id WHERE s.case_id = pl.case_id) AS clueTotal,
              (SELECT COUNT(*) FROM link_attempt la WHERE la.participant_id = ? AND la.deduction_id IS NOT NULL) AS deductions,
              (SELECT COUNT(*) FROM deduction d WHERE d.case_id = pl.case_id) AS deductionTotal
       FROM play pl WHERE pl.play_id = ?`,
      [play.participant_id, play.participant_id, play.participant_id, play.play_id],
    );
    // 결정적 증거/증언: 찾았는지 여부와, 증언이면 그걸 털어놓은 실제 대화
    const keyClues = await query<ClueRow & { scene_name: string; found_at: string | null; char_name: string | null }>(
      `SELECT k.clue_id, k.scene_id, k.character_id, k.name, k.description, k.clue_type,
              s.name AS scene_name, cd.found_at, g.name AS char_name
       FROM clue k JOIN scene s ON s.scene_id = k.scene_id
       LEFT JOIN clue_discovery cd ON cd.clue_id = k.clue_id AND cd.participant_id = ?
       LEFT JOIN game_character g ON g.character_id = k.character_id
       WHERE s.case_id = ? AND k.is_key = TRUE ORDER BY k.clue_id`,
      [play.participant_id, play.case_id],
    );
    const keyEvidence = keyClues
      .filter((k) => k.clue_type !== "증언")
      .map((k) => ({ name: k.name, description: k.description, clue_type: k.clue_type, scene_name: k.scene_name, found: k.found_at != null }));
    const t = keyClues.find((k) => k.clue_type === "증언");
    let keyTestimony = null;
    if (t) {
      const chat = t.found_at
        ? await one<{ question: string; answer: string }>(
            `SELECT question, answer FROM interrogation
             WHERE participant_id = ? AND character_id = ? AND asked_at <= ?
             ORDER BY asked_at DESC, interrogation_id DESC LIMIT 1`,
            [play.participant_id, t.character_id, t.found_at],
          )
        : null;
      keyTestimony = { name: t.name, description: t.description, character: t.char_name, found: t.found_at != null, chat };
    }
    res.json({
      result,
      culpritCorrect: !!accused.is_culprit,
      // 범인을 틀렸으면 근거 설명은 진범 기준이라 의미가 없으므로 이름만
      evidence: picked.map((p) => ({ slot: p.slot, name: p.name, ok: p.ok, note: accused.is_culprit ? p.note : null })),
      accused: accused.name,
      culprit, truth: c.truth, timeline, stats, keyEvidence, keyTestimony, caseId: play.case_id });
  }),
);

router.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message });
    return;
  }
  if (err instanceof LlmBusyError) {
    res.status(429).json({ error: "AI가 잠깐 숨을 고르는 중이에요. 몇 초 뒤에 다시 물어보세요." });
    return;
  }
  console.error(err);
  res.status(500).json({ error: "서버에서 문제가 생겼어요." });
});
