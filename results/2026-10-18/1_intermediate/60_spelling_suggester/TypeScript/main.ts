import { readFileSync } from "node:fs";

type WordToken = {
  number: number; text: string; word: string;
  start: number; end: number; gap: string;
  sentenceStart: boolean; repeat: boolean; mixedCase: boolean;
};
type Candidate = {word: string; distance: number; frequency: number};
type UndoRecord = {
  name: string;
  dictionary: Map<string, number>;
  ignored: Set<string>;
  rules: Map<string, string>;
};

const ADJACENT: Record<string, string> = {
  a: "qswz", b: "ghnv", c: "dfvx", d: "cefrsx", e: "drsw",
  f: "cdgrtv", g: "bfhtvy", h: "bgjnuy", i: "jkou", j: "hikmnu",
  k: "ijlmo", l: "kop", m: "jkn", n: "bhjm", o: "iklp",
  p: "lo", q: "aw", r: "deft", s: "adewxz", t: "fgry",
  u: "hijy", v: "bcfg", w: "aeqs", x: "cdsz", y: "ghtu",
  z: "asx"
};
const SOUND_DIGITS: Record<string, string> = {};
for (const [letters, digit] of [
  ["bfpv", "1"], ["cgjkqsxz", "2"], ["dt", "3"],
  ["l", "4"], ["mn", "5"], ["r", "6"], ["aeiouy", "0"]
]) for (const letter of letters) SOUND_DIGITS[letter] = digit;

const TEXT_COMMANDS = new Set(["CHECK", "CORRECT", "FIX", "PROFILE", "LEARN"]);
const ARITIES: Record<string, number> = {
  SUGGEST: 1, DIST: 2, SOUNDEX: 1, SOUNDS: 1, SPLIT: 1,
  PREFIX: 2, COMPLETE: 2, LIST: 2, WORD: 1, ADD: 2,
  REMOVE: 1, IGNORE: 1, UNIGNORE: 1, RULE: 2, UNRULE: 1,
  RULES: 0, KEYBOARD: 1, SET: 2, UNDO: 0, REPORT: 0,
  HISTORY: 0, STATS: 0
};
const COUNTERS = ["checked", "unknown", "case", "capital", "repeats", "corrected"];
const FINDINGS = ["unknown", "case", "capital", "repeats"];
const cmp = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;

class CommandError extends Error {}

function wordArgument(text: string): string {
  if (!/^[A-Za-z]{1,30}$/.test(text)) throw new CommandError("BAD WORD " + text);
  return text.toLowerCase();
}

function numberArgument(text: string, minimum: number, maximum: number): number {
  if (!/^[0-9]{1,7}$/.test(text)) throw new CommandError("BAD NUMBER " + text);
  const value = Number(text);
  if (value < minimum || value > maximum)
    throw new CommandError("BAD NUMBER " + text);
  return value;
}

function decimalText(numerator: number, denominator: number, digits: number): string {
  const scale = 10 ** digits;
  const rounded = Math.floor((2 * numerator * scale + denominator) / (2 * denominator));
  return Math.floor(rounded / scale) + "." + String(rounded % scale).padStart(digits, "0");
}

function applyCase(token: string, replacement: string): string {
  if (token.length >= 2 && token === token.toUpperCase()) return replacement.toUpperCase();
  if (/[A-Z]/.test(token[0])) return replacement[0].toUpperCase() + replacement.slice(1);
  return replacement;
}

function tokens(text: string): WordToken[] {
  const result: WordToken[] = [];
  let previous: WordToken | null = null, lastEnd = 0;
  for (const match of text.matchAll(/[A-Za-z]+/g)) {
    const spelling = match[0];
    const start = match.index ?? 0;
    const gap = text.slice(lastEnd, start);
    const word = spelling.toLowerCase();
    const token = {
      number: result.length + 1,
      text: spelling,
      word,
      start,
      end: start + spelling.length,
      gap,
      sentenceStart: previous === null || /[.!?]/.test(gap),
      repeat: previous !== null && word === previous.word && /^ *$/.test(gap),
      mixedCase: /[A-Z]/.test(spelling.slice(1)) && spelling !== spelling.toUpperCase()
    };
    result.push(token);
    previous = token;
    lastEnd = token.end;
  }
  return result;
}

