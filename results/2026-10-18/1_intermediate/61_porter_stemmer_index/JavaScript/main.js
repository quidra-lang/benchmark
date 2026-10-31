import { readFileSync } from 'node:fs';

const TOKEN_PATTERN = /[A-Za-z]+/g;
const WORD_PATTERN = /^[A-Za-z]{1,30}$/;
const NUMBER_PATTERN = /^[0-9]{1,7}$/;
const PREFIX_TERM_PATTERN = /^[A-Za-z]{1,30}\*$/;
const LEXEME_PATTERN = /[()]|[^ ()]+/g;
const OPERATORS = new Set(['AND', 'OR', 'NOT']);
const PARENTHESES = new Set(['(', ')']);
const CONJUNCTION_CONTINUATIONS = new Set(['AND', 'NOT', '(', 'term', 'prefix']);
const VOWELS = 'aeiou';
const STEP_NAMES = ['1a', '1b', '1c', '2', '3', '4', '5a', '5b'];
const STEP_4_SUFFIXES = [
  'al',
  'ance',
  'ence',
  'er',
  'ic',
  'able',
  'ible',
  'ant',
  'ement',
  'ment',
  'ent',
  'ion',
  'ou',
  'ism',
  'ate',
  'iti',
  'ous',
  'ive',
  'ize',
];
const KWIC_WIDTH = 30;
const MAX_COUNT = 100;
const MAX_DOCUMENT_NUMBER = 999;
const MAX_LINE_NUMBER = 999;

class CommandError extends Error {}

function letterPattern(word) {
  let kinds = '';
  for (let index = 0; index < word.length; index++) {
    const letter = word[index];
    const vowel =
      VOWELS.includes(letter) || (letter === 'y' && index > 0 && kinds[index - 1] === 'C');
    kinds += vowel ? 'V' : 'C';
  }
  return kinds;
}

function measure(word) {
  return letterPattern(word).split('VC').length - 1;
}

function hasVowel(word) {
  return letterPattern(word).includes('V');
}

function endsDouble(word) {
  return letterPattern(word).endsWith('CC') && word.at(-1) === word.at(-2);
}

function endsCvc(word) {
  return letterPattern(word).endsWith('CVC') && !'wxy'.includes(word.at(-1));
}

function always() {
  return true;
}

function measureAboveZero(remainder) {
  return measure(remainder) > 0;
}

function measureAboveOne(remainder) {
  return measure(remainder) > 1;
}

function ionCondition(remainder) {
  return measure(remainder) > 1 && (remainder.endsWith('s') || remainder.endsWith('t'));
}

function finalECondition(remainder) {
  const value = measure(remainder);
  return value > 1 || (value === 1 && !endsCvc(remainder));
}

function rulesWith(condition, replacements) {
  return Object.entries(replacements).map(([suffix, replacement]) => ({
    suffix,
    replacement,
    condition,
  }));
}

const RULE_TABLES = {
  '1a': rulesWith(always, { sses: 'ss', ies: 'i', ss: 'ss', s: '' }),
  '1b': [
    { suffix: 'eed', replacement: 'ee', condition: measureAboveZero },
    { suffix: 'ed', replacement: '', condition: hasVowel },
    { suffix: 'ing', replacement: '', condition: hasVowel },
  ],
  '1c': [{ suffix: 'y', replacement: 'i', condition: hasVowel }],
  2: rulesWith(measureAboveZero, {
    ational: 'ate',
    tional: 'tion',
    enci: 'ence',
    anci: 'ance',
    izer: 'ize',
    abli: 'able',
    alli: 'al',
    entli: 'ent',
    eli: 'e',
    ousli: 'ous',
    ization: 'ize',
    ation: 'ate',
    ator: 'ate',
    alism: 'al',
    iveness: 'ive',
    fulness: 'ful',
    ousness: 'ous',
    aliti: 'al',
    iviti: 'ive',
    biliti: 'ble',
  }),
  3: rulesWith(measureAboveZero, {
    icate: 'ic',
    ative: '',
    alize: 'al',
    iciti: 'ic',
    ical: 'ic',
    ful: '',
    ness: '',
  }),
  4: STEP_4_SUFFIXES.map((suffix) => ({
    suffix,
    replacement: '',
    condition: suffix === 'ion' ? ionCondition : measureAboveOne,
  })),
  '5a': [{ suffix: 'e', replacement: '', condition: finalECondition }],
};

