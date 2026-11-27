/*
 * 범인 진술 회귀 시나리오: scenarios/*.json 의 질문을 차례로 실제 AI에게 던지고,
 * 답마다 지금 입장(처음/물러선 이야기)과 금지된 말(fallback_guard)에 걸렸는지 표시한다.
 * 실행: npm run scenarios -w server  (server/.env 의 DB·AI 키를 쓴다. 요청 수만큼 AI 한도를 쓴다)
 */
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { one, pool } from "./db.js";
import { interrogate, onFallback, storyViolation, formatQuestion } from "./llm.js";
import type { CaseRow, CharacterRow } from "./types.js";

interface Scenario { character_id: number; note?: string; turns: { q: string; evidence?: number }[] }

const dir = join(import.meta.dirname, "..", "scenarios");
let failed = 0;
for (const file of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
  const sc = JSON.parse(readFileSync(join(dir, file), "utf8")) as Scenario;
  const ch = (await one<CharacterRow>(`SELECT * FROM game_character WHERE character_id = ?`, [sc.character_id]))!;
  const c = (await one<CaseRow>(`SELECT * FROM case_file WHERE case_id = ?`, [ch.case_id]))!;
  console.log(`\n=== ${file} · ${ch.name}${sc.note ? ` · ${sc.note}` : ""}`);
  const history: { question: string; answer: string }[] = [];
  const shown: number[] = [];
  for (const t of sc.turns) {
    const ev = t.evidence
      ? (await one<{ clue_id: number; name: string; description: string | null }>(
          `SELECT clue_id, name, description FROM clue WHERE clue_id = ?`, [t.evidence]))!
      : undefined;
    const discovered = [...new Set([...shown, ...(ev ? [ev.clue_id] : [])])];
    const r = await interrogate(c, ch, history, t.q, ev, discovered, shown);
    if (ev) shown.push(ev.clue_id);
    history.push({ question: formatQuestion(t.q, ev), answer: r.answer });
    const stage = onFallback(ch, { discovered, shownBefore: shown }, history) ? "물러선 이야기" : "처음 이야기";
    const bad = storyViolation(ch, stage === "물러선 이야기", r.answer);
    if (bad) failed++;
    console.log(`\n탐정${ev ? ` [증거: ${ev.name}]` : ""}: ${t.q}\n${ch.name} (${stage}): ${r.answer}${bad ? `\n  ✗ 금지된 말: /${bad}/` : ""}`);
  }
}
console.log(`\n금지된 말 ${failed}건`);
await pool.end();
process.exit(failed ? 1 : 0);
