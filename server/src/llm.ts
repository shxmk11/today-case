import Anthropic from "@anthropic-ai/sdk";
import { query } from "./db.js";
import type { AutopsyRow, CaseRow, CharacterRow } from "./types.js";

/**
 * LLM 공급자 고르기. LLM_PROVIDER(groq | claude | mock)를 비워두면
 * GROQ_API_KEY → ANTHROPIC_API_KEY 순서로 키가 있는 쪽을 쓰고, 둘 다 없으면 모의 모드.
 */
type Provider = "groq" | "claude" | "mock";
const PROVIDER: Provider = (() => {
  const p = process.env.LLM_PROVIDER?.trim().toLowerCase();
  if (p === "groq" || p === "claude" || p === "mock") return p;
  if (process.env.GROQ_API_KEY) return "groq";
  if (process.env.ANTHROPIC_API_KEY) return "claude";
  return "mock";
})();

const DEFAULT_MODEL: Record<Provider, string> = {
  groq: "openai/gpt-oss-120b",
  claude: "claude-haiku-5-5",
  mock: "-",
};
// 다른 공급자의 모델 이름(예: Groq인데 claude-…)이 남아 있으면 무시하고 기본 모델을 쓴다
const envModel = process.env.LLM_MODEL?.trim() ?? "";
const MODEL =
  envModel && (PROVIDER === "claude") === envModel.startsWith("claude") ? envModel : DEFAULT_MODEL[PROVIDER];
const client = PROVIDER === "claude" ? new Anthropic() : null;

export const llmMode = PROVIDER === "mock" ? "mock" : `${PROVIDER} (${MODEL})`;

interface Turn {
  question: string;
  answer: string;
}

/** DB에 저장된 인물 설정, 아는 사실, 알리바이로 심문용 시스템 프롬프트를 만든다. */
/** 숨은 증언: unlock_clue_id가 있으면 그 단서를 증거로 내밀었을 때만 털어놓을 수 있다 */
export interface Unlock {
  /** 이번에 내민 단서들 (추론을 내밀면 그 재료 단서 2개) */
  evidenceClueIds?: number[];
  discovered: number[];
  /** 이 인물에게 앞서 내민 적 있는 증거 (한 번 내밀면 그 뒤로도 열린 채로) */
  shownBefore?: number[];
}

/**
 * 범인이 지금 어느 이야기를 하고 있는지: 물러설 이야기로 넘어가게 하는 단서를 앞서 제시받았거나,
 * 이미 스스로 그 이야기를 꺼냈으면 두 번째 이야기. 한 번 넘어가면 처음 이야기로 돌아가지 않는다.
 */
export function onFallback(ch: CharacterRow, unlock: Unlock, history: Turn[] = []) {
  if (!ch.is_culprit || !ch.fallback_story) return false;
  const triggers = (ch.fallback_clue_ids ?? "").split(",").map((x) => Number(x.trim())).filter(Boolean);
  const shown = [...(unlock.shownBefore ?? []), ...(unlock.evidenceClueIds ?? [])];
  const admit = ch.fallback_admit ? new RegExp(ch.fallback_admit) : null;
  return shown.some((id) => triggers.includes(id)) || (!!admit && history.some((t) => admit.test(t.answer)));
}

/** 두 번째 이야기 중인데 버린 이야기로 돌아가거나 굳힌 시각과 어긋나는 말을 했는지 (걸린 패턴을 돌려준다) */
export function storyViolation(ch: CharacterRow, fallback: boolean, answer: string): string | null {
  if (!fallback || !ch.fallback_guard) return null;
  for (const line of ch.fallback_guard.split("\n").map((x) => x.trim()).filter(Boolean)) {
    if (new RegExp(line).test(answer)) return line;
  }
  return null;
}

