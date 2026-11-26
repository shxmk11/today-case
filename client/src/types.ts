export type Difficulty = "쉬움" | "보통" | "어려움";

export interface CaseSummary {
  case_id: number;
  title: string;
  genre: string;
  difficulty: Difficulty;
  summary: string;
  suspect_count?: number;
}

export interface Character {
  character_id: number;
  name: string;
  age: number | null;
  job: string | null;
  personality: string | null;
  character_type: "피해자" | "용의자" | "목격자";
}

export interface Scene {
  scene_id: number;
  name: string;
  description: string | null;
  investigated: boolean;
}

export interface Fact {
  fact_id: number;
  occurred_at: string;
  place: string | null;
  content: string;
  is_initial?: boolean;
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
}

export interface PlayState {
  playId: number;
  status: "진행중" | "종료";
  case: CaseSummary;
  characters: Character[];
  scenes: Scene[];
  facts: Fact[];
  clues: Clue[];
  chats: Chat[];
}

export interface AccuseResult {
  result: "성공" | "실패";
  accused: string;
  culprit: { character_id: number; name: string };
  truth: string;
  timeline: Fact[];
  stats: { minutes: number; questions: number; clues: number };
}
