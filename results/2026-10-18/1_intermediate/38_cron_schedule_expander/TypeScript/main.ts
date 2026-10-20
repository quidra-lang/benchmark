import { readFileSync } from 'node:fs';

const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] as const;
const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'] as const;
const fieldNames = ['minute', 'hour', 'day-of-month', 'month', 'day-of-week'] as const;
const fieldIndices = [0, 1, 2, 3, 4] as const;
type FieldIndex = typeof fieldIndices[number];
type Policy = 'ALLOW' | 'FORBID' | 'REPLACE';
type Conjunction = 'and' | 'or';
const limits = [[0, 59], [0, 23], [1, 31], [1, 12], [0, 7]] as const;
const macros = new Map<string, string>([
    ['@yearly', '0 0 1 1 *'], ['@annually', '0 0 1 1 *'], ['@monthly', '0 0 1 * *'],
    ['@weekly', '0 0 * * 0'], ['@daily', '0 0 * * *'], ['@midnight', '0 0 * * *'], ['@hourly', '0 * * * *'],
]);
class CommandError extends Error {}
function fail(reason: string): never { throw new CommandError(reason); }
const pad = (value: number): string => String(value).padStart(2, '0');
const ascii = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const leap = (year: number): boolean => year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
const monthLength = (year: number, month: number): number => month === 2 && leap(year) ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
const leapCount = (year: number): number => Math.floor(year / 4) - Math.floor(year / 100) + Math.floor(year / 400);
const yearStart = (year: number): number => 365 * (year - 2000) + leapCount(year - 1) - leapCount(1999);
interface YearMonth { readonly year: number; readonly month: number }
interface CivilDate extends YearMonth { readonly number: number; readonly day: number; readonly weekday: number; readonly length: number }
interface Window { readonly low: number; readonly high: number }
function dayNumber(year: number, month: number, day: number): number {
    let result = yearStart(year) + day - 1;
    for (let prior = 1; prior < month; ++prior) result += monthLength(year, prior);
    return result;
}
function civil(day: number): CivilDate {
    let year = 2000 + Math.floor(day / 366);
    while (yearStart(year + 1) <= day) ++year;
    let remaining = day - yearStart(year), month = 1;
    while (remaining >= monthLength(year, month)) remaining -= monthLength(year, month++);
    return { number: day, year, month, day: remaining + 1, weekday: (day + 6) % 7, length: monthLength(year, month) };
}
const dateText = (date: CivilDate): string => `${date.year}-${pad(date.month)}-${pad(date.day)}`;
const timeText = (minute: number): string => `${pad(Math.floor(minute / 60))}:${pad(minute % 60)}`;
function dateNotation(day: number): string {
    const date = civil(day);
    return `${dateText(date)} ${weekdays[date.weekday].slice(0, 3)}`;
}
function datetimeNotation(minute: number): string {
    const date = civil(Math.floor(minute / 1440));
    return `${dateText(date)} ${timeText(minute % 1440)} ${weekdays[date.weekday].slice(0, 3)}`;
}
const spanText = (minutes: number): string => `${Math.floor(minutes / 1440)}d${pad(Math.floor(minutes % 1440 / 60))}h${pad(minutes % 60)}m`;
function parseDate(text: string, reason = 'invalid date'): number {
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(text)) fail(reason);
    const [year, month, day] = text.split('-').map(Number);
    if (year < 2001 || year > 2098 || month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) fail(reason);
    return dayNumber(year, month, day);
}
function parseDatetime(words: readonly string[], position: number): number {
    const day = parseDate(words[position], 'invalid datetime'), text = words[position + 1];
    if (!/^[0-9]{2}:[0-9]{2}$/.test(text)) fail('invalid datetime');
    const [hour, minute] = text.split(':').map(Number);
    if (hour > 23 || minute > 59) fail('invalid datetime');
    return day * 1440 + hour * 60 + minute;
}
function parseMonth(text: string): YearMonth {
    if (!/^[0-9]{4}-[0-9]{2}$/.test(text)) fail('invalid month');
    const [year, month] = text.split('-').map(Number);
    if (year < 2001 || year > 2098 || month < 1 || month > 12) fail('invalid month');
    return { year, month };
}
function parseWindow(words: readonly string[], position: number): Window {
    const low = parseDatetime(words, position), high = parseDatetime(words, position + 2);
    if (low > high) fail('invalid window');
    if (high - low > 44640) fail('window too long');
    return { low, high };
}
function positive(text: string, width: number, maximum: number, reason: string): number {
    if (!/^[1-9][0-9]*$/.test(text) || text.length > width || Number(text) > maximum) fail(reason);
    return Number(text);
}
function natural(text: string, minimum: number, maximum: number, error: (reason: string) => never): number {
    if (!/^[0-9]{1,2}$/.test(text)) error('invalid value');
    const value = Number(text);
    if (value < minimum || value > maximum) error('out of range');
    return value;
}
type Special = Readonly<
    { kind: 'last' | 'lastWeekday' } | { kind: 'before' | 'nearest'; number: number } |
    { kind: 'nth'; weekday: number; number: number } | { kind: 'lastDow'; weekday: number }