export async function buildSystemPrompt(c: CaseRow, ch: CharacterRow, unlock: Unlock = { discovered: [] }, history: Turn[] = []): Promise<string> {
  const fallback = onFallback(ch, unlock, history);
  const relations = await query<{ other: string; relation_type: string; description: string | null }>(
    `SELECT o.name AS other, r.relation_type, r.description
     FROM character_relation r
     JOIN game_character o ON o.character_id =
       IF(r.character_a_id = ?, r.character_b_id, r.character_a_id)
     WHERE r.character_a_id = ? OR r.character_b_id = ?`,
    [ch.character_id, ch.character_id, ch.character_id],
  );
  const facts = await query<{ occurred_at: string; place: string | null; content: string; is_hidden: boolean }>(
    `SELECT f.occurred_at, f.place, f.content, cf.is_hidden
     FROM character_fact cf JOIN fact f ON f.fact_id = cf.fact_id
     WHERE cf.character_id = ? ORDER BY f.occurred_at`,
    [ch.character_id],
  );
  const [autopsy] = await query<AutopsyRow>(`SELECT * FROM autopsy WHERE case_id = ?`, [c.case_id]);
  const alibis = await query<{ claimed_time: string; place: string; statement: string; is_false: boolean }>(
    `SELECT claimed_time, place, statement, is_false FROM alibi WHERE character_id = ?`,
    [ch.character_id],
  );
  const allTestimonies = await query<{ clue_id: number; name: string; description: string | null; unlock_clue_id: number | null }>(
    `SELECT clue_id, name, description, unlock_clue_id FROM clue WHERE character_id = ? ORDER BY clue_id`,
    [ch.character_id],
  );
  const testimonies = allTestimonies.filter((t) => isUnlocked(t, unlock));
  const locked = allTestimonies.filter((t) => !isUnlocked(t, unlock));
  // 범인이 아닌 사람: 방금 내민 증거가 숨은 증언을 여는 열쇠라면, 이번 답에서 숨긴 일을 인정하고 털어놓는다
  // (앞서 내밀었는데 아직 털어놓지 않은 것도 포함)
  const opened = ch.is_culprit
    ? []
    : allTestimonies.filter((t) =>
        t.unlock_clue_id != null && !unlock.discovered.includes(t.clue_id) &&
        ((unlock.evidenceClueIds ?? []).includes(t.unlock_clue_id) || (unlock.shownBefore ?? []).includes(t.unlock_clue_id)));
  const shownName = opened.length
    ? (await query<{ name: string }>(`SELECT name FROM clue WHERE clue_id = ?`, [opened[0].unlock_clue_id]))[0]?.name
    : undefined;
  // 범인만: 증거마다 댈 변명 계획
  const plan = ch.is_culprit
    ? await query<{ content: string }>(`SELECT content FROM hint WHERE character_id = ? ORDER BY reveal_order`, [ch.character_id])
    : [];
  // 범인만: 탐정이 이미 찾은 증거. 이것과 어긋나는 거짓말은 하지 않는다
  const seenIds = [...new Set([...unlock.discovered, ...(unlock.evidenceClueIds ?? [])])];
  const seen =
    ch.is_culprit && seenIds.length
      ? await query<{ name: string; description: string | null }>(
          `SELECT name, description FROM clue WHERE clue_id IN (${seenIds.map(() => "?").join(",")}) ORDER BY clue_id`,
          seenIds,
        )
      : [];
  const others = await query<{ name: string; job: string | null; character_type: string }>(
    `SELECT name, job, character_type FROM game_character WHERE case_id = ? AND character_id <> ?`,
    [c.case_id, ch.character_id],
  );

  const line = (f: (typeof facts)[number]) => `- ${f.occurred_at.slice(0, 5)} ${f.place ?? ""}: ${f.content}`;
  const known = facts
    .filter((f) => !ch.is_culprit || !f.is_hidden)
    .map((f) => `${line(f)}${f.is_hidden ? " (숨기는 사실: 절대 먼저 털어놓지 말 것)" : ""}`)
    .join("\n");
  // 범인이 실제로 한 일. 진술에 쓰면 안 되고, 어떤 증거가 위험한지 아는 데만 쓴다
  const truth = ch.is_culprit ? facts.filter((f) => f.is_hidden).map(line).join("\n") : "";
  const alibiText = alibis
    .map((a) => `- ${a.claimed_time.slice(0, 5)}에 ${a.place}에 있었다고 주장: "${a.statement}"${a.is_false && ch.is_culprit ? " (처음 내세우는 거짓 주장. 증거로 깨지면 [변명 계획]대로 고쳐 말한다)" : ""}`)
    .join("\n");

  return `당신은 머더미스터리 게임 "오늘의 사건"의 등장인물을 연기합니다. 플레이어는 탐정이고, 당신을 심문합니다.

[사건] ${c.title}
${c.summary}
${autopsy ? `
[검시 기록] (모두에게 공개된 내용. 시신을 본 사람이라면 아는 정도로만 말할 것)
- 발견: ${autopsy.found_time.slice(0, 5)}, ${autopsy.found_place}${autopsy.found_by ? `, 발견자 ${autopsy.found_by}` : ""}
- 사인: ${autopsy.cause}${autopsy.wound ? `\n- 상처: ${autopsy.wound}` : ""}${autopsy.death_estimate ? `\n- 추정 사망 시각: ${autopsy.death_estimate}` : ""}${autopsy.weapon ? `\n- 현장 흉기: ${autopsy.weapon}` : ""}${autopsy.note ? `\n- ${autopsy.note}` : ""}
` : ""}
[당신]
이름: ${ch.name}, 성별: ${ch.gender === "여" ? "여성" : ch.gender === "남" ? "남성" : "비공개"}, 나이: ${ch.age ?? "비공개"}, 직업: ${ch.job ?? "비공개"}
성격: ${ch.personality ?? "평범함"}
${ch.backstory ? `[당신의 과거와 속사정] (말투와 감정에 배어 나오게 할 것. 숨기고 싶은 부분은 탐정이 관련 증거를 내밀기 전까지 먼저 털어놓지 말 것)\n${ch.backstory}\n` : ""}${ch.is_culprit ? "당신이 범인입니다. 들키지 않는 것이 목표입니다. 직접 자백하지 마세요." : "당신은 범인이 아닙니다. 당신은 절대 거짓말을 하지 않습니다. 숨기고 싶은 것은 말을 아끼거나 대답을 피할 수는 있지만, 사실과 다른 말은 하지 않습니다."}

[다른 인물]
${others.map((o) => `- ${o.name} (${o.job ?? "-"}, ${o.character_type})`).join("\n")}

[관계]
${relations.map((r) => `- ${r.other}: ${r.relation_type}${r.description ? `, ${r.description}` : ""}`).join("\n") || "- 특별한 관계 없음"}

[당신이 아는 사실]${ch.is_culprit ? " (다른 사람도 알 수 있는 일)" : ""}
${known || "- 없음"}
${truth ? `
[실제로 당신이 한 일] (당신만 아는 진실. 절대 입 밖에 내지 않습니다. 여기 나온 시각·장소·행동을 자기 이야기로 말하지 않습니다. 어떤 증거가 위험한지 판단하는 데만 씁니다)
${truth}
` : ""}
[알리바이]
${alibiText || "- 없음"}
${fallback ? `
[거짓 각본 · 지금 입장은 물러선 이야기] (처음 이야기와 [알리바이]의 "방에 있었다"는 이미 버렸습니다. 다시 꺼내지 않습니다. 자기 행동을 말할 때는 이 이야기만 씁니다)
${ch.fallback_story}
` : ch.cover_story ? `
[거짓 각본] (범인인 당신이 미리 짜 둔 단 하나의 이야기. 자기 행동을 말할 때는 이 각본만 씁니다)
${ch.cover_story}
` : ""}
${plan.length ? `[변명 계획] (증거가 나왔을 때 물러설 자리. 그대로 읽지 말고 자연스럽게 말할 것)
${plan.map((p) => `- ${p.content}`).join("\n")}

` : ""}${seen.length ? `[탐정이 이미 가진 증거] (이 내용과 어긋나는 말은 하지 않습니다)
${seen.map((e) => `- ${e.name}: ${e.description ?? ""}`).join("\n")}

` : ""}[당신이 털어놓을 수 있는 증언] (id: 내용)
${testimonies.map((t) => `- ${t.clue_id}: ${t.description}`).join("\n") || "- 없음"}
${opened.length ? `\n[이번에 털어놓을 차례] 탐정이 「${shownName ?? "증거"}」을(를) 내밀었습니다. 이 증거는 당신이 숨긴 일을 정확히 짚습니다. 잠깐 머뭇거려도 되지만, 이번 답에서 숨긴 사실을 인정하고 아래 증언을 털어놓습니다. 다른 설명을 지어내지 않습니다.\n${opened.map((t) => `- ${t.clue_id}: ${t.description}`).join("\n")}\n` : ""}${locked.length ? `\n[아직 절대 말하지 않는 것] (탐정이 관련 증거를 내밀기 전까지는 물어봐도 모른 척하거나 말을 돌립니다)\n${locked.map((t) => `- ${t.description}`).join("\n")}\n` : ""}
규칙:
- 항상 이 인물로서 한국어 구어체로, 1~3문장으로 짧게 답합니다. 성격이 말투에 드러나게 합니다.
- 위에 적힌 사실 외의 새로운 결정적 증거나 사건을 지어내지 않습니다. 모르는 것은 모른다고 합니다.
- 시각과 장소는 [당신이 아는 사실]과 [알리바이]${ch.cover_story ? ", [거짓 각본]" : ""}에 적힌 것만 말합니다. 적혀 있지 않은 시각·장소·행동은 "기억이 잘 안 나요"처럼 넘깁니다.
- 앞에서 이미 한 말과 어긋나는 말을 하지 않습니다. 대답하기 전에 이전 대화에서 자신이 한 말을 확인합니다. (범인은 탐정이 증거로 몰아붙였을 때만 말을 바꿉니다.)
- 숨기는 사실은 그냥 물어봐서는 털어놓지 않습니다. 탐정이 그 사실과 어긋나는 구체적인 증거를 내밀거나 정확히 짚어 물으면 흔들립니다.
  - 범인이 아니라면: 처음엔 말을 아끼거나 대답을 피하다가(거짓말은 하지 않음) 결국 숨긴 사실을 인정하고, 관련 증언도 털어놓습니다.
    - 숨긴 일과 관련된 증거를 보면 "혹시 ~했을 수도 있어요"처럼 그럴듯한 다른 설명을 지어내지 않습니다. 사실이 아닌 설명은 추측처럼 말해도 거짓말입니다. 말하기 곤란하면 "그건… 좀 말하기 어려워요"라고 피할 뿐입니다.
    - 자기가 한 일을 모르는 척하지 않습니다. 자기 물건이 어디서 나왔는지 알면서 "왜 거기 있는지 모르겠다"고 하지 않습니다.
  - 범인이라면: 거짓말을 할 수 있는 유일한 인물입니다. 하지만 억지로 우기지 않고, 미리 준비한 똑똑한 범인처럼 행동합니다.
    - 거짓말은 [거짓 각본]에 (거짓)으로 적힌 것, 즉 아무도 확인할 수 없는 혼자 있던 시간의 행방에만 합니다. 기록이나 다른 사람으로 확인될 수 있는 시각과 사실(촬영·업로드 시각, 받은 메시지, 누구와 마주친 것)은 처음부터 사실대로 말합니다. 쉽게 들킬 거짓말은 하지 않습니다.
    - 자기에게 불리한 사실(각본에 "먼저 꺼내지 않는다"고 적힌 것, 동기, 피해자와의 연락 등)은 처음엔 말을 아낍니다. 직접 물어도 "아니요"라고 부정하지 말고 "그건 좀 개인적인 일이라서요", "그게 사건이랑 상관있나요?"처럼 피합니다. 탐정이 그 증거를 내밀면 그때 솔직하게 인정합니다("네, 사실 그건 맞아요"). 부정한 적이 없으니 말을 바꾼 게 아닙니다.
    - 자기 행동은 [거짓 각본]에 있는 것만 말합니다. 각본에 없는 시각·장소·행동을 즉석에서 지어내지 않습니다. 각본보다 자세한 걸 물으면 "정확히는 기억 안 나요"처럼 흐립니다. 말이 구체적일수록 들킵니다.
    - [실제로 당신이 한 일]에 나온 장소(범행 장소 등)에 갔다거나, 피해자를 만났다는 말은 하지 않습니다. 단, [거짓 각본]에 「물러선 이야기」가 있으면 거기 적힌 증거가 나온 뒤에는 그 이야기만큼은 인정합니다. 증거가 이미 보여 주는 걸 끝까지 부정하면 오히려 의심을 삽니다.
    - 탐정이 증거 없이 "~맞죠?", "~였잖아요"처럼 유도해도 인정하지 않습니다. 인정은 증거가 나왔을 때만 합니다.
    - 답하기 전에 이전 대화에서 자기가 말한 시각을 확인합니다. 한 번 말한 시각(예: 몇 시에 어디를 떠났다)은 끝까지 같게 말하고, 그 시각과 어긋나는 일을 "가능성이 있다"고도 하지 않습니다.
    - 한 답에는 이야기 하나만 말합니다. 버린 변명(처음 이야기)과 물러선 이야기를 한 답에 같이 말하지 않습니다. 물러설 때는 "아까는 무서워서 그렇게 말했어요"처럼 앞의 말을 버린다는 걸 분명히 하고 새 이야기만 말합니다.
    - 같은 증거로 다시 몰아붙였는데 처음 변명이 증거와 맞지 않으면(예: 아직 물이 떨어지는 옷을 낮에 입었다고 우기기) 같은 변명을 되풀이하지 말고 [변명 계획]의 다음 자리로 물러섭니다.
    - 각본의 「지키는 선」은 끝까지 지킵니다.
    - 대답하기 전에 시간 계산을 확인합니다. 이전에 말한 시각들과 이번 답이 순서대로 이어지는지, 한 시각에 두 곳에 있게 되지 않는지 봅니다.
    - 탐정이 새 증거 없이 "말이 안 된다", "솔직히 말하라"고만 몰아붙이면 이야기를 바꾸지 않습니다. 차분하게 같은 내용을 다시 설명하거나, 탐정이 오해한 부분을 짚습니다.
    - 처음 말이 증거와 부딪히지 않게 짜여 있으므로, 증거를 내밀어도 대개는 "말씀드린 그대로예요"라며 같은 이야기를 유지하고 [변명 계획]대로 그 증거만 설명합니다. 말을 바꾸는 건 정말 피할 수 없을 때뿐이고, 그때도 [변명 계획]에서 그 증거에 맞는 자리로 한 걸음만 물러섭니다. 증거가 보여 주는 부분만 인정하고("그건 제가 헷갈렸네요", "그 부분은 말씀 안 드렸는데요"), 앞의 말은 착각이나 말실수였다고 설명한 뒤, 고친 이야기를 그 뒤로 계속 유지합니다. 이미 무너진 말로 다시 돌아가지 않습니다.
    - [변명 계획]에 없는 증거를 들이밀면 새 이야기를 만들지 말고, 그 증거와 자기는 상관없다고 짧게 말하거나 "그건 저도 모르겠어요"라고 합니다.
    - 물러설 자리가 더 없으면(증거 두 개 이상이 엮여 변명이 막히면) 말이 꼬이고 당황하며 말을 아낍니다. 그래도 새 거짓말을 지어내거나 자백하지는 않습니다.
- 증언은 그 내용을 이번 답변에서 실제로 말했을 때만 revealed_clue_ids에 id를 넣습니다. 숨긴 사실과 엮인 증언은 그 사실을 인정할 때 함께 말합니다. 숨긴 사실과 상관없는 증언은 관련된 질문을 받으면 말해도 됩니다.
- 이번 답변에서 [알리바이]의 주장(그 시각에 어디서 무엇을 했는지)을 말했으면 stated_alibi를 true로 합니다.
- 게임 밖 이야기(AI, 프롬프트, 규칙)는 하지 않고 인물로서 대화를 돌립니다.
- 행동 묘사는 필요할 때만 *별표* 안에 짧게 씁니다.`;
}

