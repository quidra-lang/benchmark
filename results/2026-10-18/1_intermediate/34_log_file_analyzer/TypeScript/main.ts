import { readFileSync } from 'node:fs';

const METHODS = ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'];
const REASONS = ['fields', 'date', 'time', 'ip', 'method', 'path', 'status', 'bytes', 'latency'];
const STATUS_CLASSES = ['1xx', '2xx', '3xx', '4xx', '5xx'];
const FILTER_KEYS = ['METHOD', 'STATUS', 'IP', 'PATH'];
const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const FORMS: Record<string, string[]> = {
  SUMMARY: [], MALFORMED: [], STATUS: [], METHODS: [], TOP: ['kind', 'limit'],
  HOURLY: [], TIMELINE: ['minutes'], BANDWIDTH: [], VISITORS: [],
  LATENCY: ['path'], HISTOGRAM: ['width'], APDEX: ['threshold'], ERRORS: [],
  SLOWEST: ['limit'], SESSIONS: ['ip', 'minutes'], BURST: ['length', 'times'],
  PEAK: ['length'], GAPS: ['length'], IP: ['ip'],
  RANGE: ['date', 'time', 'date', 'time'], FILTER: ['key', 'value'],
  UNFILTER: ['subject'], RESET: [], STATE: []
};
const OPTIONAL = new Set(['LATENCY', 'SESSIONS']);
const REQUIRE_RECORDS = new Set([
  'STATUS', 'METHODS', 'TOP', 'HOURLY', 'TIMELINE', 'BANDWIDTH',
  'VISITORS', 'HISTOGRAM', 'APDEX', 'ERRORS', 'SLOWEST', 'BURST', 'PEAK', 'GAPS'
]);
const RANGES: Record<string, [number, number]> = {
  limit: [1, 100], minutes: [1, 1440], width: [1, 100000],
  threshold: [1, 100000], length: [1, 86400], times: [1, 1000]
};
const ERRORS: Record<string, string> = {
  limit: 'invalid number', minutes: 'invalid number', width: 'invalid number',
  threshold: 'invalid number', length: 'invalid number', times: 'invalid number',
  kind: 'invalid kind', path: 'invalid path', ip: 'invalid ip',
  date: 'invalid timestamp', time: 'invalid timestamp',
  key: 'invalid key', subject: 'invalid key', value: 'invalid value'
};
const DAY_SECONDS = 86400;
const MAX_BUCKETS = 60;

type LogRecord = {line: number; date: string; hour: number; timestamp: string; seconds: number; ip: string; method: string; path: string; status: number; size: number; latency: number};
type MalformedLine = {line: number; reason: string};
type FilterRange = {start: string; end: string; startSeconds: number; endSeconds: number};
type Apdex = {count: number; satisfied: number; tolerating: number; frustrated: number; points: number; total: number; notation: string; rating: string};
type PeakWindow = {size: number; start: LogRecord | null; end: LogRecord | null};

class QueryError extends Error {}

