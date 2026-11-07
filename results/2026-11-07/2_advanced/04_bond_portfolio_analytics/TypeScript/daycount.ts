import { dateParts, dayNumber, daysInMonth, isLeap } from './dates_calendar.ts';
export type DayCount = '30/360' | '30E/360' | 'ACT/360' | 'ACT/365F' | 'ACT/ACT';
export function yearFraction(first: number, last: number, convention: DayCount): [number, number] {
  let [y1, m1, d1] = dateParts(first);
  let [y2, m2, d2] = dateParts(last);
  if (convention === '30/360' || convention === '30E/360') {
    if (convention === '30/360') {
      const feb1 = m1 === 2 && d1 === daysInMonth(y1, m1);
      const feb2 = m2 === 2 && d2 === daysInMonth(y2, m2);
      if (feb1 && feb2) d2 = 30;
      if (feb1) d1 = 30;
      if (d2 === 31 && d1 >= 30) d2 = 30;
      if (d1 === 31) d1 = 30;
    } else {
      if (d1 === 31) d1 = 30;
      if (d2 === 31) d2 = 30;
    }
    return [360 * (y2 - y1) + 30 * (m2 - m1) + d2 - d1, 360];
  }
  if (convention === 'ACT/360') return [last - first, 360];
  if (convention === 'ACT/365F') return [last - first, 365];
  let leap = 0;
  let ordinary = 0;
  let cursor = first;
  for (let year = y1; cursor < last; year++) {
    const end = Math.min(last, dayNumber(year + 1, 1, 1));
    if (isLeap(year)) leap += end - cursor;
    else ordinary += end - cursor;
    cursor = end;
  }
  return [365 * leap + 366 * ordinary, 133590];
}
