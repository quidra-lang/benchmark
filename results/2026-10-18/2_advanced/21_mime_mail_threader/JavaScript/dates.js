'use strict';

const { removeComments, words } = require('./headers');

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const ZONES = new Map([
    ['ut', 0], ['gmt', 0], ['z', 0], ['est', -300], ['edt', -240],
    ['cst', -360], ['cdt', -300], ['mst', -420], ['mdt', -360], ['pst', -480], ['pdt', -420],
]);

function leap(year) {
    return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function monthDays(year, month) {
    return [31, leap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}

function daysSinceEpoch(year, month, day) {
    let days = day - 1;
    for (let current = 1970; current < year; current++) days += leap(current) ? 366 : 365;
    for (let current = 1; current < month; current++) days += monthDays(year, current);
    return days;
}

function parseDate(text) {
    const failure = error => ({ seconds: null, error });
    const uncommented = removeComments(text);
    if (uncommented === null) return failure('bad Date syntax');
    const tokens = words(uncommented.replace(/,/g, ' , '));
    let weekday = -1;
    if (tokens.length >= 3 && tokens[1] === ',' && WEEKDAYS.includes(tokens[0].toLowerCase())) {
        weekday = WEEKDAYS.indexOf(tokens.shift().toLowerCase());
        tokens.shift();
    }
    if (tokens.length !== 5) return failure('bad Date syntax');
    const [dayText, monthText, yearText, timeText, zoneText] = tokens;
    const month = MONTHS.indexOf(monthText.toLowerCase()) + 1;
    const time = timeText.split(':');
    const numericZone = /^([+-])([0-9]{2})([0-9]{2})$/.exec(zoneText);
    if (!/^[0-9]{1,2}$/.test(dayText) || month === 0 || !/^(?:[0-9]{2}|[0-9]{4})$/.test(yearText)
        || (time.length !== 2 && time.length !== 3) || time.some(piece => !/^[0-9]{2}$/.test(piece))
        || (numericZone === null && !ZONES.has(zoneText.toLowerCase()))) return failure('bad Date syntax');
    const day = Number(dayText);
    let year = Number(yearText);
    if (yearText.length === 2) year += year < 50 ? 2000 : 1900;
    const hour = Number(time[0]);
    const minute = Number(time[1]);
    const second = time.length === 3 ? Number(time[2]) : 0;
    let offset;
    if (numericZone !== null) {
        const zoneHour = Number(numericZone[2]);
        const zoneMinute = Number(numericZone[3]);
        if (zoneHour > 23 || zoneMinute > 59) return failure('Date out of range');
        offset = (zoneHour * 60 + zoneMinute) * (numericZone[1] === '-' ? -1 : 1);
    } else offset = ZONES.get(zoneText.toLowerCase());
    if (year < 1970 || year > 2099 || day < 1 || day > monthDays(year, month)
        || hour > 23 || minute > 59 || second > 59) return failure('Date out of range');
    const days = daysSinceEpoch(year, month, day);
    const seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60;
    if (seconds < 0) return failure('Date out of range');
    if (weekday !== -1 && (days + 3) % 7 !== weekday) return failure('Date weekday mismatch');
    return { seconds, error: null };
}

function formatDate(seconds) {
    let days = Math.floor(seconds / 86400);
    const remainder = seconds % 86400;
    let year = 1970;
    while (days >= (leap(year) ? 366 : 365)) {
        days -= leap(year) ? 366 : 365;
        year++;
    }
    let month = 1;
    while (days >= monthDays(year, month)) {
        days -= monthDays(year, month);
        month++;
    }
    const pad = (value, width = 2) => String(value).padStart(width, '0');
    return `${pad(year, 4)}-${pad(month)}-${pad(days + 1)} ${pad(Math.floor(remainder / 3600))}:${pad(Math.floor((remainder % 3600) / 60))}:${pad(remainder % 60)}`;
}

module.exports = { parseDate, formatDate };
