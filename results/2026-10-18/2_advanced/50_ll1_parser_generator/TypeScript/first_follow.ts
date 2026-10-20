import { isNonterminal, type Grammar } from './grammar_parser.ts';

export interface GrammarSets { nullable: Map<string, boolean>; first: Map<string, Set<string>>; follow: Map<string, Set<string>>; passes: { nullable: number; first: number; follow: number } }
export function firstOf(symbols: string[], nullable: Map<string, boolean>, first: Map<string, Set<string>>) {
    const terminals = new Set<string>();
    for (const symbol of symbols) {
        if (!isNonterminal(symbol)) { terminals.add(symbol); return { terminals, nullable: false }; }
        for (const terminal of first.get(symbol)!) terminals.add(terminal);
        if (!nullable.get(symbol)) return { terminals, nullable: false };
    }
    return { terminals, nullable: true };
}
function addAll(target: Set<string>, values: Set<string>): boolean {
    let changed = false; for (const value of values) if (!target.has(value)) { target.add(value); changed = true; } return changed;
}
export function computeSets(grammar: Grammar): GrammarSets {
    const nullable = new Map(grammar.order.map(name => [name, false])), first = new Map(grammar.order.map(name => [name, new Set<string>()])), follow = new Map(grammar.order.map(name => [name, new Set<string>()]));
    follow.get(grammar.start)!.add('$'); const passes = { nullable: 0, first: 0, follow: 0 }; let changed: boolean;
    do {
        changed = false; passes.nullable++;
        for (const name of grammar.order) if (!nullable.get(name) && grammar.rules.get(name)!.some(right => right.every(s => isNonterminal(s) && nullable.get(s)))) { nullable.set(name, true); changed = true; }
    } while (changed);
    do {
        changed = false; passes.first++;
        for (const name of grammar.order) for (const right of grammar.rules.get(name)!) if (addAll(first.get(name)!, firstOf(right, nullable, first).terminals)) changed = true;
    } while (changed);
    do {
        changed = false; passes.follow++;
        for (const name of grammar.order) for (const right of grammar.rules.get(name)!) for (let i = 0; i < right.length; i++) {
            const symbol = right[i]; if (!isNonterminal(symbol)) continue; const suffix = firstOf(right.slice(i + 1), nullable, first);
            if (addAll(follow.get(symbol)!, suffix.terminals)) changed = true;
            if (suffix.nullable && addAll(follow.get(symbol)!, follow.get(name)!)) changed = true;
        }
    } while (changed);
    return { nullable, first, follow, passes };
}
