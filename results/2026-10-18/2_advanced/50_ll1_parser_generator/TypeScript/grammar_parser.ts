export interface Grammar { start: string; order: string[]; rules: Map<string, string[][]> }
export interface GrammarToken { kind: string; value: string; start: number; end: number }
export const isNonterminal = (symbol: string): boolean => symbol.startsWith('<') && symbol.endsWith('>');
export const notation = (symbols: string[]): string => symbols.length ? symbols.join(' ') : '%empty';
export const productionText = (left: string, right: string[]): string => left + ' -> ' + notation(right);
export function copyGrammar(grammar: Grammar): Grammar {
    return { start: grammar.start, order: grammar.order.slice(), rules: new Map([...grammar.rules].map(([left, alternatives]) => [left, alternatives.map(right => right.slice())])) };
}
function tokenize(line: string): GrammarToken[] {
    const tokens: GrammarToken[] = []; let position = 0;
    while (position < line.length) {
        if (line[position] === ' ') { position++; continue; }
        if (line[position] === '#') break;
        const rest = line.slice(position); let kind = 'invalid', text = '', value = '', match: RegExpExecArray | null;
        if ((match = /^<[A-Za-z][A-Za-z0-9_]*>/.exec(rest))) { kind = 'nonterminal'; text = value = match[0]; }
        else if ((match = /^"([^ "]+)"/.exec(rest))) { kind = 'quoted'; text = match[0]; value = match[1]; }
        else if ((match = /^[A-Za-z][A-Za-z0-9_]*/.exec(rest))) { kind = 'word'; text = value = match[0]; }
        else if (rest.startsWith('::=')) { kind = 'definition'; text = value = '::='; }
        else if (rest[0] === '|') { kind = 'separator'; text = value = '|'; }
        else if ((match = /^%([A-Za-z]+)/.exec(rest)) && ['empty', 'start', 'token'].includes(match[1])) { kind = match[1]; text = value = match[0]; }
        tokens.push({ kind, value, start: position + 1, end: position + text.length });
        if (kind === 'invalid') break; position += text.length;
    }
    return tokens;
}
function syntaxError(tokens: GrammarToken[]): number | null {
    let state = 'begin';
    for (const token of tokens) {
        const kind = token.kind; let next: string | null = null;
        if (state === 'begin') {
            if (kind === 'nonterminal') next = 'definition'; else if (kind === 'separator') next = 'alternative';
            else if (kind === 'start') next = 'start_symbol'; else if (kind === 'token') next = 'declaration';
        } else if (state === 'definition') { if (kind === 'definition') next = 'alternative'; }
        else if (state === 'alternative') { if (['nonterminal', 'word', 'quoted'].includes(kind)) next = 'symbols'; else if (kind === 'empty') next = 'empty'; }
        else if (state === 'symbols') { if (['nonterminal', 'word', 'quoted'].includes(kind)) next = 'symbols'; else if (kind === 'separator') next = 'alternative'; }
        else if (state === 'empty') { if (kind === 'separator') next = 'alternative'; }
        else if (state === 'start_symbol') { if (kind === 'nonterminal') next = 'complete'; }
        else if (state === 'declaration' || state === 'words') { if (kind === 'word') next = 'words'; }
        if (next === null) return token.start; state = next;
    }
    return ['symbols', 'empty', 'complete', 'words'].includes(state) ? null : tokens[tokens.length - 1].end + 1;
}
export function parseGrammar(lines: string[]) {
    const grammar: Grammar = { start: '', order: [], rules: new Map() }, declared = new Set<string>(), wordLines = new Map<string, number>(), diagnostics: string[] = [];
    let hasDeclarations = false, attached: string | null = null;
    lines.forEach((line, index) => {
        const number = index + 1, tokens = tokenize(line); if (!tokens.length) return;
        const column = syntaxError(tokens);
        if (column !== null) { diagnostics.push(`line ${number}: syntax error at column ${column}`); attached = null; return; }
        const first = tokens[0];
        if (first.kind === 'start') {
            if (grammar.start === '') grammar.start = tokens[1].value; else diagnostics.push(`line ${number}: duplicate %start`); attached = null; return;
        }
        if (first.kind === 'token') { hasDeclarations = true; for (const token of tokens.slice(1)) declared.add(token.value); attached = null; return; }
        let offset = 1;
        if (first.kind === 'nonterminal') {
            attached = first.value; if (!grammar.rules.has(attached)) { grammar.order.push(attached); grammar.rules.set(attached, []); } offset = 2;
        } else if (attached === null) { diagnostics.push(`line ${number}: continuation without a rule`); return; }
        const alternatives: string[][] = [[]];
        for (const token of tokens.slice(offset)) {
            if (token.kind === 'separator') alternatives.push([]); else if (token.kind !== 'empty') alternatives[alternatives.length - 1].push(token.value);
            if (token.kind === 'word' && !wordLines.has(token.value)) wordLines.set(token.value, number);
        }
        const left = attached!, previous = grammar.rules.get(left)!, seen = new Set(previous.map(right => JSON.stringify(right)));
        for (const right of alternatives) {
            const key = JSON.stringify(right);
            if (seen.has(key)) diagnostics.push(`line ${number}: duplicate alternative ${productionText(left, right)}`); else { seen.add(key); previous.push(right); }
        }
    });
    if (grammar.start === '') grammar.start = grammar.order[0];
    return { grammar, declared, hasDeclarations, wordLines, diagnostics };
}
