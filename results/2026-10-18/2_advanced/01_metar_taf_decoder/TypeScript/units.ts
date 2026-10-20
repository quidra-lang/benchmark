import type { Visibility } from './groups.ts';

export type Fraction = [number, number];
export interface Period { start: number; end: number }
export function floorDiv(numerator: number, denominator: number): number {
  const n = BigInt(numerator), d = BigInt(denominator), quotient = n / d;
  return Number(quotient - (n < 0n && n % d !== 0n ? 1n : 0n));
}
export const pad = (value: number, width: number) => String(value).padStart(width, '0');
export const modulo = (value: number, divisor: number) => ((value % divisor) + divisor) % divisor;
const SINE: Record<number, number> = { 0: 0, 10: 174, 20: 342, 30: 500, 40: 643, 50: 766,
  60: 866, 70: 940, 80: 985, 90: 1000 };
export function sin(angle: number): number {
  const y = modulo(angle, 360);
  if (y <= 90) return SINE[y];
  if (y <= 180) return SINE[180 - y];
  if (y <= 270) return -SINE[y - 180];
  return -SINE[360 - y];
}
export const cos = (angle: number) => sin(angle + 90);
export const knots = (value: number) => floorDiv(value * 1944 + 500, 1000);
export const inHg = (value: number) => floorDiv(value * 2953 + 500, 1000);
export const hPa = (value: number) => floorDiv(value * 33864 + 50000, 100000);
export function daysInMonth(year: number, month: number): number {
  if (month === 2) return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28;
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}
export class Calendar {
  readonly year: number;
  readonly month: number;
  readonly days: number;
  readonly nextYear: number;
  readonly nextMonth: number;
  readonly nextDays: number;
  constructor(year: number, month: number) {
    this.year = year; this.month = month; this.days = daysInMonth(year, month);
    this.nextYear = month === 12 ? year + 1 : year;
    this.nextMonth = month === 12 ? 1 : month + 1;
    this.nextDays = daysInMonth(this.nextYear, this.nextMonth);
  }
  observationTime(word: string): number | null {
    const match = /^(\d{2})(\d{2})(\d{2})Z$/.exec(word);
    if (!match) return null;
    const [day, hour, minute] = match.slice(1).map(Number);
    if (day < 1 || day > this.days || hour > 23 || minute > 59) return null;
    return ((day - 1) * 24 + hour) * 60 + minute;
  }
  dayTime(day: number, hour: number, minute: number, issueDay: number): number | null {
    const following = day < issueDay;
    if (day < 1 || day > (following ? this.nextDays : this.days)) return null;
    return (following ? this.days * 1440 : 0) + ((day - 1) * 24 + hour) * 60 + minute;
  }
  period(word: string, issueDay: number, maximum: number | null = null): Period | null {
    const match = /^(\d{2})(\d{2})\/(\d{2})(\d{2})$/.exec(word);
    if (!match) return null;
    const [firstDay, firstHour, lastDay, lastHour] = match.slice(1).map(Number);
    if (firstHour > 23 || lastHour < 1 || lastHour > 24) return null;
    const start = this.dayTime(firstDay, firstHour, 0, issueDay), end = this.dayTime(lastDay, lastHour, 0, issueDay);
    if (start === null || end === null || start >= end || maximum !== null && end - start > maximum) return null;
    return { start, end };
  }
  changeTime(word: string, issueDay: number): number | null {
    const match = /^FM(\d{2})(\d{2})(\d{2})$/.exec(word);
    if (!match) return null;
    const [day, hour, minute] = match.slice(1).map(Number);
    return hour > 23 || minute > 59 ? null : this.dayTime(day, hour, minute, issueDay);
  }
  stamp(time: number): string {
    const following = time >= this.days * 1440, value = time - (following ? this.days * 1440 : 0);
    return `${pad(following ? this.nextYear : this.year, 4)}-${pad(following ? this.nextMonth : this.month, 2)}`
      + `-${pad(floorDiv(value, 1440) + 1, 2)}T${pad(floorDiv(value % 1440, 60), 2)}:${pad(value % 60, 2)}Z`;
  }
}
export function mileFraction(visibility: Visibility): Fraction {
  return visibility.kind === 'mile'
    ? [visibility.whole * visibility.denominator + visibility.numerator, visibility.denominator]
    : [visibility.meters * 1000, 1609344];
}
export function meterValue(visibility: Visibility): number {
  if (visibility.kind !== 'mile') return visibility.meters;
  const [numerator, denominator] = mileFraction(visibility);
  return floorDiv(1609344 * numerator, 1000 * denominator);
}
export function compareVisibility(first: Visibility, second: Visibility): number {
  const [a, b] = mileFraction(first), [c, d] = mileFraction(second);
  return a * d - c * b;
}
export function fraction(numerator: number, denominator: number): string {
  if (denominator === 0) return 'undefined';
  let first = Math.abs(numerator), second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  return `${floorDiv(numerator, first)}/${floorDiv(denominator, first)}`;
}
