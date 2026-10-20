import { yearFraction } from './daycount.ts';
import { couponSchedule, type Frequency } from './schedule.ts';
import { bisect } from './pricing.ts';
export interface Pillar { maturity: number; coupon: number; frequency: Frequency }
export interface CurveFlow { days: number; amount: number }
export class Curve {
  readonly days: number[];
  readonly rates: number[];
  constructor(days: number[], rates: number[]) { this.days = days; this.rates = rates; }
  rate(day: number): number {
    if (day <= this.days[0]) return this.rates[0];
    const last = this.days.length - 1;
    if (day >= this.days[last]) return this.rates[last];
    for (let j = 1; j <= last; j++) {
      if (day === this.days[j]) return this.rates[j];
      if (day < this.days[j]) return this.rates[j - 1] + (this.rates[j] - this.rates[j - 1])
        * ((day - this.days[j - 1]) / (this.days[j] - this.days[j - 1]));
    }
    return this.rates[last];
  }
  discount(day: number, spread = 0): number {
    const rate = this.rate(day) + spread, years = Math.floor(day / 365), remainder = day % 365;
    let power = 1;
    for (let y = 0; y < years; y++) power *= 1 + rate;
    return 1 / (power * (1 + rate * remainder / 365));
  }
  present(flows: CurveFlow[], spread = 0): number {
    let total = 0;
    for (const flow of flows) total += flow.amount * this.discount(flow.days, spread);
    return total;
  }
  forward(first: number, last: number): number { return (this.discount(first) / this.discount(last) - 1) * 365 / (last - first); }
  shifted(shifts: number[]): Curve { return new Curve(this.days, this.rates.map((rate, j) => rate + shifts[j])); }
  zspread(flows: CurveFlow[], target: number): number { return bisect(s => this.present(flows, s), -0.5, 0.5, target); }
}
export function bootstrap(pillars: Pillar[], settlement: number): Curve {
  const days: number[] = [], rates: number[] = [];
  for (const pillar of pillars) {
    const schedule = couponSchedule(settlement, pillar.maturity, pillar.frequency), flows: CurveFlow[] = [];
    for (let i = 1; i < schedule.length; i++) {
      const [n, m] = yearFraction(schedule[i - 1], schedule[i], '30/360');
      let amount = pillar.coupon * n / (10000 * m);
      if (i === schedule.length - 1) amount += 1;
      flows.push({ days: schedule[i] - settlement, amount });
    }
    days.push(pillar.maturity - settlement);
    rates.push(bisect(rate => new Curve(days, [...rates, rate]).present(flows), 0, 1, 1));
  }
  return new Curve(days, rates);
}