function check(condition: boolean, reason: string): asserts condition {
  if (!condition) throw new QueryError(reason);
}
function digits(text: string): boolean {
  return /^[0-9]+$/.test(text);
}
function canonical(text: string, maxDigits: number): boolean {
  return typeof text === 'string' && digits(text) && text.length <= maxDigits &&
    (text.length === 1 || text[0] !== '0');
}
function leapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}
function daysInYear(year: number): number {
  return leapYear(year) ? 366 : 365;
}
function daysInMonth(year: number, month: number): number {
  return month === 2 && leapYear(year) ? 29 : MONTH_DAYS[month - 1];
}
function validDate(text: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return false;
  const [year, month, day] = text.split('-').map(Number);
  return year >= 2000 && year <= 2059 && month >= 1 && month <= 12 &&
    day >= 1 && day <= daysInMonth(year, month);
}
function validTime(text: string): boolean {
  if (!/^\d{2}:\d{2}:\d{2}$/.test(text)) return false;
  const [hour, minute, second] = text.split(':').map(Number);
  return hour < 24 && minute < 60 && second < 60;
}
function validIp(text: string): boolean {
  const parts = text.split('.');
  return parts.length === 4 && parts.every(part => canonical(part, 3) && Number(part) <= 255);
}
function validStatus(text: string): boolean {
  return /^\d{3}$/.test(text) && Number(text) >= 100 && Number(text) <= 599;
}
function validFilterValue(kind: string, value: string): boolean {
  if (kind === 'METHOD') return METHODS.includes(value);
  if (kind === 'STATUS') return STATUS_CLASSES.includes(value) || validStatus(value);
  if (kind === 'IP') return validIp(value);
  return value.startsWith('/');
}
function validArgument(type: string, text: string, args: string[]): boolean {
  if (Object.hasOwn(RANGES, type)) {
    const [low, high] = RANGES[type];
    return canonical(text, 6) && Number(text) >= low && Number(text) <= high;
  }
  switch (type) {
    case 'kind': return ['PATHS', 'IPS'].includes(text);
    case 'path': return text.startsWith('/');
    case 'ip': return validIp(text);
    case 'date': return validDate(text);
    case 'time': return validTime(text);
    case 'key': return FILTER_KEYS.includes(text);
    case 'subject': return text === 'RANGE' || FILTER_KEYS.includes(text);
    default: return validFilterValue(args[0], text);
  }
}
function malformedReason(fields: string[]): string | null {
  if (fields.length !== 8) return 'fields';
  const [date, clock, ip, method, path, status, bytes, latency] = fields;
  if (!validDate(date)) return 'date';
  if (!validTime(clock)) return 'time';
  if (!validIp(ip)) return 'ip';
  if (!METHODS.includes(method)) return 'method';
  if (!path.startsWith('/')) return 'path';
  if (!validStatus(status)) return 'status';
  if (!canonical(bytes, 8)) return 'bytes';
  if (!canonical(latency, 6)) return 'latency';
  return null;
}
function dayNumber(year: number, month: number, day: number): number {
  let days = day - 1;
  for (let y = 2000; y < year; ++y) days += daysInYear(y);
  for (let m = 1; m < month; ++m) days += daysInMonth(year, m);
  return days;
}
function secondsOf(date: string, clock: string): number {
  const [year, month, day] = date.split('-').map(Number);
  const [hour, minute, second] = clock.split(':').map(Number);
  return dayNumber(year, month, day) * DAY_SECONDS + hour * 3600 + minute * 60 + second;
}
function intervalLabel(seconds: number): string {
  let days = Math.floor(seconds / DAY_SECONDS);
  let rest = seconds % DAY_SECONDS;
  let year = 2000;
  while (days >= daysInYear(year)) days -= daysInYear(year++);
  let month = 1;
  while (days >= daysInMonth(year, month)) days -= daysInMonth(year, month++);
  return year + '-' + String(month).padStart(2, '0') + '-' + String(days + 1).padStart(2, '0') +
    ' ' + String(Math.floor(rest / 3600)).padStart(2, '0') + ':' +
    String(Math.floor(rest % 3600 / 60)).padStart(2, '0');
}
function normalizePath(raw: string): string {
  const parts = [];
  for (const item of raw.split('?')[0].split('/')) {
    if (item === '..') parts.pop();
    else if (item !== '' && item !== '.') parts.push(item);
  }
  return '/' + parts.map(part => {
    if (digits(part)) return '{id}';
    if (part.length >= 8 && /^[0-9a-f]+$/.test(part) && /[0-9]/.test(part)) return '{hex}';
    return part;
  }).join('/');
}
function compareIp(a: string, b: string): number {
  const left = a.split('.').map(Number), right = b.split('.').map(Number);
  for (let i = 0; i < 4; ++i) if (left[i] !== right[i]) return left[i] - right[i];
  return 0;
}
function statusMatches(filter: string, status: number): boolean {
  return STATUS_CLASSES.includes(filter) ? Math.floor(status / 100) === Number(filter[0]) : status === Number(filter);
}
function decimal(numerator: number, denominator: number, places: number): string {
  const scale = 10 ** places;
  const value = Math.floor(numerator * scale / denominator);
  return Math.floor(value / scale) + '.' + String(value % scale).padStart(places, '0');
}
function percent(numerator: number, denominator: number): string {
  return decimal(numerator * 100, denominator, 2) + '%';
}
function bar(count: number, maximum: number): string {
  return '#'.repeat(Math.floor((count * 30 + maximum - 1) / maximum));
}
function bytesText(size: number): string {
  for (const [unit, suffix] of ([[1073741824, 'GB'], [1048576, 'MB'], [1024, 'KB']] as [number, string][])) {
    if (size >= unit) return decimal(size, unit, 1) + suffix;
  }
  return size + 'B';
}
function sum(records: LogRecord[], key: "size" | "latency"): number {
  return records.reduce((total, record) => total + record[key], 0);
}
function grouped(records: LogRecord[], key: keyof LogRecord | ((r: LogRecord) => string)): Map<string, LogRecord[]> {
  const groups = new Map<string, LogRecord[]>();
  for (const row of records) {
    const k = typeof key === 'function' ? key(row) : String(row[key]);
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k)!.push(row);
  }
  return groups;
}
function tallied<T extends string | number>(values: T[]): Map<T, number> {
  const counts = new Map<T, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return counts;
}
function sortedByCount<T extends string | number>(counts: Map<T, number>, comparator: (a: T, b: T) => number = (a, b) => a < b ? -1 : (a > b ? 1 : 0)): T[] {
  return [...counts.keys()].sort((a, b) => (counts.get(b)! - counts.get(a)!) || comparator(a, b));
}
function statusClassCounts(records: LogRecord[]): number[] {
  const counts = [0, 0, 0, 0, 0];
  for (const record of records) ++counts[Math.floor(record.status / 100) - 1];
  return counts;
}
function bucketCounts(numbers: number[]): [number, number[]] {
  const first = Math.min(...numbers), last = Math.max(...numbers);
  check(last - first + 1 <= MAX_BUCKETS, 'too many buckets');
  const counts = Array(last - first + 1).fill(0);
  for (const n of numbers) ++counts[n - first];
  return [first, counts];
}
function percentile(sorted: number[], rank: number): number {
  return sorted[Math.floor((rank * sorted.length + 99) / 100) - 1];
}
function windowPeak(records: LogRecord[], length: number): PeakWindow {
  let size = 0, start: LogRecord | null = null, end: LogRecord | null = null;
  let first = 0;
  for (let last = 0; last < records.length; ++last) {
    while (records[last].seconds - records[first].seconds >= length) ++first;
    if (last - first + 1 > size) {
      size = last - first + 1;
      start = records[first];
      end = records[last];
    }
  }
  return {size, start, end};
}
function apdexScore(records: LogRecord[], threshold: number): Apdex {
  const satisfied = records.filter(r => r.status < 500 && r.latency <= threshold).length;
  const tolerating = records.filter(r => r.status < 500 && r.latency > threshold && r.latency <= 4 * threshold).length;
  const frustrated = records.length - satisfied - tolerating;
  const points = 2 * satisfied + tolerating, total = 2 * records.length;
  const ratio = points / total;
  const rating = ratio >= 0.94 ? 'excellent' : ratio >= 0.85 ? 'good' :
    ratio >= 0.70 ? 'fair' : ratio >= 0.50 ? 'poor' : 'unacceptable';
  return {count: records.length, satisfied, tolerating, frustrated, points, total,
    notation: decimal(points, total, 3), rating};
}

