import { useState } from "react";
import { hhmm } from "../api";
import type { Clue, Fact, Scene } from "../types";

interface Props {
  scenes: Scene[];
  clues: Clue[];
  facts: Fact[];
  onInvestigate: (sceneId: number) => Promise<void>;
}

type Tab = "scene" | "clue" | "fact";

export default function CasePanel({ scenes, clues, facts, onInvestigate }: Props) {
  const [tab, setTab] = useState<Tab>("scene");
  const [busy, setBusy] = useState<number | null>(null);

  async function investigate(id: number) {
    setBusy(id);
    try {
      await onInvestigate(id);
    } finally {
      setBusy(null);
    }
  }

  return (
    <aside className="panel">
      <nav className="tabs">
        <button className={tab === "scene" ? "on" : ""} onClick={() => setTab("scene")}>현장</button>
        <button className={tab === "clue" ? "on" : ""} onClick={() => setTab("clue")}>
          단서 <span className="count">{clues.length}</span>
        </button>
        <button className={tab === "fact" ? "on" : ""} onClick={() => setTab("fact")}>알려진 사실</button>
      </nav>

      {tab === "scene" &&
        scenes.map((s) => (
          <div key={s.scene_id} className="scene">
            <h4>{s.name}</h4>
            <p className="muted">{s.description}</p>
            <button
              className="btn ghost small"
              disabled={s.investigated || busy !== null}
              onClick={() => void investigate(s.scene_id)}
            >
              {s.investigated ? "조사 완료" : busy === s.scene_id ? "조사 중…" : "조사하기"}
            </button>
          </div>
        ))}

      {tab === "clue" &&
        (clues.length === 0 ? (
          <p className="muted">현장을 조사하거나 인물을 심문하면 단서가 모여요.</p>
        ) : (
          <div className="clue-board">
            {clues.map((c) => (
              <div key={c.clue_id} className={`clue type-${c.clue_type}`}>
                <span className="clue-type">{c.clue_type}</span>
                <h4>{c.name}</h4>
                <p>{c.description}</p>
                <small className="muted">{c.scene_name}</small>
              </div>
            ))}
          </div>
        ))}

      {tab === "fact" && (
        <ol className="timeline">
          {facts.map((f) => (
            <li key={f.fact_id}>
              <time>{hhmm(f.occurred_at)}</time>
              <span>
                {f.place && <strong>{f.place} · </strong>}
                {f.content}
              </span>
            </li>
          ))}
        </ol>
      )}
    </aside>
  );
}
