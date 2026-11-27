import { useEffect, useRef, useState, type FormEvent } from "react";
import type { Character, Chat, Clue, Deduction } from "../types";
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
  onAsk: (question: string, evidence?: Shown) => Promise<void>;
}

const SUGGESTIONS = ["사건이 일어났을 때 어디 계셨어요?", "피해자와는 어떤 사이였죠?", "오늘 밤 이상한 걸 보거나 듣지 못했나요?"];

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

  async function send(question: string, withEvidence?: Shown) {
    const ev = withEvidence ?? evidence ?? undefined;
    const q = question.trim() || (ev ? "이건 어떻게 설명하실 건가요?" : "");
    if (!q || busy) return;
    setInput("");
    setEvidence(null);
    setPicking(false);
    setError("");
    try {
      await onAsk(q, ev);
    } catch (e) {
      setError((e as Error).message);
      setInput(question);
      setEvidence(ev ?? null);
    }
  }

  // 첫 질문 칩: 이 인물에게 이미 한 질문만 빠진다
  const suggestions = SUGGESTIONS.filter((q) => !chats.some((c) => splitEvidence(c.question).question === q));

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
              {c.newClues?.map((n) => (
                <span key={n} className="stamp-new">＋ 새 단서 · {n}</span>
              ))}
            </div>
          );
        })}
      </div>

      {suggestions.length > 0 && !picking && (
        <div className="suggestions">
          {suggestions.map((s) => (
            <button key={s} className="pill outline" onClick={() => void send(s)}>
              {s}
            </button>
          ))}
        </div>
      )}
      {error && <p className="error pad">{error}</p>}
      {picking && (
        <div className="picker">
          <p className="lbl">제시할 증거나 추론을 고르면 첨부돼요. 한마디 적어 보내거나 그냥 보내세요.</p>
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
            value={input}
            maxLength={300}
            placeholder={evidence ? `${shownName(evidence)}을(를) 제시하며 한마디 (비워 두고 보내도 돼요)` : `${character.name}에게 질문하기`}
            onChange={(e) => setInput(e.target.value)}
          />
          <button
            className={`send ${evidence ? "with-ev" : ""}`}
            aria-label={evidence ? `${shownName(evidence)} 제시하며 보내기` : "보내기"}
            disabled={busy || (!input.trim() && !evidence)}
          >
            ↑
          </button>
        </div>
      </form>
    </section>
  );
}
