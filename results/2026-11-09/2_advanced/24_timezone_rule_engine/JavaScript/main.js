'use strict';

const fs = require('node:fs');
const parser = require('./tz_parser');
const { daysInMonth, dayNumber, timeValue, splitTime } = require('./day_rules');
const { expandInstances, adj, processInstances, abbreviation } = require('./transitions');
const { periodIndex, periodRange, resolveLocal } = require('./resolver');
const report = require('./report');
const readLines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
const compareText = (a, b) => a < b ? -1 : a > b ? 1 : 0;

function classifyLines(texts) {
    const lines = [];
    const blocks = [];
    let previous = null;
    for (let index = 0; index < texts.length; index++) {
        const parsed = parser.extractLine(texts[index]);
        if (parsed === null) continue;
        const kind = parsed.continuation ? 'continuation' : ['Rule', 'Zone', 'Link'].includes(parsed.fields[0]) ? parsed.fields[0] : 'unknown';
        const line = { ...parsed, number: index + 1, kind, block: null };
        if (kind === 'Zone') {
            line.block = { name: line.fields[1], lines: [line] };
            blocks.push(line.block);
        } else if (kind === 'continuation' && previous !== null && previous.block !== null
            && ((previous.kind === 'Zone' && previous.fields.length >= 6)
                || (previous.kind === 'continuation' && previous.fields.length >= 4))) {
            line.block = previous.block;
            line.block.lines.push(line);
        }
        lines.push(line);
        previous = line;
    }
    return { lines, blocks };
}

function checkRule(line) {
    const f = line.fields;
    const from = parser.year(f[2]);
    if (from === null) return 'bad year';
    const to = parser.toYear(f[3], from);
    if (to === null) return 'bad year';
    if (f[4] !== '-') return 'syntax error';
    const month = parser.month(f[5]);
    if (month === null) return 'bad month';
    const day = parser.daySpec(f[6], month);
    if (day === null) return 'bad day spec';
    const at = parser.time(f[7]);
    if (at === null) return 'bad time';
    const save = parser.save(f[8]);
    if (save === null) return 'bad save';
    const letter = parser.letter(f[9]);
    if (letter === null) return 'bad letter';
    line.rule = { number: line.number, name: f[1], from, to, month, day, at, save, letter, raw: f };
    return null;
}

function checkZoneLine(line) {
    const f = line.fields.slice(line.kind === 'Zone' ? 2 : 0);
    const stdOffset = parser.offset(f[0]);
    if (stdOffset === null) return 'bad offset';
    let rules;
    if (f[1] === '-') rules = { kind: 'none', save: 0 };
    else if (/^[0-9]/.test(f[1])) {
        const save = parser.save(f[1]);
        if (save === null) return 'bad save';
        rules = { kind: 'fixed', save };
    } else rules = { kind: 'named', name: f[1] };
    if (!parser.validFormat(f[2], rules.kind === 'named')) return 'bad format';
    const until = parser.until(f.slice(3));
    if (until.error) return until.error;
    line.zoneLine = { number: line.number, stdOffset, rules, format: f[2], until: until.value };
    return null;
}

function fieldError(line) {
    const count = line.fields.length;
    if (line.kind === 'unknown' || (line.kind === 'continuation' && line.block === null)) return 'syntax error';
    if (line.kind === 'Rule') return count !== 10 ? 'syntax error' : checkRule(line);
    if (line.kind === 'Zone') return count < 5 || count > 9 ? 'syntax error' : checkZoneLine(line);
    if (line.kind === 'continuation') return count < 3 || count > 7 ? 'syntax error' : checkZoneLine(line);
    return count === 3 ? null : 'syntax error';
}

