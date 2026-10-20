import { readFileSync } from 'node:fs';
import type { Entry } from './raft_node.ts';
export type Payload = { type: 'RV'; lastIndex: number; lastTerm: number } | { type: 'RVR'; granted: boolean }
  | { type: 'AE'; prev: number; prevTerm: number; entries: Entry[]; commit: number } | { type: 'AER'; success: boolean; m: number } | { type: 'TN' };
export type MessageType = Payload['type'];
export type Message = Payload & { source: number; destination: number; term: number; serial: number };
export const TYPES: MessageType[] = ['RV', 'RVR', 'AE', 'AER', 'TN'];
export interface Counts { sent: number; delivered: number; inflight: number; partition: number; rule: number; loss: number; down: number }
const newCounts = (): Counts => ({ sent: 0, delivered: 0, inflight: 0, partition: 0, rule: 0, loss: 0, down: 0 });
interface DropRule { type: string; first: number; last: number }
interface Link { source: number; destination: number; delay: number; loss: number; pass: number; drops: DropRule[]; counts: Counts }
const matches = (pattern: string, node: number) => pattern === '*' || Number(pattern) === node;
export class Network {
  groups: number[]; queue = new Map<number, Message[]>(); serial = 0; total = newCounts();
  types = new Map(TYPES.map(type => [type, newCounts()])); links = new Map<string, Link>();
  constructor(size: number, path: string) {
    this.groups = Array<number>(size + 1).fill(0);
    const lines = readFileSync(path, 'ascii').split('\n').slice(0, -1).map(line => line.split(' '));
    for (let source = 1; source <= size; source++) for (let destination = 1; destination <= size; destination++) {
      if (source === destination) continue;
      const link: Link = { source, destination, delay: Number(lines[0][1]), loss: 0, pass: 0, drops: [], counts: newCounts() };
      for (const [kind, a, b, ...args] of lines.slice(1)) {
        if (!matches(a, source) || !matches(b, destination)) continue;
        if (kind === 'DELAY') link.delay = Number(args[0]);
        else if (kind === 'LOSS') link.loss = Number(args[0]);
        else link.drops.push({ type: args[0], first: Number(args[1]), last: Number(args[2]) });
      }
      this.links.set(`${source}/${destination}`, link);
    }
  }
  separated(source: number, destination: number): boolean { return this.groups[source] !== this.groups[destination]; }
  partition(groups: number[][]): void { groups.forEach((group, i) => group.forEach(node => { this.groups[node] = i; })); }
  heal(): void { this.groups.fill(0); }
  count(message: Message, field: keyof Counts, amount = 1): void {
    this.total[field] += amount; this.types.get(message.type)![field] += amount;
    this.links.get(`${message.source}/${message.destination}`)!.counts[field] += amount;
  }
  send(time: number, source: number, destination: number, term: number, payload: Payload): void {
    const message: Message = { ...payload, source, destination, term, serial: this.serial++ }, link = this.links.get(`${source}/${destination}`)!;
    this.count(message, 'sent');
    if (this.separated(source, destination)) { this.count(message, 'partition'); return; }
    if (link.drops.some(r => (r.type === payload.type || r.type === 'ALL') && r.first <= time && time <= r.last)) { this.count(message, 'rule'); return; }
    link.pass++;
    if (link.loss > 0 && link.pass % link.loss === 0) { this.count(message, 'loss'); return; }
    const arrival = time + link.delay, waiting = this.queue.get(arrival) ?? []; waiting.push(message); this.queue.set(arrival, waiting); this.count(message, 'inflight');
  }
  take(time: number): Message[] {
    const messages = this.queue.get(time) ?? []; this.queue.delete(time); return messages.sort((a, b) => a.source - b.source || a.serial - b.serial);
  }
  resolve(message: Message, outcome: 'down' | 'partition' | 'delivered'): void { this.count(message, 'inflight', -1); this.count(message, outcome); }
}