>;
function canonical(item: Special): string {
    switch (item.kind) {
        case 'last': return 'L';
        case 'lastWeekday': return 'LW';
        case 'before': return `L-${item.number}`;
        case 'nearest': return `${item.number}W`;
        case 'nth': return `${item.weekday}#${item.number}`;
        case 'lastDow': return `${item.weekday}L`;
    }
}
class Field {
    readonly unrestricted: boolean;
    readonly set: ReadonlySet<number>;
    readonly values: readonly number[];
    readonly specials: readonly Special[];
    constructor(text: string, readonly index: FieldIndex) {
        this.unrestricted = text.startsWith('*');
        const values = new Set<number>(), specials: Special[] = [];
        const [minimum, maximum] = limits[index];
        const error = (reason: string): never => fail(`${fieldNames[index]} ${reason}`);
        const value = (text: string): number => {
            const names: readonly string[] = index === 3 ? months : index === 4 ? weekdays : [];
            const named = names.findIndex(name => name.slice(0, 3).toUpperCase() === text);
            return named >= 0 ? named + (index === 3 ? 1 : 0) : natural(text, minimum, maximum, error);
        };
        const addSpecial = (item: Special): void => {
            if (!specials.some(existing => canonical(existing) === canonical(item))) specials.push(item);
        };
        for (const item of text.split(',')) {
            if (item === '') error('empty item');
            if (index === 2 && (item.startsWith('L') || item.endsWith('W'))) {
                if (item === 'L') addSpecial({ kind: 'last' });
                else if (item === 'LW') addSpecial({ kind: 'lastWeekday' });
                else if (item.startsWith('L-')) addSpecial({ kind: 'before', number: natural(item.slice(2), 1, 30, error) });
                else if (item.endsWith('W')) addSpecial({ kind: 'nearest', number: natural(item.slice(0, -1), 1, 31, error) });
                else error('invalid value');
                continue;
            }
            if (index === 4 && item.includes('#')) {
                const split = item.indexOf('#'), weekday = value(item.slice(0, split)) % 7, part = item.slice(split + 1);
                if (!/^[0-9]$/.test(part)) error('invalid value');
                const number = Number(part);
                if (number < 1 || number > 5) error('out of range');
                addSpecial({ kind: 'nth', weekday, number });
                continue;
            }
            if (index === 4 && item.length >= 2 && item.endsWith('L')) {
                addSpecial({ kind: 'lastDow', weekday: value(item.slice(0, -1)) % 7 });
                continue;
            }
            const slash = item.indexOf('/'), base = slash < 0 ? item : item.slice(0, slash);
            let first: number, last: number, step = 1;
            if (base === '*') { first = minimum; last = maximum; }
            else if (base.includes('-')) {
                const dash = base.indexOf('-');
                first = value(base.slice(0, dash)); last = value(base.slice(dash + 1));
                if (first > last) error('invalid range');
            } else { first = value(base); last = slash < 0 ? first : maximum; }
            if (slash >= 0) {
                const part = item.slice(slash + 1);
                if (!/^[0-9]{1,2}$/.test(part) || Number(part) < 1) error('invalid step');
                step = Number(part);
            }
            for (let number = first; number <= last; number += step) values.add(index === 4 ? number % 7 : number);
        }
        this.set = values;
        this.values = [...values].sort((a, b) => a - b);
        this.specials = specials;
    }
}
interface DayStatus { readonly monthDay: boolean; readonly weekDay: boolean; readonly matches: boolean }
class Cron {
    readonly text: string;
    readonly expanded: string;
    readonly fields: readonly [Field, Field, Field, Field, Field];
    readonly or: boolean;
    readonly times: readonly number[];
    constructor(tokens: readonly string[]) {
        this.text = tokens.join(' ');
        if (tokens.length === 1 && tokens[0].startsWith('@')) {
            const expanded = macros.get(tokens[0]);
            if (expanded === undefined) fail('unknown macro');
            tokens = expanded.split(' ');
        }
        if (tokens.length !== 5) fail('field count');
        this.expanded = tokens.join(' ');
        this.fields = [new Field(tokens[0], 0), new Field(tokens[1], 1), new Field(tokens[2], 2), new Field(tokens[3], 3), new Field(tokens[4], 4)];
        this.or = !this.fields[2].unrestricted && !this.fields[4].unrestricted;
        this.times = this.fields[1].values.flatMap(hour => this.fields[0].values.map(minute => 60 * hour + minute));
    }
    days(date: CivilDate): DayStatus {
        const dom = this.fields[2], dow = this.fields[4];
        const nearest = (day: number): number => {
            const weekday = (date.number - date.day + day + 6) % 7;
            if (weekday === 6) return day === 1 ? 3 : day - 1;
            if (weekday === 0) return day === date.length ? day - 2 : day + 1;
            return day;
        };
        const monthDay = dom.set.has(date.day) || dom.specials.some(item => {
            switch (item.kind) {
                case 'last': return date.day === date.length;
                case 'lastWeekday': return date.day === nearest(date.length);
                case 'before': return date.day === date.length - item.number;
                case 'nearest': return item.number <= date.length && date.day === nearest(item.number);
                default: return false;
            }
        });
        const weekDay = dow.set.has(date.weekday) || dow.specials.some(item => {
            switch (item.kind) {
                case 'nth': return item.weekday === date.weekday && Math.floor((date.day - 1) / 7) + 1 === item.number;
                case 'lastDow': return item.weekday === date.weekday && date.day + 7 > date.length;
                default: return false;
            }
        });
        return { monthDay, weekDay, matches: this.or ? monthDay || weekDay : monthDay && weekDay };
    }
    scheduled(date: CivilDate): boolean { return this.fields[3].set.has(date.month) && this.days(date).matches; }
    reasons(minute: number, holidays: ReadonlySet<number>): string[] {
        const date = civil(Math.floor(minute / 1440)), days = this.days(date), reasons: string[] = [];
        if (!this.fields[0].set.has(minute % 60)) reasons.push('minute');
        if (!this.fields[1].set.has(Math.floor(minute % 1440 / 60))) reasons.push('hour');
        if (!days.matches && !days.monthDay) reasons.push('day-of-month');
        if (!this.fields[3].set.has(date.month)) reasons.push('month');
        if (!days.matches && !days.weekDay) reasons.push('day-of-week');
        if (holidays.has(date.number)) reasons.push('excluded');
        return reasons;
    }
    *fires(low: number, high: number, holidays: ReadonlySet<number>, reverse = false): Generator<number> {
        const first = Math.floor(low / 1440), last = Math.floor(high / 1440), step = reverse ? -1 : 1;
        const times = reverse ? this.times.slice().reverse() : this.times;
        for (let day = reverse ? last : first; reverse ? day >= first : day <= last; day += step) {
            if (holidays.has(day) || !this.scheduled(civil(day))) continue;
            for (const time of times) {
                const minute = 1440 * day + time;
                if (low <= minute && minute <= high) yield minute;
            }
        }
    }
}
function list(parts: readonly string[], conjunction: Conjunction = 'and'): string {
    return parts.length < 2 ? parts.join('') : parts.slice(0, -1).join(', ') + ` ${conjunction} ` + parts[parts.length - 1];
}
function valueList(values: readonly number[], index: FieldIndex, conjunction: Conjunction = 'and'): string {
    const label = (value: number): string => index === 3 ? months[value - 1] : index === 4 ? weekdays[value] : String(value);
    const parts: string[] = [];
    for (let first = 0; first < values.length;) {
        let end = first + 1;
        while (end < values.length && values[end] === values[end - 1] + 1) ++end;
        if (end - first >= 3) parts.push(`${label(values[first])} through ${label(values[end - 1])}`);
        else for (let position = first; position < end; ++position) parts.push(label(values[position]));
        first = end;
    }
    return list(parts, conjunction);
}
function stepped(values: readonly number[], maximum: number): number | null {
    if (values.length < 2 || values[0] !== 0 || values[1] < 2) return null;
    const step = values[1];
    return values.length === Math.floor(maximum / step) + 1 && values.every((value, index) => value === index * step) ? step : null;
}
function description(cron: Cron): string {
    const [minutes, hours, dom, month, dow] = cron.fields;
    let time: string;
    if (cron.times.length <= 4) time = 'At ' + list(cron.times.map(timeText));
    else {
        const minuteStep = stepped(minutes.values, 59), hourStep = stepped(hours.values, 23);
        if (minutes.values.length === 60) time = 'Every minute';
        else if (minuteStep !== null) time = `Every ${minuteStep} minutes`;
        else if (minutes.values.length === 1) time = `At minute ${minutes.values[0]}`;
        else time = 'At minutes ' + valueList(minutes.values, 0);
        if (hours.values.length === 24) { if (time.startsWith('At minute')) time += ' of every hour'; }
        else if (hourStep !== null) time += `, every ${hourStep} hours`;
        else if (hours.values[hours.values.length - 1] - hours.values[0] + 1 === hours.values.length) {
            time += `, between ${pad(hours.values[0])}:00 and ${pad(hours.values[hours.values.length - 1])}:59`;
        } else time += ', during hours ' + valueList(hours.values, 1);
    }
    const domParts: string[] = [];
    if (dom.values.length) domParts.push(dom.values.length === 1 ? `day ${dom.values[0]}` : 'days ' + valueList(dom.values, 2));
    for (const item of dom.specials) {
        switch (item.kind) {
            case 'last': domParts.push('the last day'); break;
            case 'lastWeekday': domParts.push('the last weekday'); break;
            case 'before': domParts.push(`${item.number} ${item.number === 1 ? 'day' : 'days'} before the last day`); break;
            case 'nearest': domParts.push(`the weekday nearest day ${item.number}`); break;
        }
    }
    const domClause = list(domParts) + ' of the month';
    const dowClause = (conjunction: Conjunction = 'and'): string => {
        const parts = dow.values.length ? [valueList(dow.values, 4, conjunction)] : [];
        for (const item of dow.specials) {
            if (item.kind === 'nth') parts.push(`the ${['1st', '2nd', '3rd', '4th', '5th'][item.number - 1]} ${weekdays[item.weekday]}`);
            else if (item.kind === 'lastDow') parts.push(`the last ${weekdays[item.weekday]}`);
        }
        return list(parts, conjunction) + (dow.specials.length ? ' of the month' : '');
    };
    const domFull = dom.values.length === 31, dowFull = dow.values.length === 7;
    let day = '';
    if (cron.or) { if (!domFull && !dowFull) day = `, on ${domClause} or on ${dowClause()}`; }
    else if (!domFull && !dowFull) day = `, on ${domClause} if it is ${dowClause('or')}`;
    else if (!domFull) day = `, on ${domClause}`;
    else if (!dowFull) day = `, on ${dowClause()}`;
    return time + day + (month.values.length === 12 ? '' : ', in ' + valueList(month.values, 3));
}

