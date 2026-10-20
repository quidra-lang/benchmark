import { readFileSync } from 'node:fs';
import type { Snapshot } from './snapshot.ts';

export type Action = { type: 'LOCAL'; label: string } | { type: 'BROADCAST'; tag: string } | { type: 'SNAPSHOT'; name: string }
    | { type: 'SEND'; destination: number | 'SENDER'; tag: string } | { type: 'TRANSFER'; destination: number | 'SENDER'; amount: number };
export interface Program { index: number; balance: number; scheduled: { time: number; period: number; action: Action }[]; reactions: { tag: string; action: Action }[] }
export type EventType = 'LOCAL' | 'NOFUNDS' | 'SEND' | 'BCAST' | 'RECV';
export interface EventDetails { label?: string; destination?: number; amount?: number; message?: Message; copy?: Copy }
export interface SimEvent extends EventDetails { type: EventType; number: number; process: number; local: number; time: number; L: number; V: number[]; balance: number }
export interface Message { id: number; source: number; destination: number | null; kind: 'P2P' | 'BCAST'; tag: string; amount: number; stamp: number[]; event?: SimEvent; copies: Copy[] }
export interface PacketBase { source: number; destination: number; sequence: number; dispatched: number; arrival: number; fifoWait: boolean; place: 'fifo' | 'causal' | null }
export interface Copy extends PacketBase { kind: 'copy'; order: number; message: Message; received: SimEvent | null; delivery: number | null; causalWait: boolean; missing: number[] }
export interface Marker extends PacketBase { kind: 'marker'; snapshot: Snapshot }
export type Packet = Copy | Marker;
function action(words: string[], names: string[]): Action {
    const type = words[0];
    if (type === 'LOCAL') return { type, label: words[1] }; if (type === 'BROADCAST') return { type, tag: words[1] }; if (type === 'SNAPSHOT') return { type, name: words[1] };
    const destination = words[1] === 'SENDER' ? 'SENDER' : names.indexOf(words[1]);
    return type === 'SEND' ? { type, destination, tag: words[2] } : { type: 'TRANSFER', destination, amount: Number(words[2]) };
}
export function readPrograms(names: string[]): Program[] {
    const programs: Program[] = []; let current: Program | undefined;
    for (const line of readFileSync('input/programs.txt', 'ascii').trimEnd().split('\n')) {
        const w = line.split(' ');
        if (w[0] === 'PROCESS') { current = { index: names.indexOf(w[1]), balance: Number(w[3]), scheduled: [], reactions: [] }; programs.push(current); }
        else if (w[0] === 'ON') current!.reactions.push({ tag: w[1], action: action(w.slice(2), names) });
        else if (w[0] === 'AT') { const recurring = w[2] === 'EVERY'; current!.scheduled.push({ time: Number(w[1]), period: recurring ? Number(w[3]) : 0, action: action(w.slice(recurring ? 4 : 2), names) }); }
    }
    return programs;
}
export class Process {
    index: number; initial: number; balance: number; minimum: number; L = 0; V: number[]; B: number[]; next: number[];
    reorder: Map<number, Packet>[]; hold: Copy[] = []; reactions: Program['reactions']; events: SimEvent[] = []; deliveries: Copy[] = [];
    maxHeld = 0; received = 0; sent = 0; counts: Record<EventType, number> = { LOCAL: 0, NOFUNDS: 0, SEND: 0, BCAST: 0, RECV: 0 };
    constructor(program: Program, size: number) {
        this.index = program.index; this.initial = this.balance = this.minimum = program.balance;
        this.V = Array(size).fill(0); this.B = Array(size).fill(0); this.next = Array(size).fill(1);
        this.reorder = Array.from({ length: size }, () => new Map()); this.reactions = program.reactions;
    }
}
export interface Scheduled { kind: 'action'; time: number; process: number; action: Action }
export function expandScheduled(programs: Program[], end: number): Scheduled[] {
    const items: Scheduled[] = [];
    for (const program of programs) for (const line of program.scheduled) for (let time = line.time; time <= end; time += line.period) {
        items.push({ kind: 'action', time, process: program.index, action: line.action }); if (!line.period) break;
    }
    return items;
}
export const balanceAt = (process: Process, count: number): number => count === 0 ? process.initial : process.events[count - 1].balance;
