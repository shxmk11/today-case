import { useState } from "react";
import { hhmm } from "../api";
import type { AccuseResult } from "../types";
import { Line, Topline, splitEvidence } from "./Common";

interface Props {
  result: AccuseResult;
  title: string;
  onHome: () => void;
  onRetry: () => Promise<void>;
}

export default function Result({ result, title, onHome, onRetry }: Props) {
  const win = result.result === "성공";
  const [retrying, setRetrying] = useState(false);
  const t = result.keyTestimony;
  const asked = t?.chat ? splitEvidence(t.chat.question) : null;

  return (
    <main className="result">
      <Topline onHome={onHome} right={`${title} · 사건 종결`} />
      <div className="result-main">
        <section className="result-left">
          <div className="vhead">
            <span className="lbl">{title} · 판정</span>
            <span className={`res ${win ? "" : "red"}`}>
              <i />
              {win ? "지목 성공" : "지목 실패"}
            </span>
          </div>
          <h1 className={`display verdict ${win ? "" : "red"}`}>
            {win ? "사건" : "미궁"}
            <br />
            {win ? "해결." : "속으로."}
          </h1>
          <p className="verdict-line">
            당신은 <b>{result.accused}</b>을(를) 지목했습니다.{" "}
            {win ? (
              "범인도, 근거도 정확합니다."
            ) : result.culpritCorrect ? (
              <>범인은 맞혔지만 근거가 부족해 혐의를 입증하지 못했습니다.</>
            ) : (
              <>
                진범은 <b className="red">{result.culprit.name}</b>이었습니다.
              </>
            )}
          </p>
          <div className="verdict-ev">
            {result.evidence.map((e) => (
              <span key={e.name} className={e.isKey ? "hit" : "miss"}>
                {e.isKey ? "● " : "○ "}
                {e.name}
              </span>
            ))}
          </div>
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
            <div className="card culprit"><span className="lbl">진범</span><b className="display red">{result.culprit.name}</b></div>
          </div>
          <div className="result-actions">
            <button className="pill white" onClick={onHome}>다른 사건 보기</button>
            <button
              className="pill outline"
              disabled={retrying}
              onClick={() => {
                setRetrying(true);
                onRetry().catch(() => setRetrying(false));
              }}
            >
              {win ? "다시 하기" : "다시 도전하기"}
            </button>
          </div>
        </section>

        <section className="result-right">
          <div className="sec truth">
            <div className="lbl row-between">
              <span>사건의 진상</span>
              <span>범인 · {result.culprit.name}</span>
            </div>
            <p>{result.truth}</p>
          </div>
          <div className="split">
            <div className="sec">
              <div className="lbl row-between">
                <span>그날 밤의 타임라인</span>
                <span>빨강 = 숨겨진 사실</span>
              </div>
              <ol className="dots-timeline">
                {result.timeline.map((f) => (
                  <li key={f.fact_id} className={f.is_initial ? "" : "hot"}>
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
              {result.keyEvidence.length > 0 && (
                <div className="sec">
                  <div className="lbl row-between">
                    <span>결정적 증거</span>
                    <span>
                      찾음 {result.keyEvidence.filter((k) => k.found).length} / {result.keyEvidence.length}
                    </span>
                  </div>
                  <div className="evs">
                    {result.keyEvidence.map((k) => (
                      <div key={k.name} className={`evc ${k.found ? "" : "missed"}`}>
                        <i />
                        <b>{k.name}</b>
                        <small>
                          {k.scene_name} · {k.clue_type}
                          {k.found ? "" : " · 놓침"}
                        </small>
                        <p>{k.description}</p>
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
                    <p className="missed-text">{t.description}</p>
                  )}
                </div>
              )}
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
