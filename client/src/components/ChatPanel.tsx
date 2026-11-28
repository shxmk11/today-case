import { useEffect, useRef, useState, type FormEvent } from "react";
import type { Character, Chat, Clue, Deduction } from "../types";
import type { BasicTopic } from "../api";
import { Face, Line, bio, splitEvidence } from "./Common";

/** 내밀 수 있는 것: 단서 하나, 또는 추론 하나 (AI에게는 그 재료 단서 2개를 함께 내민 것으로 전해진다) */
export type Shown = { kind: "clue"; clue: Clue } | { kind: "deduction"; deduction: Deduction };

const shownName = (s: Shown) => (s.kind === "clue" ? s.clue.name : s.deduction.name);
const shownId = (s: Shown) => (s.kind === "clue" ? `c${s.clue.clue_id}` : `d${s.deduction.deduction_id}`);
const shownType = (s: Shown) => (s.kind === "clue" ? s.clue.clue_type : "추론");
const shownDesc = (s: Shown) => (s.kind === "clue" ? s.clue.description : s.deduction.description);

interface Props {
  character: Character;
  chats: Chat[];
  clues: Clue[];
  deductions: Deduction[];
  onAsk: (question: string, evidence?: Shown, topic?: BasicTopic) => Promise<void>;
}

/** 기본 질문: AI 없이 바로 답한다 (횟수 제한 없음) */
const BASIC: { topic: BasicTopic; label: string; question: string }[] = [
  { topic: "알리바이", label: "사망 추정 시간에 뭐 하고 계셨어요?", question: "사망 추정 시간에 뭐 하고 계셨어요?" },
  { topic: "관계", label: "피해자와의 관계", question: "피해자와는 어떤 사이였죠?" },
  { topic: "목격", label: "수상한 걸 보거나 들었나요?", question: "수상한 걸 보거나 들은 건 없나요?" },
  { topic: "마지막", label: "마지막으로 피해자를 본 게 언제인가요?", question: "마지막으로 피해자를 본 게 언제인가요?" },
];
/** 자유 질문은 인물마다 이만큼 */
const FREE_LIMIT = 3;

/* 증거를 제시하면 사진처럼 카드로 보낸다 */
function EvidenceCard({ name, shown }: { name: string; shown?: Shown }) {
  return (
    <div className="ev">
      <div className="thumb">
        <svg viewBox="0 0 44 56" width="30" aria-hidden>
          <path d="M3 3h26l12 12v38H3z" fill="#fff" />
          <path d="M29 3v12h12" fill="#d1d1d6" />
          <rect x="9" y="24" width="24" height="2.5" fill="#c7c7cc" />
          <rect x="9" y="30" width="20" height="2.5" fill="#c7c7cc" />
          <rect x="9" y="36" width="24" height="2.5" fill="#c7c7cc" />
        </svg>
      </div>
      <div className="cap">
        <span className="tag">
          <span>증거 제시</span>
          {shown && <span>{shownType(shown)}</span>}
        </span>
        <b>{name}</b>
        {shown && shownDesc(shown) && <span className="desc">{shownDesc(shown)}</span>}
      </div>
    </div>
  );
}

