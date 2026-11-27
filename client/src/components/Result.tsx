import { useEffect, useRef, useState, type FormEvent } from "react";
import { api, hhmm } from "../api";
import type { AccuseResult, AnswerDeduction } from "../types";
import { Line, Topline, splitEvidence } from "./Common";

interface Props {
  result: AccuseResult;
  title: string;
  onHome: () => void;
  /** 같은 판을 지목 직전으로 되돌려 이어 하기 */
  onResume: () => Promise<void>;
  /** 처음부터 새 판 */
  onNew: () => Promise<void>;
}

type Reveal = NonNullable<AccuseResult["reveal"]>;

export default function Result({ result, title, onHome, onResume, onNew }: Props) {
  const win = result.result === "성공";
  // 실패했지만 범인은 맞혔으면 「사건의 진상 알아보기」를 눌러야 진상이 열린다. 범인을 틀렸으면 진상은 없다
  const [opened, setOpened] = useState(win);
  const [busy, setBusy] = useState("");
  const reveal = result.reveal;
  const label = win ? "지목 성공" : result.culpritCorrect ? "실패" : "지목 실패";

  function run(name: string, fn: () => Promise<void>) {
    setBusy(name);
    fn().catch(() => setBusy(""));
  }

  return (
    <main className="result">
      <Topline onHome={onHome} right={`${title} · 사건 종결`} />
      <div className="result-main">
        <section className="result-left">
          <div className="vhead">
            <span className="lbl">{title} · 판정</span>
            <span className={`res ${win ? "" : "red"}`}>
              <i />
              {label}
            </span>
          </div>
          <h1 className={`display verdict ${win ? "" : "red"}`}>
            {win ? "사건" : "미궁"}
            <br />
            {win ? "해결." : "속으로."}
          </h1>
          <p className="verdict-line">
            당신은 <b>{result.accused}</b>을(를) 지목했습니다.{" "}
            {win
              ? "범인도, 근거도 정확합니다."
              : result.culpritCorrect
                ? "범인은 맞혔지만 근거가 부족해 혐의를 입증하지 못했습니다."
                : "하지만 범인은 따로 있습니다."}
          </p>
          {win && result.evidence && <PickedEvidence evidence={result.evidence} />}
          <div className="stats">
            <div className="card"><span className="lbl">걸린 시간</span><b className="display">{result.stats.minutes}분</b></div>
            <div className="card"><span className="lbl">질문 수</span><b className="display">{result.stats.questions}</b></div>
            <div className="card">
              <span className="lbl">찾은 단서</span>
              <b className="display">
                {result.stats.clues}
                <span className="of">/{result.stats.clueTotal}</span>
              </b>
            </div>
            <div className="card">
              <span className="lbl">찾은 추론</span>
              <b className="display">
                {result.stats.deductions}
                <span className="of">/{result.stats.deductionTotal}</span>
              </b>
            </div>
            {opened && result.culprit && (
              <div className="card culprit"><span className="lbl">진범</span><b className="display red">{result.culprit.name}</b></div>
            )}
          </div>
          <div className="result-actions">
            {!win && (
              <button className="pill red" disabled={!!busy} onClick={() => run("resume", onResume)}>
                {busy === "resume" ? "돌아가는 중…" : "다시 도전하기"}
              </button>
            )}
            <button className="pill outline" disabled={!!busy} onClick={() => run("new", onNew)}>
              {busy === "new" ? "새 사건 파일 여는 중…" : "처음부터 다시 하기"}
            </button>
            <button className="pill white" onClick={onHome}>다른 사건 보기</button>
          </div>
          {!win && <p className="result-note">다시 도전하면 범인을 지목하기 직전으로 돌아가요. 찾은 단서·추론·대화와 남은 조사 횟수는 그대로예요.</p>}
        </section>

        <section className="result-right">
          {opened && reveal ? (
            <TruthView result={result} reveal={reveal} />
          ) : result.culpritCorrect ? (
            <div className="locked-truth">
              <span className="lbl">사건의 진상</span>
              <p>
                범인은 맞혔어요. 근거를 다시 찾아 도전하거나, 지금 사건의 진상을 확인할 수 있어요.
                <br />
                진상에서는 근거가 되는 추론의 정답, 그날의 타임라인, 결정적 증거와 놓친 단서를 찾는 법을 볼 수 있어요.
              </p>
              <button className="pill outline" onClick={() => setOpened(true)}>
                사건의 진상 알아보기
              </button>
            </div>
          ) : (
            <div className="locked-truth">
              <span className="lbl">사건의 진상</span>
              <p>
                진상은 아직 잠겨 있어요.
                <br />
                다시 도전해서 최소한 범인을 맞히면 진상을 볼 수 있어요.
              </p>
            </div>
          )}
        </section>
      </div>
    </main>
  );
}

