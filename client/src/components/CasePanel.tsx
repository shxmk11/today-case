import { useState } from "react";
import { hhmm } from "../api";
import type { Clue, Fact, Scene } from "../types";

export type Tab = "clue" | "scene" | "fact";

interface Props {
  tab: Tab;
  onTab: (t: Tab) => void;
  scenes: Scene[];
  clues: Clue[];
  facts: Fact[];
  onInvestigate: (sceneId: number) => Promise<void>;
}

export default function CasePanel({ tab, onTab, scenes, clues, facts, onInvestigate }: Props) {
  const [busy, setBusy] = useState<number | null>(null);
  const [open, setOpen] = useState<number | null>(null);
  const [detail, setDetail] = useState<number | null>(null);

  async function investigate(id: number) {
    setBusy(id);
    try {
      await onInvestigate(id);
      setOpen(id);
      onTab("clue");
    } finally {
      setBusy(null);
    }
  }

  // 단서가 있는 장소 중 펼칠 곳: 고른 곳, 없으면 가장 최근에 단서가 나온 곳
  const openScene = open ?? clues.at(-1)?.scene_id ?? null;

  return (
    <aside className="card panel">
      <nav className="tabs">
        <button className={`pill ${tab === "clue" ? "white" : "outline"}`} onClick={() => onTab("clue")}>
          단서 {clues.length}
        </button>
        <button className={`pill ${tab === "scene" ? "white" : "outline"}`} onClick={() => onTab("scene")}>
          현장
        </button>
        <button className={`pill ${tab === "fact" ? "white" : "outline"}`} onClick={() => onTab("fact")}>
          알려진 사실
        </button>
      </nav>

      <div className="panel-body">
        {tab === "clue" &&
          (clues.length === 0 ? (
            <p className="muted pad">현장을 조사하거나 인물을 심문하면 단서가 모여요.</p>
          ) : (
            scenes.map((sc) => {
              const items = clues.filter((c) => c.scene_id === sc.scene_id);
              if (sc.scene_id === openScene && items.length > 0) {
                const d = items.find((c) => c.clue_id === detail);
                return (
                  <div key={sc.scene_id} className="scene-open">
                    <div className="row-between h">
                      <span>{sc.name}</span>
                      <span className="num">{items.length}</span>
                    </div>
                    <div className="chips">
                      {items.map((c) => (
                        <button
                          key={c.clue_id}
                          className={`chip ${c.clue_id === detail ? "on" : ""}`}
                          onClick={() => setDetail(c.clue_id === detail ? null : c.clue_id)}
                        >
                          <i className={`dot t-${c.clue_type}`} />
                          <span>{c.name}</span>
                          <small>{c.clue_type}</small>
                        </button>
                      ))}
                    </div>
                    {d && <p className="chip-detail">{d.description}</p>}
                  </div>
                );
              }
              return (
                <button
                  key={sc.scene_id}
                  className="scene-row"
                  disabled={items.length === 0}
                  onClick={() => {
                    setOpen(sc.scene_id);
                    setDetail(null);
                  }}
                >
                  <span>{sc.name}</span>
                  <span className="num">{items.length}</span>
                </button>
              );
            })
          ))}

        {tab === "scene" &&
          scenes.map((s) => (
            <div key={s.scene_id} className="scene-card">
              <div className="row-between">
                <b>{s.name}</b>
                <button
                  className={`pill small ${s.investigated ? "outline" : "white"}`}
                  disabled={s.investigated || busy !== null}
                  onClick={() => void investigate(s.scene_id)}
                >
                  {s.investigated ? "조사 완료" : busy === s.scene_id ? "조사 중…" : "조사하기"}
                </button>
              </div>
              <p>{s.description}</p>
            </div>
          ))}

        {tab === "fact" && (
          <ol className="dots-timeline">
            {facts.map((f) => (
              <li key={f.fact_id}>
                <time>{hhmm(f.occurred_at)}</time>
                <i />
                <span>
                  {f.place && <small>{f.place}</small>}
                  {f.content}
                </span>
              </li>
            ))}
          </ol>
        )}
      </div>
    </aside>
  );
}
