import { useEffect, useRef, useState, type FormEvent } from "react";
import type { Character, Chat, Clue } from "../types";
import { Face, Line, bio, splitEvidence } from "./Common";

interface Props {
  character: Character;
  chats: Chat[];
  clues: Clue[];
  onAsk: (question: string, evidence?: Clue) => Promise<void>;
}

const SUGGESTIONS = ["사건이 일어났을 때 어디 계셨어요?", "피해자와는 어떤 사이였죠?", "오늘 밤 이상한 걸 보거나 듣지 못했나요?"];

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
  const [place, setPlace] = useState<string>("방금 찾음");
  const [preview, setPreview] = useState<Clue | null>(null);
  const log = useRef<HTMLDivElement>(null);
  const busy = chats.some((c) => c.pending);

  useEffect(() => {
    log.current?.scrollTo({ top: log.current.scrollHeight, behavior: "smooth" });
  }, [chats.length, chats.at(-1)?.pending, character.character_id]);

  async function send(question: string, withEvidence?: Clue) {
    const ev = withEvidence ?? evidence ?? undefined;
    const q = question.trim() || (ev ? "이건 어떻게 설명하실 건가요?" : "");
    if (!q || busy) return;
    setInput("");
    setEvidence(null);
    setPicking(false);
    setPreview(null);
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
  const places = ["방금 찾음", ...new Set(clues.map((c) => (c.character_id ? "증언" : c.scene_name)))];
  const inPlace =
    place === "방금 찾음"
      ? clues.slice(-3).reverse()
      : clues.filter((c) => (c.character_id ? "증언" : c.scene_name) === place);

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
          <p className="lbl">내밀 증거를 고르세요</p>
          {clues.length === 0 ? (
            <p className="muted">아직 내밀 단서가 없어요. 현장을 먼저 조사해보세요.</p>
          ) : (
            <>
              <div className="picker-tabs">
                {places.map((p) => (
                  <button
                    key={p}
                    type="button"
                    className={`pill outline ${place === p ? "on" : ""}`}
                    onClick={() => {
                      setPlace(p);
                      setPreview(null);
                    }}
                  >
                    {p}
                  </button>
                ))}
              </div>
              <div className="picker-rows">
                {inPlace.map((c) => (
                  <button
                    key={c.clue_id}
                    type="button"
                    className={`picker-row ${preview?.clue_id === c.clue_id ? "on" : ""}`}
                    onClick={() => setPreview(c)}
                  >
                    <span>
                      {c.name}
                      {shown.has(c.name) && <span className="shown"> · 제시함</span>}
                    </span>
                    <small>{c.clue_type}</small>
                  </button>
                ))}
              </div>
              {preview && (
                <div className="picker-preview">
                  <p>
                    <b>{preview.name}</b>
                    {preview.description}
                  </p>
                  <button type="button" className="pill red" disabled={busy} onClick={() => void send(input, preview)}>
                    내밀기
                  </button>
                </div>
              )}
            </>
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
          onClick={() => {
            setPicking((p) => !p);
            setPreview(null);
          }}
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
