import { useState } from "react";
import type { Character } from "../types";
import { Face } from "./Common";

interface Props {
  suspects: Character[];
  onClose: () => void;
  onAccuse: (characterId: number) => Promise<void>;
}

export default function AccuseModal({ suspects, onClose, onAccuse }: Props) {
  const [pick, setPick] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function confirm() {
    if (pick === null) return;
    setBusy(true);
    try {
      await onAccuse(pick);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  return (
    <div className="modal-back" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <p className="lbl">범인 지목</p>
        <h2 className="display">범인은 누구인가요?</h2>
        <p className="modal-note">지목은 한 번뿐이에요. 지목하면 사건이 끝나고 진상이 공개돼요.</p>
        <div className="accuse-list">
          {suspects.map((s) => (
            <button key={s.character_id} className={`accuse-pick ${pick === s.character_id ? "on" : ""}`} onClick={() => setPick(s.character_id)}>
              <Face name={s.name} size={48} />
              <b>{s.name}</b>
              <small>{s.job?.split(",").at(-1)?.trim()}</small>
            </button>
          ))}
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          <button className="pill outline-dark" onClick={onClose}>더 조사하기</button>
          <button className="pill red" disabled={pick === null || busy} onClick={() => void confirm()}>
            {busy ? "판정 중…" : "이 사람이 범인이다"}
          </button>
        </div>
      </div>
    </div>
  );
}