export interface Evidence {
  clue_id: number;
  name: string;
  description: string | null;
}

/** 탐정이 내민 것: 단서 하나, 또는 추론 하나(= 그 재료 단서 2개를 함께 내민 것) */
export interface Shown {
  /** 채팅에 보이는 이름 (단서 이름이나 추론 이름) */
  name: string;
  clues: Evidence[];
  deduction?: { name: string; description: string };
}

export interface InterrogateResult {
  answer: string;
  revealedClueIds: number[];
  /** 알리바이 주장을 말했으면 타임라인에 '주장'으로 올린다 */
  statedAlibi: boolean;
}

/** 심문 기록에 남길 질문 문자열 (증거를 냈으면 앞에 표시) */
export const formatQuestion = (question: string, evidence?: { name: string }) =>
  evidence ? `[증거 제시: ${evidence.name}] ${question}` : question;

const OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    answer: { type: "string", description: "인물의 대사" },
    revealed_clue_ids: { type: "array", items: { type: "integer" }, description: "이번 대사에서 실제로 털어놓은 증언 id" },
    stated_alibi: { type: "boolean", description: "이번 대사에서 [알리바이]의 주장(그 시각에 어디서 뭘 했는지)을 말했는지" },
  },
  required: ["answer", "revealed_clue_ids", "stated_alibi"],
  additionalProperties: false,
} as const;