function readDatabase() {
    const database = classifyLines(readLines('tzdata.txt'));
    const { lines, blocks } = database;
    const ruleSets = new Map();
    for (const line of lines) {
        line.fieldError = fieldError(line);
        line.error = line.fieldError;
        if (line.kind === 'Rule' && line.error === null) {
            if (!ruleSets.has(line.rule.name)) ruleSets.set(line.rule.name, { name: line.rule.name, rules: [] });
            ruleSets.get(line.rule.name).rules.push(line.rule);
        }
    }
    const zoneNames = new Set();
    for (const line of lines) {
        if (line.fieldError !== null || (line.kind !== 'Zone' && line.kind !== 'continuation')) continue;
        if (line.kind === 'Zone') {
            const duplicate = zoneNames.has(line.fields[1]);
            zoneNames.add(line.fields[1]);
            if (duplicate) { line.error = 'duplicate zone ' + line.fields[1]; continue; }
        }
        const data = line.zoneLine;
        if (data.rules.kind === 'named' && !ruleSets.has(data.rules.name)) {
            line.error = 'unknown rule ' + data.rules.name;
            continue;
        }
        if (line.kind === 'continuation' && data.until !== null) {
            const previous = line.block.lines[line.block.lines.indexOf(line) - 1];
            if (previous.fieldError === null && data.until.nominal <= previous.zoneLine.until.nominal) {
                line.error = 'until not increasing';
                continue;
            }
        }
        if (data.until !== null && line.block.lines.at(-1) === line) line.error = 'missing continuation';
    }
    const zones = [];
    for (const block of blocks) {
        block.defined = block.lines.every(line => line.error === null);
        if (block.defined) zones.push({ name: block.name, lines: block.lines.map(line => line.zoneLine), aliases: [] });
    }
    const byName = new Map(zones.map(zone => [zone.name, zone]));
    const registry = new Map(byName);
    const aliases = new Set();
    for (const line of lines) {
        if (line.kind !== 'Link' || line.fieldError !== null) continue;
        const [, target, alias] = line.fields;
        if (!byName.has(target)) line.error = 'unknown link target ' + target;
        else if (byName.has(alias) || aliases.has(alias)) line.error = 'duplicate link ' + alias;
        else {
            aliases.add(alias);
            registry.set(alias, byName.get(target));
            byName.get(target).aliases.push(alias);
        }
    }
    for (const set of ruleSets.values()) set.instances = expandInstances(set.rules);
    return { ...database, ruleSets, zones, registry };
}

function buildPeriods(zone, ruleSets) {
    zone.periods = [];
    zone.applied = new Map();
    let start = -Infinity;
    for (const line of zone.lines) {
        line.start = start;
        const switches = [];
        if (line.rules.kind !== 'named') {
            const save = line.rules.save;
            line.end = line.until === null ? Infinity : line.until.nominal - adj(line.until.time.type, line.stdOffset, save);
            switches.push({ time: start, save, letter: '' });
        } else {
            const instances = ruleSets.get(line.rules.name).instances;
            const processed = processInstances(instances, line.stdOffset, start, line.until);
            const initial = processed.preStart;
            const startingSave = initial === null ? 0 : initial.save;
            const startingLetter = initial === null ? (instances.find(instance => instance.save === 0)?.letter ?? '') : initial.letter;
            switches.push({ time: start, save: startingSave, letter: startingLetter });
            for (const { time, instance } of processed.applied) {
                switches.push({ time, save: instance.save, letter: instance.letter });
                zone.applied.set(instance.rule.number, (zone.applied.get(instance.rule.number) ?? 0) + 1);
            }
            line.end = processed.end;
        }
        for (const item of switches) {
            const period = { start: item.time, offset: line.stdOffset + item.save, dst: item.save !== 0,
                abbreviation: abbreviation(line.format, item.save, item.letter) };
            const previous = zone.periods.at(-1);
            if (previous && previous.offset === period.offset && previous.dst === period.dst
                && previous.abbreviation === period.abbreviation) continue;
            zone.periods.push(period);
        }
        start = line.end;
    }
    zone.transitions = zone.periods.slice(1).map((after, index) => ({ time: after.start, before: zone.periods[index], after }));
}

function queryValue(text, kind) {
    const parts = text.match(/[0-9]+/g).map(Number);
    const [year, month, day, hour, minute, second] = parts;
    if (year < 1800 || year > 2099) return null;
    if (kind === 'year') return year;
    if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
    if (kind === 'date') return dayNumber(year, month, day);
    if (hour > 23 || minute > 59 || second > 59) return null;
    return timeValue(year, month, day, hour, minute, second);
}

function readSettings() {
    const rows = readLines('params.txt').map(line => line.split(' '));
    const workTime = text => { const [hour, minute] = text.split(':').map(Number); return hour * 3600 + minute * 60; };
    return { reference: queryValue(rows[0][1], 'utc'), workStart: workTime(rows[1][1]), workEnd: workTime(rows[1][2]) };
}

