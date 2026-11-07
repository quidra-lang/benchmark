'use strict';

const fs = require('node:fs');
const reader = require('./reader');
const terms = require('./terms');
const {Trail} = require('./unify');
const database = require('./database');
const predicates = require('./predicates');

const specialBuiltins = new Set([['findall', 3], ['throw', 1], ['between', 3], ['length', 2]]
  .map(([name, count]) => terms.key(name, count)));

function control(name, count) {
  return (name === ',' && count === 2) || (name === '!' && count === 0) ||
    (name === ';' && count === 2) || (name === '->' && count === 2) ||
    (name === '\\+' && count === 1) || (name === 'call' && count >= 1 && count <= 8) ||
    (name === 'catch' && count === 3);
}

function staticPredicate(term) {
  const key = terms.predicateKey(term);
  return control(term.name, terms.arity(term)) || predicates.keys.has(key) || specialBuiltins.has(key);
}

function goalConversion(term) {
  term = terms.dereference(term);
  if (term.kind === 'variable') return terms.compound('call', [term]);
  if (term.kind === 'integer') return null;
  if (term.kind === 'compound' && term.args.length === 2 && [',', ';', '->'].includes(term.name)) {
    const first = goalConversion(term.args[0]);
    if (first === null) return null;
    const second = goalConversion(term.args[1]);
    return second === null ? null : terms.compound(term.name, [first, second]);
  }
  return term;
}

