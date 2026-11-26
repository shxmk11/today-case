import type { AccuseResult, CaseSummary, Clue, PlayState } from "./types";

async function request<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`/api${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error ?? `요청 실패 (${res.status})`);
  return data as T;
}

export const api = {
  cases: () => request<CaseSummary[]>("/cases"),
  startPlay: (caseId: number) => request<{ playId: number }>("/plays", { caseId }),
  play: (playId: number) => request<PlayState>(`/plays/${playId}`),
  investigate: (playId: number, sceneId: number) =>
    request<{ clues: Clue[] }>(`/plays/${playId}/investigate`, { sceneId }),
  interrogate: (playId: number, characterId: number, question: string) =>
    request<{ answer: string; clues: Clue[] }>(`/plays/${playId}/interrogate`, { characterId, question }),
  accuse: (playId: number, characterId: number) =>
    request<AccuseResult>(`/plays/${playId}/accuse`, { characterId }),
};

export const hhmm = (t: string) => t.slice(0, 5);