function checkQuery(text, registry) {
    const words = text.split(' ');
    const command = words[0];
    const tokens = words.slice(1);
    let choice = null;
    if ((command === 'TOUTC' || command === 'CONVERT') && ['EARLIER', 'LATER'].includes(tokens.at(-1))) choice = tokens.pop();
    const forms = { TOUTC: ['zone', 'local'], TOLOCAL: ['zone', 'utc'], CONVERT: ['zone', 'zone', 'local'],
        OFFSET: ['zone', 'utc'], TRANSITIONS: ['zone', 'year', 'year'], DURATION: ['zone', 'local', 'local'] };
    const kinds = command === 'MEETING' ? ['date', ...tokens.slice(1).map(() => 'zone')] : forms[command];
    const args = [];
    for (let index = 0; index < tokens.length; index++) {
        if (kinds[index] === 'zone') {
            if (!registry.has(tokens[index])) return { error: 'ERROR unknown zone ' + tokens[index] };
            args.push(registry.get(tokens[index]));
        } else {
            const value = queryValue(tokens[index], kinds[index]);
            if (value === null) return { error: 'ERROR invalid value ' + tokens[index] };
            args.push(value);
        }
    }
    if (command === 'TRANSITIONS' && args[1] > args[2]) return { error: 'ERROR invalid range' };
    return { command, tokens, args, choice };
}

function selectLocal(zone, value, choice) {
    const resolved = resolveLocal(zone, value);
    if (resolved.candidates.length === 0) {
        const gap = resolved.gap;
        return { error: `NONEXISTENT gap ${report.localTime(gap.time + gap.before.offset)}`
            + ` to ${report.localTime(gap.time + gap.after.offset)} at ${report.utc(gap.time)}` };
    }
    if (resolved.candidates.length === 1) return resolved.candidates[0];
    if (choice !== null) return resolved.candidates[choice === 'EARLIER' ? 0 : 1];
    return { error: 'AMBIGUOUS ' + resolved.candidates.map(item => `${report.utc(item.time)} (${report.state(item.period)})`).join(' or ') };
}

function shifts(transitions) {
    let gaps = 0;
    let overlaps = 0;
    let unchanged = 0;
    for (const item of transitions) {
        const difference = item.after.offset - item.before.offset;
        if (difference > 0) gaps++;
        else if (difference < 0) overlaps++;
        else unchanged++;
    }
    return `gaps ${gaps}, overlaps ${overlaps}, no shift ${unchanged}`;
}

function transitionLine(item) {
    const difference = item.after.offset - item.before.offset;
    const kind = difference > 0 ? 'gap ' + report.duration(difference) : difference < 0 ? 'overlap ' + report.duration(-difference) : 'no shift';
    return `${report.change(item)} (local ${report.localTime(item.time + item.before.offset)}`
        + ` -> ${report.localTime(item.time + item.after.offset)}, ${kind})`;
}

function mergeIntervals(intervals) {
    const result = [];
    for (const interval of intervals.sort((a, b) => a.start - b.start || a.end - b.end)) {
        const last = result.at(-1);
        if (last && interval.start <= last.end) last.end = Math.max(last.end, interval.end);
        else result.push({ ...interval });
    }
    return result;
}

function intersectIntervals(first, second) {
    const result = [];
    let a = 0;
    let b = 0;
    while (a < first.length && b < second.length) {
        const start = Math.max(first[a].start, second[b].start);
        const end = Math.min(first[a].end, second[b].end);
        if (start < end) result.push({ start, end });
        if (first[a].end < second[b].end) a++;
        else b++;
    }
    return mergeIntervals(result);
}

function workingHours(zone, day, settings) {
    const intervals = [];
    for (let index = 0; index < zone.periods.length; index++) {
        const offset = zone.periods[index].offset;
        const range = periodRange(zone.periods, index);
        const start = Math.max(range.start, day * 86400 + settings.workStart - offset);
        const end = Math.min(range.end, day * 86400 + settings.workEnd - offset);
        if (start < end) intervals.push({ start, end });
    }
    return mergeIntervals(intervals);
}

function meeting(query, settings) {
    const zones = query.args.slice(1);
    let intervals = workingHours(zones[0], query.args[0], settings);
    for (let index = 1; index < zones.length; index++) intervals = intersectIntervals(intervals, workingHours(zones[index], query.args[0], settings));
    if (intervals.length === 0) return 'NONE';
    return intervals.map(({ start, end }) => {
        const locals = zones.map((zone, index) => {
            const period = zone.periods[periodIndex(zone.periods, start)];
            return `${query.tokens[index + 1]} ${report.localTime(start + period.offset)} ${period.abbreviation}`;
        });
        return `${report.utc(start)} to ${report.utc(end)} (${report.duration(end - start)}) [${locals.join(', ')}]`;
    }).join('; ');
}

