'use strict';

const fs = require('node:fs');
const {letterString, parseWeights, monogramFitness, bigramFitness} = require('./scoring');
const {mod, substitute} = require('./substitution');
const {railFence, columnar} = require('./transposition');
const {buildSquare, validCiphertext, playfair} = require('./playfair');
const {
  countLetters, coincidence, columns, periodStatistics, kasiski,
  percentage, pairCounts, topPairs, doubles,
} = require('./analysis');

const COMMANDS = ['ENCRYPT', 'DECRYPT', 'BREAK', 'ANALYZE', 'COMPARE', 'IDENTIFY'];
const CIPHERS = new Set(['caesar', 'affine', 'vigenere', 'autokey', 'playfair', 'railfence', 'columnar']);
const SUBSTITUTIONS = new Set(['caesar', 'affine', 'vigenere', 'autokey']);
const AFFINE_MULTIPLIERS = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25];
const NAME = /^[a-z0-9_]{1,16}$/;

class JobError extends Error {}

function makeMessage(lines) {
  const text = lines.join('\n');
  return {lines, text, letters: letterString(text)};
}

function readMessages(text) {
  const lines = text.split('\n');
  const messages = new Map();
  let index = 0;
  while (index < lines.length) {
    if (lines[index] === '') {
      index++;
      continue;
    }
    const name = lines[index].slice(8);
    const body = [];
    index++;
    while (lines[index] !== 'END') body.push(lines[index++]);
    index++;
    messages.set(name, makeMessage(body));
  }
  return messages;
}

function normalizeKey(cipher, word) {
  if (cipher === 'caesar' || cipher === 'railfence') {
    if (!/^[0-9]{1,2}$/.test(word)) return null;
    const value = Number(word);
    const minimum = cipher === 'caesar' ? 0 : 2;
    const maximum = cipher === 'caesar' ? 25 : 20;
    return value >= minimum && value <= maximum ? String(value) : null;
  }
  if (cipher === 'affine') {
    const match = /^([0-9]{1,2}),([0-9]{1,2})$/.exec(word);
    if (!match) return null;
    const multiplier = Number(match[1]);
    const offset = Number(match[2]);
    if (!AFFINE_MULTIPLIERS.includes(multiplier) || offset > 25) return null;
    return `${multiplier},${offset}`;
  }
  if (cipher === 'columnar') {
    return /^[A-Za-z0-9]{2,9}$/.test(word) ? word.toUpperCase() : null;
  }
  const maximum = cipher === 'playfair' ? 25 : 20;
  if (word.length < 1 || word.length > maximum || !/^[A-Za-z]+$/.test(word)) return null;
  const normalized = word.toUpperCase();
  return cipher === 'playfair' ? normalized.replaceAll('J', 'I') : normalized;
}

function optionRules(command, cipher) {
  if (command === 'ANALYZE') return {MAXLEN: [2, 20, 10]};
  if (command === 'IDENTIFY') return {KEYS: null};
  const rules = {TOP: [1, 20, 5]};
  if (cipher === 'vigenere') {
    rules.MAXLEN = [2, 20, 10];
    rules.IOC = [1, 100000, 6000];
    rules.KASISKI = [1, 100, 60];
    rules.REFINE = [0, 10, 5];
  } else if (cipher === 'autokey') {
    rules.MAXLEN = [1, 20, 8];
  } else if (cipher === 'railfence') {
    rules.MAXRAILS = [2, 20, 10];
  } else if (cipher === 'columnar') {
    rules.MAXLEN = [2, 6, 6];
  } else if (cipher === 'playfair') {
    rules.KEYS = null;
  }
  return rules;
}

function defaultOptions(command, cipher) {
  const options = {};
  for (const [name, rule] of Object.entries(optionRules(command, cipher))) {
    if (rule !== null) options[name] = rule[2];
  }
  return options;
}