function applyRules(word, rules) {
  const matching = rules.filter((rule) => word.endsWith(rule.suffix));
  if (matching.length === 0) {
    return [word, null];
  }
  const { suffix, replacement, condition } = matching.reduce((best, rule) =>
    rule.suffix.length > best.suffix.length ? rule : best,
  );
  const remainder = word.slice(0, -suffix.length);
  if (!condition(remainder)) {
    return [word, null];
  }
  return [remainder + replacement, suffix];
}

function tidyStep1b(word) {
  if (['at', 'bl', 'iz'].some((suffix) => word.endsWith(suffix))) {
    return word + 'e';
  }
  if (endsDouble(word) && !'lsz'.includes(word.at(-1))) {
    return word.slice(0, -1);
  }
  if (measure(word) === 1 && endsCvc(word)) {
    return word + 'e';
  }
  return word;
}

function applyStep(name, word) {
  if (name === '5b') {
    if (measure(word) > 1 && endsDouble(word) && word.endsWith('l')) {
      return word.slice(0, -1);
    }
    return word;
  }
  const [result, suffix] = applyRules(word, RULE_TABLES[name]);
  if (name === '1b' && (suffix === 'ed' || suffix === 'ing')) {
    return tidyStep1b(result);
  }
  return result;
}

function stemmingSteps(word) {
  const changes = [];
  if (word.length > 2) {
    for (const name of STEP_NAMES) {
      const result = applyStep(name, word);
      if (result !== word) {
        changes.push([name, result]);
      }
      word = result;
    }
  }
  return [word, changes];
}

const stemCache = new Map();

function porterStem(word) {
  let stem = stemCache.get(word);
  if (stem === undefined) {
    stem = stemmingSteps(word)[0];
    stemCache.set(word, stem);
  }
  return stem;
}

function yesNo(flag) {
  return flag ? 'YES' : 'NO';
}

function wordArgument(text) {
  if (!WORD_PATTERN.test(text)) {
    throw new CommandError(`BAD WORD ${text}`);
  }
  return text.toLowerCase();
}

function numberArgument(text, minimum, maximum) {
  if (!NUMBER_PATTERN.test(text)) {
    throw new CommandError(`BAD NUMBER ${text}`);
  }
  const value = Number(text);
  if (value < minimum || value > maximum) {
    throw new CommandError(`BAD NUMBER ${text}`);
  }
  return value;
}

function splitArguments(name, rest) {
  if (name === 'SEARCH') {
    return [rest];
  }
  if (name === 'APPEND') {
    const space = rest.indexOf(' ');
    return space < 0 ? [rest] : [rest.slice(0, space), rest.slice(space + 1)];
  }
  return rest.split(' ');
}

function countValues(values) {
  const counts = new Map();
  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return counts;
}

