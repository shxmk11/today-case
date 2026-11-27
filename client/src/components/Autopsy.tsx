import type { Autopsy } from "../types";
import { hhmm } from "../api";
import { Face } from "./Common";

export function AutopsyRows({ a }: { a: Autopsy }) {
  const rows: [string, string | null, string?][] = [
    ["발견", `${hhmm(a.found_time)} · ${a.found_place}`, a.found_by ? `발견자 ${a.found_by}` : undefined],
    ["사인", a.cause],
    ["상처", a.wound],
    ["사망 추정", a.death_estimate],
    ["현장 흉기", a.weapon],
    ["그 밖에", a.note],
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

/* 게임 시작 때 한 번 보여주는 검시 기록 창 */
export function AutopsyModal({ a, victim, victimImg, onClose }: { a: Autopsy; victim: string; victimImg?: string | null; onClose: () => void }) {
  return (
    <div className="modal-back" onClick={onClose}>
      <div className="modal rep-modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="검시 기록">
        <div className="rep-main">
          <div className="rep-top">
            <Face name={victim} src={victimImg} size={76} zoom />
            <div>
              <span className="lbl">사건 파일 · 피해자 {victim}</span>
              <h2 className="display">검시 기록</h2>
            </div>
          </div>
          <AutopsyRows a={a} />
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
export function AutopsyPanel({ a, victim, victimImg }: { a: Autopsy; victim: string; victimImg?: string | null }) {
  return (
    <div className="rep-panel">
      <span className="h">검시 기록</span>
      <span className="rep-victim">
        <Face name={victim} src={victimImg} size={40} zoom />
        피해자 {victim}
      </span>
      <AutopsyRows a={a} />
    </div>
  );
}
