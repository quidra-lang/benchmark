const fs = require('node:fs');
const { compareKeys, splitKey } = require('./schema');

const MASK = '********';
const originText = origin => `${origin.document}:${origin.line}`;

function stringNotation(value) {
  const escapes = { '\\': '\\\\', '"': '\\"', '\n': '\\n', '\t': '\\t' };
  return '"' + value.replace(/[\\"\n\t]/g, character => escapes[character]) + '"';
}

function valueNotation(type, value, attributes = new Map()) {
  if (type === 'string') return stringNotation(value);
  if (type === 'list') {
    const item = attributes.get('item') || 'string';
    return '[' + value.map(part => valueNotation(item, part, attributes)).join(', ') + ']';
  }
  return String(value);
}

function normalizedBlock(profile) {
  const lines = [`profile ${profile.name}`];
  let previous = null;
  for (const key of [...profile.output.keys()].sort(compareKeys)) {
    const [section, name] = splitKey(key);
    if (section !== previous) lines.push(`[${section}]`);
    lines.push(`${name} = ${profile.output.get(key).display}`);
    previous = section;
  }
  return lines;
}

function diagnosticsBlock(profile) {
  return [`profile ${profile.name} errors ${profile.errors} warnings ${profile.warnings}`,
    ...profile.diagnostics.map(item => `${originText(item.origin)} ${item.code} ${item.message}`)];
}

function reportBlock(profile) {
  const lines = [`profile ${profile.name}`, 'includes',
    ...profile.includes.map(item => ' '.repeat(2 + 2 * item.depth) + item.text), 'overridden'];
  if (profile.overridden.length === 0) lines.push('  (none)');
  for (const key of profile.overridden) lines.push(`  ${key}: ${profile.output.get(key).definition.history.join(' -> ')}`);
  const { documents, manifest, defaults } = profile.origins;
  lines.push(`keys ${profile.output.size} documents ${documents} manifest ${manifest} defaults ${defaults}`);
  lines.push(`dropped ${profile.dropped}`);
  lines.push(`errors ${profile.errors} warnings ${profile.warnings}`);
  return lines;
}

function diffBlock(first, second, changes) {
  const added = changes.filter(change => change.kind === '+').length;
  const removed = changes.filter(change => change.kind === '-').length;
  const changed = changes.filter(change => change.kind === '~').length;
  const lines = [`diff ${first.name} -> ${second.name}: ${added} added, ${removed} removed, ${changed} changed`];
  for (const change of changes) {
    if (change.kind === '~') lines.push(`~ ${change.key}: ${change.before.display} -> ${change.after.display}`);
    else lines.push(`${change.kind} ${change.key} = ${(change.after || change.before).display}`);
  }
  return lines;
}

function writeReports(profiles, differences) {
  fs.mkdirSync('output', { recursive: true });
  const files = new Map([
    ['normalized.txt', profiles.map(normalizedBlock)],
    ['diagnostics.txt', profiles.map(diagnosticsBlock)],
    ['report.txt', profiles.map(reportBlock)],
    ['diff.txt', differences.map((changes, i) => diffBlock(profiles[i], profiles[i + 1], changes))],
  ]);
  for (const [name, blocks] of files) {
    fs.writeFileSync(`output/${name}`, blocks.map(lines => lines.join('\n')).join('\n\n') + '\n', 'ascii');
  }
}

module.exports = { MASK, originText, stringNotation, valueNotation, writeReports };
