import { readFileSync } from 'node:fs';

type Condition = (remainder: string) => boolean;
type Kind = 'AND' | 'OR' | 'NOT' | '(' | ')' | 'term' | 'prefix';
type Item = [kind: Kind, spelling: string];
type Occurrence = [document: Document, token: Token];
type Evaluation = [canonical: string, documents: Set<number>];
type Handler = (args: string[]) => void;

interface Rule {
  suffix: string;
  replacement: string;
  condition: Condition;
}

interface Fraction {
  numerator: number;
  denominator: number;
}

const TOKEN_PATTERN = /[A-Za-z]+/g;
const WORD_PATTERN = /^[A-Za-z]{1,30}$/;
const NUMBER_PATTERN = /^[0-9]{1,7}$/;
const PREFIX_TERM_PATTERN = /^[A-Za-z]{1,30}\*$/;
const LEXEME_PATTERN = /[()]|[^ ()]+/g;
const OPERATORS: ReadonlySet<string> = new Set(['AND', 'OR', 'NOT']);
const PARENTHESES: ReadonlySet<string> = new Set(['(', ')']);
const CONJUNCTION_CONTINUATIONS: ReadonlySet<Kind | null> = new Set<Kind | null>([
  'AND',
  'NOT',
  '(',
  'term',
  'prefix',
]);
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

function letterPattern(word: string): string {
  let kinds = '';
  for (let index = 0; index < word.length; index++) {
    const letter = word[index];
    const vowel =
      VOWELS.includes(letter) || (letter === 'y' && index > 0 && kinds[index - 1] === 'C');
    kinds += vowel ? 'V' : 'C';
  }
  return kinds;
}

function measure(word: string): number {
  return letterPattern(word).split('VC').length - 1;
}

function hasVowel(word: string): boolean {
  return letterPattern(word).includes('V');
}

function endsDouble(word: string): boolean {
  return letterPattern(word).endsWith('CC') && word.at(-1) === word.at(-2);
}

function endsCvc(word: string): boolean {
  return letterPattern(word).endsWith('CVC') && !'wxy'.includes(word.slice(-1));
}

function always(): boolean {
  return true;
}

function measureAboveZero(remainder: string): boolean {
  return measure(remainder) > 0;
}

function measureAboveOne(remainder: string): boolean {
  return measure(remainder) > 1;
}

function ionCondition(remainder: string): boolean {
  return measure(remainder) > 1 && (remainder.endsWith('s') || remainder.endsWith('t'));
}

function finalECondition(remainder: string): boolean {
  const value = measure(remainder);
  return value > 1 || (value === 1 && !endsCvc(remainder));
}

function rulesWith(condition: Condition, replacements: Record<string, string>): Rule[] {
  return Object.entries(replacements).map(([suffix, replacement]) => ({
    suffix,
    replacement,
    condition,
  }));
}

