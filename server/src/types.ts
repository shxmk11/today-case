export interface CaseRow {
  case_id: number;
  title: string;
  genre: string;
  difficulty: "쉬움" | "보통" | "어려움";
  summary: string;
  truth: string;
  investigation_limit: number;
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
