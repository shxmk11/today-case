import { useState } from "react";
import type { Character } from "../types";

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
        <h2>범인은 누구인가요?</h2>
        <p className="muted">지목은 한 번뿐이에요. 지목하면 사건이 종료되고 진상이 공개됩니다.</p>
        <div className="accuse-list">
          {suspects.map((s, i) => (
            <button key={s.character_id} className={`suspect ${pick === s.character_id ? "active" : ""}`} onClick={() => setPick(s.character_id)}>
              <span className="num">{String(i + 1).padStart(2, "0")}</span>
              <span className="suspect-info">
                <strong>{s.name}</strong>
                <small>{s.job}</small>
              </span>
            </button>
          ))}
        </div>
        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          <button className="btn ghost" onClick={onClose}>더 조사하기</button>
          <button className="btn danger" disabled={pick === null || busy} onClick={() => void confirm()}>
            {busy ? "판정 중…" : "이 사람이 범인이다"}
          </button>
        </div>
      </div>
    </div>
  );
}