const RULE_TABLES: Record<string, Rule[]> = {
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

function applyRules(word: string, rules: Rule[]): [word: string, suffix: string | null] {
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

function tidyStep1b(word: string): string {
  if (['at', 'bl', 'iz'].some((suffix) => word.endsWith(suffix))) {
    return word + 'e';
  }
  if (endsDouble(word) && !'lsz'.includes(word.slice(-1))) {
    return word.slice(0, -1);
  }
  if (measure(word) === 1 && endsCvc(word)) {
    return word + 'e';
  }
  return word;
}

function applyStep(name: string, word: string): string {
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

function stemmingSteps(word: string): [stem: string, changes: [name: string, result: string][]] {
  const changes: [name: string, result: string][] = [];
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

const stemCache = new Map<string, string>();

function porterStem(word: string): string {
  let stem = stemCache.get(word);
  if (stem === undefined) {
    stem = stemmingSteps(word)[0];
    stemCache.set(word, stem);
  }
  return stem;
}

function yesNo(flag: boolean): string {
  return flag ? 'YES' : 'NO';
}

function wordArgument(text: string): string {
  if (!WORD_PATTERN.test(text)) {
    throw new CommandError(`BAD WORD ${text}`);
  }
  return text.toLowerCase();
}

function numberArgument(text: string, minimum: number, maximum: number): number {
  if (!NUMBER_PATTERN.test(text)) {
    throw new CommandError(`BAD NUMBER ${text}`);
  }
  const value = Number(text);
  if (value < minimum || value > maximum) {
    throw new CommandError(`BAD NUMBER ${text}`);
  }
  return value;
}

function splitArguments(name: string, rest: string): string[] {
  if (name === 'SEARCH') {
    return [rest];
  }
  if (name === 'APPEND') {
    const space = rest.indexOf(' ');
    return space < 0 ? [rest] : [rest.slice(0, space), rest.slice(space + 1)];
  }
  return rest.split(' ');
}

function countValues(values: string[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return counts;
}

function compareStrings(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function byCount(
  [leftStem, leftCount]: [string, number],
  [rightStem, rightCount]: [string, number],
): number {
  return rightCount - leftCount || compareStrings(leftStem, rightStem);
}

function documentCount(occurrences: Occurrence[]): number {
  return new Set(occurrences.map(([document]) => document.number)).size;
}

function closestDistance(positions: number[], others: number[], sameStem: boolean): number | null {
  const gaps: number[] = [];
  if (sameStem) {
    for (let index = 1; index < positions.length; index++) {
      gaps.push(positions[index] - positions[index - 1]);
    }
  } else {
    const merged = [
      ...positions.map((position): [number, number] => [position, 0]),
      ...others.map((other): [number, number] => [other, 1]),
    ].sort((left, right) => left[0] - right[0]);
    for (let index = 1; index < merged.length; index++) {
      if (merged[index - 1][1] !== merged[index][1]) {
        gaps.push(merged[index][0] - merged[index - 1][0]);
      }
    }
  }
  return gaps.length > 0 ? Math.min(...gaps) : null;
}

function classify(lexeme: string): Item {
  if (OPERATORS.has(lexeme) || PARENTHESES.has(lexeme)) {
    return [lexeme as Kind, lexeme];
  }
  if (WORD_PATTERN.test(lexeme)) {
    return ['term', lexeme.toLowerCase()];
  }
  if (PREFIX_TERM_PATTERN.test(lexeme)) {
    return ['prefix', lexeme.slice(0, -1).toLowerCase()];
  }
  throw new CommandError(`BAD TERM ${lexeme}`);
}

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

function fraction(numerator: number, denominator: number): Fraction {
  const divisor = gcd(numerator, denominator);
  return { numerator: numerator / divisor, denominator: denominator / divisor };
}

function compareFractions(left: Fraction, right: Fraction): number {
  return left.numerator * right.denominator - right.numerator * left.denominator;
}

class Token {
  readonly text: string;
  readonly line: number;
  readonly position: number;
  readonly start: number;
  readonly form: string;

  constructor(text: string, line: number, position: number, start: number) {
    this.text = text;
    this.line = line;
    this.position = position;
    this.start = start;
    this.form = text.toLowerCase();
  }

  get end(): number {
    return this.start + this.text.length;
  }
}

class Document {
  readonly number: number;
  readonly lines: string[] = [];
  readonly tokens: Token[] = [];

  constructor(number: number) {
    this.number = number;
  }

  addLine(text: string): Token[] {
    this.lines.push(text);
    const added: Token[] = [];
    for (const match of text.matchAll(TOKEN_PATTERN)) {
      const token = new Token(match[0], this.lines.length, this.tokens.length + 1, match.index);
      this.tokens.push(token);
      added.push(token);
    }
    return added;
  }

  lineTokens(lineNumber: number): Token[] {
    return this.tokens.filter((token) => token.line === lineNumber);
  }

  reference(token: Token): string {
    return `${this.number}:${token.line}:${token.position}`;
  }
}

class QueryParser {
  private readonly items: Item[];
  private readonly stemSets: Map<number, Set<string>>;
  private position = 0;

  constructor(items: Item[], stemSets: Map<number, Set<string>>) {
    this.items = items;
    this.stemSets = stemSets;
  }

  private peek(): Kind | null {
    return this.position < this.items.length ? this.items[this.position][0] : null;
  }

  private take(): Item {
    if (this.position >= this.items.length) {
      throw new CommandError('SYNTAX');
    }
    return this.items[this.position++];
  }

  parse(): Evaluation {
    const result = this.expression();
    if (this.position < this.items.length) {
      throw new CommandError('SYNTAX');
    }
    return result;
  }

  private expression(): Evaluation {
    let [canonical, documents] = this.conjunction();
    while (this.peek() === 'OR') {
      this.position += 1;
      const [right, rightDocuments] = this.conjunction();
      canonical = `(${canonical} OR ${right})`;
      documents = documents.union(rightDocuments);
    }
    return [canonical, documents];
  }

  private conjunction(): Evaluation {
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

  private negation(): Evaluation {
    if (this.peek() === 'NOT') {
      this.position += 1;
      const [canonical, documents] = this.negation();
      return [`(NOT ${canonical})`, new Set(this.stemSets.keys()).difference(documents)];
    }
    return this.element();
  }

  private element(): Evaluation {
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

  private documentsWhere(predicate: (stems: Set<string>) => boolean): Set<number> {
    const numbers = [...this.stemSets].filter(([, stems]) => predicate(stems));
    return new Set(numbers.map(([number]) => number));
  }
}

class SearchEngine {
  readonly output: string[] = [];
  private readonly stopwords: Set<string>;
  private readonly documents = new Map<number, Document>();
  private readonly handlers: Map<string, [minimum: number, maximum: number, handler: Handler]>;

  constructor(stopwords: Set<string>) {
    this.stopwords = stopwords;
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

  private emit(...parts: (string | number)[]): void {
    this.output.push(parts.join(' '));
  }

  addDocument(number: number): Document {
    const document = new Document(number);
    this.documents.set(number, document);
    return document;
  }

  private orderedDocuments(): Document[] {
    return [...this.documents]
      .sort(([left], [right]) => left - right)
      .map(([, document]) => document);
  }

  private isIndexed(token: Token): boolean {
    return !this.stopwords.has(token.form);
  }

  private indexedTokens(document: Document): Token[] {
    return document.tokens.filter((token) => this.isIndexed(token));
  }

  private termFrequencies(document: Document): Map<string, number> {
    return countValues(this.indexedTokens(document).map((token) => porterStem(token.form)));
  }

  private stemSet(document: Document): Set<string> {
    return new Set(this.termFrequencies(document).keys());
  }

  private totalFrequencies(): Map<string, number> {
    const stems = [...this.documents.values()].flatMap((document) =>
      this.indexedTokens(document).map((token) => porterStem(token.form)),
    );
    return countValues(stems);
  }

  private occurrenceMap(): Map<string, Occurrence[]> {
    const occurrences = new Map<string, Occurrence[]>();
    for (const document of this.orderedDocuments()) {
      for (const token of this.indexedTokens(document)) {
        const stem = porterStem(token.form);
        let found = occurrences.get(stem);
        if (found === undefined) {
          found = [];
          occurrences.set(stem, found);
        }
        found.push([document, token]);
      }
    }
    return occurrences;
  }

  private stemPositions(document: Document, stem: string): number[] {
    return this.indexedTokens(document)
      .filter((token) => porterStem(token.form) === stem)
      .map((token) => token.position);
  }

  private formCount(form: string): number {
    let count = 0;
    for (const document of this.documents.values()) {
      count += document.tokens.filter((token) => token.form === form).length;
    }
    return count;
  }

  private tokenMatches(token: Token, target: string): boolean {
    return target === '?' || (this.isIndexed(token) && porterStem(token.form) === target);
  }

  private describeToken(token: Token): string {
    if (this.isIndexed(token)) {
      return `${token.form}/${porterStem(token.form)}`;
    }
    return `${token.form}/-`;
  }

  private termArgument(text: string): string {
    const word = wordArgument(text);
    if (this.stopwords.has(word)) {
      throw new CommandError(`STOPWORD ${word}`);
    }
    return porterStem(word);
  }

  private documentArgument(text: string): Document {
    const number = numberArgument(text, 1, MAX_DOCUMENT_NUMBER);
    const document = this.documents.get(number);
    if (document === undefined) {
      throw new CommandError(`NO DOC ${number}`);
    }
    return document;
  }

  private stemWords(args: string[]): void {
    const words = args.map(wordArgument);
    this.emit('STEM', ...words.map((word) => `${word}:${porterStem(word)}`));
  }

  private showSteps(args: string[]): void {
    const word = wordArgument(args[0]);
    const [, changes] = stemmingSteps(word);
    if (changes.length === 0) {
      this.emit('STEPS', word, 'NONE');
    } else {
      this.emit('STEPS', word, ...changes.map(([name, result]) => `${name}:${result}`));
    }
  }

  private showMeasure(args: string[]): void {
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

  private showIndex(args: string[]): void {
    const prefix = args.length > 0 ? wordArgument(args[0]) : '';
    const occurrences = this.occurrenceMap();
    const stems = [...occurrences.keys()].filter((stem) => stem.startsWith(prefix)).sort();
    this.emit('INDEX', `stems=${stems.length}`);
    for (const stem of stems) {
      const found = occurrences.get(stem) ?? [];
      this.emit(
        stem,
        `df=${documentCount(found)}`,
        ...found.map(([document, token]) => document.reference(token)),
      );
    }
  }

  private search(args: string[]): void {
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

  private phrase(args: string[]): void {
    const words = args.map(wordArgument);
    if (words.every((word) => this.stopwords.has(word))) {
      throw new CommandError('STOPWORDS ONLY');
    }
    const targets = words.map((word) => (this.stopwords.has(word) ? '?' : porterStem(word)));
    const matches: string[] = [];
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

  private near(args: string[]): void {
    const first = this.termArgument(args[0]);
    const second = this.termArgument(args[1]);
    const limit = numberArgument(args[2], 1, MAX_COUNT);
    const found: string[] = [];
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

  private top(args: string[]): void {
    const limit = numberArgument(args[0], 1, MAX_COUNT);
    let counts: Map<string, number>;
    let header: string;
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

  private kwic(args: string[]): void {
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

  private termFrequency(args: string[]): void {
    const document = this.documentArgument(args[0]);
    const stem = this.termArgument(args[1]);
    this.emit('TF', document.number, stem, this.termFrequencies(document).get(stem) ?? 0);
  }

  private documentFrequency(args: string[]): void {
    const stem = this.termArgument(args[0]);
    this.emit('DF', stem, documentCount(this.occurrenceMap().get(stem) ?? []));
  }

  private variants(args: string[]): void {
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

  private similar(args: string[]): void {
    const document = this.documentArgument(args[0]);
    const limit = numberArgument(args[1], 1, MAX_COUNT);
    const stems = this.stemSet(document);
    const scores: { score: Fraction; number: number }[] = [];
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

  private rank(args: string[]): void {
    const limit = numberArgument(args[0], 1, MAX_COUNT);
    const query = new Set(args.slice(1).map((argument) => this.termArgument(argument)));
    const ranked: { matched: number; total: number; number: number }[] = [];
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

  private info(args: string[]): void {
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

  private showLine(args: string[]): void {
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

  private stats(): void {
    const documents = [...this.documents.values()];
    const sum = (count: (document: Document) => number) =>
      documents.reduce((total, document) => total + count(document), 0);
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

  private stop(args: string[]): void {
    const word = wordArgument(args[0]);
    if (this.stopwords.has(word)) {
      throw new CommandError(`ALREADY STOPWORD ${word}`);
    }
    this.stopwords.add(word);
    this.emit('STOP', word, `unindexed=${this.formCount(word)}`);
  }

  private unstop(args: string[]): void {
    const word = wordArgument(args[0]);
    if (!this.stopwords.has(word)) {
      throw new CommandError(`NOT STOPWORD ${word}`);
    }
    this.stopwords.delete(word);
    this.emit('UNSTOP', word, `indexed=${this.formCount(word)}`);
  }

  private append(args: string[]): void {
    const number = numberArgument(args[0], 1, MAX_DOCUMENT_NUMBER);
    const existing = this.documents.get(number);
    const document = existing ?? this.addDocument(number);
    const tokens = document.addLine(args[1]);
    const indexed = tokens.filter((token) => this.isIndexed(token)).length;
    this.emit(
      'APPEND',
      number,
      `line=${document.lines.length}`,
      `tokens=${tokens.length}`,
      `indexed=${indexed}`,
      `new=${yesNo(existing === undefined)}`,
    );
  }

  private delete(args: string[]): void {
    const document = this.documentArgument(args[0]);
    this.documents.delete(document.number);
    this.emit(
      'DELETE',
      document.number,
      `lines=${document.lines.length}`,
      `tokens=${document.tokens.length}`,
    );
  }

  execute(line: string): void {
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

function main(): void {
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
