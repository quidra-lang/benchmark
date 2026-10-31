export interface Tile {
  kind: number;
  red: boolean;
}

export interface Meld {
  letter: string;
  tiles: Tile[];
}

export interface Block {
  type: string;
  start: number;
  kinds: number[];
  concealed?: boolean;
}

export interface StandardSplit {
  pair: number;
  sets: Block[];
}

export type RawRecord = {label: string} & Record<string, string>;

export interface Rule {
  name: string;
  honba: number;
  open_tanyao: boolean;
  red_fives: boolean;
  double_yakuman: boolean;
  kazoe_yakuman: boolean;
  kiriage: boolean;
}

export interface HandSituation {
  label?: string;
  rule: Rule;
  hand: Tile[];
  win: Tile;
  melds: Meld[];
  dora: Tile[];
  ura: Tile[];
  discards: Tile[];
  seat: string;
  round: string;
  by: string;
  from?: string;
  flags: Set<string>;
  honba: number;
  sticks: number;
  closed: boolean;
  handCounts: number[];
  concealedCounts: number[];
  allTiles: Tile[];
  allCounts: number[];
}

export interface Candidate {
  type: string;
  form: string;
  wait: string;
  pair?: number;
  sets?: Block[];
  blocks?: Block[];
  triplets?: Block[];
  sequences?: Block[];
}

export interface YakuItem {
  name: string;
  han?: number;
  multiplier?: number;
}

export interface FuBreakdown {
  items: {name: string; value: number}[];
  total: number;
  rounded: number;
}

export interface ScoredCandidate extends Candidate {
  yakuman: boolean;
  yaku: YakuItem[];
  multiplier?: number;
  han?: number;
  fu?: number;
  breakdown?: FuBreakdown;
  dora?: number;
  ura?: number;
  aka?: number;
  category: string | null;
  base: number;
}

export interface Payment {
  kind: string;
  points: number;
  ron?: number;
  all?: number;
  dealer?: number;
  nondealer?: number;
}

export interface WaitingHand {
  rule: Rule;
  hand: Tile[];
  dora: Tile[];
  discards: Tile[];
  visible: Tile[];
  seat: string;
  round: string;
  riichi: string;
  handCounts: number[];
  knownCounts: number[];
  [key: string]: any;
}

export interface ScoreStatistics {
  wins: number;
  furiten: number;
  noYaku: number;
  errors: number;
  methods: Map<string, number>;
  waits: Map<string, number>;
  han: Map<number, number>;
  fu: Map<number, number>;
  categories: Map<string, number>;
  yaku: Map<string, number>;
  points: number;
  maximum: number;
  hand: string;
  rules: Map<string, {hands: number; wins: number; points: number}>;
}