function processQuery(text, database, settings, transitionBlocks) {
    const query = checkQuery(text, database.registry);
    if (query.error) return query.error;
    const { command, args } = query;
    const zone = args[0];
    if (command === 'TOUTC' || command === 'CONVERT') {
        const local = args[command === 'TOUTC' ? 1 : 2];
        const selected = selectLocal(zone, local, query.choice);
        if (selected.error) return selected.error;
        if (command === 'TOUTC') return `${report.utc(selected.time)} (${report.state(selected.period)})`;
        const destination = args[1].periods[periodIndex(args[1].periods, selected.time)];
        const converted = selected.time + destination.offset;
        const shift = Math.floor(converted / 86400) - Math.floor(local / 86400);
        return `${report.localTime(converted)} (${report.state(destination)}) at ${report.utc(selected.time)}, day shift ${shift > 0 ? '+' : ''}${shift}`;
    }
    if (command === 'TOLOCAL') {
        const period = zone.periods[periodIndex(zone.periods, args[1])];
        return `${report.localTime(args[1] + period.offset)} (${report.state(period)})`;
    }
    if (command === 'OFFSET') {
        const index = periodIndex(zone.periods, args[1]);
        let text = report.state(zone.periods[index]);
        if (index >= 1) text += ' since ' + report.utc(zone.periods[index].start);
        if (index + 1 < zone.periods.length) text += ' until ' + report.utc(zone.periods[index + 1].start);
        return text;
    }
    if (command === 'TRANSITIONS') {
        const start = timeValue(args[1], 1, 1);
        const end = timeValue(args[2] + 1, 1, 1);
        const selected = zone.transitions.filter(item => item.time >= start && item.time < end);
        transitionBlocks.push([text, ...selected.map(transitionLine), shifts(selected)]);
        return 'transitions: ' + selected.length;
    }
    if (command === 'DURATION') {
        const selected = [];
        for (let index = 1; index <= 2; index++) {
            const resolved = resolveLocal(zone, args[index]);
            if (resolved.candidates.length !== 1) return (resolved.candidates.length === 0 ? 'NONEXISTENT ' : 'AMBIGUOUS ') + query.tokens[index];
            selected.push(resolved.candidates[0]);
        }
        const elapsed = selected[1].time - selected[0].time;
        const wallClock = args[2] - args[1];
        const difference = selected[1].period.offset - selected[0].period.offset;
        return `${elapsed} s (${report.duration(elapsed)}), wall clock ${report.duration(wallClock)}, offset change ${report.offset(difference)}`;
    }
    return meeting(query, settings);
}

function databaseSummary(database) {
    const { lines, blocks, zones, ruleSets } = database;
    const rules = lines.filter(line => line.kind === 'Rule');
    const links = lines.filter(line => line.kind === 'Link');
    const validRules = rules.filter(line => line.error === null).length;
    const validLinks = links.filter(line => line.error === null).length;
    const usage = new Map();
    for (const set of ruleSets.values()) usage.set(set.name, []);
    for (const zone of zones) {
        const names = new Set(zone.lines.filter(line => line.rules.kind === 'named').map(line => line.rules.name));
        for (const name of names) usage.get(name).push(zone.name);
    }
    const unused = [...usage].filter(([, names]) => names.length === 0).map(([name]) => name);
    const invalid = blocks.filter(block => !block.defined).map(block => `${block.name} (line ${block.lines[0].number})`);
    const body = [`rule lines: ${validRules} valid, ${rules.length - validRules} invalid`,
        `zones: ${zones.length} defined, ${blocks.length - zones.length} invalid`,
        `zone lines: ${zones.reduce((sum, zone) => sum + zone.lines.length, 0)} in defined zones`,
        `links: ${validLinks} defined, ${links.length - validLinks} invalid`,
        `errors: ${lines.filter(line => line.error !== null).length}`,
        'unused rules: ' + (unused.length ? unused.join(' ') : 'none'),
        'invalid zones: ' + (invalid.length ? invalid.join(', ') : 'none')];
    for (const set of ruleSets.values()) {
        const from = Math.min(...set.rules.map(rule => rule.from));
        const to = set.rules.some(rule => rule.raw[3] === 'max') ? 'max' : Math.max(...set.rules.map(rule => rule.to));
        body.push(`rule set ${set.name}: lines ${set.rules.length}, years ${from}-${to}, zones ${usage.get(set.name).length}`);
    }
    return ['DATABASE', ...body.map(line => '  ' + line)];
}

function lineSummary(line, index, transitions) {
    const rules = line.rules.kind === 'none' ? '-' : line.rules.kind === 'fixed' ? report.clock(line.rules.save) : line.rules.name;
    let text = `line ${index + 1}: ${report.offset(line.stdOffset)} ${rules} ${line.format}`;
    if (index >= 1) text += ' from ' + report.utc(line.start);
    if (line.until !== null) {
        const until = line.until;
        text += ` until ${until.rawYear} ${until.monthName} ${until.dayText} ${report.clock(until.time.value)}${until.time.type} = ${report.utc(line.end)}`;
    }
    const count = transitions.filter(item => item.time >= line.start && item.time < line.end).length;
    return text + ', transitions ' + count;
}

