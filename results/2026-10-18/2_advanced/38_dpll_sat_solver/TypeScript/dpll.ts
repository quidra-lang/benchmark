import type { Model } from './cnf_io.ts';

export interface SearchStatistics { decisions: number; propagations: number; conflicts: number; maxDepth: number }
type TrailKind = 'D' | 'F' | 'P';
interface TrailEntry { literal: number; kind: TrailKind }
export interface RoundResult { satisfiable: boolean; model: Model | null; statistics: SearchStatistics; events: string[] }

class Round {
    private clauses: number[][];
    private values: number[];
    private trail: TrailEntry[] = [];
    private position = 0;
    private watches = new Map<number, number[]>();
    private depth = 0;
    private statistics: SearchStatistics = { decisions: 0, propagations: 0, conflicts: 0, maxDepth: 0 };
    private events: string[] = [];
    constructor(private variables: number, clauses: number[][]) {
        this.clauses = clauses.map(clause => clause.slice()); this.values = Array(variables + 1).fill(0);
    }
    private value(literal: number): number { return this.values[Math.abs(literal)] * (literal > 0 ? 1 : -1); }
    private watch(literal: number): number[] {
        let list = this.watches.get(literal);
        if (list === undefined) { list = []; this.watches.set(literal, list); }
        return list;
    }
    private assign(literal: number, kind: TrailKind): void {
        this.values[Math.abs(literal)] = literal > 0 ? 1 : -1; this.trail.push({ literal, kind }); this.events.push(kind + literal);
        if (kind !== 'P') this.depth++;
    }
    private conflict(): false { this.statistics.conflicts++; this.events.push('C'); return false; }
    private initialize(): boolean {
        this.clauses.forEach((clause, i) => { if (clause.length >= 2) { this.watch(clause[0]).push(i); this.watch(clause[1]).push(i); } });
        for (const clause of this.clauses) {
            if (clause.length === 0 || (clause.length === 1 && this.value(clause[0]) < 0)) return this.conflict();
            if (clause.length === 1 && this.value(clause[0]) === 0) { this.assign(clause[0], 'P'); this.statistics.propagations++; }
        }
        return true;
    }
    private propagate(): boolean {
        while (this.position < this.trail.length) {
            const f = -this.trail[this.position++].literal, list = this.watch(f);
            let i = 0;
            while (i < list.length) {
                const number = list[i], clause = this.clauses[number];
                if (clause[0] === f) [clause[0], clause[1]] = [clause[1], clause[0]];
                if (this.value(clause[0]) > 0) { i++; continue; }
                let replacement = 2;
                while (replacement < clause.length && this.value(clause[replacement]) < 0) replacement++;
                if (replacement < clause.length) {
                    [clause[1], clause[replacement]] = [clause[replacement], clause[1]];
                    list.splice(i, 1); this.watch(clause[1]).push(number); continue;
                }
                if (this.value(clause[0]) < 0) return this.conflict();
                this.assign(clause[0], 'P'); this.statistics.propagations++; i++;
            }
        }
        return true;
    }
    private decide(): boolean {
        const positive: number[] = Array(this.variables + 1).fill(0), negative: number[] = Array(this.variables + 1).fill(0);
        for (const clause of this.clauses) {
            if (clause.some(literal => this.value(literal) > 0)) continue;
            for (const literal of clause) if (this.value(literal) === 0) (literal > 0 ? positive : negative)[Math.abs(literal)]++;
        }
        let chosen = 0, count = 0;
        for (let x = 1; x <= this.variables; x++) {
            if (positive[x] > count) { count = positive[x]; chosen = x; }
            if (negative[x] > count) { count = negative[x]; chosen = -x; }
        }
        if (chosen === 0) return false;
        this.assign(chosen, 'D'); this.statistics.decisions++; this.statistics.maxDepth = Math.max(this.statistics.maxDepth, this.depth); return true;
    }
    private removeLast(): TrailEntry {
        const item = this.trail.pop()!; this.values[Math.abs(item.literal)] = 0;
        if (item.kind !== 'P') this.depth--;
        return item;
    }
    private backtrack(): boolean {
        while (this.trail.length > 0 && this.trail[this.trail.length - 1].kind !== 'D') this.removeLast();
        if (this.trail.length === 0) return false;
        const decision = this.removeLast(); this.position = this.trail.length; this.assign(-decision.literal, 'F'); return true;
    }
    private finish(satisfiable: boolean): RoundResult {
        return { satisfiable, model: satisfiable ? this.values.map(value => value > 0) : null, statistics: this.statistics, events: this.events };
    }
    run(): RoundResult {
        if (!this.initialize()) return this.finish(false);
        for (;;) {
            if (!this.propagate()) { if (!this.backtrack()) return this.finish(false); }
            else if (!this.decide()) return this.finish(true);
        }
    }
}
export function solveRound(variables: number, clauses: number[][]): RoundResult { return new Round(variables, clauses).run(); }
