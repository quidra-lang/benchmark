import { dateParts, dayNumber, daysInMonth } from './dates_calendar.ts';
export type Frequency = 1 | 2 | 4 | 12;
export function couponSchedule(issue: number, maturity: number, frequency: Frequency, endOfMonth = false, longStub = false): number[] {
  const [year, month, day] = dateParts(maturity), eom = endOfMonth && day === daysInMonth(year, month);
  const dates: number[] = [];
  for (let k = 0; ; k++) {
    const index = year * 12 + month - 1 - (12 / frequency) * k;
    const y = Math.floor(index / 12), m = index % 12 + 1, last = daysInMonth(y, m);
    const current = dayNumber(y, m, eom ? last : Math.min(day, last));
    if (current <= issue) { if (longStub && current !== issue && k >= 2) dates.pop(); break; }
    dates.push(current);
  }
  return [issue, ...dates.reverse()];
}
