import * as solver from './wdp_solver.ts';
import { Fraction } from './report.ts';
import type { Auction, Bid, CriticalPayment, VcgPayment, Coalition, Blockers, Participant } from './types.ts';

export function criticalPayments(order: Bid[], winners: Bid[]): Map<number, CriticalPayment> {
  const result = new Map<number, CriticalPayment>();
  for (const bid of winners) {
    const selected = solver.greedySelection(order.filter(other => other !== bid));
    const rival = selected.find(other => (bid.mask & other.mask) !== 0 || (bid.xor && other.bidder === bid.bidder));
    let payment = bid.reserve;
    if (rival !== undefined) {
      const target = rival.amount * rival.amount * bid.size;
      const precedes = (amount: number): boolean => amount * amount * rival.size > target ||
        (amount * amount * rival.size === target && bid.number < rival.number);
      let low = 1;
      let high = 1;
      while (!precedes(high)) high *= 2;
      while (low < high) {
        const middle = Math.floor((low + high) / 2);
        if (precedes(middle)) high = middle;
        else low = middle + 1;
      }
      payment = Math.max(payment, low);
    }
    result.set(bid.number, {payment, rival: rival === undefined ? null : rival.number});
  }
  return result;
}

export function vcgPayments(auction: Auction, welfare: number, values: number[]): VcgPayment[] {
  return auction.bidders.map(bidder => {
    if (values[bidder.index] === 0) return {payment: 0, alternative: null};
    const alternative = solver.solve(auction, auction.eligible.filter(bid => bid.bidder !== bidder));
    return {payment: alternative.welfare - (welfare - values[bidder.index]), alternative};
  });
}

export function coalitionWelfares(auction: Auction): Coalition[] {
  const result: Coalition[] = [];
  const count = auction.bidders.length;
  function choose(start: number, remaining: number, members: number[], mask: number): void {
    if (remaining === 0) {
      const allocation = solver.solve(auction, auction.eligible.filter(bid => (mask & bid.bidder.bit) !== 0));
      result.push({members, mask, welfare: allocation.welfare, numbers: allocation.numbers});
      return;
    }
    for (let index = start; index <= count - remaining; index++) {
      choose(index + 1, remaining - 1, members.concat(index), mask | auction.bidders[index].bit);
    }
  }
  for (let size = 0; size <= count; size++) choose(0, size, [], 0);
  return result;
}

export function blockers(coalitions: Coalition[], seller: number, utilities: number[]): Blockers {
  const blocking: Blockers['blocking'] = [];
  const minimal: Blockers['minimal'] = [];
  let maximum: Blockers['maximum'] = null;
  for (const coalition of coalitions) {
    let payoff = seller;
    for (const member of coalition.members) payoff += utilities[member];
    const deficit = coalition.welfare - payoff;
    if (deficit <= 0) continue;
    const block = {...coalition, payoff, deficit};
    blocking.push(block);
    if (maximum === null || deficit > maximum.deficit) maximum = block;
    if (!minimal.some(previous => (previous.mask & coalition.mask) === previous.mask)) minimal.push(block);
  }
  return {blocking, minimal, maximum};
}

export function gspPrice(ranking: Participant[], rank: number): number {
  return rank < ranking.length ? ranking[rank].bid : 0;
}

export function slotVCG(ranking: Participant[], rates: Fraction[], rank: number): Fraction {
  const rate = (index: number): Fraction => index <= rates.length ? rates[index - 1] : new Fraction(0);
  let payment = new Fraction(0);
  for (let next = rank + 1; next <= Math.min(ranking.length, rates.length + 1); next++) {
    payment = payment.add(rate(next - 1).subtract(rate(next)).multiply(ranking[next - 1].value));
  }
  return payment;
}

