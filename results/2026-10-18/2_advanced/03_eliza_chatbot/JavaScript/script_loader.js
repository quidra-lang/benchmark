const fs = require('node:fs');

const GLOBALS = new Set([
  'INITIAL', 'FINAL', 'QUIT', 'STOP', 'DEFAULT', 'QUESTION', 'REPEAT',
  'MEMSIZE', 'PERSIST', 'PRE', 'POST', 'SYNON',
]);
const TEXTS = new Set(['INITIAL', 'FINAL', 'DEFAULT', 'QUESTION', 'REPEAT', 'REASM']);
const RULES = new Set(['DECOMP', 'MEMORY']);
const ITEMS = new Set(['REASM', 'GOTO', 'NEWKEY', 'RESTATE']);
const DIRECTIVES = new Set([...GLOBALS, 'KEY', ...RULES, ...ITEMS]);

function isWord(text) {
  return /^[a-z0-9](?:[a-z0-9']*[a-z0-9])?$/.test(text);
}

function isReference(text) {
  return /^\([0-9]\)$/.test(text);
}

function isElement(text) {
  return text === '*' || text === '#' || isWord(text)
    || text.startsWith('@') && isWord(text.slice(1));
}

function validArguments(name, args) {
  if (TEXTS.has(name)) return args.length >= 1;
  if (name === 'QUIT' || name === 'STOP') return args.length >= 1 && args.every(isWord);
  if (name === 'PRE' || name === 'SYNON') return args.length >= 2 && args.every(isWord);
  if (name === 'POST') return args.length >= 2 && isWord(args[0]);
  if (name === 'KEY') {
    return args.length === 2 && isWord(args[0]) && /^[0-9]{1,2}$/.test(args[1]);
  }
  if (name === 'MEMSIZE') {
    return args.length === 1 && /^[0-9]{1,2}$/.test(args[0])
      && Number(args[0]) >= 1 && Number(args[0]) <= 20;
  }
  if (name === 'PERSIST') return args.length === 1 && ['cycles', 'memory'].includes(args[0]);
  if (RULES.has(name)) return args.length >= 1 && args.every(isElement);
  if (name === 'GOTO') return args.length === 1 && isWord(args[0]);
  if (name === 'NEWKEY') return args.length === 0;
  if (name === 'RESTATE') {
    return args.length >= 2 && isWord(args[0])
      && args.slice(1).every(argument => isWord(argument) || isReference(argument));
  }
  return false;
}

function readLines(path) {
  const text = fs.readFileSync(path, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}

function loadScript(path) {
  const script = {
    texts: { INITIAL: [], FINAL: [], DEFAULT: [], QUESTION: [], REPEAT: [] },
    quit: new Set(), stop: new Set(), capacity: 3, capacityLine: null,
    persistence: new Map(), pre: new Map(), post: new Map(), groups: new Map(),
    keywords: [], keywordByWord: new Map(), rules: [], diagnostics: [],
  };
  let keyword = null;
  let rule = null;
  const ignoring = Symbol('ignoring duplicate keyword');
  const lines = readLines(path);
  for (let index = 0; index < lines.length; index += 1) {
    const raw = lines[index];
    if (raw === '' || raw.startsWith('#')) continue;
    const [name, ...args] = raw.split(' ');
    const line = index + 1;
    const text = args.join(' ');
    if (GLOBALS.has(name) || name === 'KEY') {
      keyword = null;
      rule = null;
    } else if (RULES.has(name)) {
      if (keyword === ignoring) continue;
      rule = null;
    } else if (ITEMS.has(name) && keyword === ignoring) {
      continue;
    }
    const report = (code, message) => script.diagnostics.push({ line, code, message, position: 0 });
    if (!DIRECTIVES.has(name)) {
      report('SYNTAX', `unknown directive ${name}`);
      continue;
    }
    if (!validArguments(name, args)) {
      report('SYNTAX', `bad arguments for ${name}`);
      continue;
    }
    if (RULES.has(name) && keyword === null) {
      report('ORPHAN', `${name} without KEY`);
      continue;
    }
    if (name === 'REASM' && rule === null) {
      report('ORPHAN', 'REASM without DECOMP or MEMORY');
      continue;
    }
    if (['GOTO', 'NEWKEY', 'RESTATE'].includes(name) && (rule === null || rule.kind === 'memory')) {
      report('ORPHAN', `${name} without DECOMP`);
      continue;
    }
    let firstLine = null;
    if (name === 'KEY') firstLine = script.keywordByWord.get(args[0])?.line ?? null;
    if (name === 'SYNON') firstLine = script.groups.get(args[0])?.line ?? null;
    if (name === 'PRE') firstLine = script.pre.get(args[0])?.line ?? null;
    if (name === 'POST') firstLine = script.post.get(args[0])?.line ?? null;
    if (name === 'PERSIST') firstLine = script.persistence.get(args[0]) ?? null;
    if (name === 'MEMSIZE') firstLine = script.capacityLine;
    if (firstLine !== null) {
      const subject = name === 'MEMSIZE' ? name : `${name} ${args[0]}`;
      report('DUPLICATE', `${subject} first defined at line ${firstLine}`);
      if (name === 'KEY') keyword = ignoring;
      continue;
    }
    if (Object.hasOwn(script.texts, name)) {
      script.texts[name].push(text);
    } else if (name === 'QUIT' || name === 'STOP') {
      const set = name === 'QUIT' ? script.quit : script.stop;
      for (const word of args) set.add(word);
    } else if (name === 'MEMSIZE') {
      script.capacity = Number(args[0]);
      script.capacityLine = line;
    } else if (name === 'PERSIST') {
      script.persistence.set(args[0], line);
    } else if (name === 'PRE' || name === 'POST') {
      const table = name === 'PRE' ? script.pre : script.post;
      table.set(args[0], { source: args[0], replacement: args.slice(1), line });
    } else if (name === 'SYNON') {
      script.groups.set(args[0], { name: args[0], members: new Set(args), line });
    } else if (name === 'KEY') {
      keyword = { id: script.keywords.length, word: args[0], rank: Number(args[1]), line, raw,
        memory: [], decomp: [] };
      script.keywords.push(keyword);
      script.keywordByWord.set(keyword.word, keyword);
    } else if (RULES.has(name)) {
      const kind = name === 'MEMORY' ? 'memory' : 'decomp';
      rule = { id: script.rules.length, kind, number: keyword[kind].length + 1,
        pattern: args, line, raw, items: [], keyword };
      keyword[kind].push(rule);
      script.rules.push(rule);
    } else {
      rule.items.push({ kind: name, number: rule.items.length + 1, line, raw, text, args });
    }
  }
  return script;
}

module.exports = { loadScript, readLines, isWord, isReference };