function parseOptions(command, cipher, words) {
  const rules = optionRules(command, cipher);
  const options = defaultOptions(command, cipher);
  const seen = new Set();
  for (const word of words) {
    const separator = word.indexOf('=');
    const name = word.slice(0, separator);
    const value = word.slice(separator + 1);
    if (separator < 0 || !Object.hasOwn(rules, name) || seen.has(name)) {
      throw new JobError(`bad option ${word}`);
    }
    if (name === 'KEYS') {
      if (!NAME.test(value)) throw new JobError(`bad option ${word}`);
      options[name] = value;
    } else {
      const [minimum, maximum] = rules[name];
      if (!/^[0-9]{1,6}$/.test(value) || Number(value) < minimum || Number(value) > maximum) {
        throw new JobError(`bad option ${word}`);
      }
      options[name] = Number(value);
    }
    seen.add(name);
  }
  if (command === 'BREAK' && cipher === 'playfair' && options.KEYS === undefined) {
    throw new JobError('missing option KEYS');
  }
  return options;
}

function playfairKeys(message) {
  const keys = [];
  const seen = new Set();
  for (const match of message.text.matchAll(/[A-Za-z]+/g)) {
    const key = match[0].toUpperCase().replaceAll('J', 'I');
    if (!seen.has(key)) {
      keys.push(key);
      seen.add(key);
    }
  }
  return keys;
}

function identifyFamily(text, weights) {
  const ioc = coincidence(text);
  const average = Math.floor(monogramFitness(text, weights) / text.length);
  const distinct = countLetters(text).filter(count => count !== 0).length;
  const shape = text.length % 2 === 0 && !text.includes('J') && validCiphertext(text);
  let family;
  if (shape) family = 'playfair';
  else if (ioc >= 5500 && average >= 44) family = 'transposition';
  else if (ioc >= 5500) family = 'monoalphabetic';
  else family = 'polyalphabetic';
  return {ioc, average, distinct, shape: shape ? 'yes' : 'no', family};
}

function validateJob(original, messages, weights) {
  const command = original[0];
  if (!COMMANDS.includes(command)) throw new JobError('unknown command');
  let words = original;
  let newName = null;
  const cipherCommand = command === 'ENCRYPT' || command === 'DECRYPT' || command === 'BREAK';
  if (cipherCommand && words.length >= 5 && words[words.length - 2] === 'AS') {
    newName = words[words.length - 1];
    if (!NAME.test(newName)) throw new JobError('bad syntax');
    words = words.slice(0, -2);
  }
  if (((command === 'ENCRYPT' || command === 'DECRYPT') && words.length !== 4)
      || (command === 'BREAK' && words.length < 3)
      || ((command === 'ANALYZE' || command === 'IDENTIFY') && (words.length < 2 || words.length > 3))
      || (command === 'COMPARE' && words.length !== 3)) {
    throw new JobError('bad syntax');
  }
  const cipher = cipherCommand ? words[1] : null;
  if (cipherCommand && !CIPHERS.has(cipher)) throw new JobError(`unknown cipher ${cipher}`);
  let key = null;
  if (command === 'ENCRYPT' || command === 'DECRYPT') {
    key = normalizeKey(cipher, words[2]);
    if (key === null) throw new JobError(`bad key ${words[2]}`);
  }
  let options = {};
  if (command === 'BREAK') options = parseOptions(command, cipher, words.slice(3));
  else if (command === 'ANALYZE' || command === 'IDENTIFY') {
    options = parseOptions(command, cipher, words.slice(2));
  }
  const source = command === 'ENCRYPT' || command === 'DECRYPT' ? words[3]
    : command === 'BREAK' ? words[2] : words[1];
  const second = command === 'COMPARE' ? words[2] : options.KEYS;
  if (!messages.has(source)) throw new JobError(`unknown message ${source}`);
  if (second !== undefined && !messages.has(second)) throw new JobError(`unknown message ${second}`);
  if (newName !== null && messages.has(newName)) throw new JobError(`duplicate message ${newName}`);
  const message = messages.get(source);
  const job = {command, cipher, key, options, source, newName, message, keyList: []};
  if (command === 'COMPARE') {
    job.second = second;
    job.other = messages.get(second);
  } else if (command === 'ENCRYPT' || command === 'DECRYPT') {
    if (message.letters.length === 0) throw new JobError('no letters');
    if (command === 'DECRYPT' && cipher === 'playfair' && !validCiphertext(message.letters)) {
      throw new JobError('bad playfair text');
    }
  } else {
    if (message.letters.length < 40) throw new JobError('text too short');
    if (command === 'BREAK' && cipher === 'playfair') {
      if (!validCiphertext(message.letters)) throw new JobError('bad playfair text');
      job.keyList = playfairKeys(messages.get(options.KEYS));
      if (job.keyList.length === 0) throw new JobError('empty key list');
    }
    if (command === 'IDENTIFY') {
      job.identification = identifyFamily(message.letters, weights);
      if (job.identification.family === 'playfair' && options.KEYS !== undefined) {
        job.keyList = playfairKeys(messages.get(options.KEYS));
        if (job.keyList.length === 0) throw new JobError('empty key list');
      }
    }
  }
  return job;
}