function compareStrings(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function byCount([leftStem, leftCount], [rightStem, rightCount]) {
  return rightCount - leftCount || compareStrings(leftStem, rightStem);
}

function documentCount(occurrences) {
  return new Set(occurrences.map(([document]) => document.number)).size;
}

function closestDistance(positions, others, sameStem) {
  const gaps = [];
  if (sameStem) {
    for (let index = 1; index < positions.length; index++) {
      gaps.push(positions[index] - positions[index - 1]);
    }
  } else {
    const merged = [
      ...positions.map((position) => [position, 0]),
      ...others.map((other) => [other, 1]),
    ].sort((left, right) => left[0] - right[0]);
    for (let index = 1; index < merged.length; index++) {
      if (merged[index - 1][1] !== merged[index][1]) {
        gaps.push(merged[index][0] - merged[index - 1][0]);
      }
    }
  }
  return gaps.length > 0 ? Math.min(...gaps) : null;
}

function classify(lexeme) {
  if (OPERATORS.has(lexeme) || PARENTHESES.has(lexeme)) {
    return [lexeme, lexeme];
  }
  if (WORD_PATTERN.test(lexeme)) {
    return ['term', lexeme.toLowerCase()];
  }
  if (PREFIX_TERM_PATTERN.test(lexeme)) {
    return ['prefix', lexeme.slice(0, -1).toLowerCase()];
  }
  throw new CommandError(`BAD TERM ${lexeme}`);
}

function gcd(a, b) {
  return b === 0 ? a : gcd(b, a % b);
}

function fraction(numerator, denominator) {
  const divisor = gcd(numerator, denominator);
  return { numerator: numerator / divisor, denominator: denominator / divisor };
}

function compareFractions(left, right) {
  return left.numerator * right.denominator - right.numerator * left.denominator;
}

class Token {
  constructor(text, line, position, start) {
    this.text = text;
    this.line = line;
    this.position = position;
    this.start = start;
    this.form = text.toLowerCase();
  }

  get end() {
    return this.start + this.text.length;
  }
}

class Document {
  constructor(number) {
    this.number = number;
    this.lines = [];
    this.tokens = [];
  }

  addLine(text) {
    this.lines.push(text);
    const added = [];
    for (const match of text.matchAll(TOKEN_PATTERN)) {
      const token = new Token(match[0], this.lines.length, this.tokens.length + 1, match.index);
      this.tokens.push(token);
      added.push(token);
    }
    return added;
  }

  lineTokens(lineNumber) {
    return this.tokens.filter((token) => token.line === lineNumber);
  }

  reference(token) {
    return `${this.number}:${token.line}:${token.position}`;
  }
}

class QueryParser {
  constructor(items, stemSets) {
    this.items = items;
    this.position = 0;
    this.stemSets = stemSets;
  }

  peek() {
    return this.position < this.items.length ? this.items[this.position][0] : null;
  }

  take() {
    if (this.position >= this.items.length) {
      throw new CommandError('SYNTAX');
    }
    return this.items[this.position++];
  }

  parse() {
    const result = this.expression();
    if (this.position < this.items.length) {
      throw new CommandError('SYNTAX');
    }
    return result;
  }

  expression() {
    let [canonical, documents] = this.conjunction();
    while (this.peek() === 'OR') {
      this.position += 1;
      const [right, rightDocuments] = this.conjunction();
      canonical = `(${canonical} OR ${right})`;
      documents = documents.union(rightDocuments);
    }
    return [canonical, documents];
  }

  conjunction() {
    let [canonical, documents] = this.negation();
    while (CONJUNCTION_CONTINUATIONS.has(this.peek())) {
      if (this.peek() === 'AND') {
        this.position += 1;
      }
      const [right, rightDocuments] = this.negation();
      canonical = `(${canonical} AND ${right})`;
      documents = documents.intersection(rightDocuments);
    }
    return [canonical, documents];
  }

  negation() {
    if (this.peek() === 'NOT') {
      this.position += 1;
      const [canonical, documents] = this.negation();
      return [`(NOT ${canonical})`, new Set(this.stemSets.keys()).difference(documents)];
    }
    return this.element();
  }

  element() {
    const [kind, spelling] = this.take();
    if (kind === '(') {
      const result = this.expression();
      if (this.take()[0] !== ')') {
        throw new CommandError('SYNTAX');
      }
      return result;
    }
    if (kind === 'term') {
      const stem = porterStem(spelling);
      return [stem, this.documentsWhere((stems) => stems.has(stem))];
    }
    if (kind === 'prefix') {
      const documents = this.documentsWhere((stems) =>
        [...stems].some((stem) => stem.startsWith(spelling)),
      );
      return [`${spelling}*`, documents];
    }
    throw new CommandError('SYNTAX');
  }

  documentsWhere(predicate) {
    const numbers = [...this.stemSets].filter(([, stems]) => predicate(stems));
    return new Set(numbers.map(([number]) => number));
  }
}

class SearchEngine {
  constructor(stopwords) {
    this.stopwords = stopwords;
    this.documents = new Map();
    this.output = [];
    this.handlers = new Map([
      ['STEM', [1, 10, this.stemWords]],
      ['STEPS', [1, 1, this.showSteps]],
      ['MEASURE', [1, 1, this.showMeasure]],
      ['INDEX', [0, 1, this.showIndex]],
      ['SEARCH', [1, 1, this.search]],
      ['PHRASE', [2, 10, this.phrase]],
      ['NEAR', [3, 3, this.near]],
      ['TOP', [1, 2, this.top]],
      ['KWIC', [1, 1, this.kwic]],
      ['TF', [2, 2, this.termFrequency]],
      ['DF', [1, 1, this.documentFrequency]],
      ['VARIANTS', [1, 1, this.variants]],
      ['SIMILAR', [2, 2, this.similar]],
      ['RANK', [2, 11, this.rank]],
      ['INFO', [1, 1, this.info]],
      ['LINE', [2, 2, this.showLine]],
      ['STATS', [0, 0, this.stats]],
      ['STOP', [1, 1, this.stop]],
      ['UNSTOP', [1, 1, this.unstop]],
      ['APPEND', [2, 2, this.append]],
      ['DELETE', [1, 1, this.delete]],
    ]);
  }

  emit(...parts) {
    this.output.push(parts.join(' '));
  }

  addDocument(number) {
    const document = new Document(number);
    this.documents.set(number, document);
    return document;
  }

  orderedDocuments() {
    return [...this.documents.keys()]
      .sort((left, right) => left - right)
      .map((number) => this.documents.get(number));
  }

  isIndexed(token) {
    return !this.stopwords.has(token.form);
  }

  indexedTokens(document) {
    return document.tokens.filter((token) => this.isIndexed(token));
  }

  termFrequencies(document) {
    return countValues(this.indexedTokens(document).map((token) => porterStem(token.form)));
  }

  stemSet(document) {
    return new Set(this.termFrequencies(document).keys());
  }

  totalFrequencies() {
    const stems = [...this.documents.values()].flatMap((document) =>
      this.indexedTokens(document).map((token) => porterStem(token.form)),
    );
    return countValues(stems);
  }

  occurrenceMap() {
    const occurrences = new Map();
    for (const document of this.orderedDocuments()) {
      for (const token of this.indexedTokens(document)) {
        const stem = porterStem(token.form);
        if (!occurrences.has(stem)) {
          occurrences.set(stem, []);
        }
        occurrences.get(stem).push([document, token]);
      }
    }
    return occurrences;
  }

  stemPositions(document, stem) {
    return this.indexedTokens(document)
      .filter((token) => porterStem(token.form) === stem)
      .map((token) => token.position);
  }

  formCount(form) {
    let count = 0;
    for (const document of this.documents.values()) {
      count += document.tokens.filter((token) => token.form === form).length;
    }
    return count;
  }

  tokenMatches(token, target) {
    return target === '?' || (this.isIndexed(token) && porterStem(token.form) === target);
  }

  describeToken(token) {
    if (this.isIndexed(token)) {
      return `${token.form}/${porterStem(token.form)}`;
    }
    return `${token.form}/-`;
  }

  termArgument(text) {
    const word = wordArgument(text);
    if (this.stopwords.has(word)) {
      throw new CommandError(`STOPWORD ${word}`);
    }
    return porterStem(word);
  }

  documentArgument(text) {
    const number = numberArgument(text, 1, MAX_DOCUMENT_NUMBER);
    if (!this.documents.has(number)) {
      throw new CommandError(`NO DOC ${number}`);
    }
    return this.documents.get(number);
  }

  stemWords(args) {
    const words = args.map(wordArgument);
    this.emit('STEM', ...words.map((word) => `${word}:${porterStem(word)}`));
  }

  showSteps(args) {
    const word = wordArgument(args[0]);
    const [, changes] = stemmingSteps(word);
    if (changes.length === 0) {
      this.emit('STEPS', word, 'NONE');
    } else {
      this.emit('STEPS', word, ...changes.map(([name, result]) => `${name}:${result}`));
    }
  }

  showMeasure(args) {
    const word = wordArgument(args[0]);
    this.emit(
      'MEASURE',
      word,
      letterPattern(word),
      `m=${measure(word)}`,
      `vowel=${yesNo(hasVowel(word))}`,
      `double=${yesNo(endsDouble(word))}`,
      `cvc=${yesNo(endsCvc(word))}`,
    );
  }

  showIndex(args) {
    const prefix = args.length > 0 ? wordArgument(args[0]) : '';
    const occurrences = this.occurrenceMap();
    const stems = [...occurrences.keys()].filter((stem) => stem.startsWith(prefix)).sort();
    this.emit('INDEX', `stems=${stems.length}`);
    for (const stem of stems) {
      const found = occurrences.get(stem);
      this.emit(
        stem,
        `df=${documentCount(found)}`,
        ...found.map(([document, token]) => document.reference(token)),
      );
    }
  }

  search(args) {
    const items = (args[0].match(LEXEME_PATTERN) ?? []).map(classify);
    const stemSets = new Map(
      [...this.documents.values()].map((document) => [document.number, this.stemSet(document)]),
    );
    const [canonical, matches] = new QueryParser(items, stemSets).parse();
    for (const [kind, spelling] of items) {
      if (kind === 'term' && this.stopwords.has(spelling)) {
        throw new CommandError(`STOPWORD ${spelling}`);
      }
    }
    const numbers = [...matches].sort((left, right) => left - right);
    this.emit('SEARCH', canonical, `count=${matches.size}`, ...numbers);
  }

  phrase(args) {
    const words = args.map(wordArgument);
    if (words.every((word) => this.stopwords.has(word))) {
      throw new CommandError('STOPWORDS ONLY');
    }
    const targets = words.map((word) => (this.stopwords.has(word) ? '?' : porterStem(word)));
    const matches = [];
    for (const document of this.orderedDocuments()) {
      const tokens = document.tokens;
      for (let start = 0; start <= tokens.length - targets.length; start++) {
        if (targets.every((target, offset) => this.tokenMatches(tokens[start + offset], target))) {
          matches.push(document.reference(tokens[start]));
        }
      }
    }
    this.emit(`PHRASE "${targets.join(' ')}"`, `matches=${matches.length}`, ...matches);
  }

  near(args) {
    const first = this.termArgument(args[0]);
    const second = this.termArgument(args[1]);
    const limit = numberArgument(args[2], 1, MAX_COUNT);
    const found = [];
    for (const document of this.orderedDocuments()) {
      const distance = closestDistance(
        this.stemPositions(document, first),
        this.stemPositions(document, second),
        first === second,
      );
      if (distance !== null && distance <= limit) {
        found.push(`${document.number}:${distance}`);
      }
    }
    this.emit('NEAR', first, second, limit, `count=${found.length}`, ...found);
  }

  top(args) {
    const limit = numberArgument(args[0], 1, MAX_COUNT);
    let counts;
    let header;
    if (args.length === 2) {
      const document = this.documentArgument(args[1]);
      counts = this.termFrequencies(document);
      header = `TOP ${limit} doc=${document.number}`;
    } else {
      counts = this.totalFrequencies();
      header = `TOP ${limit}`;
    }
    const ranked = [...counts].sort(byCount).slice(0, limit);
    this.emit(header, ...ranked.map(([stem, count]) => `${stem}:${count}`));
  }

  kwic(args) {
    const stem = this.termArgument(args[0]);
    const found = this.occurrenceMap().get(stem) ?? [];
    this.emit('KWIC', stem, `count=${found.length}`);
    for (const [document, token] of found) {
      const text = document.lines[token.line - 1];
      const before = text.slice(Math.max(0, token.start - KWIC_WIDTH), token.start);
      const after = text.slice(token.end, token.end + KWIC_WIDTH);
      this.emit(
        `|${before.padStart(KWIC_WIDTH)}[${token.text}]${after.padEnd(KWIC_WIDTH)}|`,
        document.reference(token),
      );
    }
  }

  termFrequency(args) {
    const document = this.documentArgument(args[0]);
    const stem = this.termArgument(args[1]);
    this.emit('TF', document.number, stem, this.termFrequencies(document).get(stem) ?? 0);
  }

  documentFrequency(args) {
    const stem = this.termArgument(args[0]);
    this.emit('DF', stem, documentCount(this.occurrenceMap().get(stem) ?? []));
  }

  variants(args) {
    const stem = this.termArgument(args[0]);
    const found = this.occurrenceMap().get(stem) ?? [];
    const forms = [...countValues(found.map(([, token]) => token.form))].sort(([left], [right]) =>
      compareStrings(left, right),
    );
    this.emit(
      'VARIANTS',
      stem,
      `count=${forms.length}`,
      ...forms.map(([form, count]) => `${form}:${count}`),
    );
  }

  similar(args) {
    const document = this.documentArgument(args[0]);
    const limit = numberArgument(args[1], 1, MAX_COUNT);
    const stems = this.stemSet(document);
    const scores = [];
    for (const other of this.documents.values()) {
      if (other === document) {
        continue;
      }
      const otherStems = this.stemSet(other);
      const union = stems.union(otherStems).size;
      const score =
        union > 0 ? fraction(stems.intersection(otherStems).size, union) : fraction(0, 1);
      scores.push({ score, number: other.number });
    }
    scores.sort(
      (left, right) => compareFractions(right.score, left.score) || left.number - right.number,
    );
    this.emit(
      'SIMILAR',
      document.number,
      ...scores
        .slice(0, limit)
        .map(({ score, number }) => `${number}:${score.numerator}/${score.denominator}`),
    );
  }

  rank(args) {
    const limit = numberArgument(args[0], 1, MAX_COUNT);
    const query = new Set(args.slice(1).map((argument) => this.termArgument(argument)));
    const ranked = [];
    for (const document of this.documents.values()) {
      const counts = this.termFrequencies(document);
      const frequencies = [...query].map((stem) => counts.get(stem) ?? 0);
      const matched = frequencies.filter((count) => count > 0).length;
      const total = frequencies.reduce((sum, count) => sum + count, 0);
      if (matched > 0) {
        ranked.push({ matched, total, number: document.number });
      }
    }
    ranked.sort(
      (left, right) =>
        right.matched - left.matched || right.total - left.total || left.number - right.number,
    );
    this.emit(
      `RANK count=${ranked.length}`,
      ...ranked
        .slice(0, limit)
        .map(({ matched, total, number }) => `${number}:${matched}:${total}`),
    );
  }

  info(args) {
    const document = this.documentArgument(args[0]);
    const counts = this.termFrequencies(document);
    let top = '-';
    if (counts.size > 0) {
      const [stem, count] = [...counts].sort(byCount)[0];
      top = `${stem}:${count}`;
    }
    const indexed = [...counts.values()].reduce((sum, count) => sum + count, 0);
    this.emit(
      'INFO',
      document.number,
      `lines=${document.lines.length}`,
      `tokens=${document.tokens.length}`,
      `indexed=${indexed}`,
      `stems=${counts.size}`,
      `top=${top}`,
    );
  }

  showLine(args) {
    const document = this.documentArgument(args[0]);
    const lineNumber = numberArgument(args[1], 1, MAX_LINE_NUMBER);
    if (lineNumber > document.lines.length) {
      throw new CommandError(`NO LINE ${document.number}:${lineNumber}`);
    }
    const tokens = document.lineTokens(lineNumber);
    this.emit(
      `LINE ${document.number}:${lineNumber}`,
      `tokens=${tokens.length}`,
      ...tokens.map((token) => this.describeToken(token)),
    );
  }

  stats() {
    const documents = [...this.documents.values()];
    const sum = (count) => documents.reduce((total, document) => total + count(document), 0);
    this.emit(
      'STATS',
      `docs=${documents.length}`,
      `lines=${sum((document) => document.lines.length)}`,
      `tokens=${sum((document) => document.tokens.length)}`,
      `indexed=${sum((document) => this.indexedTokens(document).length)}`,
      `stems=${this.totalFrequencies().size}`,
      `stopwords=${this.stopwords.size}`,
    );
  }

  stop(args) {
    const word = wordArgument(args[0]);
    if (this.stopwords.has(word)) {
      throw new CommandError(`ALREADY STOPWORD ${word}`);
    }
    this.stopwords.add(word);
    this.emit('STOP', word, `unindexed=${this.formCount(word)}`);
  }

  unstop(args) {
    const word = wordArgument(args[0]);
    if (!this.stopwords.has(word)) {
      throw new CommandError(`NOT STOPWORD ${word}`);
    }
    this.stopwords.delete(word);
    this.emit('UNSTOP', word, `indexed=${this.formCount(word)}`);
  }

  append(args) {
    const number = numberArgument(args[0], 1, MAX_DOCUMENT_NUMBER);
    const created = !this.documents.has(number);
    const document = created ? this.addDocument(number) : this.documents.get(number);
    const tokens = document.addLine(args[1]);
    const indexed = tokens.filter((token) => this.isIndexed(token)).length;
    this.emit(
      'APPEND',
      number,
      `line=${document.lines.length}`,
      `tokens=${tokens.length}`,
      `indexed=${indexed}`,
      `new=${yesNo(created)}`,
    );
  }

  delete(args) {
    const document = this.documentArgument(args[0]);
    this.documents.delete(document.number);
    this.emit(
      'DELETE',
      document.number,
      `lines=${document.lines.length}`,
      `tokens=${document.tokens.length}`,
    );
  }

  execute(line) {
    const separator = line.indexOf(' ');
    const name = separator < 0 ? line : line.slice(0, separator);
    try {
      const command = this.handlers.get(name);
      if (command === undefined) {
        throw new CommandError(`UNKNOWN COMMAND ${name}`);
      }
      const [minimum, maximum, handler] = command;
      const args = separator < 0 ? [] : splitArguments(name, line.slice(separator + 1));
      if (args.length < minimum || args.length > maximum) {
        throw new CommandError(`BAD ARGUMENTS ${name}`);
      }
      handler.call(this, args);
    } catch (error) {
      if (!(error instanceof CommandError)) {
        throw error;
      }
      this.emit('ERROR', error.message);
    }
  }
}

function main() {
  const lines = readFileSync(0, 'utf8').split(/\r?\n/);
  const engine = new SearchEngine(new Set(lines[0].trim().split(/\s+/).slice(1)));
  let index = 1;
  while (lines[index].startsWith('DOC ')) {
    const document = engine.addDocument(Number(lines[index].slice(4)));
    index += 1;
    while (lines[index] !== 'ENDDOC') {
      document.addLine(lines[index]);
      index += 1;
    }
    index += 1;
  }
  for (const line of lines.slice(index)) {
    if (line === 'END') {
      break;
    }
    engine.execute(line);
  }
  process.stdout.write(engine.output.join('\n') + '\n');
}

main();
