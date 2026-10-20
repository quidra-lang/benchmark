import { copyGrammar, isNonterminal, notation, type Grammar } from './grammar_parser.ts';

function freshName(grammar: Grammar, source: string): string {
  let name = source;
  do name = name.slice(0, -1) + "'>";
  while (grammar.rules.has(name));
  return name;
}
function leadingReachable(grammar: Grammar, source: string, target: string): boolean {
  const queue = [source];
  const seen = new Set(queue);
  for (let head = 0; head < queue.length; head++) {
    for (const right of grammar.rules.get(queue[head])!) {
      const symbol = right[0];
      if (symbol === target) return true;
      if (symbol !== undefined && isNonterminal(symbol) && !seen.has(symbol)) {
        seen.add(symbol);
        queue.push(symbol);
      }
    }
  }
  return false;
}
function unique(alternatives: string[][]): string[][] {
  const seen = new Set<string>();
  return alternatives.filter((right) => {
    const key = JSON.stringify(right);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
export function eliminate(original: Grammar) {
  const grammar = copyGrammar(original);
  const order = original.order;
  const log: string[] = [];
  for (let i = 0; i < order.length; i++) {
    const left = order[i];
    for (let j = 0; j < i; j++) {
      const source = order[j];
      if (
        !grammar.rules.get(left)!.some((right) => right[0] === source) ||
        !leadingReachable(grammar, source, left)
      ) {
        continue;
      }
      const alternatives: string[][] = [];
      for (const right of grammar.rules.get(left)!) {
        if (right[0] === source) {
          for (const replacement of grammar.rules.get(source)!) {
            alternatives.push([...replacement, ...right.slice(1)]);
          }
        } else alternatives.push(right);
      }
      grammar.rules.set(left, unique(alternatives));
      log.push(`substitute ${source} into ${left}`);
    }
    let alternatives = grammar.rules.get(left)!;
    if (alternatives.some((right) => right.length === 1 && right[0] === left)) {
      alternatives = alternatives.filter((right) => right.length !== 1 || right[0] !== left);
      grammar.rules.set(left, alternatives);
      log.push(`remove cycle ${left} -> ${left}`);
    }
    const recursive = alternatives.filter((right) => right[0] === left);
    if (!recursive.length) continue;
    const name = freshName(grammar, left);
    grammar.rules.set(
      left,
      alternatives.filter((right) => right[0] !== left).map((right) => [...right, name]),
    );
    grammar.rules.set(name, [...recursive.map((right) => [...right.slice(1), name]), []]);
    grammar.order.splice(grammar.order.indexOf(left) + 1, 0, name);
    log.push(`eliminate left recursion in ${left} with ${name}`);
  }
  return { grammar, log };
}
export function factor(original: Grammar) {
  const grammar = copyGrammar(original);
  const log: string[] = [];
  for (let i = 0; i < grammar.order.length; i++) {
    const left = grammar.order[i];
    const alternatives = grammar.rules.get(left)!;
    const used = new Set<string>();
    const replacement: string[][] = [];
    const created: string[] = [];
    for (const right of alternatives) {
      if (!right.length) {
        replacement.push(right);
        continue;
      }
      if (used.has(right[0])) continue;
      used.add(right[0]);
      const group = alternatives.filter((other) => other[0] === right[0]);
      if (group.length === 1) {
        replacement.push(right);
        continue;
      }
      let length = 0;
      while (length < right.length && group.every((other) => other[length] === right[length])) {
        length++;
      }
      const prefix = right.slice(0, length);
      const name = freshName(grammar, left);
      grammar.rules.set(
        name,
        group.map((other) => other.slice(length)),
      );
      replacement.push([...prefix, name]);
      created.push(name);
      log.push(`left factor ${left} on ${notation(prefix)} with ${name}`);
    }
    grammar.rules.set(left, replacement);
    grammar.order.splice(i + 1, 0, ...created);
  }
  return { grammar, log };
}
