import { useEffect, useState } from "react";
import { api } from "../api";
import type { AccuseResult, Character, PlayState } from "../types";
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

  async function ask(ch: Character, question: string) {
    const pending = { character_id: ch.character_id, question, answer: "", pending: true };
    setState((s) => s && { ...s, chats: [...s.chats, pending] });
    try {
      const { answer, clues } = await api.interrogate(playId, ch.character_id, question);
      setState((s) => s && { ...s, clues, chats: s.chats.map((c) => (c === pending ? { ...c, answer, pending: false } : c)) });
    } catch (e) {
      setState((s) => s && { ...s, chats: s.chats.filter((c) => c !== pending) });
      throw e;
    }
  }

  async function investigate(sceneId: number) {
    const { clues } = await api.investigate(playId, sceneId);
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
        <div>
          <p className="eyebrow">{state.case.genre} · 난이도 {state.case.difficulty}</p>
          <h1>{state.case.title}</h1>
          <p className="muted">{state.case.summary}</p>
          {victim && (
            <p className="victim">
              피해자 <strong>{victim.name}</strong> ({victim.age}세, {victim.job})
            </p>
          )}
        </div>
        <button className="btn danger" onClick={() => setAccusing(true)}>
          범인 지목하기
        </button>
      </section>

      <div className="game-grid">
        <aside className="suspects">
          <h3>심문할 인물</h3>
          {suspects.map((c) => {
            const count = state.chats.filter((m) => m.character_id === c.character_id).length;
            return (
              <button
                key={c.character_id}
                className={`suspect ${c.character_id === selected ? "active" : ""}`}
                onClick={() => setSelected(c.character_id)}
              >
                <span className="avatar">{c.name.slice(-2)}</span>
                <span className="suspect-info">
                  <strong>{c.name}</strong>
                  <small>
                    {c.age}세 · {c.job}
                  </small>
                </span>
                {count > 0 && <span className="badge">{count}</span>}
              </button>
            );
          })}
        </aside>

        {current ? (
          <ChatPanel
            character={current}
            chats={state.chats.filter((m) => m.character_id === current.character_id)}
            onAsk={(q) => ask(current, q)}
          />
        ) : (
          <section className="chat empty">심문할 인물을 골라주세요.</section>
        )}

        <CasePanel scenes={state.scenes} clues={state.clues} facts={state.facts} onInvestigate={investigate} />
      </div>

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
