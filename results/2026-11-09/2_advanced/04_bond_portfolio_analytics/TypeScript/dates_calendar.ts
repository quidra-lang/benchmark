export type BusinessRule = 'FOLLOWING' | 'MODIFIED_FOLLOWING' | 'PRECEDING' | 'UNADJUSTED';
export const isLeap = (year: number): boolean =>
  year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
export function daysInMonth(year: number, month: number): number {
  return [31, isLeap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}
export function dayNumber(year: number, month: number, day: number): number {
  let result = day - 1;
  for (let y = 2000; y < year; y++) result += isLeap(y) ? 366 : 365;
  for (let y = year; y < 2000; y++) result -= isLeap(y) ? 366 : 365;
  for (let m = 1; m < month; m++) result += daysInMonth(year, m);
  return result;
}
export function dateParts(day: number): [number, number, number] {
  let year = 2000;
  let month = 1;
  while (day < 0) day += isLeap(--year) ? 366 : 365;
  while (day >= (isLeap(year) ? 366 : 365)) day -= isLeap(year++) ? 366 : 365;
  while (day >= daysInMonth(year, month)) day -= daysInMonth(year, month++);
  return [year, month, day + 1];
}
export function parseDate(text: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (
    year < 2001 ||
    year > 2099 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > daysInMonth(year, month)
  ) {
    return null;
  }
  return dayNumber(year, month, day);
}
export function formatDate(day: number): string {
  const [y, m, d] = dateParts(day);
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}
export class Calendar {
  private readonly holidays: Set<number>;
  constructor(holidays: number[]) {
    this.holidays = new Set(holidays);
  }
  business(day: number): boolean {
    return (((day + 5) % 7) + 7) % 7 < 5 && !this.holidays.has(day);
  }
  shift(day: number, count: number): number {
    const step = count < 0 ? -1 : 1;
    let remaining = Math.abs(count);
    while (remaining > 0) {
      day += step;
      if (this.business(day)) remaining--;
    }
    return day;
  }
  adjust(day: number, rule: BusinessRule): number {
    if (rule === 'UNADJUSTED') return day;
    let result = day;
    const step = rule === 'PRECEDING' ? -1 : 1;
    while (!this.business(result)) result += step;
    return rule === 'MODIFIED_FOLLOWING' && dateParts(result)[1] !== dateParts(day)[1]
      ? this.adjust(day, 'PRECEDING')
      : result;
  }
}
