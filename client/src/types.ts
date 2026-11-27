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
  suspects?: { name: string; job: string | null; gender: "남" | "여" | null; image_url?: string | null }[];
  /** 건물 단면도 그림 */
  map_url?: string | null;
}

export interface Character {
  character_id: number;
  name: string;
  age: number | null;
  gender: "남" | "여" | null;
  job: string | null;
  personality: string | null;
  character_type: "피해자" | "용의자" | "목격자";
  image_url?: string | null;
}

/** 장소 안의 조사 지점. 열 때마다 조사 1회. locked면 다른 단서를 찾아야 열림 (2차 조사) */
export interface Spot {
  spot_id: number;
  name: string;
  searched: boolean;
  locked: boolean;
  /** 현장 그림 위 위치 (%) */
  x: number | null;
  y: number | null;
}

export interface Scene {
  scene_id: number;
  name: string;
  description: string | null;
  investigated: boolean;
  spots: Spot[];
  /** 현장 그림 */
  image_url: string | null;
  /** 단면도에서 이 장소가 차지하는 칸 (%) */
  map: { x: number; y: number; w: number; h: number } | null;
}

/** 단서 2개를 연결해서 얻은 사실. 범인 지목 근거로는 추론만 낼 수 있다 */
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
  /** 추론에 다 쓰여서 더 쓸 데가 없는 단서 (목록에선 빼고 추론 카드 안에서만 보여줌) */
  retired?: boolean;
}

export interface Chat {
  character_id: number;
  question: string;
  answer: string;
  pending?: boolean;
  newClues?: string[];
}

/** 인물 관계도의 선 하나 (짝마다 지금까지 밝혀진 가장 나중 단계) */
export interface Relation {
  stage_id: number;
  a: number;
  b: number;
  label: string;
  tone: "관계" | "갈등" | "불확실";
}

/** 검시 기록: 게임 시작 때 공개되는 시신 정보 */
export interface Autopsy {
  found_time: string;
  found_place: string;
  found_by: string | null;
  cause: string;
  wound: string | null;
  death_estimate: string | null;
  weapon: string | null;
  note: string | null;
}

export interface PlayState {
  playId: number;
  status: "진행중" | "종료";
  case: CaseSummary;
  autopsy: Autopsy | null;
  characters: Character[];
  scenes: Scene[];
  facts: Fact[];
  timeline: TimelineItem[];
  clues: Clue[];
  clueTotal: number;
  investigationLimit: number;
  investigationsLeft: number;
  /** 조사 횟수를 다 쓴 뒤 「조사 무제한」을 켰는지 */
  unlimited: boolean;
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
