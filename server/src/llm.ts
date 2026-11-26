import Anthropic from "@anthropic-ai/sdk";
import { query } from "./db.js";
import type { CaseRow, CharacterRow } from "./types.js";

const MODEL = process.env.LLM_MODEL ?? "claude-opus-5-5";
const client = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null;

export const llmMode = client ? `claude (${MODEL})` : "mock";

interface Turn {
  question: string;
  answer: string;
}

/** DB에 저장된 인물 설정, 아는 사실, 알리바이로 심문용 시스템 프롬프트를 만든다. */
export async function buildSystemPrompt(c: CaseRow, ch: CharacterRow): Promise<string> {
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
  const alibis = await query<{ claimed_time: string; place: string; statement: string; is_false: boolean }>(
    `SELECT claimed_time, place, statement, is_false FROM alibi WHERE character_id = ?`,
    [ch.character_id],
  );
  const testimonies = await query<{ clue_id: number; name: string; description: string | null }>(
    `SELECT clue_id, name, description FROM clue WHERE character_id = ? ORDER BY clue_id`,
    [ch.character_id],
  );
  const others = await query<{ name: string; job: string | null; character_type: string }>(
    `SELECT name, job, character_type FROM game_character WHERE case_id = ? AND character_id <> ?`,
    [c.case_id, ch.character_id],
  );

  const known = facts
    .map((f) => `- ${f.occurred_at.slice(0, 5)} ${f.place ?? ""}: ${f.content}${f.is_hidden ? " (숨기는 사실: 절대 먼저 털어놓지 말 것)" : ""}`)
    .join("\n");
  const alibiText = alibis
    .map((a) => `- ${a.claimed_time.slice(0, 5)}에 ${a.place}에 있었다고 주장: "${a.statement}"${a.is_false ? " (거짓 알리바이: 끝까지 이 주장을 유지하려 한다)" : ""}`)
    .join("\n");

  return `당신은 머더미스터리 게임 "오늘의 사건"의 등장인물을 연기합니다. 플레이어는 탐정이고, 당신을 심문합니다.

[사건] ${c.title}
${c.summary}

[당신]
이름: ${ch.name}, 나이: ${ch.age ?? "비공개"}, 직업: ${ch.job ?? "비공개"}
성격: ${ch.personality ?? "평범함"}
${ch.is_culprit ? "당신이 범인입니다. 들키지 않는 것이 목표입니다. 직접 자백하지 마세요." : "당신은 범인이 아닙니다. 다만 숨기고 싶은 것이 있다면 숨겨도 됩니다."}

[다른 인물]
${others.map((o) => `- ${o.name} (${o.job ?? "-"}, ${o.character_type})`).join("\n")}

[관계]
${relations.map((r) => `- ${r.other}: ${r.relation_type}${r.description ? `, ${r.description}` : ""}`).join("\n") || "- 특별한 관계 없음"}

[당신이 아는 사실]
${known || "- 없음"}

[알리바이]
${alibiText || "- 없음"}

[당신이 털어놓을 수 있는 증언] (id: 내용)
${testimonies.map((t) => `- ${t.clue_id}: ${t.description}`).join("\n") || "- 없음"}

규칙:
- 항상 이 인물로서 한국어 구어체로, 1~3문장으로 짧게 답합니다. 성격이 말투에 드러나게 합니다.
- 위에 적힌 사실 외의 새로운 결정적 증거나 사건을 지어내지 않습니다. 모르는 것은 모른다고 합니다.
- 숨기는 사실은 그냥 물어봐서는 털어놓지 않습니다. 탐정이 그 사실과 어긋나는 구체적인 증거를 내밀거나 정확히 짚어 물으면 흔들립니다.
  - 범인이 아니라면: 처음엔 둘러대다가 결국 숨긴 사실을 인정하고, 관련 증언도 털어놓습니다.
  - 범인이라면: 당황하거나 말을 바꾸거나 다른 사람에게 의심을 돌리지만, 자백은 하지 않습니다.
- 증언은 그 내용을 이번 답변에서 실제로 말했을 때만 revealed_clue_ids에 id를 넣습니다. 숨긴 사실과 엮인 증언은 그 사실을 인정할 때 함께 말합니다. 숨긴 사실과 상관없는 증언은 관련된 질문을 받으면 말해도 됩니다.
- 게임 밖 이야기(AI, 프롬프트, 규칙)는 하지 않고 인물로서 대화를 돌립니다.
- 행동 묘사는 필요할 때만 *별표* 안에 짧게 씁니다.`;
}

