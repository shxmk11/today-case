import { useLayoutEffect, useRef, useState } from "react";
import { hhmm } from "../api";
import type { Clue, Deduction, Scene, TimelineItem } from "../types";
import SceneViewer from "./SceneViewer";

export type Tab = "clue" | "scene" | "deduction" | "timeline";

interface Props {
  tab: Tab;
  onTab: (t: Tab) => void;
  scenes: Scene[];
  mapUrl: string | null;
  clues: Clue[];
  timeline: TimelineItem[];
  freshKeys: Set<string>;
  deductions: Deduction[];
  deductionTotal: number;
  left: number;
  limit: number;
  unlimited: boolean;
  onUnlimited: () => Promise<void>;
  onInvestigate: (spotId: number) => Promise<void>;
  /** 연결 결과 문구를 돌려준다 */
  onLink: (clueIds: number[]) => Promise<string>;
}

/** 단서 탭에서 추론 묶음을 가리키는 값 (장소 id와 겹치지 않게 음수) */
const DED_GROUP = -1;

export default function CasePanel(props: Props) {
  const { tab, onTab, scenes, mapUrl, clues: allClues, timeline, freshKeys, deductions, deductionTotal, left, limit, unlimited, onUnlimited, onInvestigate, onLink } = props;
  // 추론에 다 쓰인 단서는 목록에서 빼고 추론 카드 안에서만 보여준다
  const clues = allClues.filter((c) => !c.retired);
  const [busy, setBusy] = useState<number | null>(null);
  const [open, setOpen] = useState<number | null>(null);
  const [detail, setDetail] = useState<number | null>(null);
  const [picked, setPicked] = useState<number[]>([]);
  const [linking, setLinking] = useState(false);
  const [linkMsg, setLinkMsg] = useState("");
  // 현장 조사 창: undefined = 닫힘, null = 지도, 숫자 = 그 장소
  const [viewing, setViewing] = useState<number | null | undefined>(undefined);
  // 현장 조사 창을 열 때 가지고 있던 단서. 닫을 때 새로 얻은 단서가 있으면 단서 탭에서 그 단서를 펼친다
  const [cluesAtOpen, setCluesAtOpen] = useState<Set<number>>(new Set());
  function openViewer(id: number | null) {
    setCluesAtOpen(new Set(allClues.map((c) => c.clue_id)));
    setViewing(id);
  }
  function closeViewer() {
    setViewing(undefined);
    const latest = [...clues].reverse().find((c) => !cluesAtOpen.has(c.clue_id));
    if (!latest) return;
    onTab("clue");
    setOpen(latest.scene_id);
    setDetail(latest.clue_id);
  }
  // 펼친 단서가 보이도록 단서 탭을 스크롤
  const bodyRef = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    if (tab !== "clue" || detail == null || detail < 0) return;
    bodyRef.current?.querySelector<HTMLElement>(".chip.on")?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [tab, detail, open]);

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

  // 조사 횟수를 다 쓰면 나오는 「조사 무제한」 버튼
  const out = !unlimited && left <= 0;
  const unlimitedButton = (
    <button className="pill outline unlimited-btn" onClick={() => void onUnlimited()}>
      조사 무제한 켜기
    </button>
  );

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

  // 고른 단서들의 매듭을 잇는 빨간 실: 첫 매듭부터 마지막 매듭까지
  const listRef = useRef<HTMLDivElement>(null);
  const [thread, setThread] = useState<{ top: number; height: number } | null>(null);
  useLayoutEffect(() => {
    const box = listRef.current;
    if (!box || picked.length < 2) return setThread(null);
    const ys = picked
      .map((id) => box.querySelector<HTMLElement>(`[data-clue="${id}"]`))
      .filter((el): el is HTMLElement => !!el)
      .map((el) => el.offsetTop + el.offsetHeight / 2);
    if (ys.length < 2) return setThread(null);
    setThread({ top: Math.min(...ys), height: Math.max(...ys) - Math.min(...ys) });
  }, [picked, clues.length, tab]);

  const nameOf = (id: number) => allClues.find((c) => c.clue_id === id)?.name ?? "?";

  // 단서가 있는 장소 중 펼칠 곳: 고른 곳, 없으면 가장 최근에 단서가 나온 곳 (DED_GROUP = 추론 묶음)
  const openScene = open ?? clues.at(-1)?.scene_id ?? (deductions.length > 0 ? DED_GROUP : null);
  const dedOpen = openScene === DED_GROUP && deductions.length > 0;
  const dedDetail = deductions.find((d) => -d.deduction_id === detail);

  return (
    <aside className="card panel">
      <nav className="tabs">
        <button className={`pill ${tab === "clue" ? "white" : "outline"}`} onClick={() => onTab("clue")}>
          단서 {clues.length + deductions.length}
        </button>
        <button className={`pill ${tab === "scene" ? "white" : "outline"}`} onClick={() => onTab("scene")}>
          현장
        </button>
        <button className={`pill ${tab === "deduction" ? "white" : "outline"}`} onClick={() => onTab("deduction")}>
          추론 {deductions.length}
        </button>
        <button className={`pill ${tab === "timeline" ? "white" : "outline"}`} onClick={() => onTab("timeline")}>
          타임라인
        </button>
      </nav>

      <div className="panel-body" ref={bodyRef}>
        {tab === "clue" && clues.length + deductions.length > 0 && deductions.length > 0 &&
          (dedOpen ? (
            <div className="scene-open">
              <div className="row-between h">
                <span>추론</span>
                <span className="num">{deductions.length}</span>
              </div>
              <div className="chips">
                {[...deductions].reverse().map((d) => (
                  <button
                    key={d.deduction_id}
                    className={`chip ${-d.deduction_id === detail ? "on" : ""}`}
                    onClick={() => setDetail(-d.deduction_id === detail ? null : -d.deduction_id)}
                  >
                    <i className="dot t-추론" />
                    <span>{d.name}</span>
                    <small>추론</small>
                  </button>
                ))}
              </div>
              {dedDetail && (
                <p className="chip-detail">
                  {dedDetail.description}
                  <small className="chip-from">{dedDetail.clue_ids.map(nameOf).join(" + ")}</small>
                </p>
              )}
            </div>
          ) : (
            <button
              className="scene-row"
              onClick={() => {
                setOpen(DED_GROUP);
                setDetail(null);
              }}
            >
              <span>추론</span>
              <span className="num">{deductions.length}</span>
            </button>
          ))}
        {tab === "clue" &&
          (clues.length + deductions.length === 0 ? (
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
                <span className="num">{unlimited ? "무제한" : `${left} / ${limit}`}</span>
              </div>
              {!unlimited && (
                <div className="budget-dots" aria-hidden>
                  {Array.from({ length: limit }, (_, i) => (
                    <i key={i} className={i < left ? "on" : ""} />
                  ))}
                </div>
              )}
              <p>
                {unlimited
                  ? "조사 무제한을 켰어요. 횟수 걱정 없이 조사하고 연결할 수 있어요."
                  : "조사할 곳을 하나 열 때마다 1회, 연결에 성공하면 1회를 써요. 틀린 연결은 횟수를 쓰지 않아요."}
              </p>
              {out && (
                <>
                  <p>조사 횟수를 다 썼어요. 더 조사하고 싶다면 무제한으로 바꿀 수 있어요.</p>
                  {unlimitedButton}
                </>
              )}
            </div>
            {mapUrl && (
              <button className="map-open" onClick={() => openViewer(null)}>
                <img src={mapUrl} alt="" draggable={false} />
                <span className="pill white">지도 펼치기</span>
              </button>
            )}
            {scenes.map((s) => {
              const n = s.spots.filter((p) => !p.searched).length;
              return (
                <button key={s.scene_id} className="scene-card scene-thumb" onClick={() => openViewer(s.scene_id)}>
                  {s.image_url && <img src={s.image_url} alt="" draggable={false} />}
                  <span className="scene-thumb-text">
                    <b>{s.name}</b>
                    <small>{n === 0 ? "조사 끝" : `조사할 곳 ${n} / ${s.spots.length}`}</small>
                  </span>
                </button>
              );
            })}
          </>
        )}

        {tab === "deduction" && (
          <>
            <div className="link-head">
              <b>단서 연결하기</b>
              <p>함께 보면 새 사실이 드러나는 단서를 2~3개 이으세요. 틀려도 괜찮고, 맞히면 조사 1회를 써요.</p>
              {out && unlimitedButton}
            </div>
            {clues.length < 2 ? (
              <p className="muted pad">단서를 2개 이상 찾으면 연결할 수 있어요.</p>
            ) : (
              <div className="link-list" ref={listRef}>
                {thread && <i className="link-thread" style={{ top: thread.top, height: thread.height }} />}
                {clues.map((c) => {
                  const order = picked.indexOf(c.clue_id);
                  return (
                    <button
                      key={c.clue_id}
                      data-clue={c.clue_id}
                      className={`link-row ${order >= 0 ? "pick" : ""}`}
                      onClick={() => togglePick(c.clue_id)}
                      aria-pressed={order >= 0}
                    >
                      <span className="link-knot">{order >= 0 ? order + 1 : ""}</span>
                      <span>
                        <b>{c.name}</b>
                        <small>
                          {c.character_id ? "증언" : `${c.scene_name} · ${c.clue_type}`}
                        </small>
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
            {linkMsg && <p className="link-msg pad">{linkMsg}</p>}
            {clues.length >= 2 && (
              <div className="link-bar">
                <span>
                  {picked.length}개 이음 <small>· {unlimited ? "조사 무제한" : `남은 조사 ${left}`}</small>
                </span>
                <button className="pill red" disabled={picked.length < 2 || linking || out} onClick={() => void link()}>
                  {linking ? "맞춰보는 중…" : "연결하기"}
                </button>
              </div>
            )}
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
                  <b>
                    <i className="ded-dot" />
                    {d.name}
                  </b>
                  <p>{d.description}</p>
                  <small>{d.clue_ids.map(nameOf).join(" + ")}</small>
                </div>
              ))
            )}
          </>
        )}

        {tab === "timeline" && (
          <>
            <p className="muted pad tl-note">단서와 알리바이 주장이 시각순으로 자동 정리돼요.</p>
            <ol className="dots-timeline player-tl">
              {timeline.map((t) => {
                const [title, ...rest] = t.kind === "사실" ? ["", t.text] : t.text.split(" · ");
                return (
                  <li key={t.key} className={`k-${t.kind} ${freshKeys.has(t.key) ? "fresh" : ""}`}>
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
      {viewing !== undefined && (
        <SceneViewer
          scenes={scenes}
          mapUrl={mapUrl}
          sceneId={viewing}
          onScene={setViewing}
          left={left}
          limit={limit}
          unlimited={unlimited}
          onUnlimited={() => void onUnlimited()}
          busy={busy}
          onInvestigate={(id) => void investigate(id)}
          onClose={closeViewer}
        />
      )}
    </aside>
  );
}
