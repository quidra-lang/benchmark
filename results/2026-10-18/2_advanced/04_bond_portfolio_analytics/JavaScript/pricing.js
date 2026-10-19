'use strict';

function bisect(functionValue, lower, upper, target) {
  for (let step = 0; step < 80; step++) {
    const middle = (lower + upper) / 2;
    if (functionValue(middle) > target) lower = middle;
    else upper = middle;
  }
  return (lower + upper) / 2;
}

function presentByYield(cashflows, frequency, fraction, yieldValue) {
  const first = 1 + fraction * yieldValue / frequency, growth = 1 + yieldValue / frequency;
  let power = 1;
  return cashflows.map(amount => {
    const present = amount / (first * power);
    power *= growth;
    return present;
  });
}

function dirty(cashflows, frequency, fraction, outstanding, yieldValue) {
  let value = 0;
  for (const amount of presentByYield(cashflows, frequency, fraction, yieldValue)) value += amount;
  return value * 100 / outstanding;
}

function yieldAnalytics(cashflows, frequency, fraction, outstanding, target) {
  const value = yieldValue => dirty(cashflows, frequency, fraction, outstanding, yieldValue);
  const ytm = bisect(value, 0, 1, target);
  const present = presentByYield(cashflows, frequency, fraction, ytm);
  let total = 0, weighted = 0, second = 0;
  for (let index = 0; index < present.length; index++) {
    const time = (index + fraction) / frequency;
    total += present[index];
    weighted += time * present[index];
    second += time * (time + 1 / frequency) * present[index];
  }
  const growth = 1 + ytm / frequency, macaulay = weighted / total;
  return { ytm, macaulay, modified: macaulay / growth, convexity: second / (total * growth * growth),
    dv01: (value(ytm - 0.0001) - value(ytm + 0.0001)) / 2 };
}

module.exports = { bisect, dirty, yieldAnalytics };