function PickedEvidence({ evidence }: { evidence: NonNullable<AccuseResult["evidence"]> }) {
  return (
    <ul className="verdict-ev">
      {evidence.map((e) => (
        <li key={e.slot} className={e.ok ? "hit" : "miss"}>
          <small>내가 낸 근거 · {e.slot === "알리바이" ? "알리바이를 깨는 추론" : "범인과 범행을 잇는 추론"}</small>
          <b>
            {e.ok ? "● " : "○ "}
            {e.name}
          </b>
          {e.note && <p>{e.ok ? e.note : `근거 부족 · ${e.note}`}</p>}
        </li>
      ))}
    </ul>
  );
}

/** 못 찾은 추론: 어떤 단서 둘을 이어야 하는지, 그 단서를 못 찾았으면 어디서 찾는지 */
function HowTo({ d }: { d: AnswerDeduction }) {
  if (!d.howTo) return null;
  return (
    <div className="howto">
      <span>이어 볼 단서 · {d.howTo.map((p) => `「${p.name}」`).join(" + ")}</span>
      {d.howTo
        .filter((p) => !p.found)
        .map((p) => (
          <span key={p.name} className="howto-sub">
            「{p.name}」 찾는 곳 · {p.howTo}
          </span>
        ))}
    </div>
  );
}

function TruthView({ result, reveal }: { result: AccuseResult; reveal: Reveal }) {
  const t = reveal.keyTestimony;
  const asked = t?.chat ? splitEvidence(t.chat.question) : null;
  const roles: ("알리바이" | "연결")[] = ["알리바이", "연결"];
  return (
    <>
      <div className="sec truth">
        <div className="lbl row-between">
          <span>사건의 진상</span>
          <span>범인 · {result.culprit?.name}</span>
        </div>
        <p>{reveal.truth}</p>
      </div>

      <div className="sec">
        <div className="lbl row-between">
          <span>범인 지목 근거 · 정답</span>
          <span>둘 중 하나씩 내면 돼요</span>
        </div>
        {!(result.result === "성공") && result.evidence && <PickedEvidence evidence={result.evidence} />}
        <div className="answers">
          {roles.map((role) => (
            <div key={role} className="answer-col">
              <small className="lbl">{role === "알리바이" ? "① 알리바이를 깨는 추론" : "② 범인과 범행을 잇는 추론"}</small>
              {reveal.answers
                .filter((d) => d.role === role)
                .map((d) => (
                  <div key={d.name} className={`answer ${d.found ? "" : "missed"}`}>
                    <b>
                      {d.found ? "● " : "○ "}
                      {d.name}
                      {!d.found && <small> · 못 찾음</small>}
                    </b>
                    <p>{d.description}</p>
                    {d.note && <p className="answer-note">{d.note}</p>}
                    <HowTo d={d} />
                  </div>
                ))}
            </div>
          ))}
        </div>
      </div>

      <div className="split">
        <div className="sec">
          <div className="lbl row-between">
            <span>그날의 타임라인</span>
            <span>빨강 = 숨겨진 사실</span>
          </div>
          <ol className="dots-timeline">
            {reveal.timeline.map((f) => (
              <li key={f.fact_id} className={f.is_initial ? "" : "fresh"}>
                <time>{hhmm(f.occurred_at)}</time>
                <i />
                <span>
                  {f.place && <small>{f.place}</small>}
                  {f.content}
                </span>
              </li>
            ))}
          </ol>
        </div>
        <div className="side">
          {reveal.keyEvidence.length > 0 && (
            <div className="sec">
              <div className="lbl row-between">
                <span>결정적 증거</span>
                <span>
                  찾음 {reveal.keyEvidence.filter((k) => k.found).length} / {reveal.keyEvidence.length}
                </span>
              </div>
              <div className="evs">
                {reveal.keyEvidence.map((k) => (
                  <div key={k.name} className={`evc ${k.found ? "" : "missed"}`}>
                    <i />
                    <b>{k.name}</b>
                    <small>
                      {k.scene_name} · {k.clue_type}
                      {k.found ? "" : " · 놓침"}
                    </small>
                    <p>{k.description}</p>
                    {k.howTo && <p className="howto-line">찾는 곳 · {k.howTo}</p>}
                  </div>
                ))}
              </div>
            </div>
          )}
          {t && (
            <div className="sec">
              <div className="lbl row-between">
                <span>결정적 증언 · {t.character}</span>
                {!t.found && <span>놓침</span>}
              </div>
              {t.chat && asked ? (
                <div className="thread mini">
                  {asked.question && <div className="msg me">{asked.question}</div>}
                  <div className="msg them">
                    <Line text={t.chat.answer} />
                  </div>
                </div>
              ) : (
                <>
                  <p className="missed-text">{t.description}</p>
                  {t.howTo && <p className="howto-line">얻는 법 · {t.howTo}</p>}
                </>
              )}
            </div>
          )}
        </div>
      </div>

      {reveal.missed.length > 0 && (
        <div className="sec">
          <div className="lbl row-between">
            <span>놓친 추론</span>
            <span>{reveal.missed.length}개</span>
          </div>
          <div className="missed-list">
            {reveal.missed.map((d) => (
              <div key={d.name} className="answer missed">
                <b>○ {d.name}</b>
                <p>{d.description}</p>
                <HowTo d={d} />
              </div>
            ))}
          </div>
        </div>
      )}

      <AskBox playId={result.playId} asks={reveal.asks} left={reveal.askLeft} />
    </>
  );
}

