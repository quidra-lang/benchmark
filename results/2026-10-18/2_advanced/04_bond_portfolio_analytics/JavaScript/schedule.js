'use strict';

const { dateParts, daysInMonth, dayNumber } = require('./dates_calendar');

function couponSchedule(issue, maturity, frequency, endOfMonth = false, longStub = false) {
  const [year, month, day] = dateParts(maturity);
  const eom = endOfMonth && day === daysInMonth(year, month);
  const dates = [];
  for (let index = 0; ; index++) {
    const monthIndex = year * 12 + month - 1 - (12 / frequency) * index;
    const currentYear = Math.floor(monthIndex / 12), currentMonth = monthIndex % 12 + 1;
    const lastDay = daysInMonth(currentYear, currentMonth);
    const current = dayNumber(currentYear, currentMonth, eom ? lastDay : Math.min(day, lastDay));
    if (current <= issue) {
      if (longStub && current !== issue && index >= 2) dates.pop();
      break;
    }
    dates.push(current);
  }
  return [issue, ...dates.reverse()];
}

module.exports = { couponSchedule };
