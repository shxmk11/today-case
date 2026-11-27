import type { AccuseResult, CaseSummary, Clue, Deduction, Me, PlayState, Relation, Scene, TimelineItem } from "./types";

export type BasicTopic = "알리바이" | "관계" | "목격";
export interface AskReply {
  answer: string;
  question: string;
  kind?: "기본" | "증거" | "자유";
  clues?: Clue[];
  newClues?: number[];
  timeline?: TimelineItem[];
  /** AI 한도·오류로 인물이 대화를 피함 (저장 안 됨, 횟수 안 씀) */
  busy?: boolean;
  notice?: string;
}

/*
 * 세션 토큰: 로그인하지 않아도 브라우저마다 게스트 회원 토큰을 하나 받아 둔다.
 * 게스트 기록은 이 브라우저에만 남고, 로그인하면 어느 기기에서든 이어 할 수 있다.
 */
const TOKEN_KEY = "tc-token";
let memoryToken: string | null = null;
function getToken() {
  try {
    return localStorage.getItem(TOKEN_KEY) ?? memoryToken;
  } catch {
    return memoryToken;
  }
}
function setToken(t: string | null) {
  memoryToken = t;
  try {
    if (t) localStorage.setItem(TOKEN_KEY, t);
    else localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* 저장이 막힌 브라우저: 이번 창에서만 유지 */
  }
}

async function request<T>(path: string, body?: unknown): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {};
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`/api${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers,
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

/** 저장된 토큰이 살아 있으면 그 회원, 아니면 새 게스트 세션 */
async function session(): Promise<Me> {
  if (getToken()) {
    try {
      return await request<Me>("/auth/me");
    } catch {
      /* 만료된 토큰이면 게스트로 새로 시작 */
    }
  }
  const g = await request<{ token: string; me: Me }>("/auth/guest", {});
  setToken(g.token);
  return g.me;
}

async function signIn(path: "/auth/login" | "/auth/signup", body: object): Promise<Me> {
  const r = await request<{ token: string; me: Me }>(path, body);
  setToken(r.token);
  return r.me;
}

export const api = {
  session,
  login: (id: string, password: string) => signIn("/auth/login", { id, password }),
  signup: (id: string, password: string, nickname: string) => signIn("/auth/signup", { id, password, nickname }),
  logout: async () => {
    await request("/auth/logout", {}).catch(() => undefined);
    setToken(null);
    return session();
  },
  cases: () => request<CaseSummary[]>("/cases"),
  startPlay: (caseId: number) => request<{ playId: number }>("/plays", { caseId }),
  play: (playId: number) => request<PlayState>(`/plays/${playId}`),
  resume: (playId: number) => request<{ playId: number }>(`/plays/${playId}/resume`, {}),
  result: (playId: number) => request<AccuseResult>(`/plays/${playId}/result`),
  investigate: (playId: number, spotId: number) =>
    request<{ clues: Clue[]; timeline: TimelineItem[]; scenes: Scene[]; investigationsLeft: number }>(`/plays/${playId}/investigate`, { spotId }),
  link: (playId: number, clueIds: number[]) =>
    request<{
      ok: boolean; deduction: Deduction | null; deductions: Deduction[]; revealed: number[];
      clues: Clue[]; timeline: TimelineItem[]; investigationsLeft: number; scenes: Scene[];
    }>(`/plays/${playId}/link`, { clueIds }),
  relations: (playId: number) => request<Relation[]>(`/plays/${playId}/relations`),
  unlimited: (playId: number) => request<{ unlimited: true }>(`/plays/${playId}/unlimited`, {}),
  /** 증거 제시: 단서 하나 또는 추론 하나 */
  /** 증거 제시 또는 자유 질문. AI가 한도에 걸리면 busy와 함께 인물이 대화를 피하는 말이 온다 (저장 안 됨) */
  interrogate: (playId: number, characterId: number, question: string, shown?: { clueId?: number; deductionId?: number }) =>
    request<AskReply>(`/plays/${playId}/interrogate`, { characterId, question, ...shown }),
  /** 기본 질문: AI 없이 정해 둔 답 */
  basic: (playId: number, characterId: number, topic: BasicTopic) =>
    request<AskReply>(`/plays/${playId}/basic`, { characterId, topic }),
  memo: (playId: number, content: string) => request<{ ok: true }>(`/plays/${playId}/memo`, { content }),
  mark: (playId: number, characterId: number, excluded: boolean) =>
    request<{ excluded: number[] }>(`/plays/${playId}/mark`, { characterId, excluded }),
  accuse: (playId: number, characterId: number, alibiDeductionId: number, linkDeductionId: number) =>
    request<AccuseResult>(`/plays/${playId}/accuse`, { characterId, alibiDeductionId, linkDeductionId }),
  ask: (playId: number, question: string) => request<{ question: string; answer: string; left: number }>(`/plays/${playId}/ask`, { question }),
};

export const hhmm = (t: string) => t.slice(0, 5);

/** "11. 28. 03:42" */
export function shortDate(iso: string) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return `${d.getMonth() + 1}. ${d.getDate()}. ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}