class Job {
    enabled = true;
    duration = 1;
    policy: Policy = 'ALLOW';
    constructor(public id: string, readonly cron: Cron) {}
}
type Command = Readonly<
    { kind: 'JOB'; id: string; cron: Cron } | { kind: 'VALIDATE'; cron: Cron } |
    { kind: 'REMOVE' | 'ENABLE' | 'DISABLE' | 'DESCRIBE'; job: Job } |
    { kind: 'RENAME'; job: Job; id: string } | { kind: 'RUNTIME'; job: Job; duration: number; policy: Policy } |
    { kind: 'LIST' | 'HOLIDAYS' } | { kind: 'EXPAND'; job: Job; field: FieldIndex } |
    { kind: 'MATCH' | 'GAP'; job: Job; base: number } | { kind: 'NEXT' | 'PREV'; job: Job; base: number; count: number } |
    { kind: 'COUNT'; job: Job; window: Window } | { kind: 'OVERLAP'; first: Job; second: Job; window: Window } |
    { kind: 'TIMELINE' | 'CONFLICTS' | 'SIMULATE'; window: Window } |
    { kind: 'WEEK'; day: number; original: string } | { kind: 'CALENDAR'; job: Job; month: YearMonth; original: string } |
    { kind: 'EXCLUDE' | 'INCLUDE'; day: number }
