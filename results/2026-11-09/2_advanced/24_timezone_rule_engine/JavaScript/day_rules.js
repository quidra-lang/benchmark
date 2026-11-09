'use strict';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const COMMON_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const mod = (a, b) => a - b * Math.floor(a / b);
const leapYear = year => year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
const daysInMonth = (year, month) => month === 2 && leapYear(year) ? 29 : COMMON_DAYS[month - 1];

function daysBeforeYear(year) {
    const previous = year - 1;
    return 365 * previous + Math.floor(previous / 4) - Math.floor(previous / 100) + Math.floor(previous / 400);
}

function dayNumber(year, month, day) {
    let total = daysBeforeYear(year) - daysBeforeYear(1970) + day - 1;
    for (let m = 1; m < month; m++) total += daysInMonth(year, m);
    return total;
}

function dateFromDay(number) {
    let year = 1970 + Math.floor(number / 365);
    while (number < dayNumber(year, 1, 1)) year--;
    while (number >= dayNumber(year + 1, 1, 1)) year++;
    let remaining = number - dayNumber(year, 1, 1);
    let month = 1;
    while (remaining >= daysInMonth(year, month)) remaining -= daysInMonth(year, month++);
    return { year, month, day: remaining + 1 };
}

const weekday = number => mod(number + 4, 7);

function specifiedDay(year, month, spec) {
    if (spec.kind === 'day') return dayNumber(year, month, spec.day);
    if (spec.kind === 'last') {
        const end = dayNumber(year, month, daysInMonth(year, month));
        return end - mod(weekday(end) - spec.weekday, 7);
    }
    const base = dayNumber(year, month, spec.day);
    return spec.kind === 'ge' ? base + mod(spec.weekday - weekday(base), 7)
        : base - mod(weekday(base) - spec.weekday, 7);
}

function timeValue(year, month, day, hour = 0, minute = 0, second = 0) {
    return dayNumber(year, month, day) * 86400 + hour * 3600 + minute * 60 + second;
}

function splitTime(value) {
    const date = dateFromDay(Math.floor(value / 86400));
    const seconds = mod(value, 86400);
    return { ...date, hour: Math.floor(seconds / 3600), minute: Math.floor(seconds % 3600 / 60), second: seconds % 60 };
}

module.exports = { MONTHS, WEEKDAYS, COMMON_DAYS, mod, leapYear, daysInMonth, dayNumber, dateFromDay, weekday,
    specifiedDay, timeValue, splitTime };