function transform(cipher, key, text, decrypt) {
  if (SUBSTITUTIONS.has(cipher)) return substitute(cipher, key, text, decrypt);
  if (cipher === 'railfence') return railFence(text, Number(key), decrypt);
  if (cipher === 'columnar') return columnar(text, key, decrypt);
  return playfair(text, key, decrypt);
}

function fiveLetterGroups(text) {
  const lines = [];
  for (let start = 0; start < text.length; start += 50) {
    const groups = [];
    for (let offset = start; offset < Math.min(start + 50, text.length); offset += 5) {
      groups.push(text.slice(offset, offset + 5));
    }
    lines.push(groups.join(' '));
  }
  return lines;
}

function breakResultLines(cipher, key, message, plaintext) {
  if (SUBSTITUTIONS.has(cipher)) return substitute(cipher, key, message.text, true).split('\n');
  return fiveLetterGroups(plaintext);
}

function columnKey(text, length, cipher, weights) {
  let key = '';
  for (const column of columns(text, length)) {
    const values = Array.from(column, character => character.charCodeAt(0) - 65);
    let bestValue = 0;
    let bestScore = -1;
    for (let value = 0; value < 26; value++) {
      let previous = value;
      let score = 0;
      for (const ciphertext of values) {
        const plaintext = mod(ciphertext - (cipher === 'autokey' ? previous : value), 26);
        score += weights.monograms[plaintext];
        previous = plaintext;
      }
      if (score > bestScore) {
        bestValue = value;
        bestScore = score;
      }
    }
    key += String.fromCharCode(65 + bestValue);
  }
  return key;
}

function visitColumnarKeys(length, visit) {
  const used = Array(length + 1).fill(false);
  function extend(prefix) {
    if (prefix.length === length) {
      visit(prefix);
      return;
    }
    for (let digit = 1; digit <= length; digit++) {
      if (used[digit]) continue;
      used[digit] = true;
      extend(prefix + digit);
      used[digit] = false;
    }
  }
  extend('');
}

function determineLength(table, examination, options) {
  let kasiskiLength = 0;
  if (examination.gaps.length > 0) {
    for (const row of table) {
      if (row.period >= 2 && 100 * row.divisible >= options.KASISKI * examination.gaps.length) {
        kasiskiLength = row.period;
      }
    }
  }
  if (kasiskiLength > 0 && table[kasiskiLength - 1].average >= options.IOC) {
    return {length: kasiskiLength, method: 'kasiski'};
  }
  for (const row of table) {
    if (row.average >= options.IOC) return {length: row.period, method: 'ioc'};
  }
  let best = table[0];
  for (const row of table) {
    if (row.average > best.average) best = row;
  }
  return {length: best.period, method: 'maxioc'};
}