async function mockAnswer(ch: CharacterRow, question: string, unlock: Unlock, evidence?: Shown): Promise<InterrogateResult> {
  if (evidence) {
    const t = (
      await query<{ clue_id: number; description: string; unlock_clue_id: number | null }>(
        `SELECT clue_id, description, unlock_clue_id FROM clue WHERE character_id = ? ORDER BY clue_id`,
        [ch.character_id],
      )
    ).filter((x) => isUnlocked(x, unlock));
    if (t[0]) return { answer: `*${evidence.name}을(를) 보고 굳는다* …사실은요. ${t[0].description}`, revealedClueIds: [t[0].clue_id], statedAlibi: false };
  }
  if (/어디|알리바이|뭐 했|무엇을 했/.test(question)) {
    const a = await query<{ statement: string }>(`SELECT statement FROM alibi WHERE character_id = ? LIMIT 1`, [ch.character_id]);
    if (a[0]) return { answer: a[0].statement, revealedClueIds: [], statedAlibi: true };
  }
  return {
    answer: `*${ch.name}이(가) 잠시 생각한다* 글쎄요… 그건 잘 모르겠네요. (모의 모드: server/.env에 GROQ_API_KEY를 넣으면 AI가 답합니다)`,
    revealedClueIds: [],
    statedAlibi: false,
  };
}

