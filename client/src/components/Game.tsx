import { useEffect, useRef, useState } from "react";
import { api } from "../api";
import type { AccuseResult, Character, PlayState, Relation, TimelineItem } from "../types";
import ChatPanel, { type Shown } from "./ChatPanel";
import CasePanel, { type Tab } from "./CasePanel";
import AccuseModal from "./AccuseModal";
import { Face, Topline, bio } from "./Common";
import { AutopsyModal } from "./Autopsy";
import RelationMap from "./RelationMap";

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
  const [tab, setTab] = useState<Tab>("scene");
  const [toast, setToast] = useState("");
  // 검시 기록 창: 플레이마다 처음 한 번만 띄운다
  const seenKey = `autopsy-seen-${playId}`;
  // first = 처음 띄운 창(「수사 시작」), 그 뒤로는 피해자 정보를 눌러 다시 연다
  const [autopsyFirst, setAutopsyFirst] = useState(true);
  const [autopsyOpen, setAutopsyOpen] = useState(() => {
    try {
      return !localStorage.getItem(seenKey);
    } catch {
      return true;
    }
  });
  function closeAutopsy() {
    setAutopsyOpen(false);
    setAutopsyFirst(false);
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

  // 인물 관계도: 단서·추론이 늘 때마다 다시 받아 온다. seen = 마지막으로 펼쳐 본 선들
  const [relations, setRelations] = useState<Relation[]>([]);
  const [seenStages, setSeenStages] = useState<Set<number> | null>(null);
  const clueCount = state?.clues.length ?? -1;
  const dedCount = state?.deductions.length ?? -1;
  useEffect(() => {
    if (clueCount < 0) return;
    api
      .relations(playId)
      .then((rs) => {
        setRelations(rs);
        // 처음 받은 선들은 새 선으로 치지 않는다
        setSeenStages((seen) => seen ?? new Set(rs.map((r) => r.stage_id)));
      })
      .catch(() => {
        /* 관계도는 못 받아도 게임은 계속 */
      });
  }, [playId, clueCount, dedCount]);
  const freshStages = new Set(relations.filter((r) => seenStages && !seenStages.has(r.stage_id)).map((r) => r.stage_id));

  if (error) return <p className="error page">{error}</p>;
  if (!state) return <p className="loading-center">현장으로 이동 중…</p>;

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

  async function ask(ch: Character, question: string, evidence?: Shown) {
    const name = evidence ? (evidence.kind === "clue" ? evidence.clue.name : evidence.deduction.name) : "";
    const shown = evidence ? `[증거 제시: ${name}] ${question}` : question;
    const pending = { character_id: ch.character_id, question: shown, answer: "", pending: true };
    setState((s) => s && { ...s, chats: [...s.chats, pending] });
    try {
      const res = await api.interrogate(
        playId,
        ch.character_id,
        question,
        evidence && (evidence.kind === "clue" ? { clueId: evidence.clue.clue_id } : { deductionId: evidence.deduction.deduction_id }),
      );
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
    const opened = res.clues.filter((c) => res.revealed.includes(c.clue_id)).map((c) => c.name);
    if (res.deduction) {
      const known = new Set(state!.timeline.map((t) => t.key));
      const added = res.timeline.filter((t) => !known.has(t.key));
      if (added.length > 0) setFreshKeys(new Set(added.map((t) => t.key)));
    }
    setState((s) => s && {
      ...s,
      deductions: res.deductions,
      clues: res.clues,
      timeline: res.timeline,
      investigationsLeft: res.investigationsLeft,
    });
    if (res.deduction) {
      showToast(`＋ 새 추론 · ${res.deduction.name}${opened.length > 0 ? `  ·  새 단서 · ${opened.join(", ")}` : ""}`);
      return `새 추론 「${res.deduction.name}」을 얻었어요.${opened.length > 0 ? ` 「${opened.join(", ")}」이(가) 단서에 들어왔어요.` : ""}`;
    }
    return "이어지는 게 없었어요. 다른 조합을 해보세요.";
  }

  async function unlimited() {
    try {
      await api.unlimited(playId);
      setState((s) => s && { ...s, unlimited: true });
      showToast("조사 무제한을 켰어요.");
    } catch (e) {
      showToast((e as Error).message);
    }
  }

  async function toggleExcluded(characterId: number) {
    const next = !state!.excluded.includes(characterId);
    // 먼저 화면에 반영하고, 저장이 실패하면 되돌린다
    setState((s) => s && { ...s, excluded: next ? [...s.excluded, characterId] : s.excluded.filter((x) => x !== characterId) });
    try {
      const { excluded } = await api.mark(playId, characterId, next);
      setState((s) => s && { ...s, excluded });
    } catch (e) {
      setState((s) => s && { ...s, excluded: next ? s.excluded.filter((x) => x !== characterId) : [...s.excluded, characterId] });
      showToast((e as Error).message);
    }
  }

  async function accuse(characterId: number, alibiDeductionId: number, linkDeductionId: number) {
    const result = await api.accuse(playId, characterId, alibiDeductionId, linkDeductionId);
    onFinish(result, state!.case.title);
  }

  return (
    <main className="game">
      <Topline onHome={onHome} right={`질문 ${state.chats.length} · 조사 ${state.unlimited ? "무제한" : `${state.investigationsLeft} / ${state.investigationLimit}`} · 단서 ${state.clues.length} · 추론 ${state.deductions.length} / ${state.deductionTotal}`} />

      <section className="game-head">
        <h1 className="display">{state.case.title}</h1>
        <button className="pill red accuse" onClick={() => setAccusing(true)}>
          범인 지목하기
        </button>
      </section>
      <section className="game-meta">
        <span>{state.case.summary}</span>
        {victim && (
          <button
            className="meta-victim"
            disabled={!state.autopsy}
            onClick={() => {
              setAutopsyFirst(false);
              setAutopsyOpen(true);
            }}
            aria-label={`피해자 ${victim.name} 검시 기록 보기`}
          >
            <Face name={victim.name} src={victim.image_url} size={44} />
            <span>
              피해자
              <br />
              <b>
                <span className="red">{victim.name}</span> {bio(victim)}, {victim.job}
              </b>
              {state.autopsy && <small className="meta-victim-more">검시 기록 보기 ›</small>}
            </span>
          </button>
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
            const out = state.excluded.includes(c.character_id);
            return (
              <div key={c.character_id} className={`suspect ${c.character_id === selected ? "on" : ""} ${out ? "out" : ""}`}>
                <button className="suspect-main" onClick={() => setSelected(c.character_id)}>
                  <Face name={c.name} src={c.image_url} size={38} zoom />
                  <span className="grow">
                    <b>{c.name}</b>
                    <small>
                      {bio(c)}, {c.job}
                    </small>
                  </span>
                </button>
                <span className="suspect-side">
                  {count > 0 && <span className="q">질문 {count}</span>}
                  {c.character_type === "용의자" && (
                    <button
                      className={`mark ${out ? "on" : ""}`}
                      aria-pressed={out}
                      title="표시만 해 두는 기능이에요. 판정에는 영향이 없어요."
                      onClick={() => void toggleExcluded(c.character_id)}
                    >
                      {out ? "제외함" : "용의선상 제외"}
                    </button>
                  )}
                </span>
              </div>
            );
          })}
          <RelationMap
            characters={state.characters}
            relations={relations}
            fresh={freshStages}
            onSeen={() => setSeenStages(new Set(relations.map((r) => r.stage_id)))}
          />
        </aside>

        {current ? (
          <ChatPanel
            character={current}
            chats={state.chats.filter((m) => m.character_id === current.character_id)}
            clues={state.clues}
            deductions={state.deductions}
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
          freshKeys={freshKeys}
          deductions={state.deductions}
          deductionTotal={state.deductionTotal}
          left={state.investigationsLeft}
          limit={state.investigationLimit}
          unlimited={state.unlimited}
          onUnlimited={unlimited}
          onInvestigate={investigate}
          onLink={link}
          memo={state.memo}
          onMemo={(content) => api.memo(playId, content)}
        />
      </div>

      {toast && (
        <div className="toast" role="status">
          {toast}
        </div>
      )}

      {autopsyOpen && state.autopsy && (
        <AutopsyModal
          a={state.autopsy}
          victim={victim?.name ?? "피해자"}
          victimImg={victim?.image_url}
          first={autopsyFirst}
          onClose={closeAutopsy}
        />
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
