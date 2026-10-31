import { isWildcard, type Script, type Diagnostic, type Rule } from './script_loader.ts';
import { covers } from './matcher.ts';

const codes = [
  'SYNTAX',
  'ORPHAN',
  'DUPLICATE',
  'KEY_NO_DECOMP',
  'KEY_UNREACHABLE',
  'SYNON_UNUSED',
  'PRE_CHAIN',
  'SYNON_UNKNOWN',
  'RULE_NO_REASM',
  'RULE_SHADOWED',
  'REF_UNBOUND',
  'TARGET_UNDEFINED',
  'TARGET_CYCLE',
];
const errors = new Set([
  'SYNTAX',
  'ORPHAN',
  'DUPLICATE',
  'SYNON_UNKNOWN',
  'REF_UNBOUND',
  'TARGET_UNDEFINED',
  'TARGET_CYCLE',
]);
export function lint(script: Script): string[] {
  const diagnostics: Diagnostic[] = [...script.diagnostics];
  const add = (line: number, code: string, message: string) =>
    diagnostics.push({ line, code, message });
  const keywords = [...script.keywords.values()];
  const rules = keywords.flatMap((keyword) => [...keyword.memory, ...keyword.decomp]);
  const items = rules.flatMap((rule) => rule.items);
  const targets = new Set(
    items.flatMap((item) => (item.kind === 'GOTO' || item.kind === 'RESTATE' ? [item.target] : [])),
  );
  const graph = new Map(
    keywords.map((keyword) => [
      keyword.word,
      keyword.decomp.flatMap((rule) =>
        rule.items.flatMap((item) =>
          (item.kind === 'GOTO' || item.kind === 'RESTATE') && script.keywords.has(item.target)
            ? [item.target]
            : [],
        ),
      ),
    ]),
  );
  function reachable(from: string, goal: string, visited = new Set<string>()): boolean {
    if (from === goal) return true;
    if (visited.has(from)) return false;
    visited.add(from);
    return (graph.get(from) ?? []).some((next) => reachable(next, goal, visited));
  }
  const undefinedGroup = (rule: Rule) =>
    rule.pattern.some((element) => element.startsWith('@') && !script.groups.has(element.slice(1)));
  for (const keyword of keywords) {
    if (!keyword.decomp.length) {
      add(keyword.line, 'KEY_NO_DECOMP', `keyword ${keyword.word} has no DECOMP`);
    }
    if (
      script.pre.has(keyword.word) &&
      ![...script.pre.values()].some((pre) => pre.replacement.includes(keyword.word)) &&
      !targets.has(keyword.word)
    ) {
      add(keyword.line, 'KEY_UNREACHABLE', `keyword ${keyword.word} is replaced by PRE`);
    }
    for (const sameKind of [keyword.memory, keyword.decomp]) {
      for (let index = 0; index < sameKind.length; index++) {
        const rule = sameKind[index];
        for (const element of rule.pattern) {
          if (element.startsWith('@') && !script.groups.has(element.slice(1))) {
            add(rule.line, 'SYNON_UNKNOWN', `unknown group ${element.slice(1)}`);
          }
        }
        if (!rule.items.length) add(rule.line, 'RULE_NO_REASM', 'rule has no reassembly');
        if (!undefinedGroup(rule)) {
          const shadow = sameKind
            .slice(0, index)
            .find(
              (earlier) =>
                !undefinedGroup(earlier) && covers(earlier.pattern, rule.pattern, script.groups),
            );
          if (shadow) add(rule.line, 'RULE_SHADOWED', `pattern is shadowed by line ${shadow.line}`);
        }
        const wildcards = rule.pattern.filter(isWildcard).length;
        for (const item of rule.items) {
          const text =
            item.kind === 'REASM' ? item.text : item.kind === 'RESTATE' ? item.words.join(' ') : '';
          for (const reference of text.matchAll(/\((\d)\)/g)) {
            const number = Number(reference[1]);
            if (number === 0 || number > wildcards) {
              add(item.line, 'REF_UNBOUND', `reference (${number}) is not bound`);
            }
          }
          if (item.kind === 'GOTO' || item.kind === 'RESTATE') {
            if (!script.keywords.has(item.target)) {
              add(item.line, 'TARGET_UNDEFINED', `target ${item.target} is not a keyword`);
            } else if (reachable(item.target, keyword.word)) {
              add(
                item.line,
                'TARGET_CYCLE',
                `edge ${keyword.word} -> ${item.target} is on a cycle`,
              );
            }
          }
        }
      }
    }
  }
  for (const group of script.groups.values()) {
    if (!rules.some((rule) => rule.pattern.includes('@' + group.name))) {
      add(group.line, 'SYNON_UNUSED', `group ${group.name} is never used`);
    }
  }
  for (const pre of script.pre.values()) {
    for (const word of pre.replacement) {
      if (script.pre.has(word)) {
        add(pre.line, 'PRE_CHAIN', `replacement ${word} is itself replaced by PRE`);
      }
    }
  }
  diagnostics.sort((a, b) => a.line - b.line || codes.indexOf(a.code) - codes.indexOf(b.code));
  if (!diagnostics.length) return ['OK'];
  const errorCount = diagnostics.filter((diagnostic) => errors.has(diagnostic.code)).length;
  return [
    ...diagnostics.map(
      (diagnostic) => `${diagnostic.line} ${diagnostic.code} ${diagnostic.message}`,
    ),
    `TOTAL ${diagnostics.length} errors=${errorCount} warnings=${diagnostics.length - errorCount}`,
  ];
}
