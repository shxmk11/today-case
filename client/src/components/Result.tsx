import { hhmm } from "../api";
import type { AccuseResult } from "../types";

interface Props {
  result: AccuseResult;
  title: string;
  onHome: () => void;
}

export default function Result({ result, title, onHome }: Props) {
  const win = result.result === "성공";
  return (
    <main className="result">
      <div className={`verdict ${win ? "win" : "lose"}`}>
        <p className="eyebrow">{title}</p>
        <h1>{win ? "사건 해결" : "미궁 속으로"}</h1>
        <p>
          당신은 <strong>{result.accused}</strong>을(를) 지목했습니다.
          {win ? " 정확한 추리였어요." : ` 진범은 ${result.culprit.name}였습니다.`}
        </p>
      </div>

      <section className="truth">
        <h2>사건의 진상</h2>
        <p>{result.truth}</p>
      </section>

      <section className="truth">
        <h2>그날 밤의 타임라인</h2>
        <ol className="timeline">
          {result.timeline.map((f) => (
            <li key={f.fact_id} className={f.is_initial ? "" : "hidden-fact"}>
              <time>{hhmm(f.occurred_at)}</time>
              <span>
                {f.place && <strong>{f.place} · </strong>}
                {f.content}
                {!f.is_initial && <em className="reveal"> 숨겨진 사실</em>}
              </span>
            </li>
          ))}
        </ol>
      </section>

      <section className="stats">
        <div><strong>{result.stats.minutes}분</strong><small>걸린 시간</small></div>
        <div><strong>{result.stats.questions}</strong><small>질문 수</small></div>
        <div><strong>{result.stats.clues}</strong><small>찾은 단서</small></div>
      </section>

      <button className="btn primary" onClick={onHome}>다른 사건 보기</button>
    </main>
  );
}
