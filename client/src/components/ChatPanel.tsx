import { useEffect, useRef, useState, type FormEvent } from "react";
import type { Character, Chat, Clue } from "../types";

interface Props {
  character: Character;
  chats: Chat[];
  clues: Clue[];
  onAsk: (question: string, evidence?: Clue) => Promise<void>;
}

const SUGGESTIONS = ["21시 40분쯤 어디 계셨어요?", "피해자와는 어떤 사이였죠?", "오늘 밤 이상한 걸 보거나 듣지 못했나요?"];

/* "[증거 제시: 이름] 질문" 을 증거 꼬리표와 질문으로 나눈다 */
function Question({ text }: { text: string }) {
  const m = text.match(/^\[증거 제시: (.+?)\] ?(.*)$/s);
  if (!m) return <>{text}</>;
  return (
    <>
      <span className="evidence-tag">증거 · {m[1]}</span>
      {m[2]}
    </>
  );
}

/* *행동 묘사* 를 기울임꼴로 보여준다 */
function Line({ text }: { text: string }) {
  return (
    <>
      {text.split(/(\*[^*]+\*)/g).map((part, i) =>
        part.startsWith("*") && part.endsWith("*") ? <em key={i}>{part.slice(1, -1)}</em> : part,
      )}
    </>
  );
}

export default function ChatPanel({ character, chats, clues, onAsk }: Props) {
  const [input, setInput] = useState("");
  const [error, setError] = useState("");
  const [evidence, setEvidence] = useState<Clue | null>(null);
  const [picking, setPicking] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);
  const busy = chats.some((c) => c.pending);

  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: "smooth" });
  }, [chats.length, chats.at(-1)?.pending]);

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
    <section className="chat">
      <div className="chat-head">
        <h2>{character.name}</h2>
        <p className="label">
          {character.age}세, {character.job}
          <br />
          {character.personality}
        </p>
      </div>

      <div className="chat-log">
        {chats.length === 0 && <p className="muted center">아직 아무것도 묻지 않았어요. 첫 질문을 던져보세요.</p>}
        {chats.map((c, i) => (
          <div key={i} className="turn">
            <div className="bubble me">
              <Question text={c.question} />
            </div>
            <div className={`bubble them ${c.pending ? "typing" : ""}`}>
              {c.pending ? <span className="dots"><i /><i /><i /></span> : <Line text={c.answer} />}
            </div>
          </div>
        ))}
        <div ref={bottom} />
      </div>

      {chats.length === 0 && (
        <div className="suggestions">
          {SUGGESTIONS.map((s) => (
            <button key={s} className="chip" onClick={() => void send(s)}>
              {s}
            </button>
          ))}
        </div>
      )}
      {error && <p className="error">{error}</p>}
      {picking && (
        <div className="evidence-picker">
          {clues.length === 0 ? (
            <p className="muted">아직 내밀 단서가 없어요. 현장을 먼저 조사해보세요.</p>
          ) : (
            clues.map((c) => (
              <button
                key={c.clue_id}
                type="button"
                className={`chip ${evidence?.clue_id === c.clue_id ? "on" : ""}`}
                onClick={() => {
                  setEvidence(c);
                  setPicking(false);
                }}
              >
                {c.name}
              </button>
            ))
          )}
        </div>
      )}
      {evidence && (
        <div className="evidence-selected">
          <span className="evidence-tag">증거 · {evidence.name}</span>
          <button type="button" className="link" onClick={() => setEvidence(null)}>
            빼기
          </button>
        </div>
      )}
      <form className="chat-input" onSubmit={submit}>
        <button
          type="button"
          className={`btn ghost ${picking || evidence ? "on" : ""}`}
          title="찾은 단서를 증거로 내밀기"
          onClick={() => setPicking((p) => !p)}
        >
          증거
        </button>
        <input
          value={input}
          maxLength={300}
          placeholder={evidence ? `${evidence.name}을(를) 내밀며 한마디` : `${character.name}에게 질문하기`}
          onChange={(e) => setInput(e.target.value)}
        />
        <button className="btn primary" disabled={busy || (!input.trim() && !evidence)}>
          묻기
        </button>
      </form>
    </section>
  );
}
