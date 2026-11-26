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
        <h1 className="display">오늘은 어떤<br />사건을 맡을까요?</h1>
        <p className="label">용의자를 심문하세요. 거짓말을 하는 사람은 범인뿐입니다.</p>
        <p className="label">현장을 조사해 단서를 모으고, 증거를 들이미세요.</p>
        <p className="label">범인 지목은 한 번뿐입니다.</p>
      </section>

      {error && <p className="error">{error}</p>}
      {!cases && !error && <p className="muted">사건 파일을 여는 중…</p>}

      <div className="case-list">
        {cases?.map((c, i) => (
          <article key={c.case_id} className="case-row">
            <span className="num">{i + 1}</span>
            <div>
              <h2 className="display">{c.title}</h2>
              <p>{c.summary}</p>
            </div>
            <div className="case-meta">
              <p className="label">
                장르
                <br />
                <span className="eyebrow">{c.genre}</span>
              </p>
              <p className="label">
                난이도
                <br />
                <span className={`eyebrow diff-${c.difficulty}`}>{c.difficulty}</span>
              </p>
              {c.suspect_count != null && (
                <p className="label">
                  용의자
                  <br />
                  <span className="eyebrow">{c.suspect_count}명</span>
                </p>
              )}
              <button className="btn primary" disabled={starting !== null} onClick={() => start(c.case_id)}>
                {starting === c.case_id ? "사건 파일 여는 중…" : "수사 시작"}
              </button>
            </div>
          </article>
        ))}
      </div>
    </main>
  );
}
