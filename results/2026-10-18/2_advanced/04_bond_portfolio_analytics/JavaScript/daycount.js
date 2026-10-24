'use strict';

const { isLeap, daysInMonth, dayNumber, dateParts } = require('./dates_calendar');

function yearFraction(first, last, convention) {
  let [year1, month1, day1] = dateParts(first);
  let [year2, month2, day2] = dateParts(last);
  if (convention === '30/360' || convention === '30E/360') {
    if (convention === '30/360') {
      const february1 = month1 === 2 && day1 === daysInMonth(year1, month1);
      const february2 = month2 === 2 && day2 === daysInMonth(year2, month2);
      if (february1 && february2) day2 = 30;
      if (february1) day1 = 30;
      if (day2 === 31 && day1 >= 30) day2 = 30;
      if (day1 === 31) day1 = 30;
    } else {
      if (day1 === 31) day1 = 30;
      if (day2 === 31) day2 = 30;
    }
    return [360 * (year2 - year1) + 30 * (month2 - month1) + day2 - day1, 360];
  }
  if (convention === 'ACT/360') return [last - first, 360];
  if (convention === 'ACT/365F') return [last - first, 365];
  let leapDays = 0, ordinaryDays = 0, cursor = first;
  for (let year = year1; cursor < last; year++) {
    const end = Math.min(last, dayNumber(year + 1, 1, 1));
    if (isLeap(year)) leapDays += end - cursor;
    else ordinaryDays += end - cursor;
    cursor = end;
  }
  return [365 * leapDays + 366 * ordinaryDays, 133590];
}

module.exports = { yearFraction };
