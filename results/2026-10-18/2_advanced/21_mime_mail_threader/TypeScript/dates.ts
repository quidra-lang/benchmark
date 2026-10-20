import { removeComments, strip } from './headers.ts';

const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const zones: Record<string, number> = { ut: 0, gmt: 0, z: 0, est: -300, edt: -240, cst: -360, cdt: -300, mst: -420, mdt: -360, pst: -480, pdt: -420 };
const leap = (year: number) => year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
function monthDays(year: number, month: number): number { return month === 1 ? leap(year) ? 29 : 28 : [3, 5, 8, 10].includes(month) ? 30 : 31; }
export type ParsedDate = { seconds: number } | { problem: string };
export function parseDate(text: string): ParsedDate {
  const syntax = { problem: 'bad Date syntax' }, range = { problem: 'Date out of range' };
  const uncommented = removeComments(text);
  if (uncommented === undefined) return syntax;
  const tokens = strip(uncommented.replaceAll(',', ' , ')).split(/[ \t]+/).filter(Boolean);
  let weekday = -1;
  if (tokens.length >= 3 && weekdays.includes(tokens[0].toLowerCase()) && tokens[1] === ',') weekday = weekdays.indexOf(tokens.splice(0, 2)[0].toLowerCase());
  if (tokens.length !== 5) return syntax;
  const [dayText, monthText, yearText, timeText, zoneText] = tokens;
  const month = months.indexOf(monthText.toLowerCase()), time = timeText.split(':');
  const numericZone = /^[+-][0-9]{4}$/.test(zoneText), zoneName = zoneText.toLowerCase();
  if (!/^[0-9]{1,2}$/.test(dayText) || month < 0 || !/^([0-9]{2}|[0-9]{4})$/.test(yearText) ||
    (time.length !== 2 && time.length !== 3) || time.some(t => !/^[0-9]{2}$/.test(t)) || (!numericZone && !Object.hasOwn(zones, zoneName))) return syntax;
  let year = +yearText;
  if (yearText.length === 2) year += year < 50 ? 2000 : 1900;
  const day = +dayText, hour = +time[0], minute = +time[1], second = +(time[2] ?? 0);
  let offset = zones[zoneName];
  if (numericZone) {
    const hours = +zoneText.slice(1, 3), minutes = +zoneText.slice(3);
    if (hours > 23 || minutes > 59) return range;
    offset = (hours * 60 + minutes) * (zoneText[0] === '-' ? -1 : 1);
  }
  if (year < 1970 || year > 2099 || day < 1 || day > monthDays(year, month) || hour > 23 || minute > 59 || second > 59) return range;
  let days = 0;
  for (let y = 1970; y < year; y++) days += leap(y) ? 366 : 365;
  for (let m = 0; m < month; m++) days += monthDays(year, m);
  days += day - 1;
  const seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60;
  if (seconds < 0) return range;
  if (weekday >= 0 && (days + 3) % 7 !== weekday) return { problem: 'Date weekday mismatch' };
  return { seconds };
}
export function formatDate(seconds: number): string {
  let days = Math.floor(seconds / 86400), year = 1970, month = 0;
  while (days >= (leap(year) ? 366 : 365)) { days -= leap(year) ? 366 : 365; year++; }
  while (days >= monthDays(year, month)) { days -= monthDays(year, month); month++; }
  const remainder = seconds % 86400, pad = (n: number) => String(n).padStart(2, '0');
  return `${year}-${pad(month + 1)}-${pad(days + 1)} ${pad(Math.floor(remainder / 3600))}:${pad(Math.floor((remainder % 3600) / 60))}:${pad(remainder % 60)}`;
}