function refineVigenere(text, candidate, maximum, weights) {
  let key = candidate.key;
  let score = candidate.score;
  let passes = 0;
  let changes = 0;
  while (passes < maximum) {
    let changed = 0;
    for (let position = 0; position < key.length; position++) {
      let bestKey = key;
      let bestScore = -1;
      for (let value = 0; value < 26; value++) {
        const trial = key.slice(0, position) + String.fromCharCode(65 + value) + key.slice(position + 1);
        const trialScore = bigramFitness(substitute('vigenere', trial, text, true), weights);
        if (trialScore > bestScore) {
          bestKey = trial;
          bestScore = trialScore;
        }
      }
      if (bestScore > score) {
        key = bestKey;
        score = bestScore;
        changed++;
      }
    }
    passes++;
    changes += changed;
    if (changed === 0) break;
  }
  return {key, score, passes, changes, plaintext: substitute('vigenere', key, text, true)};
}

function breakCipher(cipher, text, options, keyList, weights) {
  const candidates = [];
  const fitness = cipher === 'caesar' || cipher === 'affine' ? monogramFitness : bigramFitness;
  function addCandidate(key) {
    const plaintext = transform(cipher, key, text, true);
    candidates.push({key, plaintext, score: fitness(plaintext, weights), order: candidates.length});
  }
  if (cipher === 'caesar') {
    for (let key = 0; key < 26; key++) addCandidate(String(key));
  } else if (cipher === 'affine') {
    for (const multiplier of AFFINE_MULTIPLIERS) {
      for (let offset = 0; offset < 26; offset++) addCandidate(`${multiplier},${offset}`);
    }
  } else if (cipher === 'railfence') {
    for (let rails = 2; rails <= options.MAXRAILS; rails++) addCandidate(String(rails));
  } else if (cipher === 'columnar') {
    for (let length = 2; length <= options.MAXLEN; length++) visitColumnarKeys(length, addCandidate);
  } else if (cipher === 'playfair') {
    for (const key of keyList) addCandidate(key);
  } else {
    for (let length = 1; length <= options.MAXLEN; length++) {
      addCandidate(columnKey(text, length, cipher, weights));
    }
  }
  const ranked = candidates.slice().sort((left, right) => right.score - left.score || left.order - right.order);
  if (cipher !== 'vigenere') return {...ranked[0], ranked};
  const examination = kasiski(text);
  const table = periodStatistics(text, options.MAXLEN, examination);
  const decision = determineLength(table, examination, options);
  const refined = refineVigenere(text, candidates[decision.length - 1], options.REFINE, weights);
  return {...refined, ranked, examination, table, decision};
}

function statisticalTable(table, examination) {
  const lines = table.map(row =>
    `L=${row.period} ioc=${row.average} kasiski=${row.divisible} cols=${row.indices.join(',')}`);
  lines.push(`kasiski repeats=${examination.repeats.length} spacings=${examination.gaps.length}`);
  for (const repeated of examination.repeats) {
    lines.push(`${repeated.trigram} at=${repeated.positions.join(',')} gaps=${repeated.gaps.join(',')} gcd=${repeated.gcd}`);
  }
  return lines;
}

function encryptionJob(number, job) {
  const input = SUBSTITUTIONS.has(job.cipher) ? job.message.text : job.message.letters;
  const transformed = transform(job.cipher, job.key, input, job.command === 'DECRYPT');
  const lines = SUBSTITUTIONS.has(job.cipher) ? transformed.split('\n') : fiveLetterGroups(transformed);
  const suffix = job.newName === null ? '' : ` as=${job.newName}`;
  const header = `JOB ${number} ${job.command} ${job.cipher} key=${job.key} source=${job.source}`
    + ` letters=${letterString(transformed).length} lines=${lines.length}${suffix}`;
  return {results: [header, ...lines], candidates: [], analysis: [], newLines: lines};
}

