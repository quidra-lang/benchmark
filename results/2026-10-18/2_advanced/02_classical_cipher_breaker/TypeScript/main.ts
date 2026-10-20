import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { parseWeights, letters, mono, bigram } from './scoring.ts';
import { affineMultipliers, mod, substitute, type SubstitutionCipher } from './substitution.ts';
import { railfence, columnar } from './transposition.ts';
import { playfair, validPlayfair, square } from './playfair.ts';
import { counts, ioc, columns, kasiski, periods, percentage, pairCounts, topPairs, type Kasiski, type Period } from './analysis.ts';

type Cipher = SubstitutionCipher | 'railfence' | 'columnar' | 'playfair';
type Command = 'ENCRYPT' | 'DECRYPT' | 'BREAK' | 'ANALYZE' | 'COMPARE' | 'IDENTIFY';
interface Options { TOP: number; MAXLEN: number; IOC: number; KASISKI: number; REFINE: number; MAXRAILS: number; KEYS?: string }
interface Job { command: Command; cipher?: Cipher; key?: string; source: string; other?: string; newName?: string; options: Options }
interface Candidate { key: string; plaintext: string; score: number; order: number }
interface BreakResult { ranked: Candidate[]; key: string; score: number; details: string[] }
const commands: Command[] = ['ENCRYPT', 'DECRYPT', 'BREAK', 'ANALYZE', 'COMPARE', 'IDENTIFY'];
const ciphers: Cipher[] = ['caesar', 'affine', 'vigenere', 'autokey', 'playfair', 'railfence', 'columnar'];
const weights = parseWeights(readFileSync('input/weights.txt', 'utf8'));
const messages = new Map<string, string[]>();
const results: string[] = [], candidates: string[] = [], analysis: string[] = [];
const totals = new Map(commands.map(command => [command, { ok: 0, errors: 0 }]));
function isCommand(value: string): value is Command { return commands.some(command => command === value); }
function isCipher(value: string): value is Cipher { return ciphers.some(cipher => cipher === value); }
function substitution(cipher: Cipher): cipher is SubstitutionCipher {
  return cipher === 'caesar' || cipher === 'affine' || cipher === 'vigenere' || cipher === 'autokey';
}
function fail(reason: string): never { throw new Error(reason); }
function defaults(cipher?: Cipher): Options {
  return { TOP: 5, MAXLEN: cipher === 'autokey' ? 8 : cipher === 'columnar' ? 6 : 10,
    IOC: 6000, KASISKI: 60, REFINE: 5, MAXRAILS: 10 };
}
const validName = (name: string) => /^[a-z0-9_]{1,16}$/.test(name);
function normalizeKey(cipher: Cipher, key: string): string {
  const small = /^\d{1,2}$/;
  let valid = false;
  if (cipher === 'caesar') valid = small.test(key) && Number(key) <= 25;
  else if (cipher === 'railfence') valid = small.test(key) && Number(key) >= 2 && Number(key) <= 20;
  else if (cipher === 'affine') {
    const parts = key.split(',');
    valid = parts.length === 2 && parts.every(part => small.test(part)) && affineMultipliers.includes(Number(parts[0])) && Number(parts[1]) <= 25;
  } else if (cipher === 'columnar') valid = /^[A-Za-z0-9]{2,9}$/.test(key);
  else valid = (cipher === 'playfair' ? /^[A-Za-z]{1,25}$/ : /^[A-Za-z]{1,20}$/).test(key);
  if (!valid) fail(`bad key ${key}`);
  if (cipher === 'caesar' || cipher === 'railfence') return String(Number(key));
  if (cipher === 'affine') return key.split(',').map(Number).join(',');
  return cipher === 'playfair' ? key.toUpperCase().replaceAll('J', 'I') : key.toUpperCase();
}
function parseJob(line: string): Job {
  const words = line.split(' '), command = words[0];
  if (!isCommand(command)) fail('unknown command');
  let newName: string | undefined;
  if (['ENCRYPT', 'DECRYPT', 'BREAK'].includes(command) && words.length >= 5 && words.at(-2) === 'AS') {
    newName = words.pop()!; words.pop();
    if (!validName(newName)) fail('bad syntax');
  }
  if ((command === 'ENCRYPT' || command === 'DECRYPT') && words.length !== 4
    || command === 'BREAK' && words.length < 3
    || (command === 'ANALYZE' || command === 'IDENTIFY') && (words.length < 2 || words.length > 3)
    || command === 'COMPARE' && words.length !== 3) fail('bad syntax');
  let cipher: Cipher | undefined, key: string | undefined;
  if (command === 'ENCRYPT' || command === 'DECRYPT' || command === 'BREAK') {
    if (!isCipher(words[1])) fail(`unknown cipher ${words[1]}`);
    cipher = words[1];
    if (command !== 'BREAK') key = normalizeKey(cipher, words[2]);
  }
  const options = defaults(cipher);
  if (command === 'BREAK' || command === 'ANALYZE' || command === 'IDENTIFY') {
    const allowed = command === 'ANALYZE' ? ['MAXLEN'] : command === 'IDENTIFY' ? ['KEYS']
      : cipher === 'vigenere' ? ['TOP', 'MAXLEN', 'IOC', 'KASISKI', 'REFINE']
      : cipher === 'autokey' || cipher === 'columnar' ? ['TOP', 'MAXLEN']
      : cipher === 'railfence' ? ['TOP', 'MAXRAILS'] : cipher === 'playfair' ? ['TOP', 'KEYS'] : ['TOP'];
    const seen = new Set<string>();
    for (const option of words.slice(command === 'BREAK' ? 3 : 2)) {
      const equal = option.indexOf('='), name = option.slice(0, equal), value = option.slice(equal + 1);
      if (equal < 0 || !allowed.includes(name) || seen.has(name)) fail(`bad option ${option}`);
      seen.add(name);
      if (name === 'KEYS') {
        if (!validName(value)) fail(`bad option ${option}`);
        options.KEYS = value; continue;
      }
      let low = 1, high = 20;
      if (name === 'MAXLEN') { low = cipher === 'autokey' ? 1 : 2; high = cipher === 'columnar' ? 6 : 20; }
      else if (name === 'IOC') high = 100000;
      else if (name === 'KASISKI') high = 100;
      else if (name === 'REFINE') { low = 0; high = 10; }
      else if (name === 'MAXRAILS') low = 2;
      const number = Number(value);
      if (!/^\d{1,6}$/.test(value) || number < low || number > high) fail(`bad option ${option}`);
      switch (name) {
        case 'TOP': options.TOP = number; break;
        case 'MAXLEN': options.MAXLEN = number; break;
        case 'IOC': options.IOC = number; break;
        case 'KASISKI': options.KASISKI = number; break;
        case 'REFINE': options.REFINE = number; break;
        case 'MAXRAILS': options.MAXRAILS = number; break;
      }
    }
    if (command === 'BREAK' && cipher === 'playfair' && !options.KEYS) fail('missing option KEYS');
  }
  const source = words[command === 'ENCRYPT' || command === 'DECRYPT' ? 3 : command === 'BREAK' ? 2 : 1];
  const other = command === 'COMPARE' ? words[2] : options.KEYS;
  for (const name of [source, other]) if (name !== undefined && !messages.has(name)) fail(`unknown message ${name}`);
  if (newName !== undefined && messages.has(newName)) fail(`duplicate message ${newName}`);
  return { command, cipher, key, source, other, newName, options };
}
function transform(text: string, cipher: Cipher, key: string, decrypt: boolean): string {
  if (substitution(cipher)) return substitute(text, cipher, key, decrypt);
  if (cipher === 'railfence') return railfence(text, Number(key), decrypt);
  if (cipher === 'columnar') return columnar(text, key, decrypt);
  return playfair(text, key, decrypt);
}
function groups(text: string): string[] {
  const words = text.match(/.{1,5}/g) ?? [], lines: string[] = [];
  for (let i = 0; i < words.length; i += 10) lines.push(words.slice(i, i + 10).join(' '));
  return lines;
}
function resultLines(body: string, cipher: Cipher, key: string, decrypt = true): string[] {
  const text = transform(substitution(cipher) ? body : letters(body), cipher, key, decrypt);
  return substitution(cipher) ? text.split('\n') : groups(text);
}
function keyList(name?: string): string[] {
  if (name === undefined) return [];
  return [...new Set((messages.get(name)!.join('\n').match(/[A-Za-z]+/g) ?? []).map(word => word.toUpperCase().replaceAll('J', 'I')))];
}
function tableLines(table: Period[], examination: Kasiski): string[] {
  return [...table.map(row => `L=${row.length} ioc=${row.average} kasiski=${row.kasiski} cols=${row.columns.join(',')}`),
    `kasiski repeats=${examination.repeats.length} spacings=${examination.gaps.length}`,
    ...examination.repeats.map(repeat => `${repeat.trigram} at=${repeat.positions.join(',')} gaps=${repeat.gaps.join(',')} gcd=${repeat.gcd}`)];
}
function* permutations(prefix: string, remaining: string): Generator<string> {
  if (!remaining) { yield prefix; return; }
  for (let i = 0; i < remaining.length; i++) yield* permutations(prefix + remaining[i], remaining.slice(0, i) + remaining.slice(i + 1));
}
function columnKey(text: string, length: number, autokey: boolean): string {
  return columns(text, length).map(column => {
    let best = -1, bestValue = 0;
    for (let value = 0; value < 26; value++) {
      let previous = value, score = 0;
      for (const c of column) {
        const plain = mod(c.charCodeAt(0) - 65 - (autokey ? previous : value));
        score += weights.mono[plain]; previous = plain;
      }
      if (score > best) { best = score; bestValue = value; }
    }
    return String.fromCharCode(65 + bestValue);
  }).join('');
}
function breakCipher(text: string, cipher: Cipher, options: Options, keys: string[]): BreakResult {
  const list: Candidate[] = [];
  function add(key: string): void {
    const plaintext = transform(text, cipher, key, true);
    list.push({ key, plaintext, score: cipher === 'caesar' || cipher === 'affine' ? mono(plaintext, weights) : bigram(plaintext, weights), order: list.length });
  }
  if (cipher === 'caesar') for (let key = 0; key < 26; key++) add(String(key));
  else if (cipher === 'affine') for (const a of affineMultipliers) for (let b = 0; b < 26; b++) add(`${a},${b}`);
  else if (cipher === 'railfence') for (let r = 2; r <= options.MAXRAILS; r++) add(String(r));
  else if (cipher === 'columnar') for (let k = 2; k <= options.MAXLEN; k++) for (const key of permutations('', '123456'.slice(0, k))) add(key);
  else if (cipher === 'playfair') keys.forEach(add);
  else for (let length = 1; length <= options.MAXLEN; length++) add(columnKey(text, length, cipher === 'autokey'));
  const ranked = [...list].sort((a, b) => b.score - a.score || a.order - b.order);
  let key = ranked[0].key, score = ranked[0].score;
  const details: string[] = [];
  if (cipher === 'vigenere') {
    const examination = kasiski(text), table = periods(text, options.MAXLEN, examination);
    let selected: Period | undefined;
    if (examination.gaps.length) for (const row of table) if (row.length >= 2 && 100 * row.kasiski >= options.KASISKI * examination.gaps.length) selected = row;
    let method: string;
    if (selected && selected.average >= options.IOC) method = 'kasiski';
    else {
      selected = table.find(row => row.average >= options.IOC);
      if (selected) method = 'ioc';
      else { selected = table.reduce((best, row) => row.average > best.average ? row : best); method = 'maxioc'; }
    }
    key = list[selected.length - 1].key; score = list[selected.length - 1].score;
    let passes = 0, changes = 0;
    for (; passes < options.REFINE;) {
      passes++; let changed = false;
      for (let j = 0; j < key.length; j++) {
        let bestScore = -1, bestKey = key;
        for (let v = 0; v < 26; v++) {
          const trial = key.slice(0, j) + String.fromCharCode(65 + v) + key.slice(j + 1);
          const value = bigram(substitute(text, 'vigenere', trial, true), weights);
          if (value > bestScore) { bestScore = value; bestKey = trial; }
        }
        if (bestScore > score) { key = bestKey; score = bestScore; changes++; changed = true; }
      }
      if (!changed) break;
    }
    details.push(`letters=${text.length}`, ...tableLines(table, examination), `decision length=${selected.length} method=${method}`, `refine passes=${passes} changes=${changes} key=${key}`);
  } else if (cipher === 'playfair') {
    const pairs = pairCounts(text.replaceAll('J', 'I'), 2), grid = square(key);
    details.push(`letters=${text.length}`, `digraphs pairs=${text.length / 2} distinct=${pairs.size}`, `top ${topPairs(pairs)}`, `square ${grid.match(/.{5}/g)!.join(' ')}`);
  }
  return { ranked, key, score, details };
}
function analyze(text: string, maximum: number): string[] {
  const frequency = counts(text), examination = kasiski(text);
  let doubles = 0, pairDoubles = 0;
  for (let i = 0; i + 1 < text.length; i++) if (text[i] === text[i + 1]) { doubles++; if (i % 2 === 0) pairDoubles++; }
  return [`letters=${text.length}`, `ioc=${ioc(text)} mono=${mono(text, weights)} bigram=${bigram(text, weights)}`,
    `doubles=${doubles} pair_doubles=${pairDoubles} distinct=${frequency.filter(n => n > 0).length}`,
    ...frequency.map((count, i) => `${String.fromCharCode(65 + i)} ${count} ${percentage(count, text.length)}`),
    `bigrams ${topPairs(pairCounts(text, 1))}`, ...tableLines(periods(text, maximum, examination), examination)];
}
function execute(job: Job, number: number): void {
  const { command, source, options, newName } = job;
  const body = messages.get(source)!.join('\n'), text = letters(body), header = `JOB ${number}`;
  const suffix = newName === undefined ? '' : ` as=${newName}`;
  let lines: string[] | undefined;
  if (command === 'ENCRYPT' || command === 'DECRYPT') {
    if (!text.length) fail('no letters');
    if (command === 'DECRYPT' && job.cipher === 'playfair' && !validPlayfair(text)) fail('bad playfair text');
    lines = resultLines(body, job.cipher!, job.key!, command === 'DECRYPT');
    results.push(`${header} ${command} ${job.cipher} key=${job.key} source=${source} letters=${letters(lines.join('\n')).length} lines=${lines.length}${suffix}`, ...lines);
  } else if (command === 'BREAK') {
    if (text.length < 40) fail('text too short');
    const keys = keyList(options.KEYS);
    if (job.cipher === 'playfair') {
      if (!validPlayfair(text)) fail('bad playfair text');
      if (!keys.length) fail('empty key list');
    }
    const broken = breakCipher(text, job.cipher!, options, keys), ranked = broken.ranked;
    lines = resultLines(body, job.cipher!, broken.key);
    results.push(`${header} BREAK ${job.cipher} source=${source} key=${broken.key} score=${broken.score} lines=${lines.length}${suffix}`, ...lines);
    candidates.push(`${header} BREAK ${job.cipher} source=${source} tried=${ranked.length} margin=${ranked.length > 1 ? ranked[0].score - ranked[1].score : 0}`,
      ...ranked.slice(0, options.TOP).map((candidate, i) => `${i + 1} ${candidate.key} ${candidate.score} ${candidate.plaintext.slice(0, 40)}`));
    if (broken.details.length) analysis.push(`${header} BREAK ${job.cipher} source=${source}`, ...broken.details);
  } else if (command === 'ANALYZE') {
    if (text.length < 40) fail('text too short');
    results.push(`${header} ANALYZE source=${source} letters=${text.length}`);
    analysis.push(`${header} ANALYZE source=${source}`, ...analyze(text, options.MAXLEN));
  } else if (command === 'COMPARE') {
    const other = letters(messages.get(job.other!)!.join('\n'));
    if (text === other) results.push(`${header} COMPARE ${source} ${job.other} equal letters=${text.length}`);
    else {
      let first = Math.min(text.length, other.length) + 1, mismatches = 0;
      for (let i = 0; i < Math.min(text.length, other.length); i++) if (text[i] !== other[i]) { if (!mismatches) first = i + 1; mismatches++; }
      results.push(`${header} COMPARE ${source} ${job.other} differ letters=${text.length},${other.length} first=${first} mismatches=${mismatches}`);
    }
  } else {
    if (text.length < 40) fail('text too short');
    const index = ioc(text), average = Math.floor(mono(text, weights) / text.length), distinct = new Set(text).size;
    const shape = !text.includes('J') && validPlayfair(text);
    const family = shape ? 'playfair' : index >= 5500 && average >= 44 ? 'transposition' : index >= 5500 ? 'monoalphabetic' : 'polyalphabetic';
    const keys = keyList(options.KEYS);
    if (family === 'playfair' && options.KEYS !== undefined && !keys.length) fail('empty key list');
    const trials: Cipher[] = family === 'playfair' ? options.KEYS ? ['playfair'] : []
      : family === 'transposition' ? ['railfence', 'columnar'] : family === 'monoalphabetic' ? ['affine'] : ['vigenere', 'autokey'];
    analysis.push(`${header} IDENTIFY source=${source}`, `letters=${text.length} ioc=${index} mono_avg=${average} distinct=${distinct} shape=${shape ? 'yes' : 'no'}`, `family=${family}`);
    let choice: { cipher: Cipher; result: BreakResult } | undefined;
    for (const cipher of trials) {
      const result = breakCipher(text, cipher, defaults(cipher), keys);
      analysis.push(`try ${cipher} key=${result.key} score=${result.score}`);
      if (!choice || result.score > choice.result.score) choice = { cipher, result };
    }
    if (!choice) results.push(`${header} IDENTIFY source=${source} family=${family}`);
    else {
      let cipher = choice.cipher, key = choice.result.key;
      if (cipher === 'affine' && key.startsWith('1,')) { cipher = 'caesar'; key = key.split(',')[1]; }
      const output = resultLines(body, cipher, key);
      results.push(`${header} IDENTIFY source=${source} family=${family} cipher=${cipher} key=${key} score=${choice.result.score} lines=${output.length}`, ...output);
      analysis.push(`choice ${cipher}`);
    }
  }
  if (newName !== undefined && lines !== undefined) messages.set(newName, lines);
}

