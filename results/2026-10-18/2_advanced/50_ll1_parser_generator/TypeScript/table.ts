import { isNonterminal, type Grammar } from './grammar_parser.ts';
import { firstOf, type GrammarSets } from './first_follow.ts';

export type Reason = 'FIRST' | 'FOLLOW';
export interface Production { number: number; left: string; right: string[]; reasons: Map<string, Reason> }
export interface Conflict { left: string; terminal: string; entries: Production[]; chosen: Production; kind: string }
export function numberProductions(grammar: Grammar): Production[] {
    const productions: Production[] = [];
    for (const left of grammar.order) for (const right of grammar.rules.get(left)!) productions.push({ number: productions.length + 1, left, right, reasons: new Map() }); return productions;
}
export function buildTable(grammar: Grammar, sets: GrammarSets) {
    const productions = numberProductions(grammar), known = new Set<string>();
    for (const p of productions) for (const s of p.right) if (!isNonterminal(s)) known.add(s);
    const columns = [...known].sort(); columns.push('$');
    const cells = new Map<string, Map<string, Production[]>>(grammar.order.map(left => [left, new Map(columns.map(t => [t, []]))]));
    const byLeft = new Map<string, Production[]>(grammar.order.map(left => [left, []]));
    for (const p of productions) {
        const sequence = firstOf(p.right, sets.nullable, sets.first), reasons = new Map<string, Reason>([...sequence.terminals].map(t => [t, 'FIRST']));
        if (sequence.nullable) for (const t of sets.follow.get(p.left)!) if (!reasons.has(t)) reasons.set(t, 'FOLLOW');
        p.reasons = reasons; byLeft.get(p.left)!.push(p); for (const t of reasons.keys()) cells.get(p.left)!.get(t)!.push(p);
    }
    const choices = new Map<string, Map<string, Production>>(grammar.order.map(left => [left, new Map()])), conflicts: Conflict[] = [];
    for (const left of grammar.order) for (const terminal of columns) {
        const entries = cells.get(left)!.get(terminal)!; if (!entries.length) continue;
        const chosen = entries.find(p => p.reasons.get(terminal) === 'FIRST') ?? entries[0]; choices.get(left)!.set(terminal, chosen);
        if (entries.length < 2) continue; const reasons = new Set(entries.map(p => p.reasons.get(terminal)));
        conflicts.push({ left, terminal, entries, chosen, kind: reasons.size === 2 ? 'FIRST/FOLLOW' : reasons.has('FIRST') ? 'FIRST/FIRST' : 'FOLLOW/FOLLOW' });
    }
    return { productions, known, columns, cells, choices, conflicts, byLeft };
}
export type ParseTable = ReturnType<typeof buildTable>;
