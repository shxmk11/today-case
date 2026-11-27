import { useEffect, useRef, useState } from "react";
import { api } from "../api";
import type { AccuseResult, Character, Clue, PlayState, TimelineItem } from "../types";
import ChatPanel from "./ChatPanel";
import CasePanel, { type Tab } from "./CasePanel";
import AccuseModal from "./AccuseModal";
import { Face, Topline, bio } from "./Common";
import { AutopsyModal } from "./Autopsy";

interface Props {
  playId: number;
  onHome: () => void;
  onFinish: (result: AccuseResult, title: string) => void;
}

export default function Game({ playId, onHome, onFinish }: Props) {
  const [state, setState] = useState<PlayState | null>(null);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<number | null>(null);
  const [accusing, setAccusing] = useState(false);
  const [tab, setTab] = useState<Tab>("clue");
  const [toast, setToast] = useState("");
  // 검시 기록 창: 플레이마다 처음 한 번만 띄운다
  const seenKey = `autopsy-seen-${playId}`;
  const [autopsyOpen, setAutopsyOpen] = useState(() => {
    try {
      return !localStorage.getItem(seenKey);
    } catch {
      return true;
    }
  });
  function closeAutopsy() {
    setAutopsyOpen(false);
    try {
      localStorage.setItem(seenKey, "1");
    } catch {
      /* 저장이 막혀 있으면 다음에 또 뜰 뿐 */
    }
  }
  // 마지막 행동으로 타임라인에 새로 붙은 줄 (빨간 점으로 표시)
  const [freshKeys, setFreshKeys] = useState<Set<string>>(new Set());
  const toastTimer = useRef<number>(undefined);

  useEffect(() => {
    api
      .play(playId)
      .then((s) => {
        setState(s);
        setSelected(s.characters.find((c) => c.character_type === "용의자")?.character_id ?? null);
      })
      .catch((e: Error) => setError(e.message));
  }, [playId]);

  if (error) return <p className="error page">{error}</p>;
  if (!state) return <p className="muted page">현장으로 이동 중…</p>;

  const suspects = state.characters.filter((c) => c.character_type !== "피해자");
  const victim = state.characters.find((c) => c.character_type === "피해자");
  const current = suspects.find((c) => c.character_id === selected) ?? null;

  function showToast(text: string) {
    setToast(text);
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(""), 4000);
  }

  /** 새 단서·타임라인 줄을 알림으로 띄우고, 새 줄을 표시해둔다 */
  function announce(newClueNames: string[], timeline: TimelineItem[]) {
    const known = new Set(state!.timeline.map((t) => t.key));
    const added = timeline.filter((t) => !known.has(t.key));
    if (added.length > 0) setFreshKeys(new Set(added.map((t) => t.key)));
    const claims = added.filter((t) => t.kind === "주장").length;
    const parts = [
      newClueNames.length > 0 && `새 단서 · ${newClueNames.join(", ")}`,
      added.length > 0 && `타임라인 +${added.length}${claims > 0 ? " (알리바이 주장)" : ""}`,
    ].filter(Boolean);
    if (parts.length > 0) showToast(`＋ ${parts.join("  ·  ")}`);
  }

  async function ask(ch: Character, question: string, evidence?: Clue) {
    const shown = evidence ? `[증거 제시: ${evidence.name}] ${question}` : question;
    const pending = { character_id: ch.character_id, question: shown, answer: "", pending: true };
    setState((s) => s && { ...s, chats: [...s.chats, pending] });
    try {
      const res = await api.interrogate(playId, ch.character_id, question, evidence?.clue_id);
      const fresh = res.clues.filter((c) => res.newClues.includes(c.clue_id)).map((c) => c.name);
      announce(fresh, res.timeline);
      setState((s) => s && {
        ...s,
        clues: res.clues,
        timeline: res.timeline,
        chats: s.chats.map((c) =>
          c === pending ? { ...c, question: res.question, answer: res.answer, pending: false, newClues: fresh } : c,
        ),
      });
    } catch (e) {
      setState((s) => s && { ...s, chats: s.chats.filter((c) => c !== pending) });
      throw e;
    }
  }

  async function investigate(spotId: number) {
    const before = new Set(state!.clues.map((c) => c.clue_id));
    try {
      const { clues, timeline, scenes, investigationsLeft } = await api.investigate(playId, spotId);
      const fresh = clues.filter((c) => !before.has(c.clue_id)).map((c) => c.name);
      if (fresh.length === 0) showToast("특별한 건 없었다.");
      else announce(fresh, timeline);
      setState((s) => s && { ...s, clues, timeline, scenes, investigationsLeft });
    } catch (e) {
      showToast((e as Error).message);
    }
  }

  async function link(clueIds: number[]): Promise<string> {
    const res = await api.link(playId, clueIds);
    setState((s) => s && { ...s, deductions: res.deductions, investigationsLeft: res.investigationsLeft });
    if (res.deduction) {
      showToast(`＋ 새 추론 · ${res.deduction.name}`);
      return `새 추론 「${res.deduction.name}」을 얻었어요.`;
    }
    return `이어지는 게 없었어요. 조사 1회가 줄었어요. (남은 조사 ${res.investigationsLeft})`;
  }

  async function accuse(characterId: number, alibiDeductionId: number, linkDeductionId: number) {
    const result = await api.accuse(playId, characterId, alibiDeductionId, linkDeductionId);
    onFinish(result, state!.case.title);
  }

  return (
    <main className="game">
      <Topline onHome={onHome} right={`질문 ${state.chats.length} · 조사 ${state.investigationsLeft} / ${state.investigationLimit} · 단서 ${state.clues.length} · 추론 ${state.deductions.length} / ${state.deductionTotal}`} />

      <section className="game-head">
        <h1 className="display">{state.case.title}</h1>
        <button className="pill red accuse" onClick={() => setAccusing(true)}>
          범인 지목하기
        </button>
      </section>
      <section className="game-meta">
        <span>{state.case.summary}</span>
        {victim && (
          <span>
            피해자
            <br />
            <b>
              <span className="red">{victim.name}</span> {bio(victim)}, {victim.job}
            </b>
          </span>
        )}
        <span>
          규칙
          <br />
          <b>거짓말은 범인만 한다</b>
        </span>
      </section>

      <div className="game-grid">
        <aside className="suspects">
          <div className="lbl row-between head">
            <span>심문할 인물</span>
            <span>{suspects.length}명</span>
          </div>
          {suspects.map((c) => {
            const count = state.chats.filter((m) => m.character_id === c.character_id).length;
            return (
              <button
                key={c.character_id}
                className={`suspect ${c.character_id === selected ? "on" : ""}`}
                onClick={() => setSelected(c.character_id)}
              >
                <Face name={c.name} src={c.image_url} size={38} zoom />
                <span className="grow">
                  <b>{c.name}</b>
                  <small>
                    {bio(c)}, {c.job}
                  </small>
                </span>
                {count > 0 && <span className="q">질문 {count}</span>}
              </button>
            );
          })}
        </aside>

        {current ? (
          <ChatPanel
            character={current}
            chats={state.chats.filter((m) => m.character_id === current.character_id)}
            clues={state.clues}
            onAsk={(q, ev) => ask(current, q, ev)}
          />
        ) : (
          <section className="card chat empty">심문할 인물을 골라주세요.</section>
        )}

        <CasePanel
          tab={tab}
          onTab={setTab}
          scenes={state.scenes}
          mapUrl={state.case.map_url ?? null}
          clues={state.clues}
          timeline={state.timeline}
          autopsy={state.autopsy}
          victim={victim?.name ?? "피해자"}
          freshKeys={freshKeys}
          deductions={state.deductions}
          deductionTotal={state.deductionTotal}
          left={state.investigationsLeft}
          limit={state.investigationLimit}
          onInvestigate={investigate}
          onLink={link}
        />
      </div>

      {toast && (
        <div className="toast" role="status">
          {toast}
        </div>
      )}

      {autopsyOpen && state.autopsy && (
        <AutopsyModal a={state.autopsy} victim={victim?.name ?? "피해자"} onClose={closeAutopsy} />
      )}

      {accusing && (
        <AccuseModal
          suspects={state.characters.filter((c) => c.character_type === "용의자")}
          onClose={() => setAccusing(false)}
          deductions={state.deductions}
          onAccuse={accuse}
        />
      )}
    </main>
  );
}
