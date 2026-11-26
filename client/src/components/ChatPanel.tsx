import { useEffect, useRef, useState, type FormEvent } from "react";
import type { Character, Chat } from "../types";

interface Props {
  character: Character;
  chats: Chat[];
  onAsk: (question: string) => Promise<void>;
}

const SUGGESTIONS = ["21시 40분에 어디 있었나요?", "피해자와는 어떤 사이였죠?", "오늘 밤 이상한 걸 보거나 듣지 못했나요?"];

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

export default function ChatPanel({ character, chats, onAsk }: Props) {
  const [input, setInput] = useState("");
  const [error, setError] = useState("");
  const bottom = useRef<HTMLDivElement>(null);
  const busy = chats.some((c) => c.pending);

  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: "smooth" });
  }, [chats.length, chats.at(-1)?.pending]);

  async function send(question: string) {
    const q = question.trim();
    if (!q || busy) return;
    setInput("");
    setError("");
    try {
      await onAsk(q);
    } catch (e) {
      setError((e as Error).message);
      setInput(q);
    }
  }

  function submit(e: FormEvent) {
    e.preventDefault();
    void send(input);
  }

  return (
    <section className="chat">
      <div className="chat-head">
        <span className="avatar big">{character.name.slice(-2)}</span>
        <div>
          <h2>{character.name}</h2>
          <p className="muted">
            {character.age}세 · {character.job} · {character.personality}
          </p>
        </div>
      </div>

      <div className="chat-log">
        {chats.length === 0 && <p className="muted center">아직 아무것도 묻지 않았어요. 첫 질문을 던져보세요.</p>}
        {chats.map((c, i) => (
          <div key={i} className="turn">
            <div className="bubble me">{c.question}</div>
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
      <form className="chat-input" onSubmit={submit}>
        <input
          value={input}
          maxLength={300}
          placeholder={`${character.name}에게 질문하기`}
          onChange={(e) => setInput(e.target.value)}
        />
        <button className="btn primary" disabled={busy || !input.trim()}>
          묻기
        </button>
      </form>
    </section>
  );
}