>;
const arities = {
    JOB: -3, VALIDATE: -2, REMOVE: 2, RENAME: 3, ENABLE: 2, DISABLE: 2, RUNTIME: 4,
    LIST: 1, EXPAND: 3, DESCRIBE: 2, MATCH: 4, NEXT: 5, PREV: 5, COUNT: 6, GAP: 4,
    OVERLAP: 7, TIMELINE: 5, CONFLICTS: 5, WEEK: 2, CALENDAR: 3, SIMULATE: 5,
    EXCLUDE: 2, INCLUDE: 2, HOLIDAYS: 1,
} as const;
type CommandName = keyof typeof arities;
function isCommandName(text: string): text is CommandName { return Object.hasOwn(arities, text); }
class Scheduler {
    private readonly jobs = new Map<string, Job>();
    private readonly holidays = new Set<number>();
    private newId(id: string): string {
        if (!/^[a-z][a-z0-9_]{0,15}$/.test(id)) fail('invalid id');
        if (this.jobs.has(id)) fail('duplicate job');
        return id;
    }
    private job(id: string): Job {
        const job = this.jobs.get(id);
        if (job === undefined) fail('unknown job');
        return job;
    }
    private ordered(enabled = false): Job[] {
        return [...this.jobs.values()].filter(job => !enabled || job.enabled).sort((a, b) => ascii(a.id, b.id));
    }
    parse(line: string): Command {
        const words = line.trim().split(/ +/), kind = words[0];
        if (!isCommandName(kind)) fail('unknown command');
        const expected = arities[kind];
        if (expected < 0 ? words.length < -expected : words.length !== expected) fail('wrong arguments');
        switch (kind) {
            case 'JOB': {
                const id = this.newId(words[1]), cron = new Cron(words.slice(2));
                return { kind, id, cron };
            }
            case 'VALIDATE': return { kind, cron: new Cron(words.slice(1)) };
            case 'REMOVE': case 'ENABLE': case 'DISABLE': case 'DESCRIBE': return { kind, job: this.job(words[1]) };
            case 'RENAME': {
                const job = this.job(words[1]), id = this.newId(words[2]);
                return { kind, job, id };
            }
            case 'RUNTIME': {
                const job = this.job(words[1]), duration = positive(words[2], 4, 1440, 'invalid duration'), policy = words[3];
                if (policy !== 'ALLOW' && policy !== 'FORBID' && policy !== 'REPLACE') fail('invalid policy');
                return { kind, job, duration, policy };
            }
            case 'LIST': case 'HOLIDAYS': return { kind };
            case 'EXPAND': {
                const job = this.job(words[1]), field = fieldIndices.find(index => fieldNames[index] === words[2]);
                if (field === undefined) fail('invalid field');
                return { kind, job, field };
            }
            case 'MATCH': case 'GAP': {
                const job = this.job(words[1]), base = parseDatetime(words, 2);
                return { kind, job, base };
            }
            case 'NEXT': case 'PREV': {
                const job = this.job(words[1]), base = parseDatetime(words, 2), count = positive(words[4], 2, 50, 'invalid count');
                return { kind, job, base, count };
            }
            case 'COUNT': {
                const job = this.job(words[1]), window = parseWindow(words, 2);
                return { kind, job, window };
            }
            case 'OVERLAP': {
                const first = this.job(words[1]), second = this.job(words[2]), window = parseWindow(words, 3);
                return { kind, first, second, window };
            }
            case 'TIMELINE': case 'CONFLICTS': case 'SIMULATE': return { kind, window: parseWindow(words, 1) };
            case 'WEEK': return { kind, day: parseDate(words[1]), original: words[1] };
            case 'CALENDAR': {
                const job = this.job(words[1]), month = parseMonth(words[2]);
                return { kind, job, month, original: words[2] };
            }
            case 'EXCLUDE': case 'INCLUDE': return { kind, day: parseDate(words[1]) };
        }
    }
    private fires(job: Job, low: number, high: number, reverse = false): Generator<number> {
        return job.cron.fires(low, high, this.holidays, reverse);
    }
    private grouped(window: Window): [number, string[]][] {
        const groups = new Map<number, string[]>();
        for (const job of this.ordered(true)) for (const minute of this.fires(job, window.low, window.high)) {
            const ids = groups.get(minute);
            if (ids === undefined) groups.set(minute, [job.id]); else ids.push(job.id);
        }
        return [...groups].sort((a, b) => a[0] - b[0]);
    }
    private simulate(window: Window): string[] {
        const jobs = this.ordered(true), events = new Map<number, number>(), rows: string[] = [];
        const event = (minute: number, difference: number): void => { events.set(minute, (events.get(minute) ?? 0) + difference); };
        for (const job of jobs) {
            let lastEnd: number | null = null, started = 0, skipped = 0, replaced = 0, busy = 0;
            for (const minute of this.fires(job, window.low, window.high)) {
                if (lastEnd !== null && lastEnd > minute) {
                    if (job.policy === 'FORBID') { ++skipped; continue; }
                    if (job.policy === 'REPLACE') {
                        event(lastEnd, 1); event(minute, -1);
                        busy -= lastEnd - minute;
                        ++replaced;
                    }
                }
                lastEnd = minute + job.duration;
                event(minute, 1); event(lastEnd, -1);
                busy += job.duration;
                ++started;
            }
            rows.push(`${job.id} ${job.policy} started ${started} skipped ${skipped} replaced ${replaced} busy ${busy}`);
        }
        let running = 0, peak = 0, earliest: number | null = null;
        for (const [minute, difference] of [...events].sort((a, b) => a[0] - b[0])) {
            running += difference;
            if (running > peak) { peak = running; earliest = minute; }
        }
        return [`SIMULATE ${jobs.length} peak ${peak}${earliest === null ? '' : ` at ${datetimeNotation(earliest)}`}`, ...rows];
    }
    private week(first: number, text: string): string[] {
        const jobs = this.ordered(true), rows: string[] = [];
        let total = 0;
        for (let day = first; day < first + 7; ++day) {
            const hours = Array<number>(24).fill(0), date = civil(day);
            if (!this.holidays.has(day)) for (const job of jobs) if (job.cron.scheduled(date)) {
                for (const hour of job.cron.fields[1].values) hours[hour] += job.cron.fields[0].values.length;
            }
            const count = hours.reduce((a, b) => a + b, 0);
            total += count;
            rows.push(`${dateNotation(day)} ${hours.map(value => value === 0 ? '.' : value < 10 ? String(value) : '+').join('')} ${count}`);
        }
        return [`WEEK ${text} ${total}`, ...rows];
    }
    private calendar(job: Job, date: YearMonth, text: string): string[] {
        const first = dayNumber(date.year, date.month, 1), length = monthLength(date.year, date.month);
        const cells = Array<string>((first + 6) % 7).fill('...');
        let active = 0;
        for (let day = 1; day <= length; ++day) {
            const number = first + day - 1;
            const mark = !job.cron.scheduled(civil(number)) ? '-' : this.holidays.has(number) ? 'x' : '*';
            if (mark === '*') ++active;
            cells.push(`${pad(day)}${mark}`);
        }
        while (cells.length % 7) cells.push('...');
        const rows = [`CALENDAR ${job.id} ${text} days ${active} runs ${active * job.cron.times.length}`, 'Sun Mon Tue Wed Thu Fri Sat'];
        for (let index = 0; index < cells.length; index += 7) rows.push(cells.slice(index, index + 7).join(' '));
        return rows;
    }
    private gap(job: Job, base: number): string[] {
        const times = [...this.fires(job, base, base + 44640)];
        if (times.length < 2) return [`GAP ${job.id} runs ${times.length} none`];
        const counts = new Map<number, number>();
        let shortest = times[1] - times[0], longest = shortest, from = 0;
        for (let index = 1; index < times.length; ++index) {
            const gap = times[index] - times[index - 1];
            counts.set(gap, (counts.get(gap) ?? 0) + 1);
            shortest = Math.min(shortest, gap);
            if (gap > longest) { longest = gap; from = index - 1; }
        }
        return [`GAP ${job.id} runs ${times.length} shortest ${spanText(shortest)} longest ${spanText(longest)} from ${datetimeNotation(times[from])} to ${datetimeNotation(times[from + 1])}`,
            ...[...counts].sort((a, b) => a[0] - b[0]).map(([gap, count]) => `${spanText(gap)} ${count}`)];
    }
    execute(command: Command): string[] {
        switch (command.kind) {
            case 'JOB': {
                this.jobs.set(command.id, new Job(command.id, command.cron));
                return [`JOB ${command.id} added`];
            }
            case 'VALIDATE': return [`VALID ${command.cron.expanded} ${command.cron.or ? 'OR' : 'AND'} ${command.cron.times.length}`];
            case 'REMOVE': {
                this.jobs.delete(command.job.id);
                return [`REMOVE ${command.job.id}`];
            }
            case 'RENAME': {
                const { job, id } = command, previous = job.id;
                this.jobs.delete(previous); job.id = id; this.jobs.set(id, job);
                return [`RENAME ${previous} ${id}`];
            }
            case 'ENABLE': case 'DISABLE': {
                const job = command.job, enabled = command.kind === 'ENABLE';
                if (job.enabled === enabled) fail(enabled ? 'already enabled' : 'already disabled');
                job.enabled = enabled;
                return [`${command.kind} ${job.id}`];
            }
            case 'RUNTIME': {
                const { job, duration, policy } = command;
                job.duration = duration; job.policy = policy;
                return [`RUNTIME ${job.id} ${duration} ${policy}`];
            }
            case 'LIST': return [`LIST ${this.jobs.size}`, ...this.ordered().map(job => `${job.id} ${job.enabled ? 'on' : 'off'} ${job.duration} ${job.policy} ${job.cron.text}`)];
            case 'EXPAND': {
                const { job, field: index } = command, field = job.cron.fields[index];
                return [[`EXPAND ${job.id} ${fieldNames[index]} ${field.values.length}`, ...field.values, ...field.specials.map(canonical)].join(' ')];
            }
            case 'DESCRIBE': return [`DESCRIBE ${command.job.id} ${description(command.job.cron)}`];
            case 'MATCH': {
                const { job, base } = command, reasons = job.cron.reasons(base, this.holidays);
                return [`MATCH ${job.id} ${datetimeNotation(base)} ${reasons.length ? 'no ' + reasons.join(' ') : 'yes'}`];
            }
            case 'NEXT': case 'PREV': {
                const { job, base, count } = command, reverse = command.kind === 'PREV', times: number[] = [];
                const low = reverse ? base - 527040 : base + 1, high = reverse ? base - 1 : base + 527040;
                for (const minute of this.fires(job, low, high, reverse)) {
                    times.push(minute);
                    if (times.length === count) break;
                }
                const rows = [`${command.kind} ${job.id} ${times.length}`, ...times.map(minute => `${datetimeNotation(minute)} ${reverse ? '-' : '+'}${spanText(Math.abs(minute - base))}`)];
                if (times.length < count) rows.push('NONE');
                return rows;
            }
            case 'COUNT': {
                const { job, window } = command, days = new Set<number>();
                let runs = 0;
                for (const minute of this.fires(job, window.low, window.high)) { ++runs; days.add(Math.floor(minute / 1440)); }
                return [`COUNT ${job.id} runs ${runs} days ${days.size}`];
            }
            case 'GAP': return this.gap(command.job, command.base);
            case 'OVERLAP': {
                const { first, second, window } = command, other = new Set(this.fires(second, window.low, window.high));
                const shared = [...this.fires(first, window.low, window.high)].filter(minute => other.has(minute));
                const detail = shared.length ? ` first ${datetimeNotation(shared[0])} last ${datetimeNotation(shared[shared.length - 1])}` : '';
                return [`OVERLAP ${first.id} ${second.id} ${shared.length}${detail}`];
            }
            case 'TIMELINE': {
                const groups = this.grouped(command.window), count = groups.reduce((value, [, ids]) => value + ids.length, 0), rows = [`TIMELINE ${count}`];
                let shown = 0;
                for (const [minute, ids] of groups) {
                    if (shown === 100) break;
                    for (const id of ids) {
                        rows.push(`${datetimeNotation(minute)} ${id}`);
                        if (++shown === 100) break;
                    }
                }
                if (count > 100) rows.push(`... ${count - 100} more`);
                return rows;
            }
            case 'CONFLICTS': {
                const groups = this.grouped(command.window).filter(([, ids]) => ids.length >= 2);
                const peak = groups.reduce((value, [, ids]) => Math.max(value, ids.length), 0);
                const rows = [`CONFLICTS ${groups.length} peak ${peak}`, ...groups.slice(0, 100).map(([minute, ids]) => `${datetimeNotation(minute)} ${ids.length} ${ids.join(' ')}`)];
                if (groups.length > 100) rows.push(`... ${groups.length - 100} more`);
                return rows;
            }
            case 'WEEK': return this.week(command.day, command.original);
            case 'CALENDAR': return this.calendar(command.job, command.month, command.original);
            case 'SIMULATE': return this.simulate(command.window);
            case 'EXCLUDE': case 'INCLUDE': {
                const day = command.day, exclude = command.kind === 'EXCLUDE';
                if (this.holidays.has(day) === exclude) fail(exclude ? 'already excluded' : 'not excluded');
                if (exclude) this.holidays.add(day); else this.holidays.delete(day);
                return [`${command.kind} ${dateNotation(day)} holidays ${this.holidays.size}`];
            }
            case 'HOLIDAYS': return [`HOLIDAYS ${this.holidays.size}`, ...[...this.holidays].sort((a, b) => a - b).map(dateNotation)];
        }
    }
}

const input = readFileSync(0, 'utf8').split('\n'), scheduler = new Scheduler();
for (let index = 1; index <= Number(input[0]); ++index) {
    try { process.stdout.write(scheduler.execute(scheduler.parse(input[index])).join('\n') + '\n'); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`ERROR ${error.message}\n`);
    }
}
