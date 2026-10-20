import { existsSync, readFileSync } from 'node:fs';
import { parseDocument, type ParsedDocument } from './ini_parser.ts';
import { Schema, compareText, compareKeys, splitKey, type ScalarType, type Spec } from './schema.ts';
import { expandAll } from './interpolate.ts';
import { MASK, originText, stringNotation, valueNotation, writeReports } from './emitter.ts';
import type { RawValue } from './lexer.ts';

export interface Origin { document: string; line: number }
export interface Definition { value: RawValue; origin: Origin; number: number; history: string[] }
export type Reporter = (origin: Origin, code: string, message: string) => void;
export type Scalar = string | number | boolean;
export type Value = Scalar | Scalar[];
interface CheckedValue { value: Value; notation: string }
export interface OutputEntry extends CheckedValue { display: string; spec: Spec | null; definition: Definition }
export interface Diagnostic { origin: Origin; code: string; message: string }
interface ReferenceValue { profile: string; notation: string }
export type Change =
  | { kind: '+'; key: string; after: OutputEntry }
  | { kind: '-'; key: string; before: OutputEntry }
  | { kind: '~'; key: string; before: OutputEntry; after: OutputEntry };
const plainValue = (text: string): RawValue => ({ text, literals: new Set() });
const trimSpaces = (text: string) => text.replace(/^ +| +$/g, '');

