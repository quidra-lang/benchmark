import type { Fraction } from './report.ts';
import type { Bid } from './bids_io.ts';

export interface Item {name: string; reserve: number; number: number; bit: number}
export interface Bidder {
  name: string;
  language: 'XOR' | 'OR';
  index: number;
  bit: number;
  valid: Bid[];
  eligible: Bid[];
}
export interface RawAuction {
  name: string;
  offered: string[];
  lines: {name: string; language: string; bids: string[]}[];
}
export interface Auction {
  name: string;
  items: Item[];
  mask: number;
  bidders: Bidder[];
  valid: Bid[];
  eligible: Bid[];
  below: Bid[];
  rejected: {number: number; name: string; error: string}[];
  totalBids: number;
}
export interface Participant {name: string; value: number; bid: number; order: number}
export interface Group {
  kind: string;
  name: string;
  arguments: string[];
  participants: Participant[];
}
export interface Parameters {
  run: string[];
  max_bundle_size: number;
  max_bids_per_bidder: number;
  saa_increment: number;
  round_cap: number;
  seed: number;
  core_max_bidders: number;
  english_increment: number;
  dutch_start: number;
  dutch_decrement: number;
}
export interface InputData {
  items: Item[];
  auctions: Map<string, RawAuction>;
  groups: Group[];
  parameters: Parameters;
}
export interface Candidate {number: number; mask: number; value: number; size: number}
export interface Share {item: Item; value: number; source: number | null}
export interface Bound {usable: Bid[]; shares: Share[]; bound: number}
export interface WdpStats {
  nodes: number; pruned: number; leaves: number;
  improvements: {node: number; welfare: number; numbers: number[]}[];
}
export interface WdpResult {
  welfare: number;
  numbers: number[];
  bids: Bid[];
  stats: WdpStats;
  rootBound: Fraction;
  rootShares: {item: Item; value: Fraction; source: number | null}[];
}
export interface Allocation {
  bids: Bid[];
  accepted: number;
  mask: number;
  unsold: Item[];
  retained: number;
  welfare: number;
}
export interface CriticalPayment {payment: number; rival: number | null}
export interface VcgPayment {payment: number; alternative: WdpResult | null}
export interface Coalition {members: number[]; mask: number; welfare: number; numbers: number[]}
export interface BlockingCoalition extends Coalition {payoff: number; deficit: number}
export interface Blockers {
  blocking: BlockingCoalition[];
  minimal: BlockingCoalition[];
  maximum: BlockingCoalition | null;
}
export interface Outcome {name: string; seller: number; utilities: number[]}
export interface AscendingResult {
  lines: string[];
  rounds: number;
  reason: string;
  retained: number;
  paid: number[];
  values: number[];
  utilities: number[];
  revenue: number;
  welfare: number;
  exposure: number;
  exposed: number;
}
export interface AuctionResult {
  auction: Auction;
  search: WdpResult;
  optimal: Allocation;
  order: Bid[];
  greedy: Allocation;
  critical: Map<number, CriticalPayment>;
  optimalValues: number[];
  greedyValues: number[];
  criticalPaid: number[];
  criticalUtilities: number[];
  vcg: VcgPayment[];
  vcgUtilities: number[];
  vcgRevenue: number;
  criticalRevenue: number;
  saa: AscendingResult;
  outcomes: Outcome[];
}
export interface CoreReport {
  lines: string[];
  checked: boolean;
  membership?: Record<string, boolean>;
}
export interface LotResult {
  winner: Participant | null;
  price: number;
  utilities: number[];
  revenue: number;
  welfare: number;
  steps?: number;
}
export interface GroupReport {
  error: string | null;
  lines: string[];
  summary: string[];
  envyFree?: boolean;
  nash?: boolean;
  equilibrium?: boolean;
}