class LogAnalyzer {
  records: LogRecord[] = [];
  malformed: MalformedLine[] = [];
  lineCount: number;
  conditions: Record<string, string | null>;
  range: FilterRange | null = null;
  output: string[] = [];

  constructor(lines: string[]) {
    this.lineCount = lines.length;
    for (let i = 0; i < lines.length; ++i) {
      const fields = lines[i].trim().split(/\s+/);
      const reason = malformedReason(fields);
      if (reason !== null) {
        this.malformed.push({line: i + 1, reason});
        continue;
      }
      const [date, clock, ip, method, rawPath, status, bytes, latency] = fields;
      this.records.push({line: i + 1, date, hour: Number(clock.slice(0, 2)),
        timestamp: date + ' ' + clock, seconds: secondsOf(date, clock), ip,
        method, path: normalizePath(rawPath), status: Number(status),
        size: Number(bytes), latency: Number(latency)});
    }
    this.records.sort((a, b) => a.seconds - b.seconds || a.line - b.line);
    this.conditions = {METHOD: null, STATUS: null, IP: null, PATH: null};

  }
  emit(...parts: (number | string)[]): void {
    this.output.push(parts.join(' '));
  }
  selected(): LogRecord[] {
    return this.records.filter(r => {
      if (this.range && (r.seconds < this.range.startSeconds || r.seconds > this.range.endSeconds)) return false;
      if (this.conditions.METHOD !== null && r.method !== this.conditions.METHOD) return false;
      if (this.conditions.STATUS !== null && !statusMatches(this.conditions.STATUS, r.status)) return false;
      if (this.conditions.IP !== null && r.ip !== this.conditions.IP) return false;
      return this.conditions.PATH === null || r.path === this.conditions.PATH;
    });
  }
  barLine(label: string, count: number, maximum: number): void {
    this.emit(label, count, ...(count ? [bar(count, maximum)] : []));
  }
  execute(line: string): void {
    const [name, ...args] = line.trim().split(/\s+/);
    try {
      check(Object.hasOwn(FORMS, name), 'unknown query');
      const form = FORMS[name];
      const optional = OPTIONAL.has(name) && args.length === form.length - 1;
      check(args.length === form.length || optional, 'wrong arguments');
      for (let i = 0; i < args.length; ++i) {
        check(validArgument(form[i], args[i], args), ERRORS[form[i]]);
      }
      const records = this.selected();
      if (REQUIRE_RECORDS.has(name) && records.length === 0) {
        this.emit(name, 'no records');
        return;
      }
      this.run(name, args, records);
    } catch (error) {
      if (!(error instanceof QueryError)) throw error;
      this.emit('ERROR', error.message);
    }
  }
  run(name: string, a: string[], records: LogRecord[]): void {
    switch (name) {
      case 'SUMMARY': {
        this.emit('SUMMARY', 'lines', this.lineCount, 'valid', this.records.length,
          'malformed', this.malformed.length);
        this.emit('requests', records.length, 'bytes', sum(records, 'size'),
          'ips', new Set(records.map(r => r.ip)).size,
          'paths', new Set(records.map(r => r.path)).size);
        if (!records.length) this.emit('span', 'none');
        else this.emit('span', records[0].timestamp, records.at(-1)!.timestamp,
          records.at(-1)!.seconds - records[0].seconds);
        break;
      }
      case 'MALFORMED': {
        this.emit('MALFORMED', this.malformed.length);
        for (const reason of REASONS) {
          const lines = this.malformed.filter(x => x.reason === reason).map(x => x.line);
          if (lines.length) this.emit(reason, lines.length, ...lines);
        }
        break;
      }
      case 'STATUS': {
        this.emit('STATUS', records.length);
        const classes = statusClassCounts(records);
        STATUS_CLASSES.forEach((c, i) => this.emit(c, classes[i], percent(classes[i], records.length)));
        const counts = tallied(records.map(r => r.status));
        for (const s of [...counts.keys()].sort((x, y) => x - y))
          this.emit(s, counts.get(s)!, percent(counts.get(s)!, records.length));
        break;
      }
      case 'METHODS': {
        const counts = tallied(records.map(r => r.method));
        this.emit('METHODS', records.length);
        for (const method of sortedByCount(counts))
          this.emit(method, counts.get(method)!, percent(counts.get(method)!, records.length));
        break;
      }
      case 'TOP': {
        const [kind, token] = a;
        const counts = tallied(records.map(r => kind === 'PATHS' ? r.path : r.ip));
        const keys = sortedByCount(counts, kind === 'IPS' ? compareIp : undefined);
        const shown = Math.min(Number(token), keys.length);
        this.emit('TOP', kind, shown, 'of', keys.length);
        let rank = 0;
        keys.slice(0, shown).forEach((key, i) => {
          if (i === 0 || counts.get(key)! !== counts.get(keys[i - 1])) rank = i + 1;
          this.emit(rank, key, counts.get(key)!, percent(counts.get(key)!, records.length));
        });
        break;
      }
      case 'HOURLY': {
        const counts = Array(24).fill(0);
        for (const r of records) ++counts[r.hour];
        const maximum = Math.max(...counts);
        this.emit('HOURLY', records.length, 'peak', String(counts.indexOf(maximum)).padStart(2, '0'), maximum);
        counts.forEach((count, h) => this.barLine(String(h).padStart(2, '0'), count, maximum));
        break;
      }
      case 'TIMELINE': {
        const minutes = Number(a[0]), width = minutes * 60;
        const [first, counts] = bucketCounts(records.map(r => Math.floor(r.seconds / width)));
        this.emit('TIMELINE', minutes, counts.length);
        const maximum = Math.max(...counts);
        counts.forEach((count, i) => this.barLine(intervalLabel((first + i) * width), count, maximum));
        break;
      }
      case 'BANDWIDTH': {
        const days = grouped(records, 'date'), bytes = sum(records, 'size');
        this.emit('BANDWIDTH', days.size, bytes, bytesText(bytes));
        for (const date of [...days.keys()].sort()) {
          const volume = sum(days.get(date)!, 'size');
          this.emit(date, days.get(date)!.length, volume, bytesText(volume));
        }
        break;
      }
      case 'VISITORS': {
        const first = new Map();
        for (const r of records) if (!first.has(r.ip) || r.date < first.get(r.ip)) first.set(r.ip, r.date);
        const days = grouped(records, 'date');
        this.emit('VISITORS', days.size, first.size);
        for (const date of [...days.keys()].sort()) {
          const ips = new Set(days.get(date)!.map(r => r.ip));
          let newcomers = 0;
          for (const ip of ips) if (first.get(ip) === date) ++newcomers;
          this.emit(date, 'unique', ips.size, 'new', newcomers, 'returning', ips.size - newcomers);
        }
        break;
      }
      case 'LATENCY': {
        const label = a.length ? normalizePath(a[0]) : 'all';
        const rows = a.length ? records.filter(r => r.path === label) : records;
        if (!rows.length) { this.emit('LATENCY', 'no records'); break; }
        const values = rows.map(r => r.latency).sort((x, y) => x - y);
        const n = values.length, trim = Math.floor(n / 10);
        const trimmed = values.slice(trim, n - trim);
        this.emit('LATENCY', label, 'count', n, 'min', values[0],
          'p50', percentile(values, 50), 'p90', percentile(values, 90),
          'p99', percentile(values, 99), 'max', values.at(-1)!,
          'mean', decimal(values.reduce((v, x) => v + x, 0), n, 2),
          'trimmed', decimal(trimmed.reduce((v, x) => v + x, 0), trimmed.length, 2));
        break;
      }
      case 'HISTOGRAM': {
        const width = Number(a[0]);
        const [first, counts] = bucketCounts(records.map(r => Math.floor(r.latency / width)));
        this.emit('HISTOGRAM', width, counts.length);
        const maximum = Math.max(...counts);
        counts.forEach((count, i) => {
          const lo = (first + i) * width;
          this.barLine(lo + '-' + (lo + width - 1), count, maximum);
        });
        break;
      }
      case 'APDEX': {
        const threshold = Number(a[0]), overall = apdexScore(records, threshold);
        this.emit('APDEX', threshold, overall.notation, overall.rating,
          'satisfied', overall.satisfied, 'tolerating', overall.tolerating,
          'frustrated', overall.frustrated);
        const paths = [...grouped(records, 'path')].map(([path, rows]) => ({path, ...apdexScore(rows, threshold)}));
        paths.sort((x, y) => x.points * y.total - y.points * x.total || y.count - x.count ||
          x.path.localeCompare(y.path, 'en'));
        for (const row of paths) this.emit(row.path, row.notation, row.rating, row.count);
        break;
      }
      case 'ERRORS': {
        const failed = records.filter(r => r.status >= 400);
        this.emit('ERRORS', failed.length, 'of', records.length, percent(failed.length, records.length));
        const paths = [...grouped(records, 'path')].map(([path, rows]) => ({
          path, count: rows.length,
          client: rows.filter(r => Math.floor(r.status / 100) === 4).length,
          server: rows.filter(r => Math.floor(r.status / 100) === 5).length
        })).filter(row => row.client + row.server > 0);
        paths.sort((x, y) => {
          const xf = x.client + x.server, yf = y.client + y.server;
          return yf * x.count - xf * y.count || yf - xf || (x.path < y.path ? -1 : 1);
        });
        for (const row of paths) this.emit(row.path, row.count, row.client, row.server,
          percent(row.client + row.server, row.count));
        break;
      }
      case 'SLOWEST': {
        const groups = grouped(records, r => r.method + '\u0001' + r.path);
        const rows = [...groups].map(([key, items]) => {
          const [method, path] = key.split('\u0001');
          return {method, path, count: items.length,
            total: sum(items, 'latency'), maximum: Math.max(...items.map(r => r.latency))};
        });
        rows.sort((x, y) => y.total * x.count - x.total * y.count || y.maximum - x.maximum ||
          (x.path < y.path ? -1 : x.path > y.path ? 1 : (x.method < y.method ? -1 : 1)));
        const shown = Math.min(Number(a[0]), rows.length);
        this.emit('SLOWEST', shown, 'of', rows.length);
        rows.slice(0, shown).forEach((row, i) =>
          this.emit(i + 1, row.method, row.path, 'count', row.count,
            'avg', decimal(row.total, row.count, 2), 'max', row.maximum));
        break;
      }
      case 'SESSIONS': {
        const ip = a[0], minutes = a.length > 1 ? Number(a[1]) : 30;
        const found = records.filter(r => r.ip === ip);
        if (!found.length) { this.emit('SESSIONS', 'no records'); break; }
        const sessions = [[found[0]]];
        for (let i = 1; i < found.length; ++i) {
          const current = found[i], prev = found[i - 1];
          if (current.seconds - prev.seconds <= minutes * 60) sessions.at(-1)!.push(current);
          else sessions.push([current]);
        }
        const duration = sessions.reduce((v, session) => v + session.at(-1)!.seconds - session[0].seconds, 0);
        this.emit('SESSIONS', ip, 'timeout', minutes, 'count', sessions.length,
          'requests', found.length, 'avg_duration', decimal(duration, sessions.length, 1),
          'avg_requests', decimal(found.length, sessions.length, 1));
        sessions.forEach((session, i) => this.emit(i + 1, session[0].timestamp,
          session.at(-1)!.timestamp, session.at(-1)!.seconds - session[0].seconds,
          session.length, new Set(session.map(r => r.path)).size));
        break;
      }
      case 'BURST': {
        const [length, times] = a.map(Number);
        const ips = grouped(records.filter(r => r.status >= 400), 'ip');
        const rows = [...ips].map(([ip, items]) => ({ip, ...windowPeak(items, length)}))
          .filter(x => x.size >= times);
        rows.sort((x, y) => y.size - x.size || compareIp(x.ip, y.ip));
        this.emit('BURST', length, times, rows.length);
        for (const row of rows) this.emit(row.ip, row.size, row.start!.timestamp, row.end!.timestamp);
        break;
      }
      case 'PEAK': {
        const window = windowPeak(records, Number(a[0]));
        this.emit('PEAK', Number(a[0]), window.size, window.start!.timestamp, window.end!.timestamp);
        break;
      }
      case 'GAPS': {
        const length = Number(a[0]);
        const gaps = [];
        for (let i = 1; i < records.length; ++i) {
          if (records[i].seconds - records[i - 1].seconds >= length)
            gaps.push([records[i - 1], records[i]]);
        }
        this.emit('GAPS', length, gaps.length);
        for (const [prev, curr] of gaps)
          this.emit(prev.timestamp, curr.timestamp, curr.seconds - prev.seconds);
        break;
      }
      case 'IP': {
        const ip = a[0], found = records.filter(r => r.ip === ip);
        if (!found.length) { this.emit('IP', 'no records'); break; }
        const paths = tallied(found.map(r => r.path));
        this.emit('IP', ip, 'requests', found.length, 'bytes', sum(found, 'size'),
          'errors', found.filter(r => r.status >= 400).length, 'paths', paths.size);
        this.emit('first', found[0].timestamp, 'last', found.at(-1)!.timestamp);
        const methods = tallied(found.map(r => r.method));
        this.emit('methods', ...sortedByCount(methods).flatMap(method => [method, methods.get(method)!]));
        this.emit('classes', ...STATUS_CLASSES.flatMap((label, i) => [label, statusClassCounts(found)[i]]));
        for (const path of sortedByCount(paths).slice(0, 3)) this.emit('path', path, paths.get(path)!);
        break;
      }
      case 'RANGE': {
        const start = a[0] + ' ' + a[1], end = a[2] + ' ' + a[3];
        const startSeconds = secondsOf(a[0], a[1]), endSeconds = secondsOf(a[2], a[3]);
        check(startSeconds <= endSeconds, 'invalid range');
        this.range = {start, end, startSeconds, endSeconds};
        this.emit('RANGE', start, end, 'active', this.selected().length);
        break;
      }
      case 'FILTER': {
        const [key, raw] = a;
        const value = key === 'PATH' ? normalizePath(raw) : raw;
        this.conditions[key] = value;
        this.emit('FILTER', key, value, 'active', this.selected().length);
        break;
      }
      case 'UNFILTER': {
        const key = a[0];
        if (key === 'RANGE') {
          check(this.range !== null, 'not filtered');
          this.range = null;
        } else {
          check(this.conditions[key] !== null, 'not filtered');
          this.conditions[key] = null;
        }
        this.emit('UNFILTER', key, 'active', this.selected().length);
        break;
      }
      case 'RESET': {
        this.range = null;
        for (const key of FILTER_KEYS) this.conditions[key] = null;
        this.emit('RESET', 'active', this.selected().length);
        break;
      }
      case 'STATE': {
        const range = this.range === null ? '-' : this.range.start + ' ' + this.range.end;
        this.emit('STATE', 'active', records.length, 'range', range,
          ...FILTER_KEYS.flatMap(key => [key.toLowerCase(), this.conditions[key] ?? '-']));
        break;
      }
    }
  }
}

function main(): void {
  const lines = readFileSync(0, 'utf8').split(/\r?\n/);
  const separator = lines.indexOf('---');
  const end = lines.indexOf('END', separator + 1);
  const analyzer = new LogAnalyzer(lines.slice(0, separator));
  for (let i = separator + 1; i < end; ++i) analyzer.execute(lines[i]);
  if (analyzer.output.length) process.stdout.write(analyzer.output.join('\n') + '\n');
}

main();
