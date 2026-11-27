import { useEffect, useState } from "react";
import { api, shortDate } from "../api";
import type { CaseSummary, Me, MyPlay } from "../types";
import { Face, Topline } from "./Common";
import LoginModal from "./LoginModal";

const today = () => {
  const d = new Date();
  return `${d.getFullYear()}. ${d.getMonth() + 1}. ${d.getDate()}.`;
};

interface Props {
  me: Me;
  onMe: (me: Me) => void;
  onHome: () => void;
  onNew: (caseId: number) => Promise<void>;
  onResume: (playId: number) => Promise<void>;
  onResult: (playId: number, title: string) => Promise<void>;
}

const statusText = (m: MyPlay) => (m.status === "진행중" ? "진행 중" : m.result === "성공" ? "성공" : "실패");

export default function CaseSelect({ me, onMe, onHome, onNew, onResume, onResult }: Props) {
  const [cases, setCases] = useState<CaseSummary[] | null>(null);
  const [error, setError] = useState("");
  const [pick, setPick] = useState<number | null>(null);
  const [busy, setBusy] = useState("");
  const [loginOpen, setLoginOpen] = useState(false);

  // 로그인·로그아웃하면 내 기록이 바뀌므로 다시 받는다
  useEffect(() => {
    api
      .cases()
      .then((cs) => {
        setCases(cs);
        setPick((p) => p ?? cs[0]?.case_id ?? null);
      })
      .catch((e: Error) => setError(e.message));
  }, [me.memberId]);

  async function run(label: string, fn: () => Promise<void>) {
    setBusy(label);
    setError("");
    try {
      await fn();
    } catch (e) {
      setError((e as Error).message);
      setBusy("");
    }
  }

  async function logout() {
    onMe(await api.logout());
  }

  const list = cases ?? [];
  const placeholders = Math.max(0, 3 - list.length);
  const chosen = list.find((c) => c.case_id === pick) ?? null;
  const chosenIndex = chosen ? list.indexOf(chosen) + 1 : 0;

  return (
    <main className="select">
      <Topline
        onHome={onHome}
        right={
          <span className="account">
            <span>{today()}</span>
            {me.guest ? (
              <button className="pill outline small" onClick={() => setLoginOpen(true)}>
                로그인
              </button>
            ) : (
              <>
                <b className="account-name">{me.nickname}</b>
                <button className="link" onClick={() => void logout()}>
                  로그아웃
                </button>
              </>
            )}
          </span>
        }
      />
      <div className="select-main">
        <div className="select-left">
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
            {!cases && error && <p className="error">{error}</p>}
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
                {c.mine ? (
                  <span className={`num ${c.mine.status === "진행중" ? "ongoing" : ""}`}>{statusText(c.mine)}</span>
                ) : (
                  c.clue_count != null && <span className="num">단서 {c.clue_count}</span>
                )}
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
                  <div><small>장르</small><b className="kv-genre">{chosen.genre}</b></div>
                  <div><small>현장</small><b>{chosen.scene_count ?? "—"}곳</b></div>
                  <div><small>단서</small><b>{chosen.clue_count ?? "—"}개</b></div>
                </div>
                {chosen.suspects && (
                  <div className="ppl">
                    {chosen.suspects.map((s) => (
                      <div key={s.name}>
                        <Face name={s.name} src={s.image_url} size={44} zoom />
                        {s.name}
                        <small>{s.gender ? `${s.gender} · ` : ""}{s.job?.split(",").at(-1)?.trim()}</small>
                      </div>
                    ))}
                  </div>
                )}
                {error && <p className="error">{error}</p>}
                <div className="go-group">
                  {chosen.mine && (
                    <div className="mine">
                      <small>내 기록{chosen.mine.plays > 1 ? ` · ${chosen.mine.plays}판째` : ""}</small>
                      <b>
                        {shortDate(chosen.mine.startedAt)} 시작 ·{" "}
                        <span className={chosen.mine.result === "실패" ? "red" : ""}>{statusText(chosen.mine)}</span>
                      </b>
                      {chosen.mine.status === "종료" && (
                        <button className="link dark" disabled={!!busy} onClick={() => void run("result", () => onResult(chosen.mine!.playId, chosen.title))}>
                          결과 다시 보기
                        </button>
                      )}
                    </div>
                  )}
                  {chosen.mine && chosen.mine.result !== "성공" ? (
                    <>
                      <button className="pill red go" disabled={!!busy} onClick={() => void run("resume", () => onResume(chosen.mine!.playId))}>
                        {busy === "resume" ? "사건 파일 여는 중…" : "이어서 하기 →"}
                      </button>
                      <small className="go-note">
                        {chosen.mine.status === "진행중" ? "나간 곳부터 이어서 해요." : "범인을 지목하기 직전으로 돌아가요. 단서·추론·대화는 그대로예요."}
                      </small>
                      <button className="pill outline-ink go2" disabled={!!busy} onClick={() => void run("new", () => onNew(chosen.case_id))}>
                        {busy === "new" ? "새 사건 파일 여는 중…" : "처음부터 다시 하기"}
                      </button>
                    </>
                  ) : (
                    <button className="pill red go" disabled={!!busy} onClick={() => void run("new", () => onNew(chosen.case_id))}>
                      {busy === "new" ? "사건 파일 여는 중…" : chosen.mine ? "처음부터 다시 하기 →" : "수사 시작 →"}
                    </button>
                  )}
                </div>
                <div className="home-bar" />
              </div>
            </div>
          </div>
        )}
      </div>
      {loginOpen && (
        <LoginModal
          onClose={() => setLoginOpen(false)}
          onDone={(m) => {
            setLoginOpen(false);
            onMe(m);
          }}
        />
      )}
    </main>
  );
}
