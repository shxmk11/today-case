import { useEffect, useRef, useState, type FormEvent } from "react";
import type { Character, Chat, Clue } from "../types";
import { Face, Line, splitEvidence } from "./Common";

interface Props {
  character: Character;
  chats: Chat[];
  clues: Clue[];
  onAsk: (question: string, evidence?: Clue) => Promise<void>;
}

const SUGGESTIONS = ["21시 40분쯤 어디 계셨어요?", "피해자와는 어떤 사이였죠?", "오늘 밤 이상한 걸 보거나 듣지 못했나요?"];

/* 증거를 내밀면 사진처럼 카드로 보낸다 */
function EvidenceCard({ name, clue }: { name: string; clue?: Clue }) {
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
        <span className="tag">증거 제시{clue ? ` · ${clue.clue_type}` : ""}</span>
        <b>{name}</b>
        {clue?.description && <span className="desc">{clue.description}</span>}
      </div>
    </div>
  );
}

export default function ChatPanel({ character, chats, clues, onAsk }: Props) {
  const [input, setInput] = useState("");
  const [error, setError] = useState("");
  const [evidence, setEvidence] = useState<Clue | null>(null);
  const [picking, setPicking] = useState(false);
  const log = useRef<HTMLDivElement>(null);
  const busy = chats.some((c) => c.pending);

  useEffect(() => {
    log.current?.scrollTo({ top: log.current.scrollHeight, behavior: "smooth" });
  }, [chats.length, chats.at(-1)?.pending, character.character_id]);

  async function send(question: string) {
    const ev = evidence ?? undefined;
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

  function submit(e: FormEvent) {
    e.preventDefault();
    void send(input);
  }

  return (
    <section className="card chat">
      <div className="chat-head">
        <Face name={character.name} size={46} />
        <div className="grow">
          <b>{character.name}</b>
          <small>
            {character.age}세 · {character.job} · {character.personality}
          </small>
        </div>
      </div>

      <div className="thread" ref={log}>
        {chats.length === 0 && <p className="muted center pad">아직 아무것도 묻지 않았어요. 첫 질문을 던져보세요.</p>}
        {chats.map((c, i) => {
          const { evidence: ev, question } = splitEvidence(c.question);
          return (
            <div key={i} className="turn">
              {ev && <EvidenceCard name={ev} clue={clues.find((x) => x.name === ev)} />}
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

      {chats.length === 0 && (
        <div className="suggestions">
          {SUGGESTIONS.map((s) => (
            <button key={s} className="pill outline" onClick={() => void send(s)}>
              {s}
            </button>
          ))}
        </div>
      )}
      {error && <p className="error pad">{error}</p>}
      {picking && (
        <div className="picker">
          <p className="lbl">내밀 증거를 고르세요</p>
          {clues.length === 0 ? (
            <p className="muted">아직 내밀 단서가 없어요. 현장을 먼저 조사해보세요.</p>
          ) : (
            <div className="picker-list">
              {clues.map((c) => (
                <button
                  key={c.clue_id}
                  type="button"
                  className={`pill outline ${evidence?.clue_id === c.clue_id ? "on" : ""}`}
                  onClick={() => {
                    setEvidence(c);
                    setPicking(false);
                  }}
                >
                  {c.name}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
      {evidence && (
        <div className="picked">
          <span className="pill red small">증거 · {evidence.name}</span>
          <button type="button" className="link" onClick={() => setEvidence(null)}>
            빼기
          </button>
        </div>
      )}
      <form className="composer" onSubmit={submit}>
        <button
          type="button"
          className={`plus ${picking || evidence ? "on" : ""}`}
          title="찾은 단서를 증거로 내밀기"
          aria-label="증거 내밀기"
          onClick={() => setPicking((p) => !p)}
        >
          ＋
        </button>
        <div className="field">
          <input
            value={input}
            maxLength={300}
            placeholder={evidence ? `${evidence.name}을(를) 내밀며 한마디` : `${character.name}에게 질문하기`}
            onChange={(e) => setInput(e.target.value)}
          />
          <button className="send" aria-label="보내기" disabled={busy || (!input.trim() && !evidence)}>
            ↑
          </button>
        </div>
      </form>
    </section>
  );
}