function breakingJob(number, job, weights) {
  const broken = breakCipher(job.cipher, job.message.letters, job.options, job.keyList, weights);
  const lines = breakResultLines(job.cipher, broken.key, job.message, broken.plaintext);
  const suffix = job.newName === null ? '' : ` as=${job.newName}`;
  const header = `JOB ${number} BREAK ${job.cipher} source=${job.source}`
    + ` key=${broken.key} score=${broken.score} lines=${lines.length}${suffix}`;
  const ranked = broken.ranked;
  const margin = ranked.length > 1 ? ranked[0].score - ranked[1].score : 0;
  const candidates = [`JOB ${number} BREAK ${job.cipher} source=${job.source} tried=${ranked.length} margin=${margin}`];
  for (let rank = 0; rank < Math.min(job.options.TOP, ranked.length); rank++) {
    const candidate = ranked[rank];
    candidates.push(`${rank + 1} ${candidate.key} ${candidate.score} ${candidate.plaintext.slice(0, 40)}`);
  }
  const analysis = [];
  if (job.cipher === 'vigenere') {
    analysis.push(`JOB ${number} BREAK vigenere source=${job.source}`);
    analysis.push(`letters=${job.message.letters.length}`);
    for (const row of statisticalTable(broken.table, broken.examination)) analysis.push(row);
    analysis.push(`decision length=${broken.decision.length} method=${broken.decision.method}`);
    analysis.push(`refine passes=${broken.passes} changes=${broken.changes} key=${broken.key}`);
  } else if (job.cipher === 'playfair') {
    const text = job.message.letters.replaceAll('J', 'I');
    const counts = pairCounts(text, 2);
    const square = buildSquare(ranked[0].key);
    const rows = [];
    for (let start = 0; start < 25; start += 5) rows.push(square.slice(start, start + 5));
    analysis.push(`JOB ${number} BREAK playfair source=${job.source}`);
    analysis.push(`letters=${text.length}`);
    analysis.push(`digraphs pairs=${text.length / 2} distinct=${counts.size}`);
    analysis.push(`top ${topPairs(counts)}`);
    analysis.push(`square ${rows.join(' ')}`);
  }
  return {results: [header, ...lines], candidates, analysis, newLines: lines};
}

function analysisJob(number, job, weights) {
  const text = job.message.letters;
  const counts = countLetters(text);
  const repeated = doubles(text);
  const distinct = counts.filter(count => count !== 0).length;
  const examination = kasiski(text);
  const table = periodStatistics(text, job.options.MAXLEN, examination);
  const analysis = [
    `JOB ${number} ANALYZE source=${job.source}`,
    `letters=${text.length}`,
    `ioc=${coincidence(text)} mono=${monogramFitness(text, weights)} bigram=${bigramFitness(text, weights)}`,
    `doubles=${repeated.adjacent} pair_doubles=${repeated.paired} distinct=${distinct}`,
  ];
  for (let letter = 0; letter < 26; letter++) {
    analysis.push(`${String.fromCharCode(65 + letter)} ${counts[letter]} ${percentage(counts[letter], text.length)}`);
  }
  analysis.push(`bigrams ${topPairs(pairCounts(text, 1))}`);
  for (const row of statisticalTable(table, examination)) analysis.push(row);
  return {
    results: [`JOB ${number} ANALYZE source=${job.source} letters=${text.length}`],
    candidates: [], analysis,
  };
}

function comparisonJob(number, job) {
  const left = job.message.letters;
  const right = job.other.letters;
  const header = `JOB ${number} COMPARE ${job.source} ${job.second}`;
  let result;
  if (left === right) {
    result = `${header} equal letters=${left.length}`;
  } else {
    const common = Math.min(left.length, right.length);
    let first = common + 1;
    let mismatches = 0;
    for (let index = 0; index < common; index++) {
      if (left[index] !== right[index]) {
        if (mismatches === 0) first = index + 1;
        mismatches++;
      }
    }
    result = `${header} differ letters=${left.length},${right.length} first=${first} mismatches=${mismatches}`;
  }
  return {results: [result], candidates: [], analysis: []};
}