function zoneSummary(zone, ruleSets, reference) {
    const lines = ['aliases: ' + (zone.aliases.length ? zone.aliases.join(' ') : 'none')];
    for (let index = 0; index < zone.lines.length; index++) lines.push(lineSummary(zone.lines[index], index, zone.transitions));
    const names = new Set();
    for (const line of zone.lines) {
        if (line.rules.kind !== 'named' || names.has(line.rules.name)) continue;
        names.add(line.rules.name);
        for (const rule of ruleSets.get(line.rules.name).rules) {
            const raw = rule.raw;
            lines.push(`rule ${rule.name} ${raw[2]} ${raw[3]} ${raw[5]} ${raw[6]} ${report.clock(rule.at.value)}${rule.at.type}`
                + ` ${report.clock(rule.save)} ${raw[9]}, applied ${zone.applied.get(rule.number) ?? 0}`);
        }
    }
    let minimum = zone.periods[0].offset;
    let maximum = minimum;
    const states = new Map();
    const dstYears = [];
    for (const period of zone.periods) {
        minimum = Math.min(minimum, period.offset);
        maximum = Math.max(maximum, period.offset);
        const state = report.state(period);
        states.set(state, (states.get(state) ?? 0) + 1);
        if (period.dst) dstYears.push(splitTime(period.start).year);
    }
    lines.push(`offset range: ${report.offset(minimum)} to ${report.offset(maximum)}`);
    for (const [state, count] of states) lines.push(`state ${state}, periods ${count}`);
    const current = zone.periods[periodIndex(zone.periods, reference)];
    const currentLine = zone.lines.findIndex(line => line.start <= reference && reference < line.end) + 1;
    lines.push(`reference: ${report.localTime(reference + current.offset)} (${report.state(current)}), line ${currentLine}`);
    let previous = null;
    let next = null;
    for (const item of zone.transitions) {
        if (item.time <= reference) previous = item;
        else { next = item; break; }
    }
    lines.push('previous transition: ' + (previous === null ? 'none' : report.change(previous)),
        'next transition: ' + (next === null ? 'none' : report.change(next)),
        `transitions: ${zone.transitions.length}, ${shifts(zone.transitions)}`);
    if (dstYears.length === 0) lines.push('dst years: none');
    else {
        let first = dstYears[0];
        let last = first;
        for (const year of dstYears) { first = Math.min(first, year); last = Math.max(last, year); }
        lines.push(`dst years: ${first}-${last}`);
    }
    const year = splitTime(reference).year;
    const yearStart = timeValue(year, 1, 1);
    const yearEnd = timeValue(year + 1, 1, 1);
    const dstIntervals = [];
    for (let index = 0; index < zone.periods.length; index++) {
        if (!zone.periods[index].dst) continue;
        const range = periodRange(zone.periods, index);
        const start = Math.max(yearStart, range.start);
        const end = Math.min(yearEnd, range.end);
        if (start < end) dstIntervals.push({ start, end });
    }
    let dstTotal = 0;
    for (const { start, end } of mergeIntervals(dstIntervals)) {
        dstTotal += end - start;
        lines.push(`dst period: ${report.utc(start)} to ${report.utc(end)} (${report.duration(end - start)})`);
    }
    lines.push(`dst total ${year}: ${report.duration(dstTotal)}`);
    return ['ZONE ' + zone.name, ...lines.map(line => '  ' + line)];
}

function main() {
    const database = readDatabase();
    const settings = readSettings();
    for (const zone of database.zones) buildPeriods(zone, database.ruleSets);
    const transitionBlocks = [];
    const answers = readLines('queries.txt').map(text => text + ' => ' + processQuery(text, database, settings, transitionBlocks));
    const summaries = [databaseSummary(database)];
    for (const zone of database.zones.slice().sort((a, b) => compareText(a.name, b.name))) {
        summaries.push(zoneSummary(zone, database.ruleSets, settings.reference));
    }
    const errors = database.lines.filter(line => line.error !== null).map(line => `line ${line.number}: ${line.error}`);
    fs.mkdirSync('output', { recursive: true });
    report.writeLines('answers.txt', answers);
    report.writeBlocks('transitions.txt', transitionBlocks);
    report.writeBlocks('zone_summary.txt', summaries);
    report.writeLines('errors.txt', errors);
}

if (require.main === module) main();
