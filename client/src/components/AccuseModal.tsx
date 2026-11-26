import { useState } from "react";
import type { Character, Clue } from "../types";
import { Face } from "./Common";

interface Props {
  suspects: Character[];
  clues: Clue[];
  onClose: () => void;
  onAccuse: (characterId: number, clueIds: number[]) => Promise<void>;
}

/** 범인 한 명 + 근거가 될 단서 2개를 고른다 */
export default function AccuseModal({ suspects, clues, onClose, onAccuse }: Props) {
  const [step, setStep] = useState<1 | 2>(1);
  const [pick, setPick] = useState<number | null>(null);
  const [evidence, setEvidence] = useState<number[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const chosen = suspects.find((s) => s.character_id === pick);

  function toggle(id: number) {
    setEvidence((ev) => (ev.includes(id) ? ev.filter((x) => x !== id) : ev.length < 2 ? [...ev, id] : [ev[1], id]));
  }

  async function confirm() {
    if (pick === null || evidence.length !== 2) return;
    setBusy(true);
    try {
      await onAccuse(pick, evidence);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  return (
    <div className="modal-back" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <p className="lbl">범인 지목 · {step} / 2</p>
        {step === 1 ? (
          <>
            <h2 className="display">범인은 누구인가요?</h2>
            <p className="modal-note">다음 단계에서 근거가 될 단서 2개를 함께 골라야 해요.</p>
            <div className="accuse-list">
              {suspects.map((s) => (
                <button key={s.character_id} className={`accuse-pick ${pick === s.character_id ? "on" : ""}`} onClick={() => setPick(s.character_id)}>
                  <Face name={s.name} size={48} />
                  <b>{s.name}</b>
                  <small>{s.gender ? `${s.gender} · ` : ""}{s.job?.split(",").at(-1)?.trim()}</small>
                </button>
              ))}
            </div>
          </>
        ) : (
          <>
            <h2 className="display">결정적 증거 2개</h2>
            <p className="modal-note">
              <b>{chosen?.name}</b>이(가) 범인이라는 근거를 골라주세요. 범인과 근거가 모두 맞아야 사건이 해결돼요. 지목은 한 번뿐이에요.
            </p>
            {clues.length < 2 ? (
              <p className="modal-note">단서를 2개 이상 찾아야 지목할 수 있어요.</p>
            ) : (
              <div className="evidence-pick">
                {clues.map((c) => (
                  <button key={c.clue_id} className={`ev-chip ${evidence.includes(c.clue_id) ? "on" : ""}`} onClick={() => toggle(c.clue_id)}>
                    <b>{c.name}</b>
                    <small>{c.scene_name} · {c.clue_type}</small>
                  </button>
                ))}
              </div>
            )}
          </>
        )}
        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          {step === 1 ? (
            <>
              <button className="pill outline-dark" onClick={onClose}>더 조사하기</button>
              <button className="pill red" disabled={pick === null} onClick={() => setStep(2)}>
                다음 →
              </button>
            </>
          ) : (
            <>
              <button className="pill outline-dark" onClick={() => setStep(1)}>← 범인 다시 고르기</button>
              <button className="pill red" disabled={evidence.length !== 2 || busy} onClick={() => void confirm()}>
                {busy ? "판정 중…" : `지목하기 (${evidence.length}/2)`}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
