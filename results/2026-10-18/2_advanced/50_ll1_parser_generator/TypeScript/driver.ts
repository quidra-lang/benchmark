import { isNonterminal, type Grammar } from './grammar_parser.ts';
import type { GrammarSets } from './first_follow.ts';
import type { Production, ParseTable } from './table.ts';

export interface TreeNode { symbol: string; mark: 'missing' | 'error' | null; children: TreeNode[] }
export interface InputToken { value: string; position: number }
export type Action = 'accept' | 'match' | 'predict' | 'skip' | 'pop' | 'missing';
export interface Step { number: number; stack: string[]; input: string[]; top: string; token: InputToken; action: Action; production?: Production }
const treeNode = (symbol: string): TreeNode => ({ symbol, mark: null, children: [] });
export function parse(grammar: Grammar, table: ParseTable, sets: GrammarSets, input: InputToken[]) {
    const root = treeNode(grammar.start), stack: { symbol: string; node: TreeNode | null }[] = [{ symbol: '$', node: null }, { symbol: grammar.start, node: root }];
    const trace: Step[] = [], leftParse: number[] = [], counts = { skip: 0, pop: 0, missing: 0 }; let position = 0, matches = 0, maximumStack = 0;
    for (;;) {
        const top = stack[stack.length - 1], token = input[position]; maximumStack = Math.max(maximumStack, stack.length);
        const step: Step = { number: trace.length + 1, stack: stack.map(e => e.symbol), input: input.slice(position).map(e => e.value), top: top.symbol, token, action: 'accept' };
        if (top.symbol === '$' && token.value === '$') step.action = 'accept';
        else if (top.symbol === '$') { step.action = 'skip'; position++; }
        else if (!isNonterminal(top.symbol)) {
            stack.pop();
            if (top.symbol === token.value) { step.action = 'match'; position++; matches++; }
            else { step.action = 'missing'; top.node!.mark = 'missing'; }
        } else {
            const production = table.choices.get(top.symbol)!.get(token.value);
            if (production) {
                step.action = 'predict'; step.production = production; leftParse.push(production.number); stack.pop();
                top.node!.children = production.right.length ? production.right.map(treeNode) : [treeNode('%empty')];
                for (let i = production.right.length - 1; i >= 0; i--) stack.push({ symbol: production.right[i], node: top.node!.children[i] });
            } else if (token.value === '$' || sets.follow.get(top.symbol)!.has(token.value)) { step.action = 'pop'; top.node!.mark = 'error'; stack.pop(); }
            else { step.action = 'skip'; position++; }
        }
        if (step.action === 'skip' || step.action === 'pop' || step.action === 'missing') counts[step.action]++;
        trace.push(step); if (step.action === 'accept') break;
    }
    return { trace, root, leftParse, counts, matches, maximumStack };
}
