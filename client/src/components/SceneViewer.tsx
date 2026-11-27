import { useEffect } from "react";
import type { Scene } from "../types";

interface Props {
  scenes: Scene[];
  mapUrl: string | null;
  /** null 이면 지도, 숫자면 그 장소의 현장 그림 */
  sceneId: number | null;
  onScene: (id: number | null) => void;
  left: number;
  limit: number;
  busy: number | null;
  onInvestigate: (spotId: number) => void;
  onClose: () => void;
}

const remaining = (s: Scene) => s.spots.filter((p) => !p.searched).length;

/* 현장 조사 창: 단면도 지도에서 방을 고르고, 현장 그림 위 조사 지점을 눌러 조사한다 */
export default function SceneViewer(props: Props) {
  const { scenes, mapUrl, sceneId, onScene, left, limit, busy, onInvestigate, onClose } = props;
  const scene = scenes.find((s) => s.scene_id === sceneId) ?? null;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const canOpen = (searched: boolean, locked: boolean) => !searched && !locked && left > 0 && busy === null;

  return (
    <div className="modal-back" onClick={onClose}>
      <div className="viewer" role="dialog" aria-label="현장 조사" onClick={(e) => e.stopPropagation()}>
        <header className="viewer-head">
          <div className="viewer-title">
            {scene && mapUrl && (
              <button className="pill outline" onClick={() => onScene(null)}>
                ← 지도
              </button>
            )}
            <h2>{scene ? scene.name : "현장 지도"}</h2>
            {scene?.description && <span className="viewer-desc">{scene.description}</span>}
          </div>
          <div className="viewer-right">
            <span className="viewer-left">
              남은 조사 <b className={left <= 3 ? "red" : ""}>{left}</b> / {limit}
            </span>
            <button className="pill white" onClick={onClose} aria-label="닫기">
              닫기
            </button>
          </div>
        </header>

        {!scene && mapUrl && (
          <div className="stage map-stage">
            <img src={mapUrl} alt="건물 단면도" draggable={false} />
            {scenes
              .filter((s) => s.map)
              .map((s) => {
                const n = remaining(s);
                return (
                  <button
                    key={s.scene_id}
                    className={`room ${n === 0 ? "done" : ""}`}
                    style={{ left: `${s.map!.x}%`, top: `${s.map!.y}%`, width: `${s.map!.w}%`, height: `${s.map!.h}%` }}
                    onClick={() => onScene(s.scene_id)}
                  >
                    <b>{s.name}</b>
                    <small>{n === 0 ? "조사 끝" : `조사할 곳 ${n}`}</small>
                  </button>
                );
              })}
          </div>
        )}

        {scene && (
          <>
            <div className="stage">
              {scene.image_url ? (
                <img src={scene.image_url} alt={`${scene.name} 현장 그림`} draggable={false} />
              ) : (
                <div className="stage-empty">{scene.name}</div>
              )}
              {scene.spots
                .filter((p) => p.x != null && p.y != null)
                .map((p, i) => (
                  <button
                    key={p.spot_id}
                    className={`hot ${p.searched ? "done" : p.locked ? "locked" : ""} ${busy === p.spot_id ? "busy" : ""}`}
                    style={{ left: `${p.x}%`, top: `${p.y}%` }}
                    disabled={!canOpen(p.searched, p.locked)}
                    onClick={() => onInvestigate(p.spot_id)}
                    aria-label={`${p.name}${p.searched ? " (조사함)" : p.locked ? " (잠김)" : ""}`}
                  >
                    <span className="hot-dot">{p.searched ? "✓" : p.locked ? "·" : i + 1}</span>
                    <span className="hot-tip">
                      {p.name}
                      {p.locked && " · 잠김"}
                    </span>
                  </button>
                ))}
            </div>
            <div className="viewer-foot">
              <div className="spots">
                {scene.spots.map((p, i) => (
                  <button
                    key={p.spot_id}
                    className={`spot ${p.searched ? "done" : p.locked ? "locked" : ""}`}
                    disabled={!canOpen(p.searched, p.locked)}
                    title={p.locked ? "다른 단서를 찾아야 열 수 있어요" : undefined}
                    onClick={() => onInvestigate(p.spot_id)}
                  >
                    <span className="spot-no">{i + 1}</span>
                    {busy === p.spot_id ? "조사 중…" : p.name}
                    {p.searched && <small>조사함</small>}
                    {p.locked && <small>잠김</small>}
                  </button>
                ))}
              </div>
              <nav className="room-tabs" aria-label="다른 장소">
                {scenes.map((s) => (
                  <button
                    key={s.scene_id}
                    className={`pill ${s.scene_id === scene.scene_id ? "white" : "outline"}`}
                    onClick={() => onScene(s.scene_id)}
                  >
                    {s.name}
                  </button>
                ))}
              </nav>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
