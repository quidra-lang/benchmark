import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { loadScript, type Keyword, type Rule, type Item } from './script_loader.ts';
import { lint } from './linter.ts';
import { match } from './matcher.ts';
import { reply, restate, reflect, wrap } from './responder.ts';
import { store, recall, clear, type Memory } from './memory.ts';

type Source = 'keyword' | 'memory' | 'question' | 'default' | 'repeat';
type CycleList = 'DEFAULT' | 'QUESTION' | 'REPEAT';
interface SourceCounts { keyword: number; memory: number; question: number; default: number; repeat: number }
interface RuleState { next: number; hits: number; uses: number[] }
interface KeywordState { uses: number; replies: number }
interface Session {
  name: string; turns: number; counts: SourceCounts; previous?: string[][]; history: string[];
  trace?: string[]; traceOn: boolean; topics: Map<string, number>; words: Map<string, number>;
  stored: number; recalled: number; unrecognized: number[]; undo?: State;
}
interface State {
  rules: Map<number, RuleState>; keywords: Map<string, KeywordState>; cycles: Record<CycleList, number>;
  memory: Memory; session: Session;
}
interface Selection { index: number; words: string[]; keywords: Keyword[] }
interface Decision { text: string; trace: string[] }
const script = loadScript('input/script.txt');
mkdirSync('output', { recursive: true });
writeFileSync('output/lint.txt', lint(script).join('\n') + '\n');
const transcript: string[] = [];
const sourceNames: Source[] = ['keyword', 'memory', 'question', 'default', 'repeat'];
const zeroCounts = (): SourceCounts => ({ keyword: 0, memory: 0, question: 0, default: 0, repeat: 0 });
function newSession(name: string): Session {
  return { name, turns: 0, counts: zeroCounts(), history: [], traceOn: false, topics: new Map(), words: new Map(), stored: 0, recalled: 0, unrecognized: [] };
}
let state: State = { rules: new Map(), keywords: new Map(), cycles: { DEFAULT: 0, QUESTION: 0, REPEAT: 0 },
  memory: { queue: [], log: [] }, session: newSession('') };
