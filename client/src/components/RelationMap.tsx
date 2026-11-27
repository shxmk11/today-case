import { useEffect, useState } from "react";
import type { Character, Relation } from "../types";

interface Props {
  characters: Character[];
  relations: Relation[];
  /** 마지막으로 펼쳐 본 뒤 새로 생기거나 바뀐 선 */
  fresh: Set<number>;
  onSeen: () => void;
}

const W = 300;
const H = 280;
const R = 22; // 인물 동그라미 반지름

type Pt = { x: number; y: number };

/** 피해자는 가운데, 나머지는 둘레의 타원 위에 고르게 */
function layout(characters: Character[]) {
  const victim = characters.find((c) => c.character_type === "피해자");
  const others = characters.filter((c) => c !== victim);
  const pos = new Map<number, Pt>();
  const c = { x: W / 2, y: H / 2 };
  if (victim) pos.set(victim.character_id, c);
  const rx = W / 2 - R - 4;
  const ry = H / 2 - R - 14;
  others.forEach((ch, i) => {
    const t = -Math.PI * 0.75 + (i * 2 * Math.PI) / others.length;
    // 네 명이면 그림 네 귀퉁이 (왼쪽 위부터 시계 방향), 아니면 타원 둘레
    const p = others.length === 4
      ? { x: c.x + Math.sign(Math.cos(t)) * rx, y: c.y + Math.sign(Math.sin(t)) * ry }
      : { x: c.x + Math.cos(t) * rx, y: c.y + Math.sin(t) * ry };
    pos.set(ch.character_id, p);
  });
  return { pos, victim, center: c };
}

const short = (name: string) => (name.length >= 3 ? name.slice(1, 3) : name);

function Graph({ characters, relations, fresh }: { characters: Character[]; relations: Relation[]; fresh: Set<number> }) {
  const { pos, victim, center } = layout(characters);
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="rel-svg" role="img" aria-label="인물 관계도">
      {relations.map((r) => {
        const p = pos.get(r.a);
        const q = pos.get(r.b);
        if (!p || !q) return null;
        const mid = { x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 };
        let ctrl = mid;
        // 용의자끼리 잇는 선은 가운데(피해자)를 피해 바깥으로 휘게
        if (r.a !== victim?.character_id && r.b !== victim?.character_id) {
          const dx = q.x - p.x;
          const dy = q.y - p.y;
          const len = Math.hypot(dx, dy) || 1;
          let nx = -dy / len;
          let ny = dx / len;
          const away = (mid.x - center.x) * nx + (mid.y - center.y) * ny;
          if (away < 0) {
            nx = -nx;
            ny = -ny;
          }
          const bend = Math.hypot(mid.x - center.x, mid.y - center.y) < 20 ? 70 : 22;
          ctrl = { x: mid.x + nx * bend, y: mid.y + ny * bend };
        }
        const lx = (p.x + 2 * ctrl.x + q.x) / 4;
        const ly = (p.y + 2 * ctrl.y + q.y) / 4;
        return (
          <g key={r.stage_id} className={`rel-edge t-${r.tone} ${fresh.has(r.stage_id) ? "new" : ""}`}>
            <path d={`M${p.x},${p.y} Q${ctrl.x},${ctrl.y} ${q.x},${q.y}`} />
            <text x={lx} y={ly} dy="0.35em">
              {r.label}
            </text>
          </g>
        );
      })}
      {characters.map((ch) => {
        const p = pos.get(ch.character_id)!;
        const isVictim = ch.character_type === "피해자";
        return (
          <g key={ch.character_id} className={`rel-node ${isVictim ? "victim" : ""}`}>
            <circle cx={p.x} cy={p.y} r={R} />
            <text x={p.x} y={p.y} dy="0.35em">
              {short(ch.name)}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

/* 심문할 인물 목록 아래의 인물 관계도. 누르면 크게 펼쳐진다 */
export default function RelationMap({ characters, relations, fresh, onSeen }: Props) {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && close();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const expand = () => setOpen(true);
  // 펼쳐서 새 선을 본 뒤 닫으면 빨간 점이 사라진다
  function close() {
    setOpen(false);
    onSeen();
  }

  const legend = (
    <div className="rel-legend">
      <span className="t-갈등">원한·갈등</span>
      <span className="t-관계">관계</span>
      <span className="t-불확실">아직 불확실</span>
    </div>
  );

  return (
    <div className="rel-map">
      <button className="rel-head lbl" onClick={expand} aria-label="인물 관계도 크게 보기">
        <span>
          인물 관계도 {fresh.size > 0 && <i className="rel-dot" aria-label="새 관계" />}
        </span>
        <span aria-hidden>⤢</span>
      </button>
      <button className="rel-mini" onClick={expand} tabIndex={-1} aria-hidden>
        <Graph characters={characters} relations={relations} fresh={fresh} />
      </button>
      {open && (
        <div className="modal-back" onClick={close}>
          <div className="modal rel-modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="인물 관계도">
            <div className="row-between">
              <h2 className="display">인물 관계도</h2>
              <button className="pill outline" onClick={close}>
                닫기
              </button>
            </div>
            <p className="muted rel-note">단서와 추론을 찾을 때마다 선이 생기거나 바뀌어요.</p>
            <Graph characters={characters} relations={relations} fresh={fresh} />
            {legend}
          </div>
        </div>
      )}
      {legend}
    </div>
  );
}
