'use strict';

const fs = require('node:fs');
const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const fieldNames = ['minute', 'hour', 'day-of-month', 'month', 'day-of-week'];
const limits = [[0, 59], [0, 23], [1, 31], [1, 12], [0, 7]];
const macros = new Map([
    ['@yearly', '0 0 1 1 *'], ['@annually', '0 0 1 1 *'], ['@monthly', '0 0 1 * *'],
    ['@weekly', '0 0 * * 0'], ['@daily', '0 0 * * *'], ['@midnight', '0 0 * * *'], ['@hourly', '0 * * * *'],
]);
class CommandError extends Error {}
const fail = reason => { throw new CommandError(reason); };
const pad = value => String(value).padStart(2, '0');
const ascii = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const leap = year => year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
const monthLength = (year, month) => month === 2 && leap(year) ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
const leapCount = year => Math.floor(year / 4) - Math.floor(year / 100) + Math.floor(year / 400);
const yearStart = year => 365 * (year - 2000) + leapCount(year - 1) - leapCount(1999);
function dayNumber(year, month, day) {
    let value = yearStart(year) + day - 1;
    for (let index = 1; index < month; ++index) value += monthLength(year, index);
    return value;
}
function civil(day) {
    let year = 2000 + Math.floor(day / 366);
    while (yearStart(year + 1) <= day) ++year;
    let remaining = day - yearStart(year), month = 1;
    while (remaining >= monthLength(year, month)) remaining -= monthLength(year, month++);
    return { number: day, year, month, day: remaining + 1, weekday: (day + 6) % 7, length: monthLength(year, month) };
}
const dateText = date => `${date.year}-${pad(date.month)}-${pad(date.day)}`;
const timeText = minute => `${pad(Math.floor(minute / 60))}:${pad(minute % 60)}`;
function dateNotation(day) { const date = civil(day); return `${dateText(date)} ${weekdays[date.weekday].slice(0, 3)}`; }
function datetimeNotation(minute) {
    const date = civil(Math.floor(minute / 1440));
    return `${dateText(date)} ${timeText(minute % 1440)} ${weekdays[date.weekday].slice(0, 3)}`;
}
const spanText = minutes => `${Math.floor(minutes / 1440)}d${pad(Math.floor(minutes % 1440 / 60))}h${pad(minutes % 60)}m`;
function parseDate(text, reason = 'invalid date') {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) fail(reason);
    const [year, month, day] = text.split('-').map(Number);
    if (year < 2001 || year > 2098 || month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) fail(reason);
    return dayNumber(year, month, day);
}
function parseDatetime(date, time) {
    const day = parseDate(date, 'invalid datetime');
    if (!/^\d{2}:\d{2}$/.test(time)) fail('invalid datetime');
    const [hour, minute] = time.split(':').map(Number);
    if (hour > 23 || minute > 59) fail('invalid datetime');
    return 1440 * day + 60 * hour + minute;
}
function parseMonth(text) {
    if (!/^\d{4}-\d{2}$/.test(text)) fail('invalid month');
    const [year, month] = text.split('-').map(Number);
    if (year < 2001 || year > 2098 || month < 1 || month > 12) fail('invalid month');
    return { year, month };
}
function boundedNumber(text, digits, maximum, reason) {
    if (!/^[1-9]\d*$/.test(text) || text.length > digits || Number(text) > maximum) fail(reason);
    return Number(text);
}
function natural(text, minimum, maximum, error) {
    if (!/^\d{1,2}$/.test(text)) error('invalid value');
    const value = Number(text);
    if (value < minimum || value > maximum) error('out of range');
    return value;
}
class Field {
    constructor(text, index) {
        this.index = index;
        this.unrestricted = text.startsWith('*');
        this.set = new Set();
        this.specials = [];
        const [minimum, maximum] = limits[index];
        const error = reason => fail(`${fieldNames[index]} ${reason}`);
        const value = text => {
            const names = index === 3 ? months : index === 4 ? weekdays : [];
            const named = names.findIndex(name => name.slice(0, 3).toUpperCase() === text);
            return named >= 0 ? named + (index === 3 ? 1 : 0) : natural(text, minimum, maximum, error);
        };
        const special = (kind, canonical, number = 0, weekday = 0) => {
            if (!this.specials.some(item => item.canonical === canonical)) this.specials.push({ kind, canonical, number, weekday });
        };
        for (const item of text.split(',')) {
            if (item === '') error('empty item');
            if (index === 2 && (item.startsWith('L') || item.endsWith('W'))) {
                if (item === 'L') special('last', 'L');
                else if (item === 'LW') special('lastWeekday', 'LW');
                else if (item.startsWith('L-')) {
                    const offset = natural(item.slice(2), 1, 30, error);
                    special('before', `L-${offset}`, offset);
                } else if (item.endsWith('W')) {
                    const day = natural(item.slice(0, -1), 1, 31, error);
                    special('nearest', `${day}W`, day);
                } else error('invalid value');
                continue;
            }
            if (index === 4 && item.includes('#')) {
                const split = item.indexOf('#'), weekday = value(item.slice(0, split)) % 7, part = item.slice(split + 1);
                if (!/^\d$/.test(part)) error('invalid value');
                const number = Number(part);
                if (number < 1 || number > 5) error('out of range');
                special('nth', `${weekday}#${number}`, number, weekday);
                continue;
            }
            if (index === 4 && item.length >= 2 && item.endsWith('L')) {
                const weekday = value(item.slice(0, -1)) % 7;
                special('lastDow', `${weekday}L`, 0, weekday);
                continue;
            }
            const slash = item.indexOf('/'), base = slash < 0 ? item : item.slice(0, slash);
            let first, last, step = 1;
            if (base === '*') { first = minimum; last = maximum; }
            else if (base.includes('-')) {
                const dash = base.indexOf('-');
                first = value(base.slice(0, dash)); last = value(base.slice(dash + 1));
                if (first > last) error('invalid range');
            } else { first = value(base); last = slash < 0 ? first : maximum; }
            if (slash >= 0) {
                const part = item.slice(slash + 1);
                if (!/^\d{1,2}$/.test(part) || Number(part) < 1) error('invalid step');
                step = Number(part);
            }
            for (let number = first; number <= last; number += step) this.set.add(index === 4 ? number % 7 : number);
        }
        this.values = [...this.set].sort((a, b) => a - b);
    }
}
class Cron {
    constructor(tokens) {
        this.text = tokens.join(' ');
        if (tokens.length === 1 && tokens[0].startsWith('@')) {
            const expanded = macros.get(tokens[0]);
            if (expanded === undefined) fail('unknown macro');
            tokens = expanded.split(' ');
        }
        if (tokens.length !== 5) fail('field count');
        this.expanded = tokens.join(' ');
        this.fields = tokens.map((text, index) => new Field(text, index));
        this.or = !this.fields[2].unrestricted && !this.fields[4].unrestricted;
        this.times = this.fields[1].values.flatMap(hour => this.fields[0].values.map(minute => 60 * hour + minute));
    }
    days(date) {
        const dom = this.fields[2], dow = this.fields[4];
        const nearest = day => {
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
            }
        });
        const weekDay = dow.set.has(date.weekday) || dow.specials.some(item => item.weekday === date.weekday &&
            (item.kind === 'nth' ? Math.floor((date.day - 1) / 7) + 1 === item.number : date.day + 7 > date.length));
        return { monthDay, weekDay, matches: this.or ? monthDay || weekDay : monthDay && weekDay };
    }
    scheduled(date) { return this.fields[3].set.has(date.month) && this.days(date).matches; }
    reasons(minute, holidays) {
        const date = civil(Math.floor(minute / 1440)), days = this.days(date), reasons = [];
        if (!this.fields[0].set.has(minute % 60)) reasons.push('minute');
        if (!this.fields[1].set.has(Math.floor(minute % 1440 / 60))) reasons.push('hour');
        if (!days.matches && !days.monthDay) reasons.push('day-of-month');
        if (!this.fields[3].set.has(date.month)) reasons.push('month');
        if (!days.matches && !days.weekDay) reasons.push('day-of-week');
        if (holidays.has(date.number)) reasons.push('excluded');
        return reasons;
    }
    *fires(low, high, holidays, reverse = false) {
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

function list(parts, conjunction = 'and') {
    return parts.length === 1 ? parts[0] : parts.slice(0, -1).join(', ') + ` ${conjunction} ` + parts.at(-1);
}
function valueList(values, index, conjunction = 'and') {
    const label = value => index === 3 ? months[value - 1] : index === 4 ? weekdays[value] : String(value);
    const parts = [];
    for (let first = 0; first < values.length;) {
        let end = first + 1;
        while (end < values.length && values[end] === values[end - 1] + 1) ++end;
        if (end - first >= 3) parts.push(`${label(values[first])} through ${label(values[end - 1])}`);
        else for (let position = first; position < end; ++position) parts.push(label(values[position]));
        first = end;
    }
    return list(parts, conjunction);
}
function stepped(values, maximum) {
    if (values.length < 2 || values[0] !== 0 || values[1] < 2) return null;
    const step = values[1];
    return values.length === Math.floor(maximum / step) + 1 && values.every((value, index) => value === index * step) ? step : null;
}
function description(cron) {
    const [minutes, hours, dom, month, dow] = cron.fields;
    let time;
    if (cron.times.length <= 4) time = 'At ' + list(cron.times.map(timeText));
    else {
        const minuteStep = stepped(minutes.values, 59), hourStep = stepped(hours.values, 23);
        if (minutes.values.length === 60) time = 'Every minute';
        else if (minuteStep !== null) time = `Every ${minuteStep} minutes`;
        else if (minutes.values.length === 1) time = `At minute ${minutes.values[0]}`;
        else time = 'At minutes ' + valueList(minutes.values, 0);
        if (hours.values.length === 24) { if (time.startsWith('At minute')) time += ' of every hour'; }
        else if (hourStep !== null) time += `, every ${hourStep} hours`;
        else if (hours.values.at(-1) - hours.values[0] + 1 === hours.values.length) time += `, between ${pad(hours.values[0])}:00 and ${pad(hours.values.at(-1))}:59`;
        else time += ', during hours ' + valueList(hours.values, 1);
    }
    const domParts = [];
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
    const dowClause = (conjunction = 'and') => {
        const parts = dow.values.length ? [valueList(dow.values, 4, conjunction)] : [];
        for (const item of dow.specials) {
            const ordinal = ['1st', '2nd', '3rd', '4th', '5th'][item.number - 1];
            parts.push(item.kind === 'nth' ? `the ${ordinal} ${weekdays[item.weekday]}` : `the last ${weekdays[item.weekday]}`);
        }
        return list(parts, conjunction) + (dow.specials.length ? ' of the month' : '');
    };
    const domFull = dom.values.length === 31, dowFull = dow.values.length === 7;
    let day = '';
    if (cron.or) {
        if (!domFull && !dowFull) day = `, on ${domClause} or on ${dowClause()}`;
    } else if (!domFull && !dowFull) day = `, on ${domClause} if it is ${dowClause('or')}`;
    else if (!domFull) day = `, on ${domClause}`;
    else if (!dowFull) day = `, on ${dowClause()}`;
    return time + day + (month.values.length === 12 ? '' : ', in ' + valueList(month.values, 3));
}
class Job {
    constructor(id, cron) { this.id = id; this.cron = cron; this.enabled = true; this.duration = 1; this.policy = 'ALLOW'; }
}
const signatures = new Map([
    ['REMOVE', ['job']], ['RENAME', ['job', 'newId']], ['ENABLE', ['job']], ['DISABLE', ['job']],
    ['RUNTIME', ['job', 'duration', 'policy']], ['LIST', []], ['EXPAND', ['job', 'field']], ['DESCRIBE', ['job']],
    ['MATCH', ['job', 'datetime']], ['NEXT', ['job', 'datetime', 'count']], ['PREV', ['job', 'datetime', 'count']],
    ['COUNT', ['job', 'datetime', 'datetime']], ['GAP', ['job', 'datetime']], ['OVERLAP', ['job', 'job', 'datetime', 'datetime']],
    ['TIMELINE', ['datetime', 'datetime']], ['CONFLICTS', ['datetime', 'datetime']], ['WEEK', ['date']],
    ['CALENDAR', ['job', 'month']], ['SIMULATE', ['datetime', 'datetime']], ['EXCLUDE', ['date']], ['INCLUDE', ['date']], ['HOLIDAYS', []],
]);
class Scheduler {
    constructor() { this.jobs = new Map(); this.holidays = new Set(); }
    newId(id) {
        if (!/^[a-z][a-z0-9_]{0,15}$/.test(id)) fail('invalid id');
        if (this.jobs.has(id)) fail('duplicate job');
        return id;
    }
    ordered(enabled = false) { return [...this.jobs.values()].filter(job => !enabled || job.enabled).sort((a, b) => ascii(a.id, b.id)); }
    parseArguments(types, words) {
        let position = 0;
        const arguments_ = [], datetimes = [];
        for (const type of types) {
            const text = words[position++];
            let value;
            switch (type) {
                case 'job': value = this.jobs.get(text); if (value === undefined) fail('unknown job'); break;
                case 'newId': value = this.newId(text); break;
                case 'datetime': value = parseDatetime(text, words[position++]); datetimes.push(value); break;
                case 'date': value = parseDate(text); break;
                case 'month': value = parseMonth(text); break;
                case 'count': value = boundedNumber(text, 2, 50, 'invalid count'); break;
                case 'duration': value = boundedNumber(text, 4, 1440, 'invalid duration'); break;
                case 'policy':
                    if (!['ALLOW', 'FORBID', 'REPLACE'].includes(text)) fail('invalid policy');
                    value = text; break;
                case 'field':
                    value = fieldNames.indexOf(text);
                    if (value < 0) fail('invalid field');
                    break;
            }
            arguments_.push(value);
        }
        if (datetimes.length === 2) {
            if (datetimes[0] > datetimes[1]) fail('invalid window');
            if (datetimes[1] - datetimes[0] > 44640) fail('window too long');
        }
        return arguments_;
    }
    fires(job, low, high, reverse = false) { return job.cron.fires(low, high, this.holidays, reverse); }
    grouped(low, high) {
        const groups = new Map();
        for (const job of this.ordered(true)) for (const minute of this.fires(job, low, high)) {
            if (!groups.has(minute)) groups.set(minute, []);
            groups.get(minute).push(job.id);
        }
        return [...groups].sort((a, b) => a[0] - b[0]);
    }
    simulate(low, high) {
        const jobs = this.ordered(true), events = new Map(), rows = [];
        const event = (minute, difference) => events.set(minute, (events.get(minute) ?? 0) + difference);
        for (const job of jobs) {
            let lastEnd = null, started = 0, skipped = 0, replaced = 0, busy = 0;
            for (const minute of this.fires(job, low, high)) {
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
        let running = 0, peak = 0, earliest = null;
        for (const [minute, difference] of [...events].sort((a, b) => a[0] - b[0])) {
            running += difference;
            if (running > peak) { peak = running; earliest = minute; }
        }
        return [`SIMULATE ${jobs.length} peak ${peak}${peak ? ` at ${datetimeNotation(earliest)}` : ''}`, ...rows];
    }
    week(first, text) {
        const jobs = this.ordered(true), rows = [];
        let total = 0;
        for (let day = first; day < first + 7; ++day) {
            const hours = Array(24).fill(0), date = civil(day);
            if (!this.holidays.has(day)) for (const job of jobs) if (job.cron.scheduled(date)) {
                for (const hour of job.cron.fields[1].values) hours[hour] += job.cron.fields[0].values.length;
            }
            const count = hours.reduce((a, b) => a + b, 0);
            total += count;
            rows.push(`${dateNotation(day)} ${hours.map(value => value === 0 ? '.' : value < 10 ? String(value) : '+').join('')} ${count}`);
        }
        return [`WEEK ${text} ${total}`, ...rows];
    }
    calendar(job, date, text) {
        const first = dayNumber(date.year, date.month, 1), length = monthLength(date.year, date.month);
        const cells = Array((first + 6) % 7).fill('...');
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
    gap(job, base) {
        const times = [...this.fires(job, base, base + 44640)];
        if (times.length < 2) return [`GAP ${job.id} runs ${times.length} none`];
        const counts = new Map();
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
    execute(line) {
        const [command, ...words] = line.trim().split(/ +/);
        if (command !== 'JOB' && command !== 'VALIDATE' && !signatures.has(command)) fail('unknown command');
        if (command === 'JOB' || command === 'VALIDATE') {
            if (words.length < (command === 'JOB' ? 2 : 1)) fail('wrong arguments');
            if (command === 'VALIDATE') {
                const cron = new Cron(words);
                return [`VALID ${cron.expanded} ${cron.or ? 'OR' : 'AND'} ${cron.times.length}`];
            }
            const id = this.newId(words[0]), cron = new Cron(words.slice(1));
            this.jobs.set(id, new Job(id, cron));
            return [`JOB ${id} added`];
        }
        const signature = signatures.get(command), count = signature.reduce((size, type) => size + (type === 'datetime' ? 2 : 1), 0);
        if (words.length !== count) fail('wrong arguments');
        const args = this.parseArguments(signature, words);
        switch (command) {
            case 'REMOVE': {
                const job = args[0]; this.jobs.delete(job.id);
                return [`REMOVE ${job.id}`];
            }
            case 'RENAME': {
                const [job, id] = args, previous = job.id;
                this.jobs.delete(previous); job.id = id; this.jobs.set(id, job);
                return [`RENAME ${previous} ${id}`];
            }
            case 'ENABLE': case 'DISABLE': {
                const job = args[0], enabled = command === 'ENABLE';
                if (job.enabled === enabled) fail(enabled ? 'already enabled' : 'already disabled');
                job.enabled = enabled;
                return [`${command} ${job.id}`];
            }
            case 'RUNTIME': {
                const [job, duration, policy] = args;
                job.duration = duration; job.policy = policy;
                return [`RUNTIME ${job.id} ${duration} ${policy}`];
            }
            case 'LIST': return [`LIST ${this.jobs.size}`, ...this.ordered().map(job => `${job.id} ${job.enabled ? 'on' : 'off'} ${job.duration} ${job.policy} ${job.cron.text}`)];
            case 'EXPAND': {
                const [job, index] = args, field = job.cron.fields[index];
                return [[`EXPAND ${job.id} ${fieldNames[index]} ${field.values.length}`, ...field.values, ...field.specials.map(item => item.canonical)].join(' ')];
            }
            case 'DESCRIBE': return [`DESCRIBE ${args[0].id} ${description(args[0].cron)}`];
            case 'MATCH': {
                const [job, minute] = args, reasons = job.cron.reasons(minute, this.holidays);
                return [`MATCH ${job.id} ${datetimeNotation(minute)} ${reasons.length ? 'no ' + reasons.join(' ') : 'yes'}`];
            }
            case 'NEXT': case 'PREV': {
                const [job, base, count] = args, reverse = command === 'PREV', times = [];
                const low = reverse ? base - 527040 : base + 1, high = reverse ? base - 1 : base + 527040;
                for (const minute of this.fires(job, low, high, reverse)) {
                    times.push(minute);
                    if (times.length === count) break;
                }
                const rows = [`${command} ${job.id} ${times.length}`, ...times.map(minute => `${datetimeNotation(minute)} ${reverse ? '-' : '+'}${spanText(Math.abs(minute - base))}`)];
                if (times.length < count) rows.push('NONE');
                return rows;
            }
            case 'COUNT': {
                const [job, low, high] = args, days = new Set();
                let runs = 0;
                for (const minute of this.fires(job, low, high)) { ++runs; days.add(Math.floor(minute / 1440)); }
                return [`COUNT ${job.id} runs ${runs} days ${days.size}`];
            }
            case 'GAP': return this.gap(...args);
            case 'OVERLAP': {
                const [first, second, low, high] = args, other = new Set(this.fires(second, low, high));
                const shared = [...this.fires(first, low, high)].filter(minute => other.has(minute));
                const detail = shared.length ? ` first ${datetimeNotation(shared[0])} last ${datetimeNotation(shared.at(-1))}` : '';
                return [`OVERLAP ${first.id} ${second.id} ${shared.length}${detail}`];
            }
            case 'TIMELINE': {
                const groups = this.grouped(...args), count = groups.reduce((value, [, ids]) => value + ids.length, 0), rows = [`TIMELINE ${count}`];
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
                const groups = this.grouped(...args).filter(([, ids]) => ids.length >= 2), peak = groups.reduce((value, [, ids]) => Math.max(value, ids.length), 0);
                const rows = [`CONFLICTS ${groups.length} peak ${peak}`, ...groups.slice(0, 100).map(([minute, ids]) => `${datetimeNotation(minute)} ${ids.length} ${ids.join(' ')}`)];
                if (groups.length > 100) rows.push(`... ${groups.length - 100} more`);
                return rows;
            }
            case 'WEEK': return this.week(args[0], words[0]);
            case 'CALENDAR': return this.calendar(args[0], args[1], words[1]);
            case 'SIMULATE': return this.simulate(...args);
            case 'EXCLUDE': case 'INCLUDE': {
                const day = args[0], exclude = command === 'EXCLUDE';
                if (this.holidays.has(day) === exclude) fail(exclude ? 'already excluded' : 'not excluded');
                if (exclude) this.holidays.add(day); else this.holidays.delete(day);
                return [`${command} ${dateNotation(day)} holidays ${this.holidays.size}`];
            }
            case 'HOLIDAYS': return [`HOLIDAYS ${this.holidays.size}`, ...[...this.holidays].sort((a, b) => a - b).map(dateNotation)];
        }
    }
}

const input = fs.readFileSync(0, 'utf8').trimEnd().split(/\r?\n/), scheduler = new Scheduler();
for (let index = 1; index <= Number(input[0]); ++index) {
    try { process.stdout.write(scheduler.execute(input[index]).join('\n') + '\n'); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`ERROR ${error.message}\n`);
    }
}
