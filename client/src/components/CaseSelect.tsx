import { useEffect, useState } from "react";
import { api } from "../api";
import type { CaseSummary } from "../types";
import { Face, Topline } from "./Common";

const today = () => {
  const d = new Date();
  return `${d.getFullYear()}. ${d.getMonth() + 1}. ${d.getDate()}.`;
};

export default function CaseSelect({ onStart, onHome }: { onStart: (playId: number) => void; onHome: () => void }) {
  const [cases, setCases] = useState<CaseSummary[] | null>(null);
  const [error, setError] = useState("");
  const [pick, setPick] = useState<number | null>(null);
  const [starting, setStarting] = useState(false);

  useEffect(() => {
    api
      .cases()
      .then((cs) => {
        setCases(cs);
        setPick(cs[0]?.case_id ?? null);
      })
      .catch((e: Error) => setError(e.message));
  }, []);

  async function start(caseId: number) {
    setStarting(true);
    try {
      const { playId } = await api.startPlay(caseId);
      onStart(playId);
    } catch (e) {
      setError((e as Error).message);
      setStarting(false);
    }
  }

  const list = cases ?? [];
  const placeholders = Math.max(0, 3 - list.length);
  const chosen = list.find((c) => c.case_id === pick) ?? null;
  const chosenIndex = chosen ? list.indexOf(chosen) + 1 : 0;

  return (
    <main className="select">
      <Topline onHome={onHome} right={`${today()}`} />
      <div className="select-main">
        <div className="select-left">
          <p className="lbl">사건을 고르세요</p>
          <h1 className="display hero-title">
            오늘의
            <br />
            사건
          </h1>
          <p className="lead">
            용의자를 직접 심문하고,
            <br />
            단서를 모아 <span className="red">범인 한 명</span>을 지목하세요.
          </p>

          <section className="card case-list">
            <div className="lbl row-between">
              <span>사건 목록</span>
              <span>{list.length}</span>
            </div>
            {error && <p className="error">{error}</p>}
            {!cases && !error && <p className="muted">사건 파일을 여는 중…</p>}
            {list.map((c, i) => (
              <button
                key={c.case_id}
                className={`case-row ${c.case_id === pick ? "on" : ""}`}
                onClick={() => setPick(c.case_id)}
              >
                <span className="no">{String(i + 1).padStart(2, "0")}</span>
                <span className="grow">
                  <b>{c.title}</b>
                  <small>{c.genre}</small>
                </span>
                <span className="num">{c.difficulty}</span>
                {c.clue_count != null && <span className="num">단서 {c.clue_count}</span>}
              </button>
            ))}
            {cases &&
              Array.from({ length: placeholders }, (_, i) => (
                <div key={i} className="case-row off">
                  <span className="no">{String(list.length + i + 1).padStart(2, "0")}</span>
                  <span className="grow">
                    <b>준비 중</b>
                  </span>
                  <span className="num">곧 공개</span>
                </div>
              ))}
          </section>
        </div>

        {chosen && (
          <div className="phone">
            <div className="screen">
              <div className="island" />
              <div className="status">
                <b>{new Date().toTimeString().slice(0, 5)}</b>
                <span className="sig">
                  <i /><i /><i /><i /><em />
                </span>
              </div>
              <div className="phone-body">
                <p className="lbl">사건 {String(chosenIndex).padStart(2, "0")} · 선택됨</p>
                <h2 className="display">{chosen.title}</h2>
                <p className="phone-summary">{chosen.summary}</p>
                <div className="kv">
                  <div><small>난이도</small><b>{chosen.difficulty}</b></div>
                  <div><small>해결률</small><b className={chosen.solve_rate != null ? "red" : ""}>{chosen.solve_rate != null ? `${chosen.solve_rate}%` : "—"}</b></div>
                  <div><small>현장</small><b>{chosen.scene_count ?? "—"}곳</b></div>
                  <div><small>단서</small><b>{chosen.clue_count ?? "—"}개</b></div>
                </div>
                {chosen.suspects && (
                  <div className="ppl">
                    {chosen.suspects.map((s) => (
                      <div key={s.name}>
                        <Face name={s.name} size={44} />
                        {s.name}
                        <small>{s.job?.split(",").at(-1)?.trim()}</small>
                      </div>
                    ))}
                  </div>
                )}
                <button className="pill red go" disabled={starting} onClick={() => void start(chosen.case_id)}>
                  {starting ? "사건 파일 여는 중…" : "수사 시작 →"}
                </button>
                <div className="home-bar" />
              </div>
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
