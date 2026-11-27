export interface CaseRow {
  case_id: number;
  title: string;
  genre: string;
  difficulty: "쉬움" | "보통" | "어려움";
  summary: string;
  truth: string;
  investigation_limit: number;
  map_url: string | null;
}

/** 검시 기록: 게임 시작 때 모두에게 공개되는 시신 정보 */
export interface AutopsyRow {
  found_time: string;
  found_place: string;
  found_by: string | null;
  cause: string;
  wound: string | null;
  death_estimate: string | null;
  weapon: string | null;
  note: string | null;
}

export interface CharacterRow {
  character_id: number;
  case_id: number;
  name: string;
  age: number | null;
  gender: "남" | "여" | null;
  job: string | null;
  personality: string | null;
  backstory: string | null;
  /** 범인만: 미리 짜 둔 거짓 이야기 */
  cover_story: string | null;
  image_url: string | null;
  character_type: "피해자" | "용의자" | "목격자";
  is_culprit: boolean;
}

export interface FactRow {
  fact_id: number;
  occurred_at: string;
  place: string | null;
  content: string;
  is_initial: boolean;
}

export interface ClueRow {
  clue_id: number;
  scene_id: number;
  character_id: number | null;
  name: string;
  description: string | null;
  clue_type: "물증" | "증언" | "기록";
}