const gapCost = (keyboard: boolean): number => keyboard ? 2 : 1;
function subCost(a: string, b: string, keyboard: boolean): number {
  return a === b ? 0 : !keyboard ? 1 : ADJACENT[a].includes(b) ? 1 : 2;
}
function swapped(a: string, b: string, i: number, j: number): boolean {
  return i >= 2 && j >= 2 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1];
}

function distanceTable(a: string, b: string, keyboard: boolean): number[][] {
  const gap = gapCost(keyboard), p = a.length, q = b.length;
  const d = Array.from({length: p + 1}, () => Array(q + 1).fill(0));
  for (let i = 0; i <= p; ++i) d[i][0] = i * gap;
  for (let j = 0; j <= q; ++j) d[0][j] = j * gap;
  for (let i = 1; i <= p; ++i) {
    for (let j = 1; j <= q; ++j) {
      d[i][j] = Math.min(
        d[i - 1][j] + gap,
        d[i][j - 1] + gap,
        d[i - 1][j - 1] + subCost(a[i - 1], b[j - 1], keyboard)
      );
      if (swapped(a, b, i, j)) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
    }
  }
  return d;
}

function editDistance(a: string, b: string, keyboard: boolean): number {
  return distanceTable(a, b, keyboard)[a.length][b.length];
}

function prefixDistance(a: string, b: string, keyboard: boolean): number {
  return Math.min(...distanceTable(a, b, keyboard)[a.length]);
}

function editOperations(a: string, b: string, keyboard: boolean): [number, string[]] {
  const d = distanceTable(a, b, keyboard);
  const gap = gapCost(keyboard), operations: string[] = [];
  let i = a.length, j = b.length;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 &&
        d[i][j] === d[i - 1][j - 1] + subCost(a[i - 1], b[j - 1], keyboard)) {
      if (a[i - 1] !== b[j - 1]) operations.push("sub:" + a[i - 1] + ">" + b[j - 1]);
      --i; --j;
    } else if (swapped(a, b, i, j) && d[i][j] === d[i - 2][j - 2] + 1) {
      operations.push("swap:" + a.slice(i - 2, i));
      i -= 2; j -= 2;
    } else if (i > 0 && d[i][j] === d[i - 1][j] + gap) {
      operations.push("del:" + a[i - 1]);
      --i;
    } else {
      operations.push("ins:" + b[j - 1]);
      --j;
    }
  }
  operations.reverse();
  return [d[a.length][b.length], operations];
}

function soundex(word: string): string {
  let code = word[0].toUpperCase();
  let previous = "hw".includes(word[0]) ? "0" : SOUND_DIGITS[word[0]];
  for (const letter of word.slice(1)) {
    if ("hw".includes(letter)) continue;
    const digit = SOUND_DIGITS[letter];
    if (digit !== "0" && digit !== previous) code += digit;
    previous = digit;
  }
  return (code + "000").slice(0, 4);
}

function compareSequence(a: string[], b: string[]): number {
  for (let i = 0; i < Math.min(a.length, b.length); ++i) {
    const result = cmp(a[i], b[i]);
    if (result !== 0) return result;
  }
  return a.length - b.length;
}

function segment(word: string, dictionary: Map<string, number>): [number, string[] | null] {
  const n = word.length;
  const ways: number[] = Array(n + 1).fill(0), best: (string[] | null)[] = Array(n + 1).fill(null);
  ways[n] = 1; best[n] = [];
  for (let start = n - 1; start >= 0; --start) {
    for (let end = start + 1; end <= n; ++end) {
      const piece = word.slice(start, end);
      if (!dictionary.has(piece) || ways[end] === 0) continue;
      ways[start] += ways[end];
      const candidate = [piece, ...best[end]!];
      if (best[start] === null || candidate.length < best[start].length ||
          (candidate.length === best[start].length && compareSequence(candidate, best[start]) < 0))
        best[start] = candidate;
    }
  }
  return [ways[0], best[0]];
}

class SpellChecker {
  dictionary: Map<string, number>;
  ignored: Set<string>;
  rules: Map<string, string>;
  keyboard: boolean;
  baseLimit: number;
  suggestionCount: number;
  undoHistory: UndoRecord[];
  unknownLog: Map<string, number>;
  correctionLog: Map<string, number>;
  counters: Record<string, number>;
  output: string[];

