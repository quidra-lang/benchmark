import { sameEntry, copyEntry, RaftNode } from './raft_node.ts';
import type { Entry } from './raft_node.ts';
const PROPERTIES = ['ELECTION_SAFETY', 'LEADER_COMPLETENESS', 'LOG_MATCHING', 'STATE_MACHINE_SAFETY', 'COMMITTED_KEPT'];
export class Checker {
  leaders = new Map<number, number>(); committed = new Map<number, { term: number; time: number }>();
  applied = new Map<number, { entry: Entry; result: string | null }>(); violations = Array<number>(5).fill(0);
  elected = 0; ticks = 0; pairs = 0; applies = 0; truncations = 0; removed = 0;
  leader(node: RaftNode): void {
    this.elected++;
    if (!this.leaders.has(node.currentTerm)) this.leaders.set(node.currentTerm, node.number);
    else if (this.leaders.get(node.currentTerm) !== node.number) this.violations[0]++;
    for (const [index, record] of this.committed) if (index > node.lastIndex || node.term(index) !== record.term) { this.violations[1]++; break; }
  }
  commit(node: RaftNode, first: number, last: number, time: number): void {
    for (let i = first; i <= last; i++) if (!this.committed.has(i)) this.committed.set(i, { term: node.term(i), time });
  }
  apply(index: number, entry: Entry, result: string | null): void {
    this.applies++; const record = this.applied.get(index);
    if (record === undefined) this.applied.set(index, { entry: copyEntry(entry), result });
    else if (!sameEntry(record.entry, entry)) this.violations[3]++;
  }
  truncate(node: RaftNode, first: number): void {
    this.truncations++;
    for (let i = first; i <= node.lastIndex; i++) { this.removed++; if (this.committed.get(i)?.term === node.term(i)) this.violations[4]++; }
  }
  matching(nodes: RaftNode[]): void {
    this.ticks++;
    for (let a = 0; a < nodes.length; a++) for (let b = a + 1; b < nodes.length; b++) {
      this.pairs++; const first = nodes[a], second = nodes[b]; let greatest = Math.min(first.lastIndex, second.lastIndex);
      while (greatest > 0 && first.term(greatest) !== second.term(greatest)) greatest--;
      for (let i = 1; i <= greatest; i++) if (!sameEntry(first.entry(i), second.entry(i))) { this.violations[2]++; break; }
    }
  }
  lines(maximumTerm: number): string[] {
    const details = [`terms ${maximumTerm} leaders ${this.leaders.size} elected ${this.elected}`, `checks ${this.elected} committed ${this.committed.size}`,
      `checks ${this.ticks} pairs ${this.pairs}`, `applies ${this.applies} indices ${this.applied.size}`, `truncations ${this.truncations} removed ${this.removed}`];
    return PROPERTIES.map((p, i) => `${p} ${this.violations[i] === 0 ? 'OK' : 'FAIL'} violations ${this.violations[i]} ${details[i]}`);
  }
}
