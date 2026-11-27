import type { Autopsy } from "../types";
import { hhmm } from "../api";

/* 뒷모습 실루엣. 상처 위치(뒷머리)를 빨간 점으로 표시 */
export function BodyFigure({ width }: { width: number }) {
  return (
    <svg viewBox="0 0 120 200" width={width} role="img" aria-label="시신 그림, 뒷머리에 상처 표시">
      <g fill="#3a3a3c">
        <circle cx="60" cy="26" r="17" />
        <rect x="40" y="46" width="40" height="70" rx="14" />
        <rect x="22" y="50" width="14" height="62" rx="7" transform="rotate(12 29 50)" />
        <rect x="84" y="50" width="14" height="62" rx="7" transform="rotate(-12 91 50)" />
        <rect x="42" y="112" width="15" height="74" rx="7.5" />
        <rect x="63" y="112" width="15" height="74" rx="7.5" />
      </g>
      <circle cx="68" cy="17" r="6" fill="#c1121f" />
      <circle cx="68" cy="17" r="11" fill="none" stroke="#c1121f" strokeWidth="1.5" />
      <text x="60" y="198" fontSize="10" textAnchor="middle" fill="#636366" fontWeight="700">
        뒷모습 · 엎드림
      </text>
    </svg>
  );
}

export function AutopsyRows({ a }: { a: Autopsy }) {
  const rows: [string, string | null, string?][] = [
    ["발견", `${hhmm(a.found_time)} · ${a.found_place}`, a.found_by ? `발견자 ${a.found_by}` : undefined],
    ["사인", a.cause],
    ["상처", a.wound],
    ["사망 추정", a.death_estimate],
    ["현장 흉기", a.weapon],
  ];
  return (
    <div>
      {rows
        .filter(([, v]) => v)
        .map(([k, v, sub]) => (
          <div className="rep-row" key={k}>
            <small>{k}</small>
            <b>
              {v}
              {sub && <span className="rep-sub">{sub}</span>}
            </b>
          </div>
        ))}
    </div>
  );
}

export function AutopsyNote({ a }: { a: Autopsy }) {
  return a.note ? (
    <div className="pin">
      <i />
      {a.note}
    </div>
  ) : null;
}

/* 게임 시작 때 한 번 보여주는 검시 기록 창 */
export function AutopsyModal({ a, victim, onClose }: { a: Autopsy; victim: string; onClose: () => void }) {
  return (
    <div className="modal-back" onClick={onClose}>
      <div className="modal rep-modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="검시 기록">
        <div className="body-fig">
          <BodyFigure width={150} />
        </div>
        <div className="rep-main">
          <span className="lbl">사건 파일 · {victim}</span>
          <h2 className="display">검시 기록</h2>
          <AutopsyRows a={a} />
          <AutopsyNote a={a} />
          <div className="modal-actions">
            <span className="lbl rep-hint">오른쪽 패널 「검시」에서 다시 볼 수 있어요</span>
            <button className="pill red" onClick={onClose}>
              수사 시작
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* 오른쪽 패널 「검시」 탭 */
export function AutopsyPanel({ a, victim }: { a: Autopsy; victim: string }) {
  return (
    <div className="rep-panel">
      <span className="h">검시 기록</span>
      <div className="rep-top">
        <div className="body-fig">
          <BodyFigure width={70} />
        </div>
        <p>
          <b>{victim}</b>
          <br />
          {a.found_place}
          <br />
          {hhmm(a.found_time)}
          {a.found_by ? ` ${a.found_by}가 발견` : ""}
        </p>
      </div>
      <AutopsyRows a={a} />
      <AutopsyNote a={a} />
    </div>
  );
}