  constructor(dictionary: Map<string, number>) {
    this.dictionary = dictionary;
    this.ignored = new Set();
    this.rules = new Map();
    this.keyboard = false;
    this.baseLimit = 2;
    this.suggestionCount = 5;
    this.undoHistory = [];
    this.unknownLog = new Map();
    this.correctionLog = new Map();
    this.counters = Object.fromEntries(COUNTERS.map(key => [key, 0]));
    this.output = [];
  }

  emit(...parts: (string | number)[]): void {
    this.output.push(parts.join(" "));
  }

  get limit(): number {
    return this.keyboard ? this.baseLimit * 2 : this.baseLimit;
  }

  known(word: string): boolean {
    return this.dictionary.has(word) || this.ignored.has(word);
  }

  frequencyOrder(): string[] {
    return [...this.dictionary.keys()].sort((a, b) =>
      this.dictionary.get(b)! - this.dictionary.get(a)! || cmp(a, b));
  }

  requireEntry(word: string): number {
    if (!this.dictionary.has(word)) throw new CommandError("NOT FOUND " + word);
    return this.dictionary.get(word)!;
  }

  candidates(word: string): Candidate[] {
    const gap = gapCost(this.keyboard), limit = this.limit;
    const found: Candidate[] = [];
    for (const [other, frequency] of this.dictionary) {
      if (other === word || Math.abs(other.length - word.length) * gap > limit) continue;
      const distance = editDistance(word, other, this.keyboard);
      if (distance <= limit) found.push({word: other, distance, frequency});
    }
    found.sort((a, b) =>
      a.distance - b.distance || b.frequency - a.frequency || cmp(a.word, b.word));
    return found;
  }

  correction(word: string): string | null {
    if (this.known(word)) return null;
    if (this.rules.has(word)) return this.rules.get(word)!;
    const found = this.candidates(word);
    return found.length > 0 ? found[0].word : null;
  }

  saveUndo(name: string): void {
    this.undoHistory.push({
      name, dictionary: new Map(this.dictionary),
      ignored: new Set(this.ignored), rules: new Map(this.rules)
    });
  }

  logCorrection(original: string, replacement: string): void {
    const key = original + "\u0000" + replacement;
    this.correctionLog.set(key, (this.correctionLog.get(key) ?? 0) + 1);
    ++this.counters.corrected;
  }

  unknownFinding(token: WordToken): string {
    const prefix = "UNKNOWN " + token.number + " " + token.text;
    if (this.rules.has(token.word))
      return prefix + " RULE " + this.rules.get(token.word)!;
    const found = this.candidates(token.word);
    if (found.length === 0) return prefix + " NONE";
    return prefix + " SUGGEST " +
      found.slice(0, this.suggestionCount).map(item => item.word).join(" ");
  }

  checkText(text: string): void {
    const list = tokens(text), findings: string[] = [];
    const totals = Object.fromEntries(FINDINGS.map(key => [key, 0]));
    for (const token of list) {
      if (!this.known(token.word)) {
        findings.push(this.unknownFinding(token));
        ++totals.unknown;
        this.unknownLog.set(token.word, (this.unknownLog.get(token.word) ?? 0) + 1);
      }
      if (token.mixedCase) {
        findings.push("CASE " + token.number + " " + token.text);
        ++totals.case;
      }
      if (token.sentenceStart && /^[a-z]/.test(token.text)) {
        findings.push("CAPITAL " + token.number + " " + token.text);
        ++totals.capital;
      }
      if (token.repeat) {
        findings.push("REPEAT " + token.number + " " + token.text);
        ++totals.repeats;
      }
    }
    this.counters.checked += list.length;
    for (const key of FINDINGS) this.counters[key] += totals[key];
    this.emit("CHECK", "words=" + list.length,
      ...FINDINGS.map(key => key + "=" + totals[key]));
    for (const finding of findings) this.emit(finding);
  }

  correctText(text: string): void {
    let position = 0, changed = 0, result = "";
    for (const token of tokens(text)) {
      const replacement = this.correction(token.word);
      if (replacement === null) {
        result += token.gap + token.text;
      } else {
        result += token.gap + applyCase(token.text, replacement);
        this.logCorrection(token.word, replacement);
        ++changed;
      }
      position = token.end;
    }
    result += text.slice(position);
    this.emit("CORRECT", "changed=" + changed + ":", result);
  }