const messageLines = readFileSync('input/messages.txt', 'utf8').split('\n');
for (let i = 0; i < messageLines.length; i++) {
  if (!messageLines[i]) continue;
  const name = messageLines[i].slice(8), body: string[] = [];
  while (messageLines[++i] !== 'END') body.push(messageLines[i]);
  messages.set(name, body);
}
let jobs = 0, ok = 0, errors = 0;
for (const line of readFileSync('input/jobs.txt', 'utf8').split('\n')) {
  if (!line || line.startsWith('#')) continue;
  jobs++;
  const command = line.split(' ')[0], total = isCommand(command) ? totals.get(command) : undefined;
  try { execute(parseJob(line), jobs); ok++; if (total) total.ok++; }
  catch (error) {
    if (!(error instanceof Error)) throw error;
    results.push(`JOB ${jobs} ERROR ${error.message}`); errors++; if (total) total.errors++;
  }
}
for (const command of commands) {
  const total = totals.get(command)!;
  results.push(`TOTAL ${command} ok=${total.ok} errors=${total.errors}`);
}
results.push(`SUMMARY jobs=${jobs} ok=${ok} errors=${errors} messages=${messages.size}`);
mkdirSync('output', { recursive: true });
for (const [name, lines] of [['results', results], ['candidates', candidates], ['analysis', analysis]] as const)
  writeFileSync(`output/${name}.txt`, lines.length ? lines.join('\n') + '\n' : '');