export default function ChatPanel({ character, chats, clues, deductions, onAsk }: Props) {
  const [input, setInput] = useState("");
  const [error, setError] = useState("");
  const [evidence, setEvidence] = useState<Shown | null>(null);
  const [picking, setPicking] = useState(false);
  const [place, setPlace] = useState<string>("방금 찾음");
  const log = useRef<HTMLDivElement>(null);
  const busy = chats.some((c) => c.pending);

  useEffect(() => {
    log.current?.scrollTo({ top: log.current.scrollHeight, behavior: "smooth" });
  }, [chats.length, chats.at(-1)?.pending, character.character_id]);

  // 자유 질문 남은 횟수 (AI가 쉬어서 피한 답은 저장되지 않으니 세지 않는다)
  const freeLeft = Math.max(0, FREE_LIMIT - chats.filter((c) => c.kind === "자유").length);

  async function send(question: string, withEvidence?: Shown, topic?: BasicTopic) {
    const ev = withEvidence ?? evidence ?? undefined;
    // 증거 제시는 말을 붙이지 않는다 (같은 증거엔 같은 답을 저장해 두고 다시 쓰기 때문)
    const q = ev ? "이건 어떻게 설명하실 건가요?" : question.trim();
    if (!q || busy) return;
    if (!ev && !topic && freeLeft === 0) return;
    if (!topic && !ev) setInput("");
    setEvidence(null);
    setPicking(false);
    setError("");
    try {
      await onAsk(q, ev, topic);
    } catch (e) {
      setError((e as Error).message);
      if (!topic && !ev) setInput(question);
      setEvidence(ev ?? null);
    }
  }

  // 기본 질문은 한 번 물으면 칩에서 뺀다
  const asked = new Set(chats.filter((c) => !c.pending).map((c) => c.question));
  const basicLeft = BASIC.filter((b) => !asked.has(b.question));

  // 이 인물에게 이미 내민 증거
  const shown = new Set(chats.map((c) => splitEvidence(c.question).evidence).filter(Boolean) as string[]);
  const asClue = (c: Clue): Shown => ({ kind: "clue", clue: c });
  const places = [
    "방금 찾음",
    ...new Set(clues.map((c) => (c.character_id ? "증언" : c.scene_name))),
    ...(deductions.length > 0 ? ["추론"] : []),
  ];
  const inPlace: Shown[] =
    place === "방금 찾음"
      ? clues.slice(-3).reverse().map(asClue)
      : place === "추론"
        ? [...deductions].reverse().map((d) => ({ kind: "deduction" as const, deduction: d }))
        : clues.filter((c) => (c.character_id ? "증언" : c.scene_name) === place).map(asClue);
  /** 채팅에 남은 이름으로 단서나 추론을 찾는다 */
  const byName = (name: string): Shown | undefined => {
    const c = clues.find((x) => x.name === name);
    if (c) return asClue(c);
    const d = deductions.find((x) => x.name === name);
    return d && { kind: "deduction", deduction: d };
  };

  function submit(e: FormEvent) {
    e.preventDefault();
    void send(input);
  }

  return (
    <section className="card chat">
      <div className="chat-head">
        <Face name={character.name} src={character.image_url} size={46} zoom />
        <div className="grow">
          <b>{character.name}</b>
          <small>
            {bio(character)} · {character.job} · {character.personality}
          </small>
        </div>
      </div>

      <div className="thread" ref={log}>
        {chats.length === 0 && <p className="muted center pad">아직 아무것도 묻지 않았어요. 첫 질문을 던져보세요.</p>}
        {chats.map((c, i) => {
          const { evidence: ev, question } = splitEvidence(c.question);
          return (
            <div key={i} className="turn">
              {ev && <EvidenceCard name={ev} shown={byName(ev)} />}
              {question && <div className="msg me">{question}</div>}
              {c.pending ? (
                <div className="typing">
                  <i /><i /><i />
                </div>
              ) : (
                <div className="msg them">
                  <Line text={c.answer} />
                </div>
              )}
              {c.notice && <span className="busy-note">{c.notice}</span>}
              {c.newClues?.map((n) => (
                <span key={n} className="stamp-new">＋ 새 단서 · {n}</span>
              ))}
            </div>
          );
        })}
      </div>

      {!picking && !evidence && basicLeft.length > 0 && (
        <div className="suggestions">
          {basicLeft.map((b) => (
            <button key={b.topic} className="pill outline" disabled={busy} onClick={() => void send(b.question, undefined, b.topic)}>
              {b.label}
            </button>
          ))}
        </div>
      )}
      {error && <p className="error pad">{error}</p>}
      {picking && (
        <div className="picker">
          <p className="lbl">제시할 증거나 추론을 고르고 보내기를 누르세요.</p>
          {clues.length === 0 ? (
            <p className="muted">아직 제시할 단서가 없어요. 현장을 먼저 조사해보세요.</p>
          ) : (
            <>
              <div className="picker-tabs">
                {places.map((p) => (
                  <button
                    key={p}
                    type="button"
                    className={`pill outline ${place === p ? "on" : ""}`}
                    onClick={() => setPlace(p)}
                  >
                    {p}
                  </button>
                ))}
              </div>
              <div className="picker-rows">
                {inPlace.map((c) => {
                  const on = !!evidence && shownId(evidence) === shownId(c);
                  return (
                    <button
                      key={shownId(c)}
                      type="button"
                      className={`picker-row ${on ? "on" : ""}`}
                      aria-pressed={on}
                      onClick={() => setEvidence(on ? null : c)}
                    >
                      <span className="grow">
                        {shownName(c)}
                        {shown.has(shownName(c)) && <span className="shown"> · 제시함</span>}
                      </span>
                      <small>{shownType(c)}</small>
                    </button>
                  );
                })}
              </div>
              {evidence && (
                <div className="picker-preview">
                  <p>
                    <b>{shownName(evidence)}</b>
                    {shownDesc(evidence)}
                    {evidence.kind === "deduction" && (
                      <small className="chip-from">
                        함께 내미는 단서 · {evidence.deduction.clue_ids.map((id) => clues.find((x) => x.clue_id === id)?.name ?? "?").join(" + ")}
                      </small>
                    )}
                  </p>
                </div>
              )}
            </>
          )}
        </div>
      )}
      {evidence && (
        <div className="picked">
          <span className="pill red small">첨부한 {evidence.kind === "clue" ? "증거" : "추론"} · {shownName(evidence)}</span>
          <button type="button" className="link" onClick={() => setEvidence(null)}>
            빼기
          </button>
        </div>
      )}
      <form className="composer" onSubmit={submit}>
        <button
          type="button"
          className={`plus ${picking || evidence ? "on" : ""}`}
          title="찾은 단서나 추론을 증거로 제시하기"
          aria-label="증거 제시하기"
          onClick={() => setPicking((p) => !p)}
        >
          ＋
        </button>
        <div className="field">
          <input
            value={evidence ? "" : input}
            maxLength={300}
            disabled={!!evidence || freeLeft === 0}
            placeholder={
              evidence
                ? `${shownName(evidence)} 제시하기`
                : freeLeft === 0
                  ? "자유 질문을 다 썼어요. 기본 질문과 증거 제시는 계속 돼요"
                  : `${character.name}에게 자유 질문 (${freeLeft}/${FREE_LIMIT})`
            }
            onChange={(e) => setInput(e.target.value)}
          />
          <button
            className={`send ${evidence ? "with-ev" : ""}`}
            aria-label={evidence ? `${shownName(evidence)} 제시하기` : "보내기"}
            disabled={busy || (evidence ? false : !input.trim() || freeLeft === 0)}
          >
            ↑
          </button>
        </div>
      </form>
    </section>
  );
}
