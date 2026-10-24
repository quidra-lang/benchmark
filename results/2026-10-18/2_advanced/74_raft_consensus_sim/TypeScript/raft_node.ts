export interface Entry {
  term: number;
  command: string;
  request: number;
}
export const makeEntry = (term: number, command: string, request: number): Entry => ({
  term,
  command,
  request,
});
export const copyEntry = (entry: Entry): Entry => ({ ...entry });
export const sameEntry = (a: Entry, b: Entry) =>
  a.term === b.term && a.command === b.command && a.request === b.request;
export type Role = 'FOLLOWER' | 'CANDIDATE' | 'LEADER';
export type Trigger = 'timeout' | 'transfer';
export interface Election {
  time: number;
  node: number;
  term: number;
  trigger: Trigger;
  votes: Set<number>;
  won: number | null;
}
export class RaftNode {
  currentTerm = 0;
  votedFor: number | null = null;
  log: Entry[] = [];
  up = true;
  stats = {
    elections: 0,
    leaders: 0,
    votesGranted: 0,
    leaderTicks: 0,
    aeOk: 0,
    aeFail: 0,
    appended: 0,
    truncated: 0,
    applies: 0,
  };
  role: Role = 'FOLLOWER';
  commit = 0;
  applied = 0;
  store = new Map<string, number>();
  knownLeader: number | null = null;
  votes = new Set<number>();
  electionDeadline: number | null = null;
  next = new Map<number, number>();
  match = new Map<number, number>();
  heartbeatDeadline: number | null = null;
  quorumDeadline: number | null = null;
  heard = new Set<number>();
  transfer: { target: number; sent: boolean; deadline: number } | null = null;
  election: Election | null = null;
  constructor(readonly number: number) {}
  resetVolatile(): void {
    this.role = 'FOLLOWER';
    this.commit = 0;
    this.applied = 0;
    this.store = new Map();
    this.knownLeader = null;
    this.votes = new Set();
    this.electionDeadline = null;
    this.next = new Map();
    this.match = new Map();
    this.heartbeatDeadline = null;
    this.quorumDeadline = null;
    this.heard = new Set();
    this.transfer = null;
    this.election = null;
  }
  get lastIndex(): number {
    return this.log.length;
  }
  get lastTerm(): number {
    return this.term(this.lastIndex);
  }
  entry(index: number): Entry {
    return this.log[index - 1];
  }
  term(index: number): number {
    return index === 0 ? 0 : this.entry(index).term;
  }
  candidateCurrent(lastIndex: number, lastTerm: number): boolean {
    return lastTerm > this.lastTerm || (lastTerm === this.lastTerm && lastIndex >= this.lastIndex);
  }
}
export function applyCommand(store: Map<string, number>, command: string): string | null {
  const [kind, key, value] = command.split(' ');
  if (kind === 'NOOP') return null;
  if (kind === 'SET') {
    store.set(key, Number(value));
    return 'ok';
  }
  if (kind === 'ADD') {
    const total = (store.get(key) ?? 0) + Number(value);
    store.set(key, total);
    return String(total);
  }
  if (kind === 'DEL') {
    if (!store.has(key)) return 'missing';
    store.delete(key);
    return 'deleted';
  }
  return store.has(key) ? String(store.get(key)) : 'missing';
}
