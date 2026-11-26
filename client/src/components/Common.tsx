import type { ReactNode } from "react";

/* 맨 위 한 줄: 왼쪽 로고, 가운데 소개, 오른쪽은 화면마다 다른 정보 */
export function Topline({ right, onHome }: { right?: ReactNode; onHome?: () => void }) {
  return (
    <header className="topline">
      <button className="logo" onClick={onHome}>
        오늘의 사건<span className="logo-dot">.</span>
      </button>
      <span>AI 머더미스터리</span>
      <span className="right">{right}</span>
    </header>
  );
}

/* 이름 첫 글자를 뺀 두 글자(서진, 유나)로 만든 동그란 얼굴 */
export function Face({ name, size = 44 }: { name: string; size?: number }) {
  const label = name.length >= 3 ? name.slice(1, 3) : name;
  return (
    <span className="face" style={{ width: size, height: size, fontSize: Math.round(size * 0.3) }}>
      {label}
    </span>
  );
}

/* *행동 묘사* 를 기울임꼴로 보여준다 */
export function Line({ text }: { text: string }) {
  return (
    <>
      {text.split(/(\*[^*]+\*)/g).map((part, i) =>
        part.startsWith("*") && part.endsWith("*") ? <em key={i}>{part.slice(1, -1)}</em> : part,
      )}
    </>
  );
}

/* "[증거 제시: 이름] 질문" 을 나눈다 */
export function splitEvidence(text: string): { evidence: string | null; question: string } {
  const m = text.match(/^\[증거 제시: (.+?)\] ?(.*)$/s);
  return m ? { evidence: m[1], question: m[2] } : { evidence: null, question: text };
}
