'use strict';

const isLeap = year => year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);

function daysInMonth(year, month) {
  return [31, isLeap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}

function dayNumber(year, month, day) {
  let number = day - 1;
  for (let current = 2000; current < year; current++) number += isLeap(current) ? 366 : 365;
  for (let current = year; current < 2000; current++) number -= isLeap(current) ? 366 : 365;
  for (let current = 1; current < month; current++) number += daysInMonth(year, current);
  return number;
}

function dateParts(number) {
  let year = 2000, month = 1;
  while (number < 0) number += isLeap(--year) ? 366 : 365;
  while (number >= (isLeap(year) ? 366 : 365)) number -= isLeap(year++) ? 366 : 365;
  while (number >= daysInMonth(year, month)) number -= daysInMonth(year, month++);
  return [year, month, number + 1];
}

function parseDate(text) {
  const match = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/.exec(text);
  if (match === null) return null;
  const year = Number(match[1]), month = Number(match[2]), day = Number(match[3]);
  if (year < 2001 || year > 2099 || month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  return dayNumber(year, month, day);
}

function formatDate(number) {
  const [year, month, day] = dateParts(number);
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

class Calendar {
  constructor(holidays) {
    this.holidays = new Set(holidays);
  }

  business(number) {
    const weekday = ((number + 5) % 7 + 7) % 7;
    return weekday < 5 && !this.holidays.has(number);
  }

  shift(number, count) {
    const step = count < 0 ? -1 : 1;
    let remaining = Math.abs(count);
    while (remaining > 0) {
      number += step;
      if (this.business(number)) remaining--;
    }
    return number;
  }

  adjust(number, convention) {
    if (convention === 'UNADJUSTED') return number;
    const step = convention === 'PRECEDING' ? -1 : 1;
    let adjusted = number;
    while (!this.business(adjusted)) adjusted += step;
    if (convention === 'MODIFIED_FOLLOWING' && dateParts(adjusted)[1] !== dateParts(number)[1]) {
      return this.adjust(number, 'PRECEDING');
    }
    return adjusted;
  }
}

module.exports = { isLeap, daysInMonth, dayNumber, dateParts, parseDate, formatDate, Calendar };
