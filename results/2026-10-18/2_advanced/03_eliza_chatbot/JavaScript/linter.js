const { wildcard, covers } = require('./matcher');

const CODES = [
  'SYNTAX', 'ORPHAN', 'DUPLICATE', 'KEY_NO_DECOMP', 'KEY_UNREACHABLE',
  'SYNON_UNUSED', 'PRE_CHAIN', 'SYNON_UNKNOWN', 'RULE_NO_REASM', 'RULE_SHADOWED',
  'REF_UNBOUND', 'TARGET_UNDEFINED', 'TARGET_CYCLE',
];
const ERRORS = new Set([
  'SYNTAX', 'ORPHAN', 'DUPLICATE', 'SYNON_UNKNOWN', 'REF_UNBOUND',
  'TARGET_UNDEFINED', 'TARGET_CYCLE',
]);

function lint(script) {
  const diagnostics = script.diagnostics.slice();
  function report(line, code, message, position = 0) {
    diagnostics.push({ line, code, message, position });
  }
  const movedTo = new Set();
  const graph = new Map(script.keywords.map(keyword => [keyword.word, new Set()]));
  for (const rule of script.rules) {
    for (const item of rule.items) {
      if (item.kind !== 'GOTO' && item.kind !== 'RESTATE') continue;
      const target = item.args[0];
      movedTo.add(target);
      if (script.keywordByWord.has(target)) graph.get(rule.keyword.word).add(target);
    }
  }
  const reachable = new Map();
  for (const keyword of script.keywords) {
    const seen = new Set();
    const pending = [keyword.word];
    while (pending.length > 0) {
      const word = pending.pop();
      if (seen.has(word)) continue;
      seen.add(word);
      pending.push(...graph.get(word));
    }
    reachable.set(keyword.word, seen);
  }
  const replacements = new Set([...script.pre.values()].flatMap(entry => entry.replacement));
  for (const keyword of script.keywords) {
    if (keyword.decomp.length === 0) {
      report(keyword.line, 'KEY_NO_DECOMP', `keyword ${keyword.word} has no DECOMP`);
    }
    if (script.pre.has(keyword.word) && !replacements.has(keyword.word) && !movedTo.has(keyword.word)) {
      report(keyword.line, 'KEY_UNREACHABLE', `keyword ${keyword.word} is replaced by PRE`);
    }
  }
  const usedGroups = new Set();
  for (const rule of script.rules) {
    for (const element of rule.pattern) {
      if (element.startsWith('@')) usedGroups.add(element.slice(1));
    }
  }
  for (const group of script.groups.values()) {
    if (!usedGroups.has(group.name)) {
      report(group.line, 'SYNON_UNUSED', `group ${group.name} is never used`);
    }
  }
  for (const entry of script.pre.values()) {
    entry.replacement.forEach((word, position) => {
      if (script.pre.has(word)) {
        report(entry.line, 'PRE_CHAIN', `replacement ${word} is itself replaced by PRE`, position);
      }
    });
  }
  const hasUnknownGroup = rule => rule.pattern.some(element =>
    element.startsWith('@') && !script.groups.has(element.slice(1)));
  for (const keyword of script.keywords) {
    for (const rules of [keyword.memory, keyword.decomp]) {
      for (let index = 0; index < rules.length; index += 1) {
        const rule = rules[index];
        rule.pattern.forEach((element, position) => {
          if (element.startsWith('@') && !script.groups.has(element.slice(1))) {
            report(rule.line, 'SYNON_UNKNOWN', `unknown group ${element.slice(1)}`, position);
          }
        });
        if (rule.items.length === 0) report(rule.line, 'RULE_NO_REASM', 'rule has no reassembly');
        if (!hasUnknownGroup(rule)) {
          const previous = rules.slice(0, index).find(candidate =>
            !hasUnknownGroup(candidate) && covers(candidate.pattern, rule.pattern, script.groups));
          if (previous) {
            report(rule.line, 'RULE_SHADOWED', `pattern is shadowed by line ${previous.line}`);
          }
        }
        const bound = rule.pattern.filter(wildcard).length;
        for (const item of rule.items) {
          if (item.kind === 'REASM' || item.kind === 'RESTATE') {
            const text = item.kind === 'REASM' ? item.text : item.args.slice(1).join(' ');
            for (const reference of text.matchAll(/\(([0-9])\)/g)) {
              const number = Number(reference[1]);
              if (number === 0 || number > bound) {
                report(item.line, 'REF_UNBOUND', `reference (${number}) is not bound`, reference.index);
              }
            }
          }
          if (item.kind === 'GOTO' || item.kind === 'RESTATE') {
            const target = item.args[0];
            if (!script.keywordByWord.has(target)) {
              report(item.line, 'TARGET_UNDEFINED', `target ${target} is not a keyword`);
            } else if (reachable.get(target).has(keyword.word)) {
              report(item.line, 'TARGET_CYCLE', `edge ${keyword.word} -> ${target} is on a cycle`);
            }
          }
        }
      }
    }
  }
  diagnostics.sort((first, second) => first.line - second.line
    || CODES.indexOf(first.code) - CODES.indexOf(second.code) || first.position - second.position);
  if (diagnostics.length === 0) return ['OK'];
  const lines = diagnostics.map(entry => `${entry.line} ${entry.code} ${entry.message}`);
  const errors = diagnostics.filter(entry => ERRORS.has(entry.code)).length;
  lines.push(`TOTAL ${diagnostics.length} errors=${errors} warnings=${diagnostics.length - errors}`);
  return lines;
}

module.exports = { lint };
