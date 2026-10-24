const fs = require('node:fs');
const { loadScript, readLines } = require('./script_loader');
const { lint } = require('./linter');
const { match } = require('./matcher');
const { reflect, buildReply, restate, wrapReply } = require('./responder');
const memory = require('./memory');

const SOURCES = ['keyword', 'memory', 'question', 'default', 'repeat'];
const NO_ARGUMENT = new Set([
  ':keys', ':why', ':history', ':memory', ':forget', ':reset', ':unused', ':stats', ':undo',
]);
const TEXT_ARGUMENT = new Set([':prepare', ':reflect', ':say', ':explain']);
const ONE_ARGUMENT = new Set([':groups', ':find', ':script', ':cycles', ':coverage']);
const KEYWORD_ARGUMENT = new Set([':script', ':cycles', ':coverage', ':test']);
const COMMANDS = new Set([...NO_ARGUMENT, ...TEXT_ARGUMENT, ...ONE_ARGUMENT, ':trace', ':test']);

function compareWords(first, second) {
  return Number(first > second) - Number(first < second);
}

function normalize(text) {
  const clauses = [];
  for (const part of text.toLowerCase().split(/[,.?!;]/)) {
    const words = (part.match(/[a-z0-9']+/g) ?? [])
      .map(word => word.replace(/^'+|'+$/g, ''))
      .filter(word => word.length > 0);
    if (words.length > 0) clauses.push(words);
  }
  return clauses;
}

function sameClauses(first, second) {
  return first !== null && first.length === second.length
    && first.every((clause, index) => clause.length === second[index].length
      && clause.every((word, position) => word === second[index][position]));
}

function sourceCounts() {
  return Object.fromEntries(SOURCES.map(source => [source, 0]));
}

function increment(table, name) {
  table.set(name, (table.get(name) ?? 0) + 1);
}

function countLine(record) {
  return `turns=${record.turns} ` + SOURCES.map(source => `${source}=${record.sources[source]}`).join(' ');
}

function leaders(table) {
  const entries = [...table].filter(([, count]) => count > 0);
  entries.sort((first, second) => second[1] - first[1] || compareWords(first[0], second[0]));
  return entries.slice(0, 5).map(([word, count]) => `${word} ${count}`).join(', ') || 'none';
}

function chunkLines(values, size) {
  const lines = [];
  for (let start = 0; start < values.length; start += size) {
    lines.push(values.slice(start, start + size).join(' '));
  }
  return lines;
}

class Chatbot {
  constructor(script) {
    this.script = script;
    this.transcript = [];
    this.state = {
      rules: script.rules.map(rule => ({ next: 0, hits: 0, uses: rule.items.map(() => 0) })),
      keywords: script.keywords.map(() => ({ uses: 0, replies: 0 })),
      cycles: { DEFAULT: 0, QUESTION: 0, REPEAT: 0 },
      memory: { queue: [], log: [] },
      session: null,
      summary: { sessions: 0, turns: 0, sources: sourceCounts() },
    };
  }

  preSubstitute(clauses) {
    return clauses.map(clause => clause.flatMap(word => this.script.pre.get(word)?.replacement ?? [word]));
  }

  isQuit(clauses) {
    const words = clauses.flat();
    return words.length === 1 && this.script.quit.has(words[0]);
  }

  resetCycles() {
    for (const rule of this.state.rules) rule.next = 0;
    for (const name of Object.keys(this.state.cycles)) this.state.cycles[name] = 0;
  }

  takeItem(rule) {
    const position = this.state.rules[rule.id];
    const item = rule.items[position.next];
    position.uses[position.next] += 1;
    position.next = (position.next + 1) % rule.items.length;
    return item;
  }

  takeText(name) {
    const list = this.script.texts[name];
    const index = this.state.cycles[name];
    this.state.cycles[name] = (index + 1) % list.length;
    return list[index];
  }

  selectClause(clauses) {
    for (let index = 0; index < clauses.length; index += 1) {
      const words = clauses[index];
      const positions = new Map();
      words.forEach((word, position) => {
        if (this.script.keywordByWord.has(word) && !positions.has(word)) positions.set(word, position);
      });
      if (positions.size === 0) continue;
      const keywords = [...positions.keys()].map(word => this.script.keywordByWord.get(word));
      keywords.sort((first, second) => second.rank - first.rank
        || positions.get(first.word) - positions.get(second.word));
      return { number: index + 1, words, keywords };
    }
    return null;
  }

  applyMemoryRules(keyword, words, trace) {
    for (const rule of keyword.memory) {
      const bindings = match(rule.pattern, words, this.script.groups);
      if (bindings === null) continue;
      trace.push(`MEMORY ${keyword.word} ${rule.number}`);
      this.state.rules[rule.id].hits += 1;
      if (rule.items.length > 0) {
        const item = this.takeItem(rule);
        const text = buildReply(item.text, bindings, this.script.post);
        memory.store(this.state.memory, this.state.session, this.script.capacity, keyword.word, text);
      }
      return;
    }
  }

  keywordReply(clauses, trace) {
    const selected = this.selectClause(clauses);
    if (selected === null) {
      trace.push('CLAUSE none');
      return null;
    }
    const { words, keywords } = selected;
    trace.push(`CLAUSE ${selected.number} ${words.join(' ')}`);
    trace.push(`KEYS ${keywords.map(keyword => keyword.word).join(' ')}`);
    this.applyMemoryRules(keywords[0], words, trace);
    const entered = new Set();
    for (const initial of keywords) {
      if (entered.has(initial.word)) continue;
      trace.push(`ENTER ${initial.word}`);
      let keyword = initial;
      let currentWords = words;
      while (true) {
        entered.add(keyword.word);
        this.state.keywords[keyword.id].uses += 1;
        let chosen = null;
        let bindings = null;
        for (const rule of keyword.decomp) {
          bindings = match(rule.pattern, currentWords, this.script.groups);
          if (bindings !== null) {
            chosen = rule;
            break;
          }
        }
        if (chosen === null) {
          trace.push(`NOMATCH ${keyword.word}`);
          break;
        }
        this.state.rules[chosen.id].hits += 1;
        if (chosen.items.length === 0) {
          trace.push(`DECOMP ${keyword.word} ${chosen.number} 0`);
          break;
        }
        const item = this.takeItem(chosen);
        trace.push(`DECOMP ${keyword.word} ${chosen.number} ${item.number}`);
        if (item.kind === 'REASM') {
          const reply = buildReply(item.text, bindings, this.script.post);
          this.state.keywords[keyword.id].replies += 1;
          increment(this.state.session.topics, keyword.word);
          return reply;
        }
        if (item.kind === 'NEWKEY') break;
        const target = this.script.keywordByWord.get(item.args[0]);
        if (target === undefined || entered.has(target.word)) {
          trace.push(`BLOCKED ${item.args[0]}`);
          break;
        }
        if (item.kind === 'RESTATE') {
          currentWords = restate(item.args.slice(1), bindings);
          trace.push(`RESTATE ${target.word}` + (currentWords.length > 0 ? ` ${currentWords.join(' ')}` : ''));
        } else {
          trace.push(`GOTO ${target.word}`);
        }
        keyword = target;
      }
    }
    return null;
  }

  decide(text, clauses = normalize(text)) {
    const trace = [];
    const session = this.state.session;
    let reply;
    let source;
    if (this.script.texts.REPEAT.length > 0 && clauses.length > 0 && sameClauses(session.previous, clauses)) {
      trace.push('REPEAT');
      reply = this.takeText('REPEAT');
      source = 'repeat';
    } else {
      reply = this.keywordReply(this.preSubstitute(clauses), trace);
      if (reply !== null) {
        source = 'keyword';
      } else if (this.state.memory.queue.length > 0) {
        reply = memory.recall(this.state.memory, session);
        source = 'memory';
      } else if (text.endsWith('?') && this.script.texts.QUESTION.length > 0) {
        reply = this.takeText('QUESTION');
        source = 'question';
      } else {
        reply = this.takeText('DEFAULT');
        source = 'default';
      }
    }
    trace.push(`REPLY ${source}`);
    session.previous = clauses;
    session.sources[source] += 1;
    if (source === 'question' || source === 'default') session.unrecognized.push(session.turns);
    return { reply, trace };
  }

  startSession(name) {
    if (this.state.summary.sessions > 0) this.transcript.push('');
    if (!this.script.persistence.has('cycles')) this.resetCycles();
    if (!this.script.persistence.has('memory')) memory.clear(this.state.memory, name, 0);
    this.state.session = {
      name, turns: 0, sources: sourceCounts(), previous: null, history: [], lastTrace: null,
      traceDisplay: false, topics: new Map(), words: new Map(), stored: 0, recalled: 0,
      unrecognized: [], undo: null,
    };
    this.transcript.push(`SESSION ${name}`);
    const initial = this.script.texts.INITIAL;
    this.transcript.push(...wrapReply(initial[this.state.summary.sessions % initial.length]));
  }

  finishSession() {
    const session = this.state.session;
    this.transcript.push(`NOTES ${session.name}`);
    this.transcript.push(`  ${countLine(session)}`);
    this.transcript.push(`  topics: ${leaders(session.topics)}`);
    this.transcript.push(`  words: ${leaders(session.words)}`);
    this.transcript.push(`  memory: stored=${session.stored} recalled=${session.recalled} pending=${this.state.memory.queue.length}`);
    this.transcript.push(`  unrecognized: ${session.unrecognized.join(' ') || 'none'}`);
    const summary = this.state.summary;
    summary.sessions += 1;
    summary.turns += session.turns;
    for (const source of SOURCES) summary.sources[source] += session.sources[source];
  }

  utterance(text) {
    this.transcript.push(`YOU: ${text}`);
    const clauses = normalize(text);
    if (this.isQuit(clauses)) {
      const finals = this.script.texts.FINAL;
      this.transcript.push(...wrapReply(finals[this.state.summary.sessions % finals.length]));
      this.finishSession();
      return;
    }
    const snapshot = structuredClone(this.state);
    snapshot.session.undo = null;
    const session = this.state.session;
    session.undo = snapshot;
    session.turns += 1;
    for (const clause of clauses) {
      for (const word of clause) {
        if (!this.script.stop.has(word)) increment(session.words, word);
      }
    }
    session.history.push(`${session.turns}: ${text}`);
    const result = this.decide(text, clauses);
    this.transcript.push(...wrapReply(result.reply));
    session.lastTrace = result.trace;
    if (session.traceDisplay) this.transcript.push(...result.trace.map(line => `  ${line}`));
  }

  prepare(text) {
    const clauses = this.preSubstitute(normalize(text));
    const lines = clauses.length > 0
      ? clauses.map((clause, index) => `clause ${index + 1}: ${clause.join(' ')}`) : ['no words'];
    const selected = this.selectClause(clauses);
    if (selected === null) {
      lines.push('selected none');
    } else {
      lines.push(`selected ${selected.number}`);
      lines.push(`keys ${selected.keywords.map(keyword => `${keyword.word}/${keyword.rank}`).join(' ')}`);
    }
    return lines;
  }

  keywordRules(keyword) {
    return [...keyword.memory, ...keyword.decomp];
  }

  testRules(keyword, text) {
    const words = this.preSubstitute(normalize(text)).flat();
    const lines = [];
    for (const rule of this.keywordRules(keyword)) {
      const bindings = match(rule.pattern, words, this.script.groups);
      let result = 'no match';
      if (bindings !== null) {
        result = bindings.length === 0 ? 'match'
          : bindings.map(binding => `[${binding.join(' ')}]`).join(' ');
      }
      lines.push(`${rule.kind} ${rule.number}: ${result}`);
    }
    return lines.length > 0 ? lines : ['no rules'];
  }

  findWord(word) {
    const lines = [];
    const keyword = this.script.keywordByWord.get(word);
    if (keyword !== undefined) lines.push(`keyword rank ${keyword.rank}`);
    for (const [kind, table] of [['pre', this.script.pre], ['post', this.script.post]]) {
      for (const entry of table.values()) {
        if (entry.source === word || entry.replacement.includes(word)) {
          lines.push(`${kind} ${entry.line}: ${entry.source} -> ${entry.replacement.join(' ')}`);
        }
      }
    }
    for (const group of this.script.groups.values()) {
      if (group.members.has(word)) lines.push(`group ${group.name} line ${group.line}`);
    }
    for (const entry of this.script.keywords) {
      for (const rule of this.keywordRules(entry)) {
        if (rule.pattern.includes(word)) lines.push(`pattern ${entry.word} ${rule.kind} ${rule.number}`);
      }
    }
    if (this.script.stop.has(word)) lines.push('stop word');
    if (this.script.quit.has(word)) lines.push('quit word');
    return lines.length > 0 ? lines : ['not found'];
  }

  scriptLines(keyword) {
    const entries = [keyword];
    for (const rule of this.keywordRules(keyword)) entries.push(rule, ...rule.items);
    entries.sort((first, second) => first.line - second.line);
    return entries.map(entry => `${entry.line} ${entry.raw}`);
  }

  ruleStatistics(keyword, coverage) {
    const lines = [];
    for (const rule of this.keywordRules(keyword)) {
      const state = this.state.rules[rule.id];
      let detail;
      if (coverage) {
        detail = `hits ${state.hits} entries ${state.uses.join(' ') || '-'}`;
      } else {
        detail = rule.items.length === 0 ? 'empty' : `next ${state.next + 1}/${rule.items.length}`;
      }
      lines.push(`${rule.kind} ${rule.number}: ${detail}`);
    }
    return lines.length > 0 ? lines : ['no rules'];
  }

  unusedItems() {
    const unused = [];
    for (const rule of this.script.rules) {
      rule.items.forEach((item, index) => {
        if (this.state.rules[rule.id].uses[index] === 0) unused.push(item.line);
      });
    }
    unused.sort((first, second) => first - second);
    return [`unused ${unused.length}`, ...chunkLines(unused, 12)];
  }

  preview(text, explain) {
    const clauses = normalize(text);
    if (this.isQuit(clauses)) return ['would quit'];
    const saved = structuredClone(this.state);
    try {
      const result = this.decide(text, clauses);
      return explain ? result.trace : [result.reply];
    } finally {
      this.state = saved;
    }
  }

  command(line) {
    const space = line.indexOf(' ');
    const name = space < 0 ? line : line.slice(0, space);
    const argument = space < 0 ? '' : line.slice(space + 1);
    const args = argument === '' ? [] : argument.split(' ');
    if (!COMMANDS.has(name)) return [`unknown command ${name}`];
    if (NO_ARGUMENT.has(name) && args.length > 0
        || TEXT_ARGUMENT.has(name) && argument === ''
        || ONE_ARGUMENT.has(name) && args.length !== 1
        || name === ':trace' && (args.length !== 1 || !['on', 'off'].includes(args[0]))
        || name === ':test' && args.length < 2) return ['bad arguments'];
    const keyword = this.script.keywordByWord.get(args[0]);
    if (KEYWORD_ARGUMENT.has(name) && keyword === undefined) return [`unknown keyword ${args[0]}`];
    const session = this.state.session;
    if (name === ':prepare') return this.prepare(argument);
    if (name === ':test') return this.testRules(keyword, argument.slice(argument.indexOf(' ') + 1));
    if (name === ':reflect') {
      const clauses = this.preSubstitute(normalize(argument));
      return clauses.length > 0 ? clauses.map(clause => reflect(clause, this.script.post).join(' ')) : ['no words'];
    }
    if (name === ':keys') {
      const keywords = this.script.keywords.slice().sort((first, second) =>
        second.rank - first.rank || compareWords(first.word, second.word));
      return chunkLines(keywords.map(entry => `${entry.word}/${entry.rank}`), 8);
    }
    if (name === ':groups') {
      const groups = [...this.script.groups.values()].filter(group => group.members.has(argument));
      return [groups.map(group => group.name).sort(compareWords).join(' ') || 'none'];
    }
    if (name === ':find') return this.findWord(argument);
    if (name === ':script') return this.scriptLines(keyword);
    if (name === ':why') return session.lastTrace ?? ['no reply yet'];
    if (name === ':trace') {
      session.traceDisplay = argument === 'on';
      return [`trace ${argument}`];
    }
    if (name === ':history') return session.history.length > 0 ? session.history.slice(-5) : ['no turns yet'];
    if (name === ':memory') {
      const queue = this.state.memory.queue;
      return [`memory ${queue.length}/${this.script.capacity}`, ...queue.map((text, index) => `${index + 1}: ${text}`)];
    }
    if (name === ':forget') return [`forgot ${memory.clear(this.state.memory, session.name, session.turns)}`];
    if (name === ':cycles') return this.ruleStatistics(keyword, false);
    if (name === ':coverage') return this.ruleStatistics(keyword, true);
    if (name === ':reset') {
      this.resetCycles();
      return ['cycles reset'];
    }
    if (name === ':unused') return this.unusedItems();
    if (name === ':stats') return [countLine(session)];
    if (name === ':say' || name === ':explain') return this.preview(argument, name === ':explain');
    if (session.undo === null) return ['nothing to undo'];
    this.state = session.undo;
    return [`undone turn ${this.state.session.turns + 1}`];
  }

  run(lines) {
    for (const line of lines) {
      if (line.startsWith('SESSION ')) {
        this.startSession(line.slice(8));
      } else if (line.startsWith(':')) {
        this.transcript.push(line);
        const output = this.command(line);
        this.transcript.push(...output.map(text => `  ${text}`));
      } else {
        this.utterance(line);
      }
    }
    const summary = this.state.summary;
    this.transcript.push('', `SUMMARY sessions=${summary.sessions} ${countLine(summary)}`);
  }

  keywordStatistics() {
    const keywords = this.script.keywords.slice();
    keywords.sort((first, second) => this.state.keywords[second.id].uses - this.state.keywords[first.id].uses
      || compareWords(first.word, second.word));
    const lines = ['keyword,rank,uses,replies,decomposition_hits'];
    for (const keyword of keywords) {
      const statistics = this.state.keywords[keyword.id];
      const hits = keyword.decomp.map(rule => this.state.rules[rule.id].hits).join('/') || '-';
      lines.push(`${keyword.word},${keyword.rank},${statistics.uses},${statistics.replies},${hits}`);
    }
    return lines;
  }
}

function writeLines(name, lines) {
  fs.writeFileSync(`output/${name}`, lines.length > 0 ? `${lines.join('\n')}\n` : '', 'ascii');
}

function main() {
  const script = loadScript('input/script.txt');
  fs.mkdirSync('output', { recursive: true });
  writeLines('lint.txt', lint(script));
  const chatbot = new Chatbot(script);
  chatbot.run(readLines('input/dialogue.txt'));
  writeLines('transcript.txt', chatbot.transcript);
  writeLines('keyword_stats.csv', chatbot.keywordStatistics());
  writeLines('memory_log.txt', chatbot.state.memory.log);
}

if (require.main === module) main();
