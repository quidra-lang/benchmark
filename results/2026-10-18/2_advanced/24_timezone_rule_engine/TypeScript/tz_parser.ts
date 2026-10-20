import { MONTHS, WEEKDAYS, COMMON_DAYS, specifiedDay, type DaySpec } from './day_rules.ts';
export type TimeType = 'w' | 's' | 'u';
export interface Time { value: number; type: TimeType }
export interface Until { rawYear: string; monthName: string; dayText: string; time: Time; nominal: number }
export function extractLine(text: string) {
    const content = text.split('#', 1)[0].replace(/ +$/, '');
    return content === '' ? null : { continuation: content[0] === ' ', fields: content.trimStart().split(/ +/) };
}
export function hms(text: string) {
    const m = /^(\d{1,2})(?::(\d{2})(?::(\d{2}))?)?$/.exec(text);
    if (!m) return null;
    const hour = Number(m[1]), minute = Number(m[2] ?? 0), second = Number(m[3] ?? 0);
    return minute > 59 || second > 59 ? null : hour * 3600 + minute * 60 + second;
}
export function year(text: string) {
    const n = Number(text);
    return /^\d{4}$/.test(text) && n >= 1800 && n <= 2099 ? n : null;
}
export function toYear(text: string, from: number) {
    if (text === 'only') return from;
    if (text === 'max') return 2099;
    const n = year(text);
    return n !== null && n >= from ? n : null;
}
export function month(text: string) { const n = MONTHS.indexOf(text); return n < 0 ? null : n + 1; }
export function daySpec(text: string, month: number): DaySpec | null {
    if (/^[1-9]\d?$/.test(text)) {
        const day = Number(text);
        return day <= COMMON_DAYS[month - 1] ? { kind: 'day', day } : null;
    }
    const last = /^last([A-Za-z]{3})$/.exec(text);
    if (last) { const weekday = WEEKDAYS.indexOf(last[1]); return weekday < 0 ? null : { kind: 'last', weekday }; }
    const m = /^([A-Za-z]{3})(>=|<=)([1-9]\d?)$/.exec(text);
    if (m) {
        const weekday = WEEKDAYS.indexOf(m[1]), day = Number(m[3]);
        if (weekday >= 0 && day <= COMMON_DAYS[month - 1]) return { kind: m[2] === '>=' ? 'ge' : 'le', weekday, day };
    }
    return null;
}
export function time(text: string): Time | null {
    const suffix = text.at(-1);
    const type: TimeType = suffix === 's' || suffix === 'u' || suffix === 'w' ? suffix : 'w';
    const value = hms(type === suffix ? text.slice(0, -1) : text);
    return value === null || value > 86400 ? null : { value, type };
}
export function save(text: string) {
    if (!/^\d{1,2}(?::\d{2})?$/.test(text)) return null;
    const value = hms(text);
    return value !== null && value <= 7200 ? value : null;
}
export function offset(text: string) {
    const negative = text.startsWith('-'), value = hms(negative ? text.slice(1) : text);
    return value === null || value >= 57600 ? null : negative ? -value : value;
}
export const letter = (text: string) => text === '-' ? '' : /^[A-Z]{1,5}$/.test(text) ? text : null;
export function validFormat(text: string, named: boolean) {
    if (!/^(?:[A-Za-z0-9+\/-]|%s)+$/.test(text)) return false;
    const substitutions = text.split('%s').length - 1, slashes = text.split('/').length - 1;
    return substitutions <= 1 && slashes <= 1 && !(substitutions && slashes) && !(substitutions && !named)
        && !(slashes && (text.startsWith('/') || text.endsWith('/')));
}
export function until(fields: string[]): { value: Until | null } | { error: string } {
    if (!fields.length) return { value: null };
    const [rawYear, monthName = 'Jan', dayText = '1', timeText = '0:00'] = fields;
    const y = year(rawYear); if (y === null) return { error: 'bad year' };
    const m = month(monthName); if (m === null) return { error: 'bad month' };
    const day = daySpec(dayText, m); if (!day) return { error: 'bad day spec' };
    const at = time(timeText); if (!at) return { error: 'bad time' };
    return { value: { rawYear, monthName, dayText, time: at, nominal: specifiedDay(y, m, day) * 86400 + at.value } };
}
