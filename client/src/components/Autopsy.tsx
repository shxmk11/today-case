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
    ["기타", a.note],
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

/* 검시 기록 창: 게임 시작 때 한 번 뜨고, 그 뒤로는 위쪽 피해자 정보를 누르면 다시 열린다 */
export function AutopsyModal({ a, victim, victimImg, first, onClose }: {
  a: Autopsy; victim: string; victimImg?: string | null; first: boolean; onClose: () => void;
}) {
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
            <span className="lbl rep-hint">{first ? "위쪽 피해자 정보를 누르면 다시 볼 수 있어요" : ""}</span>
            <button className={`pill ${first ? "red" : "outline"}`} onClick={onClose}>
              {first ? "수사 시작" : "닫기"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
