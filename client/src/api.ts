import type { AccuseResult, CaseSummary, Clue, Deduction, PlayState, Scene, TimelineItem } from "./types";

async function request<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`/api${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  // 서버가 꺼져 있으면 개발 서버가 HTML을 돌려주므로 JSON인지 먼저 확인
  if (!res.headers.get("content-type")?.includes("application/json")) {
    throw new Error("게임 서버에 연결할 수 없어요. server가 켜져 있는지 확인해주세요.");
  }
  const data = await res.json();
  if (!res.ok) throw new Error(data.error ?? `요청 실패 (${res.status})`);
  return data as T;
}

export const api = {
  cases: () => request<CaseSummary[]>("/cases"),
  startPlay: (caseId: number) => request<{ playId: number }>("/plays", { caseId }),
  play: (playId: number) => request<PlayState>(`/plays/${playId}`),
  investigate: (playId: number, spotId: number) =>
    request<{ clues: Clue[]; timeline: TimelineItem[]; scenes: Scene[]; investigationsLeft: number }>(`/plays/${playId}/investigate`, { spotId }),
  link: (playId: number, clueIds: number[]) =>
    request<{ ok: boolean; deduction: Deduction | null; deductions: Deduction[]; investigationsLeft: number }>(`/plays/${playId}/link`, { clueIds }),
  interrogate: (playId: number, characterId: number, question: string, clueId?: number) =>
    request<{ answer: string; question: string; clues: Clue[]; newClues: number[]; timeline: TimelineItem[] }>(`/plays/${playId}/interrogate`, {
      characterId,
      question,
      clueId,
    }),
  accuse: (playId: number, characterId: number, alibiDeductionId: number, linkDeductionId: number) =>
    request<AccuseResult>(`/plays/${playId}/accuse`, { characterId, alibiDeductionId, linkDeductionId }),
};

export const hhmm = (t: string) => t.slice(0, 5);