for (const keyword of script.keywords.values()) {
  state.keywords.set(keyword.word, { uses: 0, replies: 0 });
  for (const rule of [...keyword.memory, ...keyword.decomp]) state.rules.set(rule.line, { next: 0, hits: 0, uses: rule.items.map(() => 0) });
}
const ascii = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0;
function normalize(text: string): string[][] {
  return text.toLowerCase().split(/[,.?!;]/).map(part => part.replace(/[^a-z0-9']/g, ' ').split(' ')
    .map(word => word.replace(/^'+|'+$/g, '')).filter(Boolean)).filter(clause => clause.length > 0);
}
function prepare(text: string): string[][] {
  return normalize(text).map(clause => clause.flatMap(word => script.pre.get(word)?.replacement ?? [word]));
}
function quit(text: string): boolean {
  const words = normalize(text).flat(); return words.length === 1 && script.quit.has(words[0]);
}
function select(clauses: string[][]): Selection | undefined {
  for (let index = 0; index < clauses.length; index++) {
    const words = clauses[index], unique = [...new Set(words)];
    const keywords = unique.flatMap(word => { const keyword = script.keywords.get(word); return keyword ? [keyword] : []; });
    keywords.sort((a, b) => b.rank - a.rank || words.indexOf(a.word) - words.indexOf(b.word));
    if (keywords.length) return { index, words, keywords };
  }
  return undefined;
}
function cycleReset(): void {
  for (const rule of state.rules.values()) rule.next = 0;
  state.cycles = { DEFAULT: 0, QUESTION: 0, REPEAT: 0 };
}
function take(rule: Rule): { item: Item; index: number } {
  const stats = state.rules.get(rule.line)!, index = stats.next;
  stats.uses[index]++; stats.next = (index + 1) % rule.items.length;
  return { item: rule.items[index], index };
}
function takeText(list: CycleList): string {
  const index = state.cycles[list];
  state.cycles[list] = (index + 1) % script.texts[list].length;
  return script.texts[list][index];
}
function prefix(): string { return `${state.session.name} ${state.session.turns}`; }
function increment(counts: Map<string, number>, word: string): void { counts.set(word, (counts.get(word) ?? 0) + 1); }
function keywordReply(clauses: string[][], trace: string[]): string | undefined {
  const selection = select(clauses);
  if (!selection) { trace.push('CLAUSE none'); return undefined; }
  const { words, keywords, index } = selection;
  trace.push(`CLAUSE ${index + 1} ${words.join(' ')}`, `KEYS ${keywords.map(keyword => keyword.word).join(' ')}`);
  const first = keywords[0];
  for (let i = 0; i < first.memory.length; i++) {
    const rule = first.memory[i], bindings = match(rule.pattern, words, script.groups);
    if (bindings === undefined) continue;
    trace.push(`MEMORY ${first.word} ${i + 1}`); state.rules.get(rule.line)!.hits++;
    if (rule.items.length) {
      const { item } = take(rule);
      if (item.kind === 'REASM') {
        const text = reply(item.text, bindings, script.post);
        if (store(state.memory, script.capacity, prefix(), first.word, text)) state.session.stored++;
      }
    }
    break;
  }
  const entered = new Set<string>();
  for (const original of keywords) {
    if (entered.has(original.word)) continue;
    trace.push(`ENTER ${original.word}`);
    let keyword = original, currentWords = words;
    while (true) {
      entered.add(keyword.word); state.keywords.get(keyword.word)!.uses++;
      let found: { rule: Rule; index: number; bindings: string[][] } | undefined;
      for (let i = 0; i < keyword.decomp.length; i++) {
        const rule = keyword.decomp[i], bindings = match(rule.pattern, currentWords, script.groups);
        if (bindings !== undefined) { found = { rule, index: i, bindings }; break; }
      }
      if (!found) { trace.push(`NOMATCH ${keyword.word}`); break; }
      const { rule, index: ruleIndex, bindings } = found;
      state.rules.get(rule.line)!.hits++;
      if (!rule.items.length) { trace.push(`DECOMP ${keyword.word} ${ruleIndex + 1} 0`); break; }
      const { item, index: itemIndex } = take(rule);
      trace.push(`DECOMP ${keyword.word} ${ruleIndex + 1} ${itemIndex + 1}`);
      if (item.kind === 'REASM') {
        state.keywords.get(keyword.word)!.replies++; increment(state.session.topics, keyword.word);
        return reply(item.text, bindings, script.post);
      }
      if (item.kind === 'NEWKEY') break;
      const target = script.keywords.get(item.target);
      if (!target || entered.has(item.target)) { trace.push(`BLOCKED ${item.target}`); break; }
      if (item.kind === 'RESTATE') {
        currentWords = restate(item.words, bindings);
        trace.push(`RESTATE ${item.target}${currentWords.length ? ' ' + currentWords.join(' ') : ''}`);
      } else trace.push(`GOTO ${item.target}`);
      keyword = target;
    }
  }
  return undefined;
}
function decide(text: string): Decision {
  const clauses = normalize(text), trace: string[] = [];
  let response: string | undefined, source: Source;
  if (script.texts.REPEAT.length && clauses.length && JSON.stringify(clauses) === JSON.stringify(state.session.previous)) {
    trace.push('REPEAT'); response = takeText('REPEAT'); source = 'repeat';
  } else {
    response = keywordReply(clauses.map(clause => clause.flatMap(word => script.pre.get(word)?.replacement ?? [word])), trace);
    if (response !== undefined) source = 'keyword';
    else if (state.memory.queue.length) { response = recall(state.memory, prefix()); state.session.recalled++; source = 'memory'; }
    else if (text.endsWith('?') && script.texts.QUESTION.length) { response = takeText('QUESTION'); source = 'question'; }
    else { response = takeText('DEFAULT'); source = 'default'; }
  }
  trace.push(`REPLY ${source}`); state.session.previous = clauses; state.session.counts[source]++;
  if (source === 'question' || source === 'default') state.session.unrecognized.push(state.session.turns);
  return { text: response, trace };
}
function chunks(values: string[], size: number): string[] {
  const lines: string[] = [];
  for (let i = 0; i < values.length; i += size) lines.push(values.slice(i, i + size).join(' '));
  return lines;
}
function countLine(turns: number, counts: SourceCounts): string {
  return `turns=${turns} keyword=${counts.keyword} memory=${counts.memory} question=${counts.question} default=${counts.default} repeat=${counts.repeat}`;
}
function orderedRules(keyword: Keyword): { kind: 'memory' | 'decomp'; number: number; rule: Rule }[] {
  return [...keyword.memory.map((rule, i) => ({ kind: 'memory' as const, number: i + 1, rule })),
    ...keyword.decomp.map((rule, i) => ({ kind: 'decomp' as const, number: i + 1, rule }))];
}
function find(word: string): string[] {
  const lines: string[] = [], keyword = script.keywords.get(word);
  if (keyword) lines.push(`keyword rank ${keyword.rank}`);
  for (const [name, substitutions] of [['pre', script.pre], ['post', script.post]] as const)
    for (const substitution of substitutions.values()) if (substitution.source === word || substitution.replacement.includes(word))
      lines.push(`${name} ${substitution.line}: ${substitution.source} -> ${substitution.replacement.join(' ')}`);
  for (const group of script.groups.values()) if (group.members.has(word)) lines.push(`group ${group.name} line ${group.line}`);
  for (const keyword of script.keywords.values()) for (const { kind, number, rule } of orderedRules(keyword))
    if (rule.pattern.includes(word)) lines.push(`pattern ${keyword.word} ${kind} ${number}`);
  if (script.stop.has(word)) lines.push('stop word');
  if (script.quit.has(word)) lines.push('quit word');
  return lines.length ? lines : ['not found'];
}
function debug(line: string): string[] {
  const space = line.indexOf(' '), command = space < 0 ? line : line.slice(0, space), text = space < 0 ? '' : line.slice(space + 1);
  const args = text ? text.split(' ') : [];
  const noArgs = [':keys', ':why', ':history', ':memory', ':forget', ':reset', ':unused', ':stats', ':undo'];
  const textArgs = [':prepare', ':reflect', ':say', ':explain'];
  const oneArg = [':groups', ':find', ':script', ':cycles', ':coverage'];
  if (![...noArgs, ...textArgs, ...oneArg, ':trace', ':test'].includes(command)) return [`unknown command ${command}`];
  if (noArgs.includes(command) && args.length !== 0 || textArgs.includes(command) && !text
    || oneArg.includes(command) && args.length !== 1 || command === ':test' && args.length < 2
    || command === ':trace' && (args.length !== 1 || !['on', 'off'].includes(args[0]))) return ['bad arguments'];
  const keyword = script.keywords.get(args[0]);
  if ([':script', ':cycles', ':coverage', ':test'].includes(command) && !keyword) return [`unknown keyword ${args[0]}`];
  switch (command) {
    case ':prepare': {
      const clauses = prepare(text), selection = select(clauses);
      return [...(clauses.length ? clauses.map((clause, i) => `clause ${i + 1}: ${clause.join(' ')}`) : ['no words']),
        ...(selection ? [`selected ${selection.index + 1}`, `keys ${selection.keywords.map(keyword => `${keyword.word}/${keyword.rank}`).join(' ')}`] : ['selected none'])];
    }
    case ':test': {
      const words = prepare(text.slice(text.indexOf(' ') + 1)).flat();
      const lines = orderedRules(keyword!).map(({ kind, number, rule }) => {
        const bindings = match(rule.pattern, words, script.groups);
        const result = bindings === undefined ? 'no match' : !bindings.length ? 'match' : bindings.map(words => `[${words.join(' ')}]`).join(' ');
        return `${kind} ${number}: ${result}`;
      });
      return lines.length ? lines : ['no rules'];
    }
    case ':reflect': {
      const clauses = prepare(text); return clauses.length ? clauses.map(clause => reflect(clause, script.post).join(' ')) : ['no words'];
    }
    case ':keys': return chunks([...script.keywords.values()].sort((a, b) => b.rank - a.rank || ascii(a.word, b.word)).map(keyword => `${keyword.word}/${keyword.rank}`), 8);
    case ':groups': {
      const groups = [...script.groups.values()].filter(group => group.members.has(args[0])).map(group => group.name).sort();
      return [groups.length ? groups.join(' ') : 'none'];
    }
    case ':find': return find(args[0]);
    case ':script': {
      const lines = [keyword!.line, ...orderedRules(keyword!).flatMap(({ rule }) => [rule.line, ...rule.items.map(item => item.line)])].sort((a, b) => a - b);
      return lines.map(number => `${number} ${script.lines[number - 1]}`);
    }
    case ':why': return state.session.trace ?? ['no reply yet'];
    case ':trace': state.session.traceOn = args[0] === 'on'; return [`trace ${args[0]}`];
    case ':history': return state.session.history.length ? state.session.history.slice(-5) : ['no turns yet'];
    case ':memory': return [`memory ${state.memory.queue.length}/${script.capacity}`, ...state.memory.queue.map((text, i) => `${i + 1}: ${text}`)];
    case ':forget': return [`forgot ${clear(state.memory, prefix())}`];
    case ':cycles': {
      const lines = orderedRules(keyword!).map(({ kind, number, rule }) => `${kind} ${number}: ${rule.items.length ? `next ${state.rules.get(rule.line)!.next + 1}/${rule.items.length}` : 'empty'}`);
      return lines.length ? lines : ['no rules'];
    }
    case ':coverage': {
      const lines = orderedRules(keyword!).map(({ kind, number, rule }) => {
        const stats = state.rules.get(rule.line)!;
        return `${kind} ${number}: hits ${stats.hits} entries ${stats.uses.length ? stats.uses.join(' ') : '-'}`;
      });
      return lines.length ? lines : ['no rules'];
    }
    case ':reset': cycleReset(); return ['cycles reset'];
    case ':unused': {
      const lines = [...script.keywords.values()].flatMap(keyword => orderedRules(keyword).flatMap(({ rule }) =>
        rule.items.filter((_, i) => state.rules.get(rule.line)!.uses[i] === 0).map(item => item.line))).sort((a, b) => a - b);
      return [`unused ${lines.length}`, ...chunks(lines.map(String), 12)];
    }
    case ':stats': return [countLine(state.session.turns, state.session.counts)];
    case ':say': case ':explain': {
      if (quit(text)) return ['would quit'];
      const saved = structuredClone(state), decision = decide(text); state = saved;
      return command === ':say' ? [decision.text] : decision.trace;
    }
    case ':undo': {
      if (!state.session.undo) return ['nothing to undo'];
      state = state.session.undo; return [`undone turn ${state.session.turns + 1}`];
    }
  }
  return [];
}
function top(counts: Map<string, number>): string {
  const entries = [...counts].filter(([, count]) => count > 0).sort(([a, x], [b, y]) => y - x || ascii(a, b)).slice(0, 5);
  return entries.length ? entries.map(([word, count]) => `${word} ${count}`).join(', ') : 'none';
}
function notes(): string[] {
  const session = state.session;
  return [`NOTES ${session.name}`, `  ${countLine(session.turns, session.counts)}`, `  topics: ${top(session.topics)}`,
    `  words: ${top(session.words)}`, `  memory: stored=${session.stored} recalled=${session.recalled} pending=${state.memory.queue.length}`,
    `  unrecognized: ${session.unrecognized.length ? session.unrecognized.join(' ') : 'none'}`];
}

let sessions = 0, turns = 0;
const totalCounts = zeroCounts();
for (const line of readFileSync('input/dialogue.txt', 'utf8').split('\n').slice(0, -1)) {
  if (line.startsWith('SESSION ')) {
    if (sessions) transcript.push('');
    sessions++;
    const name = line.slice(8);
    if (!script.persist.has('cycles')) cycleReset();
    if (!script.persist.has('memory')) clear(state.memory, `${name} 0`);
    state.session = newSession(name);
    transcript.push(`SESSION ${name}`, ...wrap(script.texts.INITIAL[(sessions - 1) % script.texts.INITIAL.length]));
  } else if (line.startsWith(':')) {
    transcript.push(line, ...debug(line).map(output => '  ' + output));
  } else {
    transcript.push('YOU: ' + line);
    if (quit(line)) {
      transcript.push(...wrap(script.texts.FINAL[(sessions - 1) % script.texts.FINAL.length]), ...notes());
      turns += state.session.turns;
      for (const source of sourceNames) totalCounts[source] += state.session.counts[source];
      continue;
    }
    const snapshot = structuredClone(state); snapshot.session.undo = undefined; state.session.undo = snapshot;
    state.session.turns++;
    for (const word of normalize(line).flat()) if (!script.stop.has(word)) increment(state.session.words, word);
    state.session.history.push(`${state.session.turns}: ${line}`);
    const decision = decide(line); state.session.trace = decision.trace;
    transcript.push(...wrap(decision.text));
    if (state.session.traceOn) transcript.push(...decision.trace.map(trace => '  ' + trace));
  }
}
transcript.push('', `SUMMARY sessions=${sessions} ${countLine(turns, totalCounts)}`);
const statistics = ['keyword,rank,uses,replies,decomposition_hits', ...[...script.keywords.values()]
  .sort((a, b) => state.keywords.get(b.word)!.uses - state.keywords.get(a.word)!.uses || ascii(a.word, b.word))
  .map(keyword => {
    const stats = state.keywords.get(keyword.word)!;
    return `${keyword.word},${keyword.rank},${stats.uses},${stats.replies},${keyword.decomp.length ? keyword.decomp.map(rule => state.rules.get(rule.line)!.hits).join('/') : '-'}`;
  })];
for (const [name, lines] of [['transcript.txt', transcript], ['keyword_stats.csv', statistics], ['memory_log.txt', state.memory.log]] as const)
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '');