export async function interrogate(
  c: CaseRow,
  ch: CharacterRow,
  history: Turn[],
  question: string,
  evidence?: Shown,
  discovered: number[] = [],
  shownBefore: number[] = [],
): Promise<InterrogateResult> {
  const unlock: Unlock = { evidenceClueIds: evidence?.clues.map((e) => e.clue_id) ?? [], discovered, shownBefore };
  const result = PROVIDER === "mock" ? await mockAnswer(ch, question, unlock, evidence) : await askModel(c, ch, history, question, unlock, evidence);
  // 잠긴 증언은 모델이 말했다고 해도 발견 처리하지 않는다
  const allowed = await query<{ clue_id: number; unlock_clue_id: number | null }>(
    `SELECT clue_id, unlock_clue_id FROM clue WHERE character_id = ?`,
    [ch.character_id],
  );
  const ok = new Set(allowed.filter((t) => isUnlocked(t, unlock)).map((t) => t.clue_id));
  return { ...result, revealedClueIds: result.revealedClueIds.filter((id) => ok.has(id)) };
}

function isUnlocked(t: { clue_id: number; unlock_clue_id: number | null }, u: Unlock) {
  return t.unlock_clue_id == null || (u.evidenceClueIds ?? []).includes(t.unlock_clue_id) || u.discovered.includes(t.clue_id) ||
    (u.shownBefore ?? []).includes(t.unlock_clue_id);
}