function identificationJob(number, job, weights) {
  const data = job.identification;
  const text = job.message.letters;
  const analysis = [
    `JOB ${number} IDENTIFY source=${job.source}`,
    `letters=${text.length} ioc=${data.ioc} mono_avg=${data.average} distinct=${data.distinct} shape=${data.shape}`,
    `family=${data.family}`,
  ];
  let ciphers;
  if (data.family === 'transposition') ciphers = ['railfence', 'columnar'];
  else if (data.family === 'monoalphabetic') ciphers = ['affine'];
  else if (data.family === 'polyalphabetic') ciphers = ['vigenere', 'autokey'];
  else ciphers = job.options.KEYS === undefined ? [] : ['playfair'];
  let chosen = null;
  for (const cipher of ciphers) {
    const options = defaultOptions('BREAK', cipher);
    const result = breakCipher(cipher, text, options, job.keyList, weights);
    analysis.push(`try ${cipher} key=${result.key} score=${result.score}`);
    if (chosen === null || result.score > chosen.score) chosen = {...result, cipher};
  }
  let header = `JOB ${number} IDENTIFY source=${job.source} family=${data.family}`;
  if (chosen === null) return {results: [header], candidates: [], analysis};
  let cipher = chosen.cipher;
  let key = chosen.key;
  if (cipher === 'affine' && key.split(',')[0] === '1') {
    cipher = 'caesar';
    key = key.split(',')[1];
  }
  const lines = breakResultLines(cipher, key, job.message, chosen.plaintext);
  header += ` cipher=${cipher} key=${key} score=${chosen.score} lines=${lines.length}`;
  analysis.push(`choice ${cipher}`);
  return {results: [header, ...lines], candidates: [], analysis};
}

function executeJob(number, job, weights) {
  if (job.command === 'ENCRYPT' || job.command === 'DECRYPT') return encryptionJob(number, job);
  if (job.command === 'BREAK') return breakingJob(number, job, weights);
  if (job.command === 'ANALYZE') return analysisJob(number, job, weights);
  if (job.command === 'COMPARE') return comparisonJob(number, job);
  return identificationJob(number, job, weights);
}

function writeReport(name, lines) {
  fs.writeFileSync(`output/${name}.txt`, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
}

function main() {
  const weights = parseWeights(fs.readFileSync('input/weights.txt', 'ascii'));
  const messages = readMessages(fs.readFileSync('input/messages.txt', 'ascii'));
  const jobs = fs.readFileSync('input/jobs.txt', 'ascii').split('\n');
  const reports = {results: [], candidates: [], analysis: []};
  const totals = new Map(COMMANDS.map(command => [command, {ok: 0, errors: 0}]));
  let number = 0;
  let ok = 0;
  let errors = 0;
  for (const line of jobs) {
    if (line.length === 0 || line.startsWith('#')) continue;
    number++;
    const words = line.split(' ');
    try {
      const job = validateJob(words, messages, weights);
      const completed = executeJob(number, job, weights);
      for (const name of ['results', 'candidates', 'analysis']) {
        for (const row of completed[name]) reports[name].push(row);
      }
      if (job.newName !== null) messages.set(job.newName, makeMessage(completed.newLines));
      totals.get(job.command).ok++;
      ok++;
    } catch (error) {
      if (!(error instanceof JobError)) throw error;
      reports.results.push(`JOB ${number} ERROR ${error.message}`);
      if (totals.has(words[0])) totals.get(words[0]).errors++;
      errors++;
    }
  }
  for (const command of COMMANDS) {
    const total = totals.get(command);
    reports.results.push(`TOTAL ${command} ok=${total.ok} errors=${total.errors}`);
  }
  reports.results.push(`SUMMARY jobs=${number} ok=${ok} errors=${errors} messages=${messages.size}`);
  fs.mkdirSync('output', {recursive: true});
  for (const name of ['results', 'candidates', 'analysis']) writeReport(name, reports[name]);
}

if (require.main === module) main();
