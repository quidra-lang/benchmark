import { balanceAt, type Process, type Copy } from './processes.ts';

export interface SnapshotRecord { process: number; time: number; reason: string; balance: number; L: number; V: number[]; pending: Copy[]; snapshot: Snapshot }
export class Snapshot {
    completed: number | null = null; records: (SnapshotRecord | null)[]; channels: Copy[][][];
    dispatched: (number | null)[][]; accepted: (number | null)[][]; remaining: number; ignored: { process: number; time: number }[] = [];
    constructor(public name: string, public started: number, size: number) {
        this.records = Array(size).fill(null); this.channels = Array.from({ length: size }, () => Array.from({ length: size }, () => []));
        this.dispatched = Array.from({ length: size }, () => Array(size).fill(null)); this.accepted = Array.from({ length: size }, () => Array(size).fill(null)); this.remaining = size * (size - 1);
    }
    record(process: Process, time: number, reason: string): SnapshotRecord {
        const record: SnapshotRecord = { process: process.index, time, reason, balance: process.balance, L: process.L, V: process.V.slice(), pending: process.hold.slice(), snapshot: this };
        this.records[process.index] = record; return record;
    }
    cut(): number[] { return this.records.map((record, i) => record!.V[i]); }
}
export function inspectCut(processes: Process[], copies: Copy[], cut: number[]) {
    const orphans: Copy[] = [], transit: Copy[] = [];
    for (const copy of copies) {
        const sent = copy.message.event!.local <= cut[copy.source], received = copy.received !== null && copy.received.local <= cut[copy.destination];
        if (received && !sent) orphans.push(copy); if (sent && !received) transit.push(copy);
    }
    let balances = 0; for (let i = 0; i < processes.length; i++) balances += balanceAt(processes[i], cut[i]);
    let money = balances; for (const copy of transit) money += copy.message.amount; return { orphans, transit, balances, money };
}
