import { readFileSync } from 'node:fs';

export type Item = { line: number } & ({ kind: 'REASM'; text: string } | { kind: 'GOTO'; target: string }
  | { kind: 'NEWKEY' } | { kind: 'RESTATE'; target: string; words: string[] });
export interface Rule { line: number; pattern: string[]; items: Item[] }
export interface Keyword { word: string; rank: number; line: number; memory: Rule[]; decomp: Rule[] }
export interface Substitution { line: number; source: string; replacement: string[] }
export interface Group { line: number; name: string; members: Set<string> }
export interface Diagnostic { line: number; code: string; message: string }
export type TextList = 'INITIAL' | 'FINAL' | 'DEFAULT' | 'QUESTION' | 'REPEAT';
export interface Script {
  lines: string[]; texts: Record<TextList, string[]>; quit: Set<string>; stop: Set<string>;
  capacity: number; persist: Map<string, number>; pre: Map<string, Substitution>; post: Map<string, Substitution>;
  groups: Map<string, Group>; keywords: Map<string, Keyword>; diagnostics: Diagnostic[];
}
export function isWord(value: string): boolean { return /^[a-z0-9](?:[a-z0-9']*[a-z0-9])?$/.test(value); }
export function isReference(value: string): boolean { return /^\(\d\)$/.test(value); }
export function isWildcard(value: string): boolean { return value === '*' || value === '#' || value.startsWith('@'); }
const globals = new Set(['INITIAL', 'FINAL', 'QUIT', 'STOP', 'DEFAULT', 'QUESTION', 'REPEAT', 'MEMSIZE', 'PERSIST', 'PRE', 'POST', 'SYNON']);
const directives = new Set([...globals, 'KEY', 'DECOMP', 'MEMORY', 'REASM', 'GOTO', 'NEWKEY', 'RESTATE']);
function isTextList(name: string): name is TextList { return ['INITIAL', 'FINAL', 'DEFAULT', 'QUESTION', 'REPEAT'].includes(name); }
function wellFormed(name: string, args: string[]): boolean {
  if (isTextList(name) || name === 'REASM') return args.length >= 1;
  if (name === 'QUIT' || name === 'STOP') return args.length >= 1 && args.every(isWord);
  if (name === 'MEMSIZE') return args.length === 1 && /^\d{1,2}$/.test(args[0]) && Number(args[0]) >= 1 && Number(args[0]) <= 20;
  if (name === 'PERSIST') return args.length === 1 && ['cycles', 'memory'].includes(args[0]);
  if (name === 'PRE' || name === 'SYNON') return args.length >= 2 && args.every(isWord);
  if (name === 'POST') return args.length >= 2 && isWord(args[0]);
  if (name === 'KEY') return args.length === 2 && isWord(args[0]) && /^\d{1,2}$/.test(args[1]);
  if (name === 'DECOMP' || name === 'MEMORY') return args.length >= 1 && args.every(value => value === '*' || value === '#' || isWord(value) || value.startsWith('@') && isWord(value.slice(1)));
  if (name === 'GOTO') return args.length === 1 && isWord(args[0]);
  if (name === 'NEWKEY') return args.length === 0;
  if (name === 'RESTATE') return args.length >= 2 && isWord(args[0]) && args.slice(1).every(value => isWord(value) || isReference(value));
  return false;
}
export function loadScript(path: string): Script {
  const script: Script = { lines: readFileSync(path, 'utf8').split('\n').slice(0, -1),
    texts: { INITIAL: [], FINAL: [], DEFAULT: [], QUESTION: [], REPEAT: [] }, quit: new Set(), stop: new Set(),
    capacity: 3, persist: new Map(), pre: new Map(), post: new Map(), groups: new Map(), keywords: new Map(), diagnostics: [] };
  let current: Keyword | 'ignoring' | undefined, rule: Rule | undefined, memoryRule = false, memsizeLine: number | undefined;
  for (let index = 0; index < script.lines.length; index++) {
    const original = script.lines[index];
    if (!original || original.startsWith('#')) continue;
    const [name, ...args] = original.split(' '), line = index + 1;
    const diagnostic = (code: string, message: string) => script.diagnostics.push({ line, code, message });
    if (globals.has(name) || name === 'KEY') { current = undefined; rule = undefined; }
    else if (name === 'DECOMP' || name === 'MEMORY') {
      if (current === 'ignoring') continue;
      rule = undefined;
    } else if (['REASM', 'GOTO', 'NEWKEY', 'RESTATE'].includes(name) && current === 'ignoring') continue;
    if (!directives.has(name)) { diagnostic('SYNTAX', `unknown directive ${name}`); continue; }
    if (!wellFormed(name, args)) { diagnostic('SYNTAX', `bad arguments for ${name}`); continue; }
    if ((name === 'DECOMP' || name === 'MEMORY') && current === undefined) { diagnostic('ORPHAN', `${name} without KEY`); continue; }
    if (name === 'REASM' && !rule) { diagnostic('ORPHAN', 'REASM without DECOMP or MEMORY'); continue; }
    if (['GOTO', 'NEWKEY', 'RESTATE'].includes(name) && (!rule || memoryRule)) { diagnostic('ORPHAN', `${name} without DECOMP`); continue; }
    let first: number | undefined;
    if (name === 'KEY') first = script.keywords.get(args[0])?.line;
    else if (name === 'SYNON') first = script.groups.get(args[0])?.line;
    else if (name === 'PRE') first = script.pre.get(args[0])?.line;
    else if (name === 'POST') first = script.post.get(args[0])?.line;
    else if (name === 'PERSIST') first = script.persist.get(args[0]);
    else if (name === 'MEMSIZE') first = memsizeLine;
    if (first !== undefined) {
      diagnostic('DUPLICATE', `${name}${name === 'MEMSIZE' ? '' : ' ' + args[0]} first defined at line ${first}`);
      if (name === 'KEY') current = 'ignoring';
      continue;
    }
    const text = original.slice(name.length + 1);
    if (isTextList(name)) script.texts[name].push(text);
    else if (name === 'QUIT' || name === 'STOP') for (const word of args) (name === 'QUIT' ? script.quit : script.stop).add(word);
    else if (name === 'MEMSIZE') { script.capacity = Number(args[0]); memsizeLine = line; }
    else if (name === 'PERSIST') script.persist.set(args[0], line);
    else if (name === 'PRE' || name === 'POST') (name === 'PRE' ? script.pre : script.post).set(args[0], { line, source: args[0], replacement: args.slice(1) });
    else if (name === 'SYNON') script.groups.set(args[0], { line, name: args[0], members: new Set(args) });
    else if (name === 'KEY') {
      current = { line, word: args[0], rank: Number(args[1]), memory: [], decomp: [] };
      script.keywords.set(args[0], current);
    } else if ((name === 'DECOMP' || name === 'MEMORY') && current && current !== 'ignoring') {
      rule = { line, pattern: args, items: [] }; memoryRule = name === 'MEMORY';
      (memoryRule ? current.memory : current.decomp).push(rule);
    } else if (rule) {
      if (name === 'REASM') rule.items.push({ line, kind: name, text });
      else if (name === 'GOTO') rule.items.push({ line, kind: name, target: args[0] });
      else if (name === 'NEWKEY') rule.items.push({ line, kind: name });
      else if (name === 'RESTATE') rule.items.push({ line, kind: name, target: args[0], words: args.slice(1) });
    }
  }
  return script;
}