function appendValue(first: RawValue, second: RawValue): RawValue {
  if (first.text === '') return second;
  const offset = first.text.length + 1;
  return { text: first.text + ',' + second.text,
    literals: new Set([...first.literals, ...[...second.literals].map(index => index + offset)]) };
}
function normalizeInteger(text: string): number | null {
  let sign = 1;
  if (text[0] === '+' || text[0] === '-') {
    if (text[0] === '-') sign = -1;
    text = text.slice(1);
  }
  if (/^0[xX][0-9a-fA-F]{1,10}$/.test(text)) return sign * Number.parseInt(text.slice(2), 16);
  if (!/^[0-9](?:_?[0-9])*$/.test(text)) return null;
  const digits = text.replace(/_/g, '');
  return digits.length <= 12 ? sign * Number(digits) : null;
}
function normalizeSize(text: string): number | null {
  const match = /^([0-9]{1,6})(?:\.([0-9]{1,3}))?(B|KB|MB|GB)?$/i.exec(text);
  if (!match) return null;
  const factors: Record<string, number> = { B: 1, KB: 1024, MB: 1048576, GB: 1073741824 };
  const factor = factors[(match[3] || 'B').toUpperCase()];
  let value = Number(match[1]) * factor;
  if (match[2] !== undefined) {
    const numerator = Number(match[2]) * factor, denominator = 10 ** match[2].length;
    if (numerator % denominator !== 0) return null;
    value += numerator / denominator;
  }
  return value;
}
function normalizeDuration(text: string): number | null {
  if (/^[0-9]{1,6}$/.test(text)) return Number(text);
  const match = /^(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?$/.exec(text);
  if (!match || text === '') return null;
  return Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0);
}
function normalizeHost(text: string): string | null {
  const parts = text.split('.');
  if (/^[0-9.]*$/.test(text)) return parts.length === 4 && parts.every(part =>
    /^(?:0|[1-9][0-9]{0,2})$/.test(part) && Number(part) <= 255) ? text : null;
  if (text.length > 253 || !parts.every(part => part.length >= 1 && part.length <= 63
    && /^[A-Za-z0-9-]+$/.test(part) && !part.startsWith('-') && !part.endsWith('-'))) return null;
  return text.toLowerCase();
}
function normalizePath(text: string): string | null {
  if (text === '' || /[ \n\t]/.test(text)) return null;
  const absolute = text.startsWith('/'), parts: string[] = [];
  for (const part of text.split('/')) {
    if (part === '' || part === '.') continue;
    if (part === '..') {
      if (parts.length && parts.at(-1) !== '..') parts.pop();
      else if (absolute) return null;
      else parts.push(part);
    } else parts.push(part);
  }
  return absolute ? '/' + parts.join('/') : parts.join('/') || '.';
}
function normalizeUrl(text: string): string | null {
  const delimiter = text.indexOf('://');
  if (delimiter < 0) return null;
  const scheme = text.slice(0, delimiter).toLowerCase();
  if (!/^[a-z][a-z0-9+.-]*$/.test(scheme)) return null;
  const remainder = text.slice(delimiter + 3);
  if (/[?#]/.test(remainder)) return null;
  const slash = remainder.indexOf('/'), authority = slash < 0 ? remainder : remainder.slice(0, slash);
  const path = normalizePath('/' + (slash < 0 ? '' : remainder.slice(slash + 1)));
  const colon = authority.indexOf(':'), host = normalizeHost(colon < 0 ? authority : authority.slice(0, colon));
  if (path === null || host === null) return null;
  let port = '';
  if (colon >= 0) {
    const digits = authority.slice(colon + 1);
    if (!/^[1-9][0-9]{0,4}$/.test(digits) || Number(digits) > 65535) return null;
    const defaultPort = scheme === 'http' ? 80 : scheme === 'https' ? 443 : null;
    if (Number(digits) !== defaultPort) port = ':' + digits;
  }
  return `${scheme}://${host}${port}${path}`;
}
function normalizeDate(text: string): string | null {
  const match = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(text);
  if (!match) return null;
  const year = Number(match[1]), month = Number(match[2]), day = Number(match[3]);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= days[month - 1] ? text : null;
}
function normalizeScalar(type: ScalarType, text: string, attributes: Map<string, string>): Scalar | null {
  if (type !== 'string' && /[\n\t]/.test(text)) return null;
  switch (type) {
    case 'string': return text;
    case 'int': return normalizeInteger(text);
    case 'size': return normalizeSize(text);
    case 'duration': return normalizeDuration(text);
    case 'host': return normalizeHost(text);
    case 'path': return normalizePath(text);
    case 'url': return normalizeUrl(text);
    case 'date': return normalizeDate(text);
    case 'enum': return attributes.get('values')!.split(',').find(value => value === text.toLowerCase()) ?? null;
    case 'bool': {
      const lower = text.toLowerCase();
      if (['true', 'yes', 'on', '1'].includes(lower)) return true;
      if (['false', 'no', 'off', '0'].includes(lower)) return false;
      return null;
    }
  }
}
function checkedValue(key: string, text: string, spec: Spec, origin: Origin, report: Reporter): CheckedValue | null {
  const attributes = spec.attributes, secret = attributes.has('secret');
  const typeError = (type: ScalarType, part: string, item: boolean) => {
    const display = (item ? 'item ' : '') + (secret ? MASK : stringNotation(part));
    if (type === 'enum') report(origin, 'E_ENUM', `${key}: ${display} is not one of ${attributes.get('values')}`);
    else report(origin, 'E_TYPE', `${key}: ${display} is not a valid ${type}`);
  };
  let value: Value;
  if (spec.type === 'list') {
    const items = /[^ ]/.test(text) ? text.split(',').map(trimSpaces) : [];
    if (items.includes('')) report(origin, 'W_EMPTY_ITEM', `${key}: empty list item ignored`);
    let normalizedItems: Scalar[] = [];
    const itemType = (attributes.get('item') || 'string') as ScalarType;
    for (const item of items) {
      if (item === '') continue;
      const normalized = normalizeScalar(itemType, item, attributes);
      if (normalized === null) { typeError(itemType, item, true); return null; }
      normalizedItems.push(normalized);
    }
    if (attributes.has('unique')) {
      const unique = [...new Set(normalizedItems)];
      if (unique.length < normalizedItems.length) report(origin, 'W_DUPLICATE_ITEM', `${key}: duplicate items removed`);
      normalizedItems = unique;
    }
    value = normalizedItems;
  } else {
    const normalized = normalizeScalar(spec.type, text, attributes);
    if (normalized === null) { typeError(spec.type, text, false); return null; }
    value = normalized;
  }
  const range = attributes.get('range');
  if (range !== undefined) {
    const count = spec.type === 'string' || spec.type === 'list';
    const bounds = range.split('..').map(bound => bound === '' ? null : count ? Number(bound)
      : normalizeScalar(spec.type as ScalarType, bound, attributes));
    const measured = Array.isArray(value) || typeof value === 'string' && count ? value.length : value;
    const outside = bounds.some((bound, i) => {
      if (bound === null) return false;
      if (typeof measured === 'number' && typeof bound === 'number') return i === 0 ? measured < bound : measured > bound;
      if (typeof measured === 'string' && typeof bound === 'string') return i === 0 ? measured < bound : measured > bound;
      return false;
    });
    if (outside) {
      const display = count ? `${spec.type === 'string' ? 'length' : 'count'} ${measured}`
        : secret ? MASK : valueNotation(spec.type, value, attributes);
      report(origin, 'E_RANGE', `${key}: ${display} is out of range ${bounds.map(bound => bound === null ? '' : String(bound)).join('..')}`);
      return null;
    }
  }
  return { value, notation: valueNotation(spec.type, value, attributes) };
}

class Documents {
  private readonly cache = new Map<string, ParsedDocument | null>();
  read(name: string): ParsedDocument | null {
    if (!this.cache.has(name)) {
      const path = `input/conf/${name}.ini`;
      this.cache.set(name, existsSync(path) ? parseDocument(readFileSync(path, 'ascii')) : null);
    }
    return this.cache.get(name)!;
  }
}
export class Profile {
  readonly name: string;
  private readonly root: string;
  private readonly schema: Schema;
  private readonly documents: Documents;
  readonly configuration = new Map<string, Definition>();
  private readonly parents = new Map<string, { parent: string; origin: Origin }>();
  readonly includes: { text: string; depth: number }[] = [];
  private readonly diagnosticSet = new Map<string, Diagnostic>();
  private number = 0;
  private sections = new Set<string>();
  readonly output = new Map<string, OutputEntry>();
  diagnostics: Diagnostic[] = [];
  errors = 0;
  warnings = 0;
  overridden: string[] = [];
  origins = { documents: 0, manifest: 0, defaults: 0 };
  dropped = 0;
  constructor(name: string, root: string, schema: Schema, documents: Documents) {
    this.name = name; this.root = root; this.schema = schema; this.documents = documents;
  }
  readonly report: Reporter = (origin, code, message) => {
    const identity = JSON.stringify([origin.document, origin.line, code, message]);
    this.diagnosticSet.set(identity, { origin, code, message });
  };
  define(key: string, value: RawValue, origin: Origin): void {
    const history = [...(this.configuration.get(key)?.history ?? [])];
    if (history.at(-1) !== originText(origin)) history.push(originText(origin));
    this.configuration.set(key, { value, origin, number: ++this.number, history });
  }
  applyDocument(name: string, chain: string[]): void {
    this.includes.push({ text: name, depth: chain.length - 1 });
    const document = this.documents.read(name)!;
    for (const diagnostic of document.diagnostics) {
      this.report({ document: name, line: diagnostic.line }, diagnostic.code, diagnostic.message);
    }
    for (const statement of document.statements) {
      const origin = { document: name, line: statement.line };
      switch (statement.kind) {
        case 'assign': this.define(statement.key, statement.value, origin); break;
        case 'append': {
          const previous = this.configuration.get(statement.key);
          this.define(statement.key, previous ? appendValue(previous.value, statement.value) : statement.value, origin);
          break;
        }
        case 'unset':
          if (!this.configuration.delete(statement.key)) this.report(origin, 'W_UNSET', `${statement.key} is not set`);
          break;
        case 'inherit': this.parents.set(statement.section, { parent: statement.parent, origin }); break;
        case 'include': {
          const target = statement.document, cycle = chain.indexOf(target);
          if (cycle >= 0) {
            this.report(origin, 'E_INCLUDE_CYCLE', `include cycle ${[...chain.slice(cycle), target].join(' -> ')}`);
            this.includes.push({ text: `${target} (cycle)`, depth: chain.length });
          } else if (this.documents.read(target) === null) {
            this.report(origin, 'E_INCLUDE_MISSING', `missing document ${target}`);
            this.includes.push({ text: `${target} (missing)`, depth: chain.length });
          } else this.applyDocument(target, [...chain, target]);
          break;
        }
      }
    }
  }
  inheritSections(): void {
    const own = new Map<string, Map<string, Definition>>();
    for (const [key, definition] of this.configuration) {
      const [section, name] = splitKey(key);
      let keys = own.get(section);
      if (!keys) { keys = new Map(); own.set(section, keys); }
      keys.set(name, definition);
    }
    for (const [section, declaration] of this.parents) {
      const path = [section];
      let next = this.parents.get(path[path.length - 1]);
      while (next && !path.includes(next.parent)) {
        path.push(next.parent);
        next = this.parents.get(path[path.length - 1]);
      }
      if (next) {
        path.push(next.parent);
        this.report(declaration.origin, 'E_INHERIT_CYCLE', `inheritance cycle ${path.join(' -> ')}`);
        continue;
      }
      const parent = path[1];
      if (!this.parents.has(parent) && !own.has(parent)) {
        this.report(declaration.origin, 'W_PARENT_EMPTY', `section ${section} inherits from empty section ${parent}`);
      }
      for (const ancestor of path.slice(1)) for (const [name, definition] of own.get(ancestor) ?? []) {
        const key = `${section}.${name}`;
        if (!this.configuration.has(key)) this.configuration.set(key, definition);
      }
    }
  }
  resolveAliases(): void {
    for (const spec of this.schema.specs) {
      const attribute = spec.attributes.get('alias');
      if (attribute === undefined) continue;
      const aliases = attribute.split(','), candidates = [spec.pattern, ...aliases].filter(key => this.configuration.has(key));
      if (!aliases.some(key => this.configuration.has(key))) continue;
      let winner = candidates[0];
      for (const key of candidates) if (this.configuration.get(key)!.number > this.configuration.get(winner)!.number) winner = key;
      const definition = this.configuration.get(winner)!;
      for (const key of candidates) {
        const origin = this.configuration.get(key)!.origin;
        if (key !== spec.pattern) this.report(origin, 'W_DEPRECATED', `${key} is deprecated, use ${spec.pattern}`);
        if (key !== winner) this.report(origin, 'W_SHADOWED', `${key} is superseded by ${winner} at ${originText(definition.origin)}`);
      }
      this.configuration.set(spec.pattern, definition);
      for (const alias of aliases) this.configuration.delete(alias);
    }
  }
  fillDefaults(): void {
    this.sections = new Set([...this.configuration.keys()].map(key => splitKey(key)[0]));
    for (const spec of this.schema.specs) {
      const fallback = spec.attributes.get('default');
      if (fallback === undefined) continue;
      for (const key of this.schema.targets(spec, this.sections)) if (!this.configuration.has(key)) {
        this.define(key, plainValue(fallback), { document: 'schema', line: spec.line });
      }
    }
  }
  validate(): void {
    const expanded = expandAll(this.configuration, this.report);
    for (const key of [...this.configuration.keys()].sort(compareKeys)) {
      const text = expanded.get(key);
      if (text === null || text === undefined) continue;
      const spec = this.schema.find(key), definition = this.configuration.get(key)!;
      let checked: CheckedValue | null;
      if (spec === null) {
        this.report(definition.origin, 'W_UNKNOWN', `${key} is not in the schema`);
        checked = { value: text, notation: stringNotation(text) };
      } else checked = checkedValue(key, text, spec, definition.origin, this.report);
      if (checked === null) continue;
      const display = spec?.attributes.has('secret') ? MASK : checked.notation;
      this.output.set(key, { ...checked, display, spec, definition });
    }
  }
  checkOrder(): void {
    const removed: string[] = [];
    for (const [key, entry] of this.output) {
      const le = entry.spec?.attributes.get('le');
      if (le === undefined) continue;
      const target = `${splitKey(key)[0]}.${le}`, other = this.output.get(target);
      if (other && typeof entry.value === 'number' && typeof other.value === 'number' && entry.value > other.value) {
        this.report(entry.definition.origin, 'E_ORDER', `${key}: ${entry.display} is greater than ${target} (${other.display})`);
        removed.push(key);
      }
    }
    for (const key of removed) this.output.delete(key);
  }
  checkRequired(): void {
    for (const spec of this.schema.specs) {
      if (!spec.attributes.has('required')) continue;
      for (const key of this.schema.targets(spec, this.sections)) {
        if (this.configuration.has(key)) continue;
        let message = `${key} is required`;
        const when = spec.attributes.get('when');
        if (when !== undefined) {
          const condition = `${splitKey(key)[0]}.${when}`;
          if (this.output.get(condition)?.value !== true) continue;
          message += ` when ${condition} is true`;
        }
        this.report({ document: this.root, line: 0 }, 'E_REQUIRED', message);
      }
    }
  }
  checkFixed(firstOutput: Map<string, ReferenceValue>): void {
    for (const [key, entry] of this.output) {
      const reference = firstOutput.get(key);
      if (entry.spec?.attributes.has('fixed') && reference && reference.notation !== entry.notation) {
        this.report(entry.definition.origin, 'E_FIXED', `${key}: value differs from profile ${reference.profile}`);
        this.output.delete(key);
      }
    }
    for (const [key, entry] of this.output) if (!firstOutput.has(key)) {
      firstOutput.set(key, { profile: this.name, notation: entry.notation });
    }
  }
  finish(): void {
    this.diagnostics = [...this.diagnosticSet.values()].sort((left, right) =>
      compareText(left.origin.document, right.origin.document) || left.origin.line - right.origin.line
      || compareText(left.code, right.code) || compareText(left.message, right.message));
    this.errors = this.diagnostics.filter(item => item.code.startsWith('E_')).length;
    this.warnings = this.diagnostics.length - this.errors;
    this.overridden = [...this.output.keys()].sort(compareKeys).filter(key => this.output.get(key)!.definition.history.length >= 2);
    for (const entry of this.output.values()) {
      const document = entry.definition.origin.document;
      this.origins[document === 'manifest' ? 'manifest' : document === 'schema' ? 'defaults' : 'documents']++;
    }
    this.dropped = this.configuration.size - this.output.size;
  }
}
function differences(first: Profile, second: Profile): Change[] {
  const keys = [...new Set([...first.output.keys(), ...second.output.keys()])].sort(compareKeys), changes: Change[] = [];
  for (const key of keys) {
    const before = first.output.get(key), after = second.output.get(key);
    if (!before && after) changes.push({ kind: '+', key, after });
    else if (before && !after) changes.push({ kind: '-', key, before });
    else if (before && after && before.notation !== after.notation) changes.push({ kind: '~', key, before, after });
  }
  return changes;
}
function main(): void {
  const schema = new Schema('input/schema.txt'), documents = new Documents();
  const manifest = readFileSync('input/manifest.txt', 'ascii').split('\n').slice(0, -1);
  const profiles: Profile[] = [], firstOutput = new Map<string, ReferenceValue>();
  for (let index = 0; index < manifest.length; index++) {
    const [name, root, ...overrides] = manifest[index].split(' '), profile = new Profile(name, root, schema, documents);
    profile.applyDocument(root, [root]);
    for (const override of overrides) {
      const equals = override.indexOf('=');
      profile.define(override.slice(0, equals), plainValue(override.slice(equals + 1)), { document: 'manifest', line: index + 1 });
    }
    profile.inheritSections(); profile.resolveAliases(); profile.fillDefaults(); profile.validate();
    profile.checkOrder(); profile.checkRequired(); profile.checkFixed(firstOutput); profile.finish();
    profiles.push(profile);
  }
  writeReports(profiles, profiles.slice(1).map((profile, index) => differences(profiles[index], profile)));
}
main();
