import { useState } from "react";
import type { Character, Clue } from "../types";
import { Face } from "./Common";

interface Props {
  suspects: Character[];
  clues: Clue[];
  onClose: () => void;
  onAccuse: (characterId: number, alibiClueId: number, linkClueId: number) => Promise<void>;
}

type Slot = "alibi" | "link";
const SLOT_LABEL: Record<Slot, string> = { alibi: "① 알리바이를 깨는 증거", link: "② 범인과 범행을 잇는 증거" };

/** 범인 한 명 + 근거 2개(알리바이를 깨는 증거, 범인과 범행을 잇는 증거)를 고른다 */
export default function AccuseModal({ suspects, clues, onClose, onAccuse }: Props) {
  const [step, setStep] = useState<1 | 2>(1);
  const [pick, setPick] = useState<number | null>(null);
  const [evidence, setEvidence] = useState<Record<Slot, number | null>>({ alibi: null, link: null });
  const [slot, setSlot] = useState<Slot>("alibi");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const chosen = suspects.find((s) => s.character_id === pick);

  const nameOf = (id: number | null) => clues.find((c) => c.clue_id === id)?.name;
  const ready = evidence.alibi !== null && evidence.link !== null;

  function choose(id: number) {
    const other: Slot = slot === "alibi" ? "link" : "alibi";
    setEvidence((ev) => ({ ...ev, [slot]: ev[slot] === id ? null : id, [other]: ev[other] === id ? null : ev[other] }));
    // 이 칸을 채웠으면 빈 다음 칸으로
    if (evidence[slot] !== id && evidence[other] === null) setSlot(other);
  }

  async function confirm() {
    if (pick === null || evidence.alibi === null || evidence.link === null) return;
    setBusy(true);
    try {
      await onAccuse(pick, evidence.alibi, evidence.link);
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
            <h2 className="display">근거를 대세요</h2>
            <p className="modal-note">
              <b>{chosen?.name}</b>이(가) 범인이라는 근거를 칸마다 하나씩 골라주세요. 범인과 두 근거가 모두 맞아야 사건이 해결돼요.
            </p>
            <div className="slots">
              {(["alibi", "link"] as Slot[]).map((s) => (
                <button key={s} className={`slot ${slot === s ? "on" : ""}`} onClick={() => setSlot(s)}>
                  <small>{SLOT_LABEL[s]}</small>
                  <b>{nameOf(evidence[s]) ?? "단서를 고르세요"}</b>
                </button>
              ))}
            </div>
            {clues.length < 2 ? (
              <p className="modal-note">단서를 2개 이상 찾아야 지목할 수 있어요.</p>
            ) : (
              <div className="evidence-pick">
                {clues.map((c) => (
                  <button
                    key={c.clue_id}
                    className={`ev-chip ${evidence[slot] === c.clue_id ? "on" : Object.values(evidence).includes(c.clue_id) ? "used" : ""}`}
                    onClick={() => choose(c.clue_id)}
                  >
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
              <button className="pill red" disabled={!ready || busy} onClick={() => void confirm()}>
                {busy ? "판정 중…" : "지목하기"}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
