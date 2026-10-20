export const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
export const COMMON_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
export type DaySpec = { kind: 'day'; day: number } | { kind: 'last'; weekday: number }
    | { kind: 'ge' | 'le'; day: number; weekday: number };
export const mod = (a: number, b: number) => a - b * Math.floor(a / b);
export const leapYear = (y: number) => y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
export const daysInMonth = (y: number, m: number) => m === 2 && leapYear(y) ? 29 : COMMON_DAYS[m - 1];
function daysBeforeYear(y: number) {
    const p = y - 1;
    return 365 * p + Math.floor(p / 4) - Math.floor(p / 100) + Math.floor(p / 400);
}
export function dayNumber(y: number, m: number, d: number) {
    let n = daysBeforeYear(y) - daysBeforeYear(1970) + d - 1;
    for (let month = 1; month < m; month++) n += daysInMonth(y, month);
    return n;
}
export function dateFromDay(n: number) {
    let year = 1970 + Math.floor(n / 365);
    while (n < dayNumber(year, 1, 1)) year--;
    while (n >= dayNumber(year + 1, 1, 1)) year++;
    let remaining = n - dayNumber(year, 1, 1), month = 1;
    while (remaining >= daysInMonth(year, month)) remaining -= daysInMonth(year, month++);
    return { year, month, day: remaining + 1 };
}
export const weekday = (n: number) => mod(n + 4, 7);
export function specifiedDay(y: number, m: number, spec: DaySpec) {
    if (spec.kind === 'day') return dayNumber(y, m, spec.day);
    if (spec.kind === 'last') {
        const end = dayNumber(y, m, daysInMonth(y, m));
        return end - mod(weekday(end) - spec.weekday, 7);
    }
    const base = dayNumber(y, m, spec.day);
    return spec.kind === 'ge' ? base + mod(spec.weekday - weekday(base), 7) : base - mod(weekday(base) - spec.weekday, 7);
}
export const timeValue = (y: number, m: number, d: number, h = 0, mi = 0, s = 0) => dayNumber(y, m, d) * 86400 + h * 3600 + mi * 60 + s;
export function splitTime(value: number) {
    const date = dateFromDay(Math.floor(value / 86400)), seconds = mod(value, 86400);
    return { ...date, hour: Math.floor(seconds / 3600), minute: Math.floor(seconds % 3600 / 60), second: seconds % 60 };
}
