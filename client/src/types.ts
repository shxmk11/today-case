export type Difficulty = "쉬움" | "보통" | "어려움";

export interface CaseSummary {
  case_id: number;
  title: string;
  genre: string;
  difficulty: Difficulty;
  summary: string;
  suspect_count?: number;
  scene_count?: number;
  clue_count?: number;
  solve_rate?: number | null;
  suspects?: { name: string; job: string | null; gender: "남" | "여" | null }[];
}

export interface Character {
  character_id: number;
  name: string;
  age: number | null;
  gender: "남" | "여" | null;
  job: string | null;
  personality: string | null;
  character_type: "피해자" | "용의자" | "목격자";
}

/** 장소 안의 조사 지점. 열 때마다 조사 1회. locked면 다른 단서를 찾아야 열림 (2차 조사) */
export interface Spot {
  spot_id: number;
  name: string;
  searched: boolean;
  locked: boolean;
}

export interface Scene {
  scene_id: number;
  name: string;
  description: string | null;
  investigated: boolean;
  spots: Spot[];
}

/** 단서 2~3개를 연결해서 얻은 사실. 범인 지목 근거로는 추론만 낼 수 있다 */
export interface Deduction {
  deduction_id: number;
  name: string;
  description: string;
  clue_ids: number[];
}

export interface Fact {
  fact_id: number;
  occurred_at: string;
  place: string | null;
  content: string;
  is_initial?: boolean;
}

/** 플레이어 타임라인 한 줄 (공개 사실 + 자동으로 쌓인 단서·주장, 시각순) */
export interface TimelineItem {
  key: string;
  time: string;
  place: string | null;
  kind: "사실" | "물증" | "기록" | "증언" | "주장";
  text: string;
}

export interface Clue {
  clue_id: number;
  scene_id: number;
  character_id: number | null;
  name: string;
  description: string | null;
  clue_type: "물증" | "증언" | "기록";
  scene_name: string;
}

export interface Chat {
  character_id: number;
  question: string;
  answer: string;
  pending?: boolean;
  newClues?: string[];
}

export interface PlayState {
  playId: number;
  status: "진행중" | "종료";
  case: CaseSummary;
  characters: Character[];
  scenes: Scene[];
  facts: Fact[];
  timeline: TimelineItem[];
  clues: Clue[];
  clueTotal: number;
  investigationLimit: number;
  investigationsLeft: number;
  deductions: Deduction[];
  deductionTotal: number;
  chats: Chat[];
}

export interface AccuseResult {
  result: "성공" | "실패";
  /** 범인은 맞혔는지 (근거가 부족하면 범인을 맞혀도 실패) */
  culpritCorrect: boolean;
  evidence: { slot: "알리바이" | "연결"; name: string; ok: boolean; note: string | null }[];
  accused: string;
  culprit: { character_id: number; name: string };
  truth: string;
  timeline: Fact[];
  stats: { minutes: number; questions: number; clues: number; clueTotal: number; deductions: number; deductionTotal: number };
  keyEvidence: { name: string; description: string | null; clue_type: Clue["clue_type"]; scene_name: string; found: boolean }[];
  keyTestimony: {
    name: string;
    description: string | null;
    character: string | null;
    found: boolean;
    chat: { question: string; answer: string } | null;
  } | null;
  caseId: number;
}