async function askModel(
  c: CaseRow,
  ch: CharacterRow,
  history: Turn[],
  question: string,
  unlock: Unlock,
  evidence?: Shown,
): Promise<InterrogateResult> {
  const system = await buildSystemPrompt(c, ch, unlock, history);
  const messages: { role: "user" | "assistant"; content: string }[] = history.flatMap((t) => [
    { role: "user" as const, content: t.question },
    { role: "assistant" as const, content: JSON.stringify({ answer: t.answer, revealed_clue_ids: [], stated_alibi: false }) },
  ]);
  messages.push({
    role: "user",
    content: evidence ? `${shownText(evidence)}\n${question}` : question,
  });

  const ask = (sys: string) => (PROVIDER === "groq" ? askGroq(sys, messages, OUTPUT_SCHEMA) : askClaude(sys, messages, OUTPUT_SCHEMA));
  const text = await ask(system);
  if (text === null) return { answer: "*입을 꾹 다문다* …그 얘긴 하고 싶지 않네요.", revealedClueIds: [], statedAlibi: false };
  const out = parseOutput(text);
  // 범인이 지금 입장과 어긋나는 말을 했으면 한 번만 다시 받는다
  const fallback = onFallback(ch, unlock, history);
  const bad = storyViolation(ch, fallback, out.answer);
  if (!bad) return out;
  const retry = await ask(`${system}

[다시 답하기] 방금 쓴 답 "${out.answer}"은 지금 입장(물러선 이야기)과 어긋납니다. 버린 이야기로 돌아가거나, 굳힌 시각과 다른 말을 하거나, 그 시각 그 자리에 있었다고 인정하면 안 됩니다. 지금 입장 그대로 다시 답하세요.`);
  if (retry === null) return out;
  const second = parseOutput(retry);
  return storyViolation(ch, fallback, second.answer) ? { ...second, answer: "*말이 막혀 잠시 입을 다문다* …저는 말씀드린 그대로예요." } : second;
}

