import { mkdirSync, writeFileSync } from 'node:fs';
import { compareKeys, splitKey, type ScalarType, type ValueType } from './schema.ts';
import type { Change, Origin, Profile, Value } from './main.ts';

export const MASK = '********';
export const originText = (origin: Origin) => `${origin.document}:${origin.line}`;
export function stringNotation(value: string): string {
  const escapes: Record<string, string> = { '\\': '\\\\', '"': '\\"', '\n': '\\n', '\t': '\\t' };
  return '"' + value.replace(/[\\"\n\t]/g, character => escapes[character]) + '"';
}
export function valueNotation(type: ValueType, value: Value, attributes = new Map<string, string>()): string {
  if (type === 'string' && typeof value === 'string') return stringNotation(value);
  if (type === 'list' && Array.isArray(value)) {
    const item = (attributes.get('item') || 'string') as ScalarType;
    return '[' + value.map(part => valueNotation(item, part, attributes)).join(', ') + ']';
  }
  return String(value);
}
function normalizedBlock(profile: Profile): string[] {
  const lines = [`profile ${profile.name}`];
  let previous: string | null = null;
  for (const key of [...profile.output.keys()].sort(compareKeys)) {
    const [section, name] = splitKey(key);
    if (section !== previous) lines.push(`[${section}]`);
    lines.push(`${name} = ${profile.output.get(key)!.display}`);
    previous = section;
  }
  return lines;
}
function diagnosticsBlock(profile: Profile): string[] {
  return [`profile ${profile.name} errors ${profile.errors} warnings ${profile.warnings}`,
    ...profile.diagnostics.map(item => `${originText(item.origin)} ${item.code} ${item.message}`)];
}
function reportBlock(profile: Profile): string[] {
  const lines = [`profile ${profile.name}`, 'includes',
    ...profile.includes.map(item => ' '.repeat(2 + 2 * item.depth) + item.text), 'overridden'];
  if (!profile.overridden.length) lines.push('  (none)');
  for (const key of profile.overridden) lines.push(`  ${key}: ${profile.output.get(key)!.definition.history.join(' -> ')}`);
  const { documents, manifest, defaults } = profile.origins;
  lines.push(`keys ${profile.output.size} documents ${documents} manifest ${manifest} defaults ${defaults}`);
  lines.push(`dropped ${profile.dropped}`, `errors ${profile.errors} warnings ${profile.warnings}`);
  return lines;
}
function diffBlock(first: Profile, second: Profile, changes: Change[]): string[] {
  const added = changes.filter(change => change.kind === '+').length;
  const removed = changes.filter(change => change.kind === '-').length;
  const changed = changes.filter(change => change.kind === '~').length;
  const lines = [`diff ${first.name} -> ${second.name}: ${added} added, ${removed} removed, ${changed} changed`];
  for (const change of changes) {
    if (change.kind === '~') lines.push(`~ ${change.key}: ${change.before.display} -> ${change.after.display}`);
    else lines.push(`${change.kind} ${change.key} = ${change.kind === '+' ? change.after.display : change.before.display}`);
  }
  return lines;
}
export function writeReports(profiles: Profile[], differences: Change[][]): void {
  mkdirSync('output', { recursive: true });
  const files = new Map<string, string[][]>([
    ['normalized.txt', profiles.map(normalizedBlock)], ['diagnostics.txt', profiles.map(diagnosticsBlock)],
    ['report.txt', profiles.map(reportBlock)],
    ['diff.txt', differences.map((changes, i) => diffBlock(profiles[i], profiles[i + 1], changes))],
  ]);
  for (const [name, blocks] of files) writeFileSync(`output/${name}`, blocks.map(lines => lines.join('\n')).join('\n\n') + '\n', 'ascii');
}