  fixText(text: string): void {
    let position = 0, removed = 0, replaced = 0, recased = 0, result = "";
    for (const token of tokens(text)) {
      position = token.end;
      if (token.repeat) {
        ++removed;
        continue;
      }
      const replacement = this.correction(token.word);
      const target = replacement === null ? token.word : replacement;
      let converted = applyCase(token.text, target);
      if (token.sentenceStart && /^[a-z]/.test(converted))
        converted = converted[0].toUpperCase() + converted.slice(1);
      if (replacement !== null) {
        this.logCorrection(token.word, replacement);
        ++replaced;
      } else if (converted !== token.text) {
        ++recased;
      }
      result += token.gap + converted;
    }
    result += text.slice(position);
    this.emit("FIX", "removed=" + removed, "replaced=" + replaced,
      "recased=" + recased + ":", result);
  }

  profileText(text: string): void {
    const list = tokens(text);
    const distinct = new Set(list.map(t => t.word)).size;
    const unknown = list.filter(t => !this.known(t.word)).length;
    const sentences = list.filter(t => t.sentenceStart).length;
    let rate = "0.0", average = "0.00", longest = "-";
    if (list.length > 0) {
      rate = decimalText(100 * unknown, list.length, 1);
      average = decimalText(list.reduce((total, t) => total + t.text.length, 0), list.length, 2);
      longest = list.reduce((best, token) =>
        token.text.length > best.text.length ? token : best).word;
    }
    this.emit("PROFILE", "words=" + list.length, "distinct=" + distinct,
      "unknown=" + unknown, "rate=" + rate, "avglen=" + average,
      "longest=" + longest, "sentences=" + sentences);
  }

  learnText(text: string): void {
    this.saveUndo("LEARN");
    let updated = 0, added = 0, skipped = 0;
    for (const token of tokens(text)) {
      if (token.word.length > 30) {
        ++skipped;
      } else if (this.dictionary.has(token.word)) {
        this.dictionary.set(token.word, this.dictionary.get(token.word)! + 1);
        ++updated;
      } else {
        this.dictionary.set(token.word, 1);
        this.ignored.delete(token.word);
        ++added;
      }
    }
    this.emit("LEARN", "updated=" + updated, "added=" + added, "skipped=" + skipped);
  }

  suggest([raw]: string[]): void {
    const word = wordArgument(raw);
    if (this.known(word)) {
      this.emit("SUGGEST", word, "KNOWN");
    } else if (this.rules.has(word)) {
      this.emit("SUGGEST", word, "RULE", this.rules.get(word)!);
    } else {
      const found = this.candidates(word);
      this.emit("SUGGEST", word, "found=" + found.length,
        ...found.slice(0, this.suggestionCount).map(item => item.word + ":" + item.distance));
    }
  }

  dist([left, right]: string[]): void {
    const first = wordArgument(left), second = wordArgument(right);
    const [distance, operations] = editOperations(first, second, this.keyboard);
    this.emit("DIST", first, second, distance, ...operations);
  }

  soundexCode([raw]: string[]): void {
    const word = wordArgument(raw);
    this.emit("SOUNDEX", word, soundex(word));
  }

  sounds([raw]: string[]): void {
    const word = wordArgument(raw), code = soundex(word);
    const found = this.frequencyOrder().filter(other =>
      other !== word && soundex(other) === code);
    this.emit("SOUNDS", word, code, "count=" + found.length, ...found.slice(0, 10));
  }

  split([raw]: string[]): void {
    const word = wordArgument(raw);
    const [ways, best] = segment(word, this.dictionary);
    this.emit("SPLIT", word, "ways=" + ways, "->", ...(ways === 0 ? ["NONE"] : best));
  }

  prefix([raw, countText]: string[]): void {
    const word = wordArgument(raw), count = numberArgument(countText, 1, 20);
    const found = this.frequencyOrder().filter(other => other.startsWith(word));
    this.emit("PREFIX", word, "count=" + found.length,
      ...found.slice(0, count).map(other => other + ":" + this.dictionary.get(other)));
  }

  complete([raw, countText]: string[]): void {
    const word = wordArgument(raw), count = numberArgument(countText, 1, 20);
    const threshold = Math.floor(this.limit / 2);
    const found: Candidate[] = [];
    for (const [other, frequency] of this.dictionary) {
      const distance = prefixDistance(word, other, this.keyboard);
      if (distance <= threshold) found.push({word: other, distance, frequency});
    }
    found.sort((a, b) => a.distance - b.distance ||
      b.frequency - a.frequency || cmp(a.word, b.word));
    this.emit("COMPLETE", word, "count=" + found.length,
      ...found.slice(0, count).map(item => item.word + ":" + item.distance));
  }

