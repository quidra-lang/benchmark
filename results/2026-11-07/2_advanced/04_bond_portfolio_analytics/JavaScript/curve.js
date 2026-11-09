'use strict';

const { yearFraction } = require('./daycount');
const { couponSchedule } = require('./schedule');
const { bisect } = require('./pricing');

class Curve {
  constructor(days, rates) {
    this.days = days;
    this.rates = rates;
  }

  rate(days) {
    if (days <= this.days[0]) return this.rates[0];
    if (days >= this.days.at(-1)) return this.rates.at(-1);
    for (let index = 1; index < this.days.length; index++) {
      if (days === this.days[index]) return this.rates[index];
      if (days < this.days[index]) return this.rates[index - 1] + (this.rates[index] - this.rates[index - 1])
        * ((days - this.days[index - 1]) / (this.days[index] - this.days[index - 1]));
    }
  }

  discount(days, spread = 0) {
    const rate = this.rate(days) + spread, years = Math.floor(days / 365), remainder = days % 365;
    let power = 1;
    for (let year = 0; year < years; year++) power *= 1 + rate;
    return 1 / (power * (1 + rate * remainder / 365));
  }

  present(cashflows, spread = 0) {
    let total = 0;
    for (const flow of cashflows) total += flow.amount * this.discount(flow.days, spread);
    return total;
  }

  forward(first, last) {
    return (this.discount(first) / this.discount(last) - 1) * 365 / (last - first);
  }

  shifted(shifts) {
    return new Curve(this.days, this.rates.map((rate, index) => rate + shifts[index]));
  }

  zspread(cashflows, target) {
    return bisect(spread => this.present(cashflows, spread), -0.5, 0.5, target);
  }
}

function bootstrap(pillars, settlement) {
  const days = [], rates = [];
  for (const pillar of pillars) {
    const schedule = couponSchedule(settlement, pillar.maturity, pillar.frequency), cashflows = [];
    for (let period = 1; period < schedule.length; period++) {
      const [numerator, denominator] = yearFraction(schedule[period - 1], schedule[period], '30/360');
      let amount = pillar.coupon * numerator / (10000 * denominator);
      if (period === schedule.length - 1) amount += 1;
      cashflows.push({ days: schedule[period] - settlement, amount });
    }
    days.push(pillar.maturity - settlement);
    const price = rate => new Curve(days, [...rates, rate]).present(cashflows);
    rates.push(bisect(price, 0, 1, 1));
  }
  return new Curve(days, rates);
}

module.exports = { Curve, bootstrap };