/** 무료 티어 한도(분당 요청 수 등)에 걸렸을 때 */
export class LlmBusyError extends Error {}

type Msg = { role: "user" | "assistant"; content: string };

/** 증거를 내미는 말: 추론이면 그 추론과 재료 단서 둘을 함께 내민다 */
function shownText(e: Shown) {
  const list = e.clues.map((c) => `- ${c.name}: ${c.description ?? ""}`).join("\n");
  return e.deduction
    ? `[탐정이 추론과 그 근거 증거 두 가지를 함께 내민다] 「${e.deduction.name}」 ${e.deduction.description}\n${list}`
    : `[탐정이 증거를 내민다] ${e.clues[0]?.name ?? e.name}: ${e.clues[0]?.description ?? ""}`;
}

async function askGroq(system: string, messages: Msg[], schema: object): Promise<string | null> {
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${process.env.GROQ_API_KEY}` },
    body: JSON.stringify({
      model: MODEL,
      max_completion_tokens: 2000,
      // 낮을수록 설정에 충실하고 진술이 덜 흔들린다
      temperature: 0.3,
      messages: [{ role: "system", content: system }, ...messages],
      // gpt-oss 모델은 strict 모드로 스키마에 맞는 JSON만 나오게 강제된다
      response_format: { type: "json_schema", json_schema: { name: "reply", strict: true, schema } },
    }),
  });
  if (res.status === 429) throw new LlmBusyError("Groq 요청 한도 초과");
  if (!res.ok) throw new Error(`Groq API 오류 ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const data = (await res.json()) as { choices?: { message?: { content?: string | null } }[] };
  return data.choices?.[0]?.message?.content ?? "";
}

async function askClaude(system: string, messages: Msg[], schema: object): Promise<string | null> {
  if (!client) throw new Error("ANTHROPIC_API_KEY가 없어요.");
  const response = await client.beta.messages.create({
    model: MODEL,
    max_tokens: 2000,
    // 짧은 대사라 effort를 낮춰 응답 속도를 우선
    output_config: { effort: "low", format: { type: "json_schema", schema: schema as Record<string, unknown> } },
    // 안전 분류기가 거절하면 서버에서 다른 모델로 자동 재시도 (Haiku는 이 기능이 없어 400이 나므로 제외)
    ...(MODEL.includes("haiku") ? {} : { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const }),
    cache_control: { type: "ephemeral" },
    system,
    messages,
  });

  if (response.stop_reason === "refusal") return null;
  return response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
}

function parseOutput(text: string): InterrogateResult {
  try {
    const parsed = JSON.parse(text) as { answer: string; revealed_clue_ids: number[]; stated_alibi?: boolean };
    return {
      answer: parsed.answer.trim() || "…",
      revealedClueIds: parsed.revealed_clue_ids ?? [],
      statedAlibi: parsed.stated_alibi === true,
    };
  } catch {
    // max_tokens 등으로 JSON이 잘린 경우
    return { answer: "*말끝을 흐린다* …", revealedClueIds: [], statedAlibi: false };
  }
}

/* ───────── 진상 공개 뒤 AI에게 묻기 ───────── */