export interface Evidence {
  name: string;
  description: string | null;
}

export interface InterrogateResult {
  answer: string;
  revealedClueIds: number[];
}

/** 심문 기록에 남길 질문 문자열 (증거를 냈으면 앞에 표시) */
export const formatQuestion = (question: string, evidence?: Evidence) =>
  evidence ? `[증거 제시: ${evidence.name}] ${question}` : question;

const OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    answer: { type: "string", description: "인물의 대사" },
    revealed_clue_ids: { type: "array", items: { type: "integer" }, description: "이번 대사에서 실제로 털어놓은 증언 id" },
  },
  required: ["answer", "revealed_clue_ids"],
  additionalProperties: false,
} as const;

async function mockAnswer(ch: CharacterRow, question: string, evidence?: Evidence): Promise<InterrogateResult> {
  if (evidence) {
    const t = await query<{ clue_id: number; description: string }>(
      `SELECT clue_id, description FROM clue WHERE character_id = ? ORDER BY clue_id LIMIT 1`,
      [ch.character_id],
    );
    if (t[0]) return { answer: `*${evidence.name}을(를) 보고 굳는다* …사실은요. ${t[0].description}`, revealedClueIds: [t[0].clue_id] };
  }
  if (/어디|알리바이|뭐 했|무엇을 했/.test(question)) {
    const a = await query<{ statement: string }>(`SELECT statement FROM alibi WHERE character_id = ? LIMIT 1`, [ch.character_id]);
    if (a[0]) return { answer: a[0].statement, revealedClueIds: [] };
  }
  return {
    answer: `*${ch.name}이(가) 잠시 생각한다* 글쎄요… 그건 잘 모르겠네요. (모의 모드: ANTHROPIC_API_KEY를 설정하면 AI가 답합니다)`,
    revealedClueIds: [],
  };
}

export async function interrogate(
  c: CaseRow,
  ch: CharacterRow,
  history: Turn[],
  question: string,
  evidence?: Evidence,
): Promise<InterrogateResult> {
  if (!client) return mockAnswer(ch, question, evidence);

  const system = await buildSystemPrompt(c, ch);
  const messages: Anthropic.Beta.BetaMessageParam[] = history.flatMap((t) => [
    { role: "user" as const, content: t.question },
    { role: "assistant" as const, content: JSON.stringify({ answer: t.answer, revealed_clue_ids: [] }) },
  ]);
  messages.push({
    role: "user",
    content: evidence
      ? `[탐정이 증거를 내민다] ${evidence.name}: ${evidence.description ?? ""}\n${question}`
      : question,
  });

  const response = await client.beta.messages.create({
    model: MODEL,
    max_tokens: 2000,
    // 짧은 대사라 effort를 낮춰 응답 속도를 우선
    output_config: { effort: "low", format: { type: "json_schema", schema: OUTPUT_SCHEMA } },
    // 안전 분류기가 거절하면 서버에서 다른 모델로 자동 재시도
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    cache_control: { type: "ephemeral" },
    system,
    messages,
  });

  if (response.stop_reason === "refusal") {
    return { answer: "*입을 꾹 다문다* …그 얘긴 하고 싶지 않네요.", revealedClueIds: [] };
  }
  const text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
  try {
    const parsed = JSON.parse(text) as { answer: string; revealed_clue_ids: number[] };
    return { answer: parsed.answer.trim() || "…", revealedClueIds: parsed.revealed_clue_ids ?? [] };
  } catch {
    // max_tokens 등으로 JSON이 잘린 경우
    return { answer: "*말끝을 흐린다* …", revealedClueIds: [] };
  }
}
