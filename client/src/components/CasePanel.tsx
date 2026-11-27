import { useState } from "react";
import { hhmm } from "../api";
import type { Autopsy, Clue, Deduction, Scene, TimelineItem } from "../types";
import { AutopsyPanel } from "./Autopsy";

export type Tab = "clue" | "scene" | "autopsy" | "deduction" | "timeline";

interface Props {
  tab: Tab;
  onTab: (t: Tab) => void;
  scenes: Scene[];
  clues: Clue[];
  timeline: TimelineItem[];
  autopsy: Autopsy | null;
  victim: string;
  freshKeys: Set<string>;
  deductions: Deduction[];
  deductionTotal: number;
  left: number;
  limit: number;
  onInvestigate: (spotId: number) => Promise<void>;
  /** 연결 결과 문구를 돌려준다 */
  onLink: (clueIds: number[]) => Promise<string>;
}

export default function CasePanel(props: Props) {
  const { tab, onTab, scenes, clues, timeline, autopsy, victim, freshKeys, deductions, deductionTotal, left, limit, onInvestigate, onLink } = props;
  const [busy, setBusy] = useState<number | null>(null);
  const [open, setOpen] = useState<number | null>(null);
  const [detail, setDetail] = useState<number | null>(null);
  const [picked, setPicked] = useState<number[]>([]);
  const [linking, setLinking] = useState(false);
  const [linkMsg, setLinkMsg] = useState("");

  async function investigate(id: number) {
    setBusy(id);
    try {
      await onInvestigate(id);
    } finally {
      setBusy(null);
    }
  }

  function togglePick(id: number) {
    setLinkMsg("");
    setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : p.length >= 3 ? p : [...p, id]));
  }

  async function link() {
    setLinking(true);
    try {
      setLinkMsg(await onLink(picked));
      setPicked([]);
    } catch (e) {
      setLinkMsg((e as Error).message);
    } finally {
      setLinking(false);
    }
  }

  const nameOf = (id: number) => clues.find((c) => c.clue_id === id)?.name ?? "?";

  // 단서가 있는 장소 중 펼칠 곳: 고른 곳, 없으면 가장 최근에 단서가 나온 곳
  const openScene = open ?? clues.at(-1)?.scene_id ?? null;

  return (
    <aside className="card panel">
      <nav className={`tabs ${autopsy ? "five" : ""}`}>
        <button className={`pill ${tab === "clue" ? "white" : "outline"}`} onClick={() => onTab("clue")}>
          단서 {clues.length}
        </button>
        <button className={`pill ${tab === "scene" ? "white" : "outline"}`} onClick={() => onTab("scene")}>
          현장
        </button>
        {autopsy && (
          <button className={`pill ${tab === "autopsy" ? "white" : "outline"}`} onClick={() => onTab("autopsy")}>
            검시
          </button>
        )}
        <button className={`pill ${tab === "deduction" ? "white" : "outline"}`} onClick={() => onTab("deduction")}>
          추론 {deductions.length}
        </button>
        <button className={`pill ${tab === "timeline" ? "white" : "outline"}`} onClick={() => onTab("timeline")}>
          타임라인
        </button>
      </nav>

      <div className="panel-body">
        {tab === "clue" &&
          (clues.length === 0 ? (
            <p className="muted pad">현장을 조사하거나 인물을 심문하면 단서가 모여요.</p>
          ) : (
            scenes.map((sc) => {
              const items = clues.filter((c) => c.scene_id === sc.scene_id);
              if (sc.scene_id === openScene && items.length > 0) {
                const d = items.find((c) => c.clue_id === detail);
                return (
                  <div key={sc.scene_id} className="scene-open">
                    <div className="row-between h">
                      <span>{sc.name}</span>
                      <span className="num">{items.length}</span>
                    </div>
                    <div className="chips">
                      {items.map((c) => (
                        <button
                          key={c.clue_id}
                          className={`chip ${c.clue_id === detail ? "on" : ""}`}
                          onClick={() => setDetail(c.clue_id === detail ? null : c.clue_id)}
                        >
                          <i className={`dot t-${c.clue_type}`} />
                          <span>{c.name}</span>
                          <small>{c.clue_type}</small>
                        </button>
                      ))}
                    </div>
                    {d && <p className="chip-detail">{d.description}</p>}
                  </div>
                );
              }
              return (
                <button
                  key={sc.scene_id}
                  className="scene-row"
                  disabled={items.length === 0}
                  onClick={() => {
                    setOpen(sc.scene_id);
                    setDetail(null);
                  }}
                >
                  <span>{sc.name}</span>
                  <span className="num">{items.length}</span>
                </button>
              );
            })
          ))}

        {tab === "scene" && (
          <>
            <div className="budget">
              <div className="row-between">
                <b>남은 조사</b>
                <span className="num">{left} / {limit}</span>
              </div>
              <div className="budget-dots" aria-hidden>
                {Array.from({ length: limit }, (_, i) => (
                  <i key={i} className={i < left ? "on" : ""} />
                ))}
              </div>
              <p>조사할 곳을 하나 열 때마다 1회를 써요. 틀린 연결도 1회를 써요.</p>
            </div>
            {scenes.map((s) => (
              <div key={s.scene_id} className="scene-card">
                <b>{s.name}</b>
                <p>{s.description}</p>
                <div className="spots">
                  {s.spots.map((sp) => (
                    <button
                      key={sp.spot_id}
                      className={`spot ${sp.searched ? "done" : sp.locked ? "locked" : ""}`}
                      disabled={sp.searched || sp.locked || left <= 0 || busy !== null}
                      title={sp.locked ? "다른 단서를 찾아야 열 수 있어요" : undefined}
                      onClick={() => void investigate(sp.spot_id)}
                    >
                      {busy === sp.spot_id ? "조사 중…" : sp.name}
                      {sp.searched && <small>조사함</small>}
                      {sp.locked && <small>잠김</small>}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </>
        )}

        {tab === "deduction" && (
          <>
            <div className="scene-open link-box">
              <div className="row-between h">
                <span>단서 연결하기</span>
                <span className="num">{picked.length} / 3</span>
              </div>
              <p className="chip-detail">
                함께 보면 새 사실이 드러나는 단서를 2~3개 고르세요. 맞으면 추론을 얻고, 틀리면 조사 1회가 줄어요. (남은 조사 {left})
              </p>
              {clues.length < 2 ? (
                <p className="chip-detail">단서를 2개 이상 찾으면 연결할 수 있어요.</p>
              ) : (
                <div className="chips">
                  {clues.map((c) => (
                    <button
                      key={c.clue_id}
                      className={`chip ${picked.includes(c.clue_id) ? "pick" : ""}`}
                      onClick={() => togglePick(c.clue_id)}
                    >
                      <i className={`dot t-${c.clue_type}`} />
                      <span>{c.name}</span>
                      <small>{c.character_id ? "증언" : c.scene_name}</small>
                    </button>
                  ))}
                </div>
              )}
              <button className="pill red" disabled={picked.length < 2 || linking} onClick={() => void link()}>
                {linking ? "맞춰보는 중…" : "연결하기"}
              </button>
              {linkMsg && <p className="link-msg">{linkMsg}</p>}
            </div>
            <div className="row-between lbl ded-head">
              <span>찾은 추론</span>
              <span>
                {deductions.length} / {deductionTotal}
              </span>
            </div>
            {deductions.length === 0 ? (
              <p className="muted pad">아직 찾은 추론이 없어요. 범인을 지목하려면 추론이 2개 필요해요.</p>
            ) : (
              [...deductions].reverse().map((d) => (
                <div key={d.deduction_id} className="deduction">
                  <b>{d.name}</b>
                  <p>{d.description}</p>
                  <small>{d.clue_ids.map(nameOf).join(" + ")}</small>
                </div>
              ))
            )}
          </>
        )}

        {tab === "autopsy" && autopsy && <AutopsyPanel a={autopsy} victim={victim} />}

        {tab === "timeline" && (
          <>
            <p className="muted pad tl-note">단서와 알리바이 주장이 시각순으로 자동 정리돼요.</p>
            <ol className="dots-timeline player-tl">
              {timeline.map((t) => {
                const [title, ...rest] = t.kind === "사실" ? ["", t.text] : t.text.split(" · ");
                return (
                  <li key={t.key} className={`k-${t.kind} ${freshKeys.has(t.key) ? "hot" : ""}`}>
                    <time>{hhmm(t.time)}</time>
                    <i />
                    <span>
                      <small>
                        {t.place ? `${t.place} · ` : ""}
                        {t.kind}
                      </small>
                      {title && <b>{title}</b>}
                      {rest.join(" · ")}
                    </span>
                  </li>
                );
              })}
            </ol>
          </>
        )}
      </div>
    </aside>
  );
}