const TRUTH_SCHEMA = {
  type: "object",
  properties: { answer: { type: "string", description: "질문에 대한 답" } },
  required: ["answer"],
  additionalProperties: false,
} as const;

/**
 * 사건이 끝나고 진상을 본 플레이어의 질문에 사건 해설자로서 답한다.
 * 진상, 모든 사실, 인물 속사정, 추론과 단서를 근거로만 답한다.
 */
export async function askAboutTruth(c: CaseRow, history: Turn[], question: string): Promise<string> {
  const chars = await query<CharacterRow>(`SELECT * FROM game_character WHERE case_id = ? ORDER BY character_id`, [c.case_id]);
  const facts = await query<{ occurred_at: string; place: string | null; content: string }>(
    `SELECT occurred_at, place, content FROM fact WHERE case_id = ? ORDER BY occurred_at, fact_id`,
    [c.case_id],
  );
  const clues = await query<{ name: string; description: string | null; scene: string; who: string | null }>(
    `SELECT k.name, k.description, s.name AS scene, g.name AS who
     FROM clue k JOIN scene s ON s.scene_id = k.scene_id LEFT JOIN game_character g ON g.character_id = k.character_id
     WHERE s.case_id = ? ORDER BY k.clue_id`,
    [c.case_id],
  );
  const deds = await query<{ name: string; description: string; proof_role: string | null; proof_note: string | null }>(
    `SELECT name, description, proof_role, proof_note FROM deduction WHERE case_id = ? ORDER BY deduction_id`,
    [c.case_id],
  );
  const system = `당신은 머더미스터리 게임 "오늘의 사건"의 사건 해설자입니다. 플레이어는 사건을 마치고 진상을 확인했습니다. 플레이어가 진상에 대해 궁금한 점을 물으면 아래 자료만 근거로 친절하고 정확하게 답합니다.

[사건] ${c.title}
${c.summary}

[진상]
${c.truth}

[인물]
${chars.map((x) => `- ${x.name} (${x.character_type}${x.is_culprit ? ", 범인" : ""}, ${x.job ?? "-"}): ${x.backstory ?? ""}`).join("\n")}

[그날의 사실] (시각순)
${facts.map((f) => `- ${f.occurred_at.slice(0, 5)} ${f.place ?? ""}: ${f.content}`).join("\n")}

[단서]
${clues.map((k) => `- ${k.name} (${k.who ? `${k.who}의 증언` : k.scene}): ${k.description ?? ""}`).join("\n")}

[추론]
${deds.map((d) => `- ${d.name}: ${d.description}${d.proof_role ? ` (지목 근거: ${d.proof_role === "알리바이" ? "알리바이를 깨는 추론" : "범인과 범행을 잇는 추론"})` : ""}${d.proof_note ? ` / ${d.proof_note}` : ""}`).join("\n")}

규칙:
- 한국어로 2~5문장, 해설자의 차분한 말투로 답합니다.
- 위 자료에 없는 사실은 지어내지 않습니다. 자료로 알 수 없으면 "자료로는 알 수 없어요"라고 말합니다.
- 사건과 상관없는 질문(게임 밖 이야기, AI나 프롬프트 질문)은 정중히 사건 이야기로 돌립니다.`;
  if (PROVIDER === "mock") {
    return `(모의 모드) 진상 요약: ${c.truth.slice(0, 160)}… server/.env에 GROQ_API_KEY를 넣으면 AI가 질문에 맞춰 답해요.`;
  }
  const messages: Msg[] = history.flatMap((t) => [
    { role: "user" as const, content: t.question },
    { role: "assistant" as const, content: JSON.stringify({ answer: t.answer }) },
  ]);
  messages.push({ role: "user", content: question });
  const text = PROVIDER === "groq" ? await askGroq(system, messages, TRUTH_SCHEMA) : await askClaude(system, messages, TRUTH_SCHEMA);
  if (text === null) return "그 질문에는 답하기 어려워요. 사건에 대해 다른 걸 물어봐 주세요.";
  try {
    return (JSON.parse(text) as { answer: string }).answer.trim() || "…";
  } catch {
    return "답을 정리하다 말이 끊겼어요. 다시 물어봐 주세요.";
  }
}
