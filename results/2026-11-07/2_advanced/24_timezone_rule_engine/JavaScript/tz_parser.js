'use strict';

const { MONTHS, WEEKDAYS, COMMON_DAYS, specifiedDay } = require('./day_rules');

function extractLine(text) {
    const content = text.split('#', 1)[0].replace(/ +$/, '');
    if (content === '') return null;
    return { content, continuation: content[0] === ' ', fields: content.replace(/^ +/, '').split(/ +/) };
}

function hms(text) {
    const match = /^(\d{1,2})(?::(\d{2})(?::(\d{2}))?)?$/.exec(text);
    if (!match) return null;
    const hour = Number(match[1]);
    const minute = Number(match[2] ?? 0);
    const second = Number(match[3] ?? 0);
    return minute > 59 || second > 59 ? null : hour * 3600 + minute * 60 + second;
}

function year(text) {
    if (!/^\d{4}$/.test(text)) return null;
    const value = Number(text);
    return value >= 1800 && value <= 2099 ? value : null;
}

function toYear(text, from) {
    if (text === 'only') return from;
    if (text === 'max') return 2099;
    const value = year(text);
    return value !== null && value >= from ? value : null;
}

function month(text) {
    const value = MONTHS.indexOf(text);
    return value < 0 ? null : value + 1;
}

function daySpec(text, monthNumber) {
    let match;
    if (/^[1-9]\d?$/.test(text)) {
        const day = Number(text);
        return day <= COMMON_DAYS[monthNumber - 1] ? { kind: 'day', day } : null;
    }
    if ((match = /^last([A-Za-z]{3})$/.exec(text))) {
        const day = WEEKDAYS.indexOf(match[1]);
        return day < 0 ? null : { kind: 'last', weekday: day };
    }
    if ((match = /^([A-Za-z]{3})(>=|<=)([1-9]\d?)$/.exec(text))) {
        const weekday = WEEKDAYS.indexOf(match[1]);
        const day = Number(match[3]);
        if (weekday >= 0 && day <= COMMON_DAYS[monthNumber - 1]) return { kind: match[2] === '>=' ? 'ge' : 'le', weekday, day };
    }
    return null;
}

function time(text) {
    const suffix = text.at(-1);
    const type = ['w', 's', 'u'].includes(suffix) ? suffix : 'w';
    const value = hms(type === suffix ? text.slice(0, -1) : text);
    return value === null || value > 86400 ? null : { value, type };
}

function save(text) {
    if (!/^\d{1,2}(?::\d{2})?$/.test(text)) return null;
    const value = hms(text);
    return value !== null && value <= 7200 ? value : null;
}

function offset(text) {
    const negative = text.startsWith('-');
    const value = hms(negative ? text.slice(1) : text);
    return value === null || value >= 57600 ? null : negative ? -value : value;
}

function letter(text) { return text === '-' ? '' : /^[A-Z]{1,5}$/.test(text) ? text : null; }

function validFormat(text, namedRules) {
    if (!/^(?:[A-Za-z0-9+\/-]|%s)+$/.test(text)) return false;
    const substitutions = text.split('%s').length - 1;
    const slashes = text.split('/').length - 1;
    return substitutions <= 1 && slashes <= 1 && !(substitutions && slashes)
        && !(substitutions && !namedRules) && !(slashes && (text.startsWith('/') || text.endsWith('/')));
}

function until(fields) {
    if (fields.length === 0) return { value: null };
    const [rawYear, monthName = 'Jan', dayText = '1', timeText = '0:00'] = fields;
    const y = year(rawYear);
    if (y === null) return { error: 'bad year' };
    const m = month(monthName);
    if (m === null) return { error: 'bad month' };
    const day = daySpec(dayText, m);
    if (day === null) return { error: 'bad day spec' };
    const at = time(timeText);
    if (at === null) return { error: 'bad time' };
    return { value: { year: y, rawYear, month: m, monthName, day, dayText, time: at,
        nominal: specifiedDay(y, m, day) * 86400 + at.value } };
}

module.exports = { extractLine, hms, year, toYear, month, daySpec, time, save, offset, letter, validFormat, until };
