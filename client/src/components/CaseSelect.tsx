import { useEffect, useState } from "react";
import { api } from "../api";
import type { CaseSummary } from "../types";

export default function CaseSelect({ onStart }: { onStart: (playId: number) => void }) {
  const [cases, setCases] = useState<CaseSummary[] | null>(null);
  const [error, setError] = useState("");
  const [starting, setStarting] = useState<number | null>(null);

  useEffect(() => {
    api.cases().then(setCases).catch((e: Error) => setError(e.message));
  }, []);

  async function start(caseId: number) {
    setStarting(caseId);
    try {
      const { playId } = await api.startPlay(caseId);
      onStart(playId);
    } catch (e) {
      setError((e as Error).message);
      setStarting(null);
    }
  }

  return (
    <main className="select">
      <section className="hero">
        <p className="eyebrow">AI 머더미스터리</p>
        <h1>오늘은 어떤 사건을 맡을까요?</h1>
        <p className="muted">용의자를 심문하고, 현장을 조사하고, 범인을 지목하세요. 용의자들은 거짓말을 할 수도 있어요.</p>
      </section>

      {error && <p className="error">{error}</p>}
      {!cases && !error && <p className="muted">사건 파일을 여는 중…</p>}

      <div className="case-grid">
        {cases?.map((c) => (
          <article key={c.case_id} className="case-card">
            <div className="case-stamp">CASE #{String(c.case_id).padStart(3, "0")}</div>
            <h2>{c.title}</h2>
            <div className="tags">
              <span className="tag">{c.genre}</span>
              <span className={`tag diff-${c.difficulty}`}>난이도 {c.difficulty}</span>
              {c.suspect_count != null && <span className="tag">용의자 {c.suspect_count}명</span>}
            </div>
            <p>{c.summary}</p>
            <button className="btn primary" disabled={starting !== null} onClick={() => start(c.case_id)}>
              {starting === c.case_id ? "사건 파일 여는 중…" : "수사 시작"}
            </button>
          </article>
        ))}
      </div>
    </main>
  );
}