  listWords([raw, countText]: string[]): void {
    const word = wordArgument(raw), count = numberArgument(countText, 1, 20);
    const found = [...this.dictionary.keys()].filter(other => cmp(other, word) >= 0).sort(cmp);
    this.emit("LIST", word, "count=" + found.length,
      ...found.slice(0, count).map(other => other + ":" + this.dictionary.get(other)));
  }

  wordInfo([raw]: string[]): void {
    const word = wordArgument(raw), frequency = this.requireEntry(word);
    const rank = this.frequencyOrder().indexOf(word) + 1;
    this.emit("WORD", word, "freq=" + frequency, "rank=" + rank,
      "soundex=" + soundex(word), "neighbors=" + this.candidates(word).length);
  }

  add([raw, number]: string[]): void {
    const word = wordArgument(raw), frequency = numberArgument(number, 1, 1_000_000);
    if (this.dictionary.has(word)) throw new CommandError("DUPLICATE " + word);
    this.saveUndo("ADD");
    this.dictionary.set(word, frequency);
    this.ignored.delete(word);
    this.emit("ADD", word, frequency);
  }

  remove([raw]: string[]): void {
    const word = wordArgument(raw), frequency = this.requireEntry(word);
    this.saveUndo("REMOVE");
    this.dictionary.delete(word);
    this.emit("REMOVE", word, frequency);
  }

  ignore([raw]: string[]): void {
    const word = wordArgument(raw);
    if (this.dictionary.has(word)) throw new CommandError("IN DICTIONARY " + word);
    if (this.ignored.has(word)) throw new CommandError("ALREADY IGNORED " + word);
    this.saveUndo("IGNORE");
    this.ignored.add(word);
    this.emit("IGNORE", word);
  }

  unignore([raw]: string[]): void {
    const word = wordArgument(raw);
    if (!this.ignored.has(word)) throw new CommandError("NOT IGNORED " + word);
    this.saveUndo("UNIGNORE");
    this.ignored.delete(word);
    this.emit("UNIGNORE", word);
  }

  rule([rawSource, rawTarget]: string[]): void {
    const source = wordArgument(rawSource), target = wordArgument(rawTarget);
    if (this.dictionary.has(source)) throw new CommandError("IN DICTIONARY " + source);
    if (!this.dictionary.has(target)) throw new CommandError("NOT FOUND " + target);
    this.saveUndo("RULE");
    const previous = this.rules.get(source);
    this.rules.set(source, target);
    if (previous === undefined) this.emit("RULE", source, target);
    else this.emit("RULE", source, target, "REPLACED", previous);
  }

  unrule([raw]: string[]): void {
    const word = wordArgument(raw);
    if (!this.rules.has(word)) throw new CommandError("NO RULE " + word);
    this.saveUndo("UNRULE");
    const target = this.rules.get(word)!;
    this.rules.delete(word);
    this.emit("UNRULE", word, target);
  }

  showRules(): void {
    const rows = [...this.rules].sort((a, b) => cmp(a[0], b[0]));
    this.emit("RULES", "count=" + rows.length,
      ...rows.map(([source, target]) => source + ">" + target));
  }

  keyboardMode([mode]: string[]): void {
    if (mode !== "ON" && mode !== "OFF") throw new CommandError("BAD MODE " + mode);
    this.keyboard = mode === "ON";
    this.emit("KEYBOARD", mode);
  }

  setOption([option, raw]: string[]): void {
    const options: Record<string, number> = {LIMIT: 3, SUGGESTIONS: 10};
    const maximum = options[option];
    if (maximum === undefined) throw new CommandError("BAD OPTION " + option);
    const value = numberArgument(raw, 1, maximum);
    if (option === "LIMIT") this.baseLimit = value;
    else this.suggestionCount = value;
    this.emit("SET", option, value);
  }

  undo(): void {
    if (this.undoHistory.length === 0) throw new CommandError("NOTHING TO UNDO");
    const record = this.undoHistory.pop()!;
    this.dictionary = record.dictionary;
    this.ignored = record.ignored;
    this.rules = record.rules;
    this.emit("UNDO", record.name);
  }

