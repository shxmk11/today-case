import { useEffect, useRef, useState } from "react";
import { api } from "../api";
import type { AccuseResult, Character, Clue, PlayState } from "../types";
import ChatPanel from "./ChatPanel";
import CasePanel from "./CasePanel";
import AccuseModal from "./AccuseModal";

interface Props {
  playId: number;
  onFinish: (result: AccuseResult, title: string) => void;
}

export default function Game({ playId, onFinish }: Props) {
  const [state, setState] = useState<PlayState | null>(null);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<number | null>(null);
  const [accusing, setAccusing] = useState(false);
  const [toast, setToast] = useState<string[]>([]);
  const toastTimer = useRef<number>(undefined);

  useEffect(() => {
    api
      .play(playId)
      .then((s) => {
        setState(s);
        setSelected(s.characters.find((c) => c.character_type === "용의자")?.character_id ?? null);
      })
      .catch((e: Error) => setError(e.message));
  }, [playId]);

  if (error) return <p className="error page">{error}</p>;
  if (!state) return <p className="muted page">현장으로 이동 중…</p>;

  const suspects = state.characters.filter((c) => c.character_type !== "피해자");
  const victim = state.characters.find((c) => c.character_type === "피해자");
  const current = suspects.find((c) => c.character_id === selected) ?? null;

  function showNewClues(names: string[]) {
    if (names.length === 0) return;
    setToast(names);
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast([]), 4000);
  }

  async function ask(ch: Character, question: string, evidence?: Clue) {
    const shown = evidence ? `[증거 제시: ${evidence.name}] ${question}` : question;
    const pending = { character_id: ch.character_id, question: shown, answer: "", pending: true };
    setState((s) => s && { ...s, chats: [...s.chats, pending] });
    try {
      const res = await api.interrogate(playId, ch.character_id, question, evidence?.clue_id);
      setState((s) => s && {
        ...s,
        clues: res.clues,
        chats: s.chats.map((c) => (c === pending ? { ...c, question: res.question, answer: res.answer, pending: false } : c)),
      });
      showNewClues(res.clues.filter((c) => res.newClues.includes(c.clue_id)).map((c) => c.name));
    } catch (e) {
      setState((s) => s && { ...s, chats: s.chats.filter((c) => c !== pending) });
      throw e;
    }
  }

  async function investigate(sceneId: number) {
    const before = new Set(state!.clues.map((c) => c.clue_id));
    const { clues } = await api.investigate(playId, sceneId);
    showNewClues(clues.filter((c) => !before.has(c.clue_id)).map((c) => c.name));
    setState((s) => s && {
      ...s,
      clues,
      scenes: s.scenes.map((sc) => (sc.scene_id === sceneId ? { ...sc, investigated: true } : sc)),
    });
  }

  async function accuse(characterId: number) {
    const result = await api.accuse(playId, characterId);
    onFinish(result, state!.case.title);
  }

  return (
    <main className="game">
      <section className="case-header">
        <h1 className="display">{state.case.title}</h1>
        <div className="actions">
          <button className="btn danger" onClick={() => setAccusing(true)}>
            범인 지목하기
          </button>
        </div>
        <p className="summary">{state.case.summary}</p>
        {victim && (
          <p className="victim">
            <span className="label">피해자</span>
            <br />
            <strong>{victim.name}</strong> {victim.age}세, {victim.job}
          </p>
        )}
        <p className="label">
          {state.case.genre}
          <br />
          난이도 {state.case.difficulty}
        </p>
      </section>

      <div className="game-grid">
        <aside className="suspects">
          <div className="col-head">
            <span>심문할 인물</span>
            <span>{suspects.length}명</span>
          </div>
          {suspects.map((c, i) => {
            const count = state.chats.filter((m) => m.character_id === c.character_id).length;
            return (
              <button
                key={c.character_id}
                className={`suspect ${c.character_id === selected ? "active" : ""}`}
                onClick={() => setSelected(c.character_id)}
              >
                <span className="num">{String(i + 1).padStart(2, "0")}</span>
                <span className="suspect-info">
                  <strong>{c.name}</strong>
                  <small>
                    {c.age}세, {c.job}
                  </small>
                </span>
                {count > 0 && <span className="badge">질문 {count}</span>}
              </button>
            );
          })}
        </aside>

        {current ? (
          <ChatPanel
            character={current}
            chats={state.chats.filter((m) => m.character_id === current.character_id)}
            clues={state.clues}
            onAsk={(q, ev) => ask(current, q, ev)}
          />
        ) : (
          <section className="chat empty">심문할 인물을 골라주세요.</section>
        )}

        <CasePanel scenes={state.scenes} clues={state.clues} facts={state.facts} onInvestigate={investigate} />
      </div>

      {toast.length > 0 && (
        <div className="toast" role="status">
          <strong>새 단서</strong> {toast.join(", ")}
        </div>
      )}

      {accusing && (
        <AccuseModal
          suspects={state.characters.filter((c) => c.character_type === "용의자")}
          onClose={() => setAccusing(false)}
          onAccuse={accuse}
        />
      )}
    </main>
  );
}