function atomName(name, quoted) {
  if (!quoted) return name;
  const ordinary = /^[a-z][A-Za-z0-9_]*$/.exec(name);
  if ((ordinary !== null && ordinary[0].length === name.length) ||
      (name !== '.' && name.length > 0 && Array.from(name).every(character => reader.symbolCharacters.has(character))) ||
      ['[]', '!', ';'].includes(name)) return name;
  const escapes = {'\\': '\\\\', "'": "\\'", '\n': '\\n', '\t': '\\t'};
  return "'" + name.replace(/[\\'\n\t]/g, character => escapes[character]) + "'";
}

function naming(fixed = new Map()) {
  let next = 1;
  return variable => {
    if (!fixed.has(variable)) fixed.set(variable, '_G' + next++);
    return fixed.get(variable);
  };
}

function writeTerm(term, quoted = true, limit = 1200, operand = false, nameVariable = naming()) {
  term = terms.dereference(term);
  if (term.kind === 'variable') return nameVariable(term);
  if (term.kind === 'integer') return String(term.value);
  if (term.kind === 'atom') {
    const text = atomName(term.name, quoted);
    return operand && reader.operatorNames.has(term.name) ? '(' + text + ')' : text;
  }
  const write = (value, maximum = 999, inOperand = false) => writeTerm(value, quoted, maximum, inOperand, nameVariable);
  if (term.name === '.' && term.args.length === 2) {
    const list = terms.listParts(term);
    return '[' + list.elements.map(value => write(value)).join(',') + (list.proper ? '' : '|' + write(list.tail)) + ']';
  }
  if (term.args.length === 2 && reader.infix.has(term.name)) {
    const operator = reader.infix.get(term.name);
    const left = write(term.args[0], operator.left, true);
    const right = write(term.args[1], operator.right, true);
    let text;
    if (term.name === ',') text = left + ',' + right;
    else if (/^[a-z]/.test(term.name)) text = left + ' ' + term.name + ' ' + right;
    else {
      const before = left.length > 0 && reader.symbolCharacters.has(left[left.length - 1]) ? ' ' : '';
      const after = right.length > 0 && reader.symbolCharacters.has(right[0]) ? ' ' : '';
      text = left + before + term.name + after + right;
    }
    return operator.priority > limit ? '(' + text + ')' : text;
  }
  if (term.args.length === 1 && reader.prefix.has(term.name)) {
    const priority = reader.prefix.get(term.name);
    const argument = write(term.args[0], priority, true);
    const space = argument.length > 0 && (reader.symbolCharacters.has(argument[0]) || /[0-9(]/.test(argument[0])) ? ' ' : '';
    const text = term.name + space + argument;
    return priority > limit ? '(' + text + ')' : text;
  }
  return atomName(term.name, quoted) + '(' + term.args.map(value => write(value)).join(',') + ')';
}

function indicatorText(name, count) { return writeTerm(terms.indicator(name, count)); }

function consulting(sources) {
  const store = new database.Database();
  const reports = [];
  const statistics = new Map([...sources.keys()].map(file => [file, {clauses: 0, errors: 0, warnings: 0}]));
  function report(file, line, message, error = false) {
    statistics.get(file)[error ? 'errors' : 'warnings']++;
    reports.push(`${file}:${line}: ${error ? 'error' : 'warning'}: ${message}`);
  }
  for (const [file, source] of sources) {
    const parser = new reader.Reader(reader.tokenize(source.text, file));
    const warned = new Set();
    let last = null;
    while (parser.current().kind !== 'eof') {
      let parsed;
      try { parsed = parser.clause(); }
      catch (error) {
        if (!(error instanceof reader.ParseError)) throw error;
        statistics.get(file).errors++;
        const position = error.token.position;
        reports.push(`${file}:${position.line}:${position.column}: syntax error: ${error.message}`);
        if (error.token.kind !== 'eof') {
          reports.push('    ' + source.lines[position.line - 1]);
          reports.push(' '.repeat(position.column + 3) + '^');
        }
        parser.recover(error);
        continue;
      }
      let head = parsed.term;
      let body = null;
      if (head.kind === 'compound' && head.name === ':-' && head.args.length === 2) [head, body] = head.args;
      let failure = null;
      if (head.kind === 'variable') failure = terms.atom('instantiation_error');
      else if (head.kind === 'integer') failure = terms.form('type_error', terms.atom('callable'), head);
      else if (staticPredicate(head)) failure = terms.form('permission_error', terms.atom('modify'),
        terms.atom('static_procedure'), terms.predicateIndicator(head));
      else if (body !== null) {
        const converted = goalConversion(body);
        if (converted === null) failure = terms.form('type_error', terms.atom('callable'), body);
        else body = converted;
      }
      if (failure !== null) { report(file, parsed.line, writeTerm(failure), true); continue; }
      const predicate = store.ensure(head);
      const display = indicatorText(predicate.name, predicate.arity);
      if (file === 'program.pl' && predicate.clauses.some(clause => clause.file === 'prelude.pl')) {
        report(file, parsed.line, 'redefining prelude procedure ' + display);
        predicate.clauses = [];
      }
      if (predicate.clauses.some(clause => clause.file === file) && last !== predicate && !warned.has(predicate)) {
        report(file, parsed.line, 'clauses of ' + display + ' are not together');
        warned.add(predicate);
      }
      predicate.clauses.push(new database.Clause(head, body, file, parsed.line));
      last = predicate;
      statistics.get(file).clauses++;
      const singleton = parsed.variables.filter(variable => !variable.name.startsWith('_') && variable.count === 1);
      const multiple = parsed.variables.filter(variable => variable.name.length >= 2 && variable.name.startsWith('_') && variable.count >= 2);
      if (singleton.length > 0) report(file, parsed.line, 'singleton variables: ' + singleton.map(variable => variable.name).join(', '));
      if (multiple.length > 0) report(file, parsed.line, 'variables starting with _ occur more than once: ' + multiple.map(variable => variable.name).join(', '));
    }
  }
  const undefinedNames = new Set();
  for (const predicate of store.predicates.values()) {
    for (const clause of predicate.clauses) {
      const pending = clause.body === null ? [] : [clause.body];
      while (pending.length > 0) {
        const goal = terms.dereference(pending.pop());
        if (!terms.callable(goal)) continue;
        const count = terms.arity(goal);
        if (count === 2 && [',', ';', '->'].includes(goal.name)) pending.push(goal.args[1], goal.args[0]);
        else if (count === 1 && ['\\+', 'call'].includes(goal.name)) pending.push(goal.args[0]);
        else if (goal.name === 'findall' && count === 3) pending.push(goal.args[1]);
        else if (goal.name === 'catch' && count === 3) pending.push(goal.args[2], goal.args[0]);
        else if (!staticPredicate(goal) && store.get(goal) === undefined) {
          const key = terms.predicateKey(goal);
          if (!undefinedNames.has(key)) {
            undefinedNames.add(key);
            report(clause.file, clause.line, `undefined procedure ${indicatorText(goal.name, count)} called from ${indicatorText(predicate.name, predicate.arity)}`);
          }
        }
      }
    }
  }
  for (const [file, counts] of statistics) reports.push(`${file}: clauses=${counts.clauses} errors=${counts.errors} warnings=${counts.warnings}`);
  let clauses = 0;
  for (const predicate of store.predicates.values()) clauses += predicate.clauses.length;
  reports.push(`database: predicates=${store.predicates.size} clauses=${clauses}`);
  return {store, reports};
}

function listing(store) {
  const blocks = [];
  for (const predicate of store.predicates.values()) {
    const lines = [];
    for (const clause of predicate.clauses) {
      const counts = new Map();
      for (const term of clause.body === null ? [clause.head] : [clause.head, clause.body]) {
        for (const variable of terms.variables(term)) counts.set(variable, (counts.get(variable) ?? 0) + 1);
      }
      const names = new Map();
      let next = 0;
      for (const [variable, count] of counts) {
        if (count === 1) names.set(variable, '_');
        else {
          names.set(variable, String.fromCharCode(65 + next % 26) + (next < 26 ? '' : Math.floor(next / 26)));
          next++;
        }
      }
      const nameVariable = naming(names);
      const head = writeTerm(clause.head, true, 1200, false, nameVariable);
      if (clause.body === null) { lines.push(head + '.'); continue; }
      lines.push(head + ' :-');
      const goals = [];
      let body = clause.body;
      while (body.kind === 'compound' && body.name === ',' && body.args.length === 2) {
        goals.push(body.args[0]);
        body = body.args[1];
      }
      goals.push(body);
      goals.forEach((goal, index) => lines.push('    ' + writeTerm(goal, true, 999, false, nameVariable) + (index + 1 === goals.length ? '.' : ',')));
    }
    blocks.push(lines.join('\n'));
  }
  return blocks.join('\n\n') + (blocks.length === 0 ? '' : '\n');
}

function answer(variables) {
  const values = variables.map(variable => terms.dereference(variable.variable));
  const fixed = new Map();
  for (let index = 0; index < variables.length; index++) {
    if (values[index].kind === 'variable' && !fixed.has(values[index])) fixed.set(values[index], variables[index].name);
  }
  const nameVariable = naming(fixed);
  const previous = new Map();
  const items = [];
  for (let index = 0; index < variables.length; index++) {
    const name = variables[index].name;
    const value = values[index];
    if (value.kind === 'variable') {
      if (previous.has(value)) items.push(previous.get(value) + ' = ' + name);
      previous.set(value, name);
    } else items.push(name + ' = ' + writeTerm(value, true, 699, true, nameVariable));
  }
  return items.length === 0 ? 'true' : items.join(', ');
}

function entry(goal, barrier, context, next) { return {goal, barrier, context, next}; }
function marker(type, fields = {}) { return {kind: 'marker', type, ...fields}; }
function prepend(goals, barrier, context, continuation) {
  for (let index = goals.length - 1; index >= 0; index--) continuation = entry(goals[index], barrier, context, continuation);
  return continuation;
}

class Raised extends Error {
  constructor(ball) { super('Prolog exception'); this.ball = ball; }
}
class InferenceLimit extends Error {}

class Machine {
  constructor(store, profile, query, variables, limit) {
    Object.assign(this, {store, profile, variables, limit});
    this.trail = new Trail();
    this.goals = entry(terms.compound('call', [query]), 0, null, null);
    this.choices = [];
    this.counts = {solutions: 0, inferences: 0, choicepoints: 0, backtracks: 0};
    this.answers = [];
    this.output = [];
    this.done = false;
  }
  write(term, quoted) { this.output.push(writeTerm(term, quoted)); }
  profileEntry(name, count) {
    const key = terms.key(name, count);
    if (!this.profile.has(key)) this.profile.set(key, {name, arity: count, calls: 0, tries: 0});
    return this.profile.get(key);
  }
  inference(name, count) {
    if (this.counts.inferences === 20000) throw new InferenceLimit();
    this.counts.inferences++;
    this.profileEntry(name, count).calls++;
  }
  choice(kind, resume, fields = {}) {
    const point = {kind, resume, mark: this.trail.mark(), ...fields};
    this.choices.push(point);
    this.counts.choicepoints++;
    return point;
  }
  cut(height) { this.choices.length = height; }
  tryClause(clause, goal, barrier, context, resume) {
    this.profileEntry(goal.name, terms.arity(goal)).tries++;
    const copied = database.copyClause(clause);
    if (!this.trail.unify(copied.head, goal)) return false;
    this.goals = copied.body === null ? resume : entry(copied.body, barrier, context, resume);
    return true;
  }
  userGoal(goal, context, resume) {
    const predicate = this.store.get(goal);
    if (predicate === undefined) predicates.fail('existence_error', terms.atom('procedure'), terms.predicateIndicator(goal));
    const clauses = database.candidates(predicate, goal);
    if (clauses.length === 0) return false;
    const barrier = this.choices.length;
    if (clauses.length >= 2) this.choice('CLAUSES', resume, {goal, clauses, next: 1, barrier, context});
    return this.tryClause(clauses[0], goal, barrier, context, resume);
  }
  between(args, context, resume) {
    const low = predicates.checkInteger(args[0]);
    const high = predicates.checkInteger(args[1]);
    const value = terms.dereference(args[2]);
    if (value.kind !== 'variable' && value.kind !== 'integer') predicates.fail('type_error', terms.atom('integer'), value);
    if (value.kind === 'integer') return low <= value.value && value.value <= high;
    if (low > high) return false;
    if (low < high) this.choice('BETWEEN', resume, {high, variable: args[2], next: low + 1, context});
    return this.trail.unify(args[2], terms.integer(low));
  }
  length(args, context, resume) {
    const number = terms.dereference(args[1]);
    if (number.kind !== 'variable' && number.kind !== 'integer') predicates.fail('type_error', terms.atom('integer'), number);
    if (number.kind === 'integer' && number.value < 0) predicates.fail('domain_error', terms.atom('not_less_than_zero'), number);
    const list = terms.listParts(args[0]);
    const size = list.elements.length;
    if (list.proper) return this.trail.unify(args[1], terms.integer(size));
    if (list.tail.kind !== 'variable') predicates.fail('type_error', terms.atom('list'), args[0]);
    if (number.kind === 'integer') {
      if (number.value < size) return false;
      return this.trail.unify(list.tail, terms.list(Array.from({length: number.value - size}, () => terms.variable())));
    }
    this.choice('LENGTH', resume, {tail: list.tail, result: args[1], base: size, next: size + 1, context});
    return this.trail.unify(list.tail, terms.empty) && this.trail.unify(args[1], terms.integer(size));
  }
  executeMarker(goal, continuation) {
    if (goal.type === 'ITE') { this.cut(goal.height); return true; }
    if (goal.type === 'NAF') { this.cut(goal.height); return false; }
    if (goal.type === 'EXIT') {
      if (this.choices[this.choices.length - 1] === goal.point) this.choices.pop();
      return true;
    }
    goal.point.results.push(terms.copy(goal.point.template));
    return false;
  }
  execute(current) {
    const continuation = current.next;
    const c = current.barrier;
    const k = current.context;
    if (current.goal.kind === 'marker') return this.executeMarker(current.goal, continuation);
    const goal = terms.dereference(current.goal);
    const count = terms.arity(goal);
    const args = goal.kind === 'compound' ? goal.args : [];
    if (control(goal.name, count)) {
      if (goal.name === ',') this.goals = prepend(args, c, k, continuation);
      else if (goal.name === '!') this.cut(c);
      else if (goal.name === ';') {
        const height = this.choices.length;
        this.choice('ALT', entry(args[1], c, k, continuation));
        const left = terms.dereference(args[0]);
        if (left.kind === 'compound' && left.name === '->' && left.args.length === 2) {
          this.goals = entry(left.args[0], height + 1, k,
            prepend([marker('ITE', {height}), left.args[1]], c, k, continuation));
        } else this.goals = entry(args[0], c, k, continuation);
      } else if (goal.name === '->') {
        const height = this.choices.length;
        this.goals = entry(args[0], height, k, prepend([marker('ITE', {height}), args[1]], c, k, continuation));
      } else if (goal.name === '\\+') {
        const height = this.choices.length;
        this.choice('ALT', continuation);
        this.goals = prepend([terms.compound('call', [args[0]]), marker('NAF', {height})], c, k, continuation);
      } else if (goal.name === 'call') {
        const called = terms.dereference(args[0]);
        if (called.kind === 'variable') predicates.fail('instantiation_error');
        if (called.kind === 'integer') predicates.fail('type_error', terms.atom('callable'), called);
        const expanded = count === 1 ? called : terms.compound(called.name,
          (called.kind === 'compound' ? called.args : []).concat(args.slice(1)));
        const converted = goalConversion(expanded);
        if (converted === null) predicates.fail('type_error', terms.atom('callable'), expanded);
        this.goals = entry(converted, this.choices.length, k, continuation);
      } else {
        const point = this.choice('CATCH', continuation, {catcher: args[1], recovery: args[2], parent: k});
        this.goals = entry(terms.compound('call', [args[0]]), c, point,
          entry(marker('EXIT', {point}), c, k, continuation));
      }
      return true;
    }
    this.inference(goal.name, count);
    const key = terms.predicateKey(goal);
    if (goal.name === 'findall' && count === 3) {
      const point = this.choice('FINDALL', continuation, {template: args[0], result: args[2], results: []});
      this.goals = prepend([terms.compound('call', [args[1]]), marker('COLLECT', {point})], c, k, null);
      return true;
    }
    if (goal.name === 'throw' && count === 1) {
      const ball = terms.dereference(args[0]);
      if (ball.kind === 'variable') predicates.fail('instantiation_error');
      throw new Raised(ball);
    }
    if (goal.name === 'between' && count === 3) return this.between(args, k, continuation);
    if (goal.name === 'length' && count === 2) return this.length(args, k, continuation);
    if (predicates.keys.has(key)) return predicates.execute(goal, this);
    return this.userGoal(goal, k, continuation);
  }
  backtrack() {
    retry: for (;;) {
      this.counts.backtracks++;
      for (;;) {
        if (this.choices.length === 0) { this.answers.push('false.'); this.done = true; return; }
        const point = this.choices[this.choices.length - 1];
        this.trail.undo(point.mark);
        if (point.kind === 'ALT') {
          this.choices.pop();
          this.goals = point.resume;
          return;
        }
        if (point.kind === 'CLAUSES') {
          const clause = point.clauses[point.next];
          if (point.next + 1 === point.clauses.length) this.choices.pop();
          else point.next++;
          if (this.tryClause(clause, point.goal, point.barrier, point.context, point.resume)) return;
          continue retry;
        }
        if (point.kind === 'BETWEEN' || point.kind === 'LENGTH') {
          this.inference(point.kind === 'BETWEEN' ? 'between' : 'length', point.kind === 'BETWEEN' ? 3 : 2);
          let success;
          const next = point.next;
          if (point.kind === 'BETWEEN') {
            if (next === point.high) this.choices.pop();
            else point.next++;
            success = this.trail.unify(point.variable, terms.integer(next));
          } else {
            point.next++;
            success = this.trail.unify(point.tail, terms.list(Array.from({length: next - point.base}, () => terms.variable()))) &&
              this.trail.unify(point.result, terms.integer(next));
          }
          if (success) { this.goals = point.resume; return; }
          continue retry;
        }
        this.choices.pop();
        if (point.kind === 'CATCH') continue;
        if (this.trail.unify(terms.list(point.results), point.result)) { this.goals = point.resume; return; }
        continue retry;
      }
    }
  }
  exception(ball, context) {
    ball = terms.copy(ball);
    let point = context;
    while (point !== null) {
      this.cut(this.choices.indexOf(point));
      this.trail.undo(point.mark);
      const mark = this.trail.mark();
      if (this.trail.unify(terms.copy(ball), point.catcher)) {
        this.goals = entry(terms.compound('call', [point.recovery]), this.choices.length, point.parent, point.resume);
        return;
      }
      this.trail.undo(mark);
      point = point.parent;
    }
    this.answers.push('uncaught exception: ' + writeTerm(ball));
    this.done = true;
  }
  run() {
    while (!this.done) {
      let current = null;
      try {
        if (this.goals === null) {
          this.counts.solutions++;
          const finished = this.counts.solutions === this.limit || this.choices.length === 0;
          this.answers.push(answer(this.variables) + (finished ? '.' : ' ;'));
          if (finished) this.done = true;
          else this.backtrack();
        } else {
          current = this.goals;
          this.goals = current.next;
          if (!this.execute(current)) this.backtrack();
        }
      } catch (error) {
        if (error instanceof InferenceLimit) { this.answers.push('inference limit exceeded'); this.done = true; }
        else if (error instanceof Raised) this.exception(error.ball, current.context);
        else if (error instanceof predicates.BuiltinError) {
          const goal = terms.dereference(current.goal);
          this.exception(terms.error(error.formal, goal.name, terms.arity(goal)), current.context);
        } else throw error;
      }
    }
    return {counts: this.counts, answers: this.answers, output: this.output.join('')};
  }
}

function readLines(text) { return text === '' ? [] : text.slice(0, -1).split('\n'); }
function countText(counts) { return Object.entries(counts).map(([name, value]) => `${name}=${value}`).join(' '); }
function linesText(lines) { return lines.join('\n') + (lines.length === 0 ? '' : '\n'); }

function runQueries(store, queryLines) {
  const answers = [];
  const writes = [];
  const statistics = [];
  const totals = {solutions: 0, inferences: 0, choicepoints: 0, backtracks: 0};
  const profile = new Map();
  for (let index = 0; index < queryLines.length; index++) {
    const source = queryLines[index];
    const bodyStart = source.indexOf('?- ') + 3;
    const limitText = source.slice(0, bodyStart - 3).trim();
    const limit = limitText === '' ? null : Number(limitText);
    const parser = new reader.Reader(reader.tokenize(source.slice(bodyStart), 'queries.txt', bodyStart + 1));
    answers.push(source);
    writes.push(`== query ${index + 1} ==\n`);
    let parsed;
    try { parsed = parser.clause(true); }
    catch (error) {
      if (!(error instanceof reader.ParseError)) throw error;
      answers.push(`syntax error at column ${error.token.position.column}: ${error.message}`);
      statistics.push(`query ${index + 1}: syntax error`);
      continue;
    }
    const variables = parsed.variables.filter(variable => !variable.name.startsWith('_'));
    const result = new Machine(store, profile, parsed.term, variables, limit).run();
    for (const line of result.answers) answers.push(line);
    writes.push(result.output);
    if (result.output.length > 0 && !result.output.endsWith('\n')) writes.push('\n');
    statistics.push(`query ${index + 1}: ${countText(result.counts)}`);
    for (const name of Object.keys(totals)) totals[name] += result.counts[name];
  }
  statistics.push('total: ' + countText(totals), '== profile ==');
  const ranked = [...profile.values()].map(record => ({...record, text: indicatorText(record.name, record.arity)}));
  ranked.sort((first, second) => second.calls - first.calls || (first.text < second.text ? -1 : first.text > second.text ? 1 : 0));
  for (const record of ranked) {
    const suffix = store.predicates.has(terms.key(record.name, record.arity)) ? ` tries=${record.tries}` : '';
    statistics.push(`${record.text} calls=${record.calls}${suffix}`);
  }
  return {'answers.txt': linesText(answers), 'write_output.txt': writes.join(''), 'stats.txt': linesText(statistics)};
}

function main() {
  const sources = new Map(['prelude.pl', 'program.pl'].map(file => {
    const text = fs.readFileSync('input/' + file, 'ascii');
    return [file, {text, lines: readLines(text)}];
  }));
  const consulted = consulting(sources);
  const files = {'consult.txt': linesText(consulted.reports), 'listing.txt': listing(consulted.store),
    ...runQueries(consulted.store, readLines(fs.readFileSync('input/queries.txt', 'ascii')))};
  fs.mkdirSync('output', {recursive: true});
  for (const [file, text] of Object.entries(files)) fs.writeFileSync('output/' + file, text, 'ascii');
}

main();