  report(): void {
    const rows = [...this.unknownLog].sort((a, b) =>
      b[1] - a[1] || cmp(a[0], b[0]));
    this.emit("REPORT", "distinct=" + rows.length,
      ...rows.slice(0, 10).map(([word, count]) => word + ":" + count));
  }

  history(): void {
    const rows = [...this.correctionLog].map(([key, count]) => {
      const [word, replacement] = key.split("\u0000");
      return {word, replacement, count};
    });
    rows.sort((a, b) =>
      b.count - a.count || cmp(a.word, b.word) || cmp(a.replacement, b.replacement));
    this.emit("HISTORY", "distinct=" + rows.length,
      ...rows.slice(0, 10).map(row =>
        row.word + ">" + row.replacement + ":" + row.count));
  }

  stats(): void {
    const top = this.frequencyOrder()[0];
    const total = [...this.dictionary.values()].reduce((a, b) => a + b, 0);
    const characters = [...this.dictionary.keys()].reduce((a, word) => a + word.length, 0);
    this.emit("STATS", "words=" + this.dictionary.size,
      "total=" + total, "avglen=" + decimalText(characters, this.dictionary.size, 2),
      "top=" + top + ":" + this.dictionary.get(top), "ignored=" + this.ignored.size,
      "rules=" + this.rules.size, "keyboard=" + (this.keyboard ? "ON" : "OFF"),
      "limit=" + this.limit, "suggestions=" + this.suggestionCount,
      "undo=" + this.undoHistory.length);
    this.emit("SESSION", ...COUNTERS.map(name => name + "=" + this.counters[name]));
  }

  execute(line: string): void {
    const separator = line.indexOf(" ");
    const name = separator === -1 ? line : line.slice(0, separator);
    const rest = separator === -1 ? "" : line.slice(separator + 1);
    try {
      if (!TEXT_COMMANDS.has(name) && !Object.hasOwn(ARITIES, name))
        throw new CommandError("UNKNOWN COMMAND " + name);
      if (TEXT_COMMANDS.has(name)) {
        if (separator === -1) throw new CommandError("BAD ARGUMENTS " + name);
        switch (name) {
          case "CHECK": this.checkText(rest); break;
          case "CORRECT": this.correctText(rest); break;
          case "FIX": this.fixText(rest); break;
          case "PROFILE": this.profileText(rest); break;
          case "LEARN": this.learnText(rest); break;
        }
        return;
      }
      const argumentsList = separator === -1 ? [] : rest.split(" ");
      if (argumentsList.length !== ARITIES[name])
        throw new CommandError("BAD ARGUMENTS " + name);
      switch (name) {
        case "SUGGEST": this.suggest(argumentsList); break;
        case "DIST": this.dist(argumentsList); break;
        case "SOUNDEX": this.soundexCode(argumentsList); break;
        case "SOUNDS": this.sounds(argumentsList); break;
        case "SPLIT": this.split(argumentsList); break;
        case "PREFIX": this.prefix(argumentsList); break;
        case "COMPLETE": this.complete(argumentsList); break;
        case "LIST": this.listWords(argumentsList); break;
        case "WORD": this.wordInfo(argumentsList); break;
        case "ADD": this.add(argumentsList); break;
        case "REMOVE": this.remove(argumentsList); break;
        case "IGNORE": this.ignore(argumentsList); break;
        case "UNIGNORE": this.unignore(argumentsList); break;
        case "RULE": this.rule(argumentsList); break;
        case "UNRULE": this.unrule(argumentsList); break;
        case "RULES": this.showRules(); break;
        case "KEYBOARD": this.keyboardMode(argumentsList); break;
        case "SET": this.setOption(argumentsList); break;
        case "UNDO": this.undo(); break;
        case "REPORT": this.report(); break;
        case "HISTORY": this.history(); break;
        case "STATS": this.stats(); break;
      }
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit("ERROR", error.message);
    }
  }
}

function main(): void {
  const lines = readFileSync(0, "utf8").split(/\r?\n/);
  let index = 0;
  const dictionary = new Map<string, number>();
  const count = Number(lines[index++]);
  for (let i = 0; i < count; ++i) {
    const [word, frequency] = lines[index++].split(" ");
    dictionary.set(word, Number(frequency));
  }
  const checker = new SpellChecker(dictionary);
  const commands = Number(lines[index++]);
  for (let i = 0; i < commands; ++i) checker.execute(lines[index++]);
  process.stdout.write(checker.output.join("\n") + "\n");
}

main();