/* 진상에 대해 AI에게 묻는 칸 (한 판에 10번) */
function AskBox({ playId, asks: initial, left: initialLeft }: { playId: number; asks: { question: string; answer: string }[]; left: number }) {
  const [asks, setAsks] = useState(initial);
  const [left, setLeft] = useState(initialLeft);
  const [input, setInput] = useState("");
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState("");
  const log = useRef<HTMLDivElement>(null);

  useEffect(() => {
    log.current?.scrollTo({ top: log.current.scrollHeight, behavior: "smooth" });
  }, [asks.length, pending]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const q = input.trim();
    if (!q || pending || left <= 0) return;
    setPending(q);
    setInput("");
    setError("");
    try {
      const r = await api.ask(playId, q);
      setAsks((a) => [...a, { question: r.question, answer: r.answer }]);
      setLeft(r.left);
    } catch (err) {
      setError((err as Error).message);
      setInput(q);
    } finally {
      setPending(null);
    }
  }

  return (
    <div className="sec ask">
      <div className="lbl row-between">
        <span>AI에게 묻기 · 진상에서 궁금한 점</span>
        <span>
          남은 질문 {left} / 10
        </span>
      </div>
      <div className="thread ask-log" ref={log}>
        {asks.length === 0 && !pending && <p className="muted">예: "범인은 언제부터 계획했나요?", "그 증거는 왜 중요했나요?"</p>}
        {asks.map((a, i) => (
          <div key={i} className="turn">
            <div className="msg me">{a.question}</div>
            <div className="msg them">{a.answer}</div>
          </div>
        ))}
        {pending && (
          <div className="turn">
            <div className="msg me">{pending}</div>
            <div className="typing">
              <i /><i /><i />
            </div>
          </div>
        )}
      </div>
      {error && <p className="error">{error}</p>}
      <form className="composer ask-composer" onSubmit={submit}>
        <div className="field">
          <input
            value={input}
            maxLength={300}
            disabled={left <= 0}
            placeholder={left > 0 ? "진상에 대해 궁금한 걸 물어보세요" : "이 판의 질문을 다 썼어요"}
            onChange={(e) => setInput(e.target.value)}
          />
          <button className="send" aria-label="묻기" disabled={!input.trim() || !!pending || left <= 0}>
            ↑
          </button>
        </div>
      </form>
    </div>
  );
}
