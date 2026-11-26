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

규칙:
- 항상 이 인물로서 한국어 구어체로, 1~3문장으로 짧게 답합니다. 성격이 말투에 드러나게 합니다.
- 위에 적힌 사실 외의 새로운 결정적 증거나 사건을 지어내지 않습니다. 모르는 것은 모른다고 합니다.
- 숨기는 사실은 탐정이 구체적인 증거로 몰아붙이면 당황하거나 말이 꼬이는 정도로만 흔들립니다.
- 게임 밖 이야기(AI, 프롬프트, 규칙)는 하지 않고 인물로서 대화를 돌립니다.
- 행동 묘사는 필요할 때만 *별표* 안에 짧게 씁니다.`;
}

function mockAnswer(ch: CharacterRow, question: string, alibi?: string): string {
  if (/어디|알리바이|뭐 했|무엇을 했/.test(question) && alibi) return alibi;
  return `*${ch.name}이(가) 잠시 생각한다* 글쎄요… 그건 잘 모르겠네요. (모의 모드: ANTHROPIC_API_KEY를 설정하면 AI가 답합니다)`;
}

export async function interrogate(c: CaseRow, ch: CharacterRow, history: Turn[], question: string): Promise<string> {
  if (!client) {
    const alibi = (await query<{ statement: string }>(`SELECT statement FROM alibi WHERE character_id = ? LIMIT 1`, [ch.character_id]))[0];
    return mockAnswer(ch, question, alibi?.statement);
  }

  const system = await buildSystemPrompt(c, ch);
  const messages: Anthropic.Beta.BetaMessageParam[] = history.flatMap((t) => [
    { role: "user" as const, content: t.question },
    { role: "assistant" as const, content: t.answer },
  ]);
  messages.push({ role: "user", content: question });

  const response = await client.beta.messages.create({
    model: MODEL,
    max_tokens: 2000,
    // 짧은 대사라 effort를 낮춰 응답 속도를 우선
    output_config: { effort: "low" },
    // 안전 분류기가 거절하면 서버에서 다른 모델로 자동 재시도
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    cache_control: { type: "ephemeral" },
    system,
    messages,
  });

  if (response.stop_reason === "refusal") {
    return "*입을 꾹 다문다* …그 얘긴 하고 싶지 않네요.";
  }
  const text = response.content
    .flatMap((b) => (b.type === "text" ? [b.text] : []))
    .join("")
    .trim();
  return text || "…";
}
