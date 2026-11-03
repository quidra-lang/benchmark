'use strict';

function floorDiv(numerator, denominator) {
  const n = BigInt(numerator);
  const d = BigInt(denominator);
  const quotient = n / d;
  return Number(quotient - (n < 0n && n % d !== 0n ? 1n : 0n));
}

function pad(value, width) {
  return String(value).padStart(width, '0');
}

function modulo(value, divisor) {
  return ((value % divisor) + divisor) % divisor;
}

const SINE = {0: 0, 10: 174, 20: 342, 30: 500, 40: 643, 50: 766,
  60: 866, 70: 940, 80: 985, 90: 1000};

function sin(angle) {
  const y = modulo(angle, 360);
  if (y <= 90) return SINE[y];
  if (y <= 180) return SINE[180 - y];
  if (y <= 270) return -SINE[y - 180];
  return -SINE[360 - y];
}

function cos(angle) {
  return sin(angle + 90);
}

function knots(value) {
  return floorDiv(value * 1944 + 500, 1000);
}

function inHg(value) {
  return floorDiv(value * 2953 + 500, 1000);
}

function hPa(value) {
  return floorDiv(value * 33864 + 50000, 100000);
}

function daysInMonth(year, month) {
  if (month === 2) {
    const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    return leap ? 29 : 28;
  }
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

class Calendar {
  constructor(year, month) {
    this.year = year;
    this.month = month;
    this.days = daysInMonth(year, month);
    this.nextYear = month === 12 ? year + 1 : year;
    this.nextMonth = month === 12 ? 1 : month + 1;
    this.nextDays = daysInMonth(this.nextYear, this.nextMonth);
  }

  observationTime(word) {
    const match = /^(\d{2})(\d{2})(\d{2})Z$/.exec(word);
    if (!match) return null;
    const [day, hour, minute] = match.slice(1).map(Number);
    if (day < 1 || day > this.days || hour > 23 || minute > 59) return null;
    return ((day - 1) * 24 + hour) * 60 + minute;
  }

  dayTime(day, hour, minute, issueDay) {
    const following = day < issueDay;
    if (day < 1 || day > (following ? this.nextDays : this.days)) return null;
    return (following ? this.days * 1440 : 0) + ((day - 1) * 24 + hour) * 60 + minute;
  }

  period(word, issueDay, maximum = null) {
    const match = /^(\d{2})(\d{2})\/(\d{2})(\d{2})$/.exec(word);
    if (!match) return null;
    const [firstDay, firstHour, lastDay, lastHour] = match.slice(1).map(Number);
    if (firstHour > 23 || lastHour < 1 || lastHour > 24) return null;
    const start = this.dayTime(firstDay, firstHour, 0, issueDay);
    const end = this.dayTime(lastDay, lastHour, 0, issueDay);
    if (start === null || end === null || start >= end) return null;
    if (maximum !== null && end - start > maximum) return null;
    return {start, end};
  }

  changeTime(word, issueDay) {
    const match = /^FM(\d{2})(\d{2})(\d{2})$/.exec(word);
    if (!match) return null;
    const [day, hour, minute] = match.slice(1).map(Number);
    if (hour > 23 || minute > 59) return null;
    return this.dayTime(day, hour, minute, issueDay);
  }

  stamp(time) {
    const following = time >= this.days * 1440;
    const value = time - (following ? this.days * 1440 : 0);
    const year = following ? this.nextYear : this.year;
    const month = following ? this.nextMonth : this.month;
    const day = floorDiv(value, 1440) + 1;
    const hour = floorDiv(value % 1440, 60);
    return `${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}T${pad(hour, 2)}:${pad(value % 60, 2)}Z`;
  }
}

function mileFraction(visibility) {
  if (visibility.kind === 'mile') {
    return [visibility.whole * visibility.denominator + visibility.numerator, visibility.denominator];
  }
  return [visibility.meters * 1000, 1609344];
}

function meterValue(visibility) {
  if (visibility.kind !== 'mile') return visibility.meters;
  const [numerator, denominator] = mileFraction(visibility);
  return floorDiv(1609344 * numerator, 1000 * denominator);
}

function compareVisibility(first, second) {
  const [a, b] = mileFraction(first);
  const [c, d] = mileFraction(second);
  return a * d - c * b;
}

function fraction(numerator, denominator) {
  if (denominator === 0) return 'undefined';
  let first = Math.abs(numerator);
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  return `${floorDiv(numerator, first)}/${floorDiv(denominator, first)}`;
}

module.exports = {floorDiv, pad, modulo, sin, cos, knots, inHg, hPa, daysInMonth,
  Calendar, mileFraction, meterValue, compareVisibility, fraction};
