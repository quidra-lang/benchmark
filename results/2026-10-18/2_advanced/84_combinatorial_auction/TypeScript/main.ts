import * as io from './bids_io.ts';
import * as solver from './wdp_solver.ts';
import * as payments from './payments.ts';
import * as auctions from './auctions.ts';
import * as report from './report.ts';
import type {
  Item, Bidder, RawAuction, Auction, Parameters, Candidate, Allocation, AscendingResult,
  AuctionResult, CoreReport, Group, GroupReport, Participant, LotResult, Outcome,
  CriticalPayment, VcgPayment
} from './types.ts';
const {Fraction} = report;
const lotFormats = ['first_price', 'second_price', 'english', 'dutch', 'all_pay'];
const outcomeNames = ['vcg', 'greedy', 'critical', 'saa'];

function total(values: number[]): number {
  let result = 0;
  for (const value of values) result += value;
  return result;
}

function numberList(numbers: number[]): string {
  return numbers.slice().sort((a, b) => a - b).join('+') || '-';
}

function validateBid(text: string, number: number, bidder: Bidder, offered: Set<string>, itemMap: Map<string,Item>, parameters: Parameters): io.Bid | {error: string} {
  const match = /^([a-z]+(?:\+[a-z]+)*):(0|[1-9][0-9]{0,4})$/.exec(text);
  if (match === null || match[0].length !== text.length) return {error: 'malformed bid'};
  const names = match[1].split('+');
  const seen = new Set<string>();
  const items: Item[] = [];
  for (const name of names) {
    if (!itemMap.has(name)) return {error: 'unknown item ' + name};
    if (!offered.has(name)) return {error: 'item not offered ' + name};
    if (seen.has(name)) return {error: 'duplicate item ' + name};
    seen.add(name);
    items.push(itemMap.get(name)!);
  }
  if (items.length > parameters.max_bundle_size) return {error: 'bundle too large'};
  const amount = Number(match[2]);
  if (amount === 0) return {error: 'zero value'};
  items.sort((a, b) => a.number - b.number);
  const bid = new io.Bid(number, bidder, items, amount);
  const previous = bidder.valid.find(earlier => earlier.mask === bid.mask);
  if (previous !== undefined) return {error: 'duplicate bundle ' + previous.number};
  if (bidder.valid.length >= parameters.max_bids_per_bidder) return {error: 'too many bids'};
  return bid;
}

function validateAuction(raw: RawAuction, items: Item[], parameters: Parameters): Auction {
  const itemMap = new Map<string, Item>(items.map(item => [item.name, item]));
  const offered = new Set<string>(raw.offered);
  const auction: Auction = {name: raw.name, items: raw.offered.map(name => itemMap.get(name)!),
    mask: 0, bidders: [], valid: [], eligible: [], below: [], rejected: [], totalBids: 0};
  for (const item of auction.items) auction.mask |= item.bit;
  const seen = new Set<string>();
  for (const line of raw.lines) {
    let lineError: string | null = null;
    if (seen.has(line.name)) lineError = 'duplicate bidder';
    else if (line.language !== 'XOR' && line.language !== 'OR') lineError = 'bad language ' + line.language;
    seen.add(line.name);
    let bidder: Bidder | null = null;
    if (lineError === null) {
      const index = auction.bidders.length;
      bidder = {name: line.name, language: line.language as 'XOR'|'OR', index, bit: 1 << index, valid: [], eligible: []};
      auction.bidders.push(bidder);
    }
    for (const text of line.bids) {
      const number = ++auction.totalBids;
      const bid = lineError === null ? validateBid(text, number, bidder!, offered, itemMap, parameters) : {error: lineError};
      if ('error' in bid) auction.rejected.push({number, name: line.name, error: bid.error});
      else {
        bidder!.valid.push(bid);
        auction.valid.push(bid);
      }
    }
  }
  auction.eligible = auction.valid.filter(bid => bid.amount >= bid.reserve);
  auction.below = auction.valid.filter(bid => bid.amount < bid.reserve);
  for (const bidder of auction.bidders) bidder.eligible = bidder.valid.filter(bid => bid.amount >= bid.reserve);
  return auction;
}

function allocation(auction: Auction, selected: io.Bid[]): Allocation {
  const bids = selected.slice().sort((a, b) => a.number - b.number);
  let accepted = 0;
  let mask = 0;
  for (const bid of bids) {
    accepted += bid.amount;
    mask |= bid.mask;
  }
  const unsold = auction.items.filter(item => (mask & item.bit) === 0);
  const retained = total(unsold.map(item => item.reserve));
  return {bids, accepted, mask, unsold, retained, welfare: accepted + retained};
}

function bidderAmounts(auction: Auction, bids: io.Bid[], amount: (bid: io.Bid) => number = bid => bid.amount): number[] {
  const result = auction.bidders.map(() => 0);
  for (const bid of bids) result[bid.bidder.index] += amount(bid);
  return result;
}

function ascending(auction: Auction, parameters: Parameters, optimalWelfare: number): AscendingResult {
  const {items, bidders} = auction;
  const candidates = bidders.map(auctions.candidates);
  const eligibility = candidates.map(list => {
    let maximum = 0;
    for (const candidate of list) maximum = Math.max(maximum, candidate.size);
    return maximum;
  });
  const prices = items.map(item => item.reserve);
  const holders = items.map(() => -1);
  const itemStats = items.map(() => ({bids: 0, rounds: 0, last: 0}));
  const lines = [`AUCTION ${auction.name} increment ${parameters.saa_increment}`];
  let randomState = parameters.seed;
  let rounds = 0;
  let reason = '';
  for (let round = 1; round <= parameters.round_cap; round++) {
    rounds = round;
    const held = bidders.map(() => 0);
    for (let index = 0; index < items.length; index++) {
      if (holders[index] !== -1) held[holders[index]] |= items[index].bit;
    }
    const requests: number[][] = items.map(() => []);
    const newBundles = bidders.map(() => 0);
    const activity = bidders.map(() => 0);
    for (const bidder of bidders) {
      const number = bidder.index;
      const asking = items.map((item, index) => prices[index] +
        (holders[index] !== -1 && holders[index] !== number ? parameters.saa_increment : 0));
      let best: Candidate | null = null;
      let surplus = 0;
      for (const candidate of candidates[number]) {
        if (auctions.bitCount(candidate.mask | held[number]) > eligibility[number]) continue;
        let cost = 0;
        for (let index = 0; index < items.length; index++) {
          if ((candidate.mask & items[index].bit) !== 0) cost += asking[index];
        }
        const value = candidate.value - cost;
        if (value > surplus) {
          best = candidate;
          surplus = value;
        }
      }
      activity[number] = auctions.bitCount(held[number] | (best === null ? 0 : best.mask));
      if (best === null) continue;
      for (let index = 0; index < items.length; index++) {
        if ((best.mask & items[index].bit) !== 0 && holders[index] !== number) {
          requests[index].push(number);
          newBundles[number] |= items[index].bit;
        }
      }
    }
    const demand = total(requests.map(request => request.length));
    if (demand === 0) lines.push(`ROUND ${round} none`);
    else {
      const entries = bidders.filter(bidder => newBundles[bidder.index] !== 0).map(bidder =>
        `${bidder.name}:${report.bundle(newBundles[bidder.index], items)}`);
      lines.push(`ROUND ${round} demand ${demand} ${entries.join(' ')}`);
      for (let index = 0; index < items.length; index++) {
        const request = requests[index];
        if (request.length === 0) continue;
        let chosen = 0;
        if (request.length >= 2) {
          randomState = (48271 * randomState) % 2147483647;
          chosen = randomState % request.length;
        }
        if (holders[index] !== -1) prices[index] += parameters.saa_increment;
        holders[index] = request[chosen];
        itemStats[index].bids += request.length;
        itemStats[index].rounds++;
        itemStats[index].last = round;
      }
      const standing = items.map((item, index) =>
        `${item.name}=${prices[index]}@${holders[index] === -1 ? '-' : bidders[holders[index]].name}`);
      lines.push('STANDING ' + standing.join(' '));
    }
    const changes: string[] = [];
    for (const bidder of bidders) {
      if (activity[bidder.index] < eligibility[bidder.index]) {
        eligibility[bidder.index] = activity[bidder.index];
        changes.push(`${bidder.name}=${eligibility[bidder.index]}`);
      }
    }
    if (changes.length > 0) lines.push('ELIGIBILITY ' + changes.join(' '));
    if (demand === 0 || round === parameters.round_cap) {
      reason = demand === 0 ? 'quiet' : 'cap';
      break;
    }
  }
  lines.push(`END rounds ${rounds} ${reason}`);
  const bought = bidders.map(() => 0);
  const paid = bidders.map(() => 0);
  let retained = 0;
  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    const holder = holders[index];
    if (holder === -1) {
      retained += item.reserve;
      lines.push(`ITEM ${item.name} unsold reserve ${item.reserve}`);
    } else {
      bought[holder] |= item.bit;
      paid[holder] += prices[index];
      const stats = itemStats[index];
      lines.push(`ITEM ${item.name} price ${prices[index]} holder ${bidders[holder].name} bids ${stats.bids} rounds ${stats.rounds} last ${stats.last}`);
    }
  }
  const values = bidders.map(bidder => auctions.valueOf(candidates[bidder.index], bought[bidder.index]));
  const utilities = values.map((value, index) => value - paid[index]);
  let exposure = 0;
  let exposed = 0;
  for (const bidder of bidders) {
    const index = bidder.index;
    let line = `BIDDER ${bidder.name} won ${report.bundle(bought[index], items)} paid ${paid[index]} ` +
      `value ${values[index]} utility ${utilities[index]} eligibility ${eligibility[index]}`;
    if (utilities[index] < 0) {
      line += ' exposed';
      exposed++;
      exposure -= utilities[index];
    }
    lines.push(line);
  }
  const revenue = total(paid);
  const welfare = total(values) + retained;
  lines.push(`TOTAL revenue ${revenue} welfare ${welfare} efficiency ${new Fraction(welfare, optimalWelfare)} exposure ${exposure} exposed ${exposed}`);
  return {lines, rounds, reason, retained, paid, values, utilities, revenue, welfare, exposure, exposed};
}

function analyzeAuction(auction: Auction, parameters: Parameters): AuctionResult {
  const search = solver.solve(auction);
  const optimal = allocation(auction, search.bids);
  const order = solver.greedyOrder(auction.eligible);
  const greedy = allocation(auction, solver.greedySelection(order));
  const critical = payments.criticalPayments(order, greedy.bids);
  const optimalValues = bidderAmounts(auction, optimal.bids);
  const greedyValues = bidderAmounts(auction, greedy.bids);
  const criticalPaid = bidderAmounts(auction, greedy.bids, bid => critical.get(bid.number)!.payment);
  const criticalUtilities = greedyValues.map((value, index) => value - criticalPaid[index]);
  const vcg = payments.vcgPayments(auction, optimal.welfare, optimalValues);
  const vcgUtilities = optimalValues.map((value, index) => value - vcg[index].payment);
  const vcgRevenue = total(vcg.map(result => result.payment));
  const criticalRevenue = total(criticalPaid);
  const saa = ascending(auction, parameters, optimal.welfare);
  const outcomes = [
    {name: 'vcg', seller: vcgRevenue + optimal.retained, utilities: vcgUtilities},
    {name: 'greedy', seller: greedy.welfare, utilities: auction.bidders.map(() => 0)},
    {name: 'critical', seller: criticalRevenue + greedy.retained, utilities: criticalUtilities},
    {name: 'saa', seller: saa.revenue + saa.retained, utilities: saa.utilities},
  ];
  return {auction, search, optimal, order, greedy, critical, optimalValues, greedyValues,
    criticalPaid, criticalUtilities, vcg, vcgUtilities, vcgRevenue, criticalRevenue, saa, outcomes};
}

function wdpLines(result: AuctionResult): string[] {
  const {auction, search, optimal, order, greedy, critical} = result;
  const lines: string[] = [`AUCTION ${auction.name} items ${auction.items.length} bidders ${auction.bidders.length} ` +
    `bids ${auction.totalBids} valid ${auction.valid.length} eligible ${auction.eligible.length}`];
  for (const bidder of auction.bidders) lines.push(`BIDDER ${bidder.name} ${bidder.language} valid ${bidder.valid.length} eligible ${bidder.eligible.length}`);
  for (const bid of auction.rejected) lines.push(`REJECT ${bid.number} ${bid.name} ${bid.error}`);
  for (const bid of auction.below) lines.push(`BELOW_RESERVE ${bid.number} ${bid.bidder.name} value ${bid.amount} reserve ${bid.reserve}`);
  for (const share of search.rootShares) lines.push(`SHARE ${share.item.name} ${share.value} ${share.source === null ? 'reserve' : 'bid ' + share.source}`);
  lines.push(`ROOT_BOUND ${search.rootBound}`);
  for (const improvement of search.stats.improvements) {
    lines.push(`IMPROVE ${improvement.node} welfare ${improvement.welfare} bids ${numberList(improvement.numbers)}`);
  }
  lines.push(`OPTIMAL welfare ${optimal.welfare} accepted ${optimal.accepted} retained ${optimal.retained} winners ${optimal.bids.length}`);
  for (const bid of optimal.bids) lines.push(`WIN ${bid.number} ${bid.bidder.name} ${report.bundle(bid.mask, auction.items)} ${bid.amount}`);
  lines.push('UNSOLD ' + (optimal.unsold.map(item => item.name).join(' ') || '-'));
  const stats = search.stats;
  lines.push(`SEARCH nodes ${stats.nodes} pruned ${stats.pruned} leaves ${stats.leaves} improvements ${stats.improvements.length}`);
  lines.push('GREEDY_ORDER ' + (order.map(bid => bid.number).join(' ') || '-'));
  lines.push(`GREEDY welfare ${greedy.welfare} accepted ${greedy.accepted} retained ${greedy.retained} winners ${greedy.bids.length} ` +
    `efficiency ${new Fraction(greedy.welfare, optimal.welfare)}`);
  for (const bid of greedy.bids) {
    const payment = critical.get(bid.number)!;
    lines.push(`GWIN ${bid.number} ${bid.bidder.name} ${report.bundle(bid.mask, auction.items)} ${bid.amount} ` +
      `critical ${payment.payment} against ${payment.rival === null ? '-' : payment.rival}`);
  }
  lines.push('GUNSOLD ' + (greedy.unsold.map(item => item.name).join(' ') || '-'));
  for (const item of auction.items) {
    const winning = optimal.bids.find(bid => (bid.mask & item.bit) !== 0);
    const approximate = greedy.bids.find(bid => (bid.mask & item.bit) !== 0);
    const demand = auction.eligible.filter(bid => (bid.mask & item.bit) !== 0).length;
    lines.push(`ITEM ${item.name} reserve ${item.reserve} demand ${demand} ` +
      `optimal ${winning === undefined ? '-' : winning.bidder.name} greedy ${approximate === undefined ? '-' : approximate.bidder.name}`);
  }
  return lines;
}

function vcgLines(result: AuctionResult): string[] {
  const {auction, optimal, optimalValues, greedyValues, criticalPaid, criticalUtilities, vcg, vcgUtilities, vcgRevenue, saa} = result;
  const lines = [`AUCTION ${auction.name} welfare ${optimal.welfare}`];
  for (const bidder of auction.bidders) {
    const index = bidder.index;
    if (optimalValues[index] === 0) lines.push(`BIDDER ${bidder.name} lost`);
    else {
      const won = optimal.bids.filter(bid => bid.bidder === bidder).map(bid => bid.number);
      const payment = vcg[index];
      lines.push(`BIDDER ${bidder.name} won ${numberList(won)} value ${optimalValues[index]} without ${payment.alternative!.welfare} ` +
        `alternative ${numberList(payment.alternative!.numbers)} payment ${payment.payment} utility ${vcgUtilities[index]}`);
    }
  }
  lines.push(`TOTAL revenue ${vcgRevenue} pay_as_bid ${optimal.accepted} retained ${optimal.retained} ` +
    `seller ${vcgRevenue + optimal.retained} bidders ${total(vcgUtilities)}`);
  for (const bidder of auction.bidders) {
    const index = bidder.index;
    lines.push(`PAYMENTS ${bidder.name} vcg ${vcg[index].payment} pay_as_bid ${optimalValues[index]} ` +
      `greedy ${greedyValues[index]} critical ${criticalPaid[index]} saa ${saa.paid[index]}`);
  }
  for (const bidder of auction.bidders) {
    const index = bidder.index;
    lines.push(`UTILITIES ${bidder.name} vcg ${vcgUtilities[index]} critical ${criticalUtilities[index]} saa ${saa.utilities[index]}`);
  }
  return lines;
}

function coreLines(result: AuctionResult, maximumBidders: number): CoreReport {
  const {auction, outcomes} = result;
  const lines = [`AUCTION ${auction.name} bidders ${auction.bidders.length}`];
  if (auction.bidders.length > maximumBidders) return {lines: lines.concat('SKIPPED'), checked: false};
  const coalitions = payments.coalitionWelfares(auction);
  lines.push(`COALITIONS ${coalitions.length}`);
  const membership: Record<string, boolean> = {};
  const name = (coalition: {members: number[]}): string => coalition.members.map(index => auction.bidders[index].name).join('+') || '-';
  for (const outcome of outcomes) {
    lines.push(`OUTCOME ${outcome.name} seller ${outcome.seller} utilities ${outcome.utilities.join(' ')}`);
    const blocks = payments.blockers(coalitions, outcome.seller, outcome.utilities);
    for (const block of blocks.minimal) {
      lines.push(`BLOCK ${name(block)} welfare ${block.welfare} payoff ${block.payoff} deficit ${block.deficit} bids ${numberList(block.numbers)}`);
    }
    membership[outcome.name] = blocks.blocking.length === 0;
    if (membership[outcome.name]) lines.push('RESULT core');
    else lines.push(`RESULT blocked ${blocks.blocking.length} minimal ${blocks.minimal.length} ` +
      `max_deficit ${blocks.maximum!.deficit} by ${name(blocks.maximum!)}`);
  }
  return {lines, checked: true, membership};
}

function summaryRow(name: string, mechanism: string, revenue: number | Fraction, welfare: number | Fraction, optimum: number | Fraction): string {
  return `${name}/${mechanism},${Fraction.from(revenue)},${Fraction.from(welfare)},${Fraction.from(welfare).divide(optimum)}`;
}

function validateLot(group: Group): string | null {
  if (group.participants.length === 0) return 'no bidders';
  const seen = new Set();
  for (const participant of group.participants) {
    if (seen.has(participant.name)) return 'duplicate bidder ' + participant.name;
    seen.add(participant.name);
  }
  for (const participant of group.participants) if (participant.bid > participant.value) return 'bid above value ' + participant.name;
  return null;
}

function highest(participants: Participant[], field: 'bid' | 'value', reserve: number): Participant | null {
  let best: Participant | null = null;
  for (const participant of participants) {
    if (participant[field] >= reserve && (best === null || participant[field] > best[field])) best = participant;
  }
  return best;
}

function lotResult(group: Group, reserve: number, winner: Participant | null, price: number, allPay = false): LotResult {
  const utilities = group.participants.map(participant => participant === winner ? participant.value - price :
    allPay && participant.bid >= reserve ? -participant.bid : 0);
  const revenue = allPay ? total(group.participants.filter(participant => participant.bid >= reserve).map(participant => participant.bid)) :
    winner === null ? 0 : price;
  return {winner, price, utilities, revenue, welfare: winner === null ? reserve : winner.value};
}

function lotLines(group: Group, parameters: Parameters): GroupReport {
  const error = validateLot(group);
  if (error !== null) return {error, lines: [`LOT ${group.name} ERROR ${error}`], summary: []};
  const participants = group.participants;
  const reserve = Number(group.arguments[0]);
  const efficient = highest(participants, 'value', reserve);
  const optimum = efficient === null ? reserve : efficient.value;
  const first = highest(participants, 'bid', reserve);
  const second = highest(participants, 'value', reserve);
  const rival = highest(participants.filter(participant => participant !== second), 'value', reserve);
  const clock = auctions.english(participants, reserve, parameters.english_increment);
  const descending = auctions.dutch(participants, reserve, parameters.dutch_start, parameters.dutch_decrement);
  const formats: LotResult[] = [
    lotResult(group, reserve, first, first === null ? 0 : first.bid),
    lotResult(group, reserve, second, second === null ? 0 : rival === null ? reserve : rival.value),
    {...lotResult(group, reserve, clock.winner, clock.price), steps: clock.steps},
    {...lotResult(group, reserve, descending.winner, descending.price), steps: descending.steps},
    lotResult(group, reserve, first, first === null ? 0 : first.bid, true),
  ];
  const lines = [`LOT ${group.name} reserve ${reserve} bidders ${participants.length} efficient ${efficient === null ? '-' : efficient.name} optimum ${optimum}`];
  const summary: string[] = [];
  for (let index = 0; index < formats.length; index++) {
    const result = formats[index];
    let line = lotFormats[index].toUpperCase();
    if (result.winner === null) line += ' unsold';
    else line += ` winner ${result.winner.name} price ${result.price} utility ${result.utilities[result.winner.order]}`;
    if (index === 2 || index === 3) line += ` steps ${result.steps}`;
    line += ` revenue ${result.revenue} welfare ${result.welfare} efficiency ${new Fraction(result.welfare, optimum)}`;
    lines.push(line);
    if (index === 2) {
      lines.push('ENGLISH_DROPS ' + participants.map(participant =>
        `${participant.name}=${clock.drops[participant.order] === null ? '-' : clock.drops[participant.order]}`).join(' '));
    }
    summary.push(summaryRow(group.name, lotFormats[index], result.revenue, result.welfare, optimum));
  }
  for (const participant of participants) {
    lines.push(`UTILITY ${participant.name} ${formats.map(result => result.utilities[participant.order]).join(' ')}`);
  }
  const ranking = formats.map((result, index) => ({...result, index}));
  ranking.sort((a, b) => b.revenue - a.revenue || a.index - b.index);
  lines.push('RANKING ' + ranking.map(result => lotFormats[result.index]).join(' '));
  return {error: null, lines, summary};
}

function validateSlots(group: Group): {error?: string; rates?: Fraction[]} {
  const rates: Fraction[] = [];
  for (const text of group.arguments) {
    const match = /^([1-9][0-9]*)\/([1-9][0-9]*)$/.exec(text);
    if (match === null || match[0].length !== text.length) return {error: 'bad ctr ' + text};
    const rate = new Fraction(match[1], match[2]);
    if (rate.compare(1) > 0 || (rates.length > 0 && rate.compare(rates.at(-1)!) >= 0)) return {error: 'bad ctr ' + text};
    rates.push(rate);
  }
  if (group.participants.length === 0) return {error: 'no advertisers'};
  const seen = new Set();
  for (const participant of group.participants) {
    if (seen.has(participant.name)) return {error: 'duplicate advertiser ' + participant.name};
    seen.add(participant.name);
  }
  return {rates};
}

function slotLines(group: Group): GroupReport {
  const checked = validateSlots(group);
  if (checked.error) return {error: checked.error, lines: [`SLOTS ${group.name} ERROR ${checked.error}`], summary: []};
  const rates = checked.rates!;
  const zero = new Fraction(0);
  const rate = (rank: number): Fraction => rank <= rates.length ? rates[rank - 1] : zero;
  const gsp = group.participants.slice().sort((a, b) => b.bid - a.bid || a.order - b.order);
  const vcg = group.participants.slice().sort((a, b) => b.value - a.value || a.order - b.order);
  const bidAt = (rank: number): number => rank <= gsp.length ? gsp[rank - 1].bid : 0;
  const count = Math.min(rates.length, gsp.length);
  let gspRevenue = zero;
  let gspWelfare = zero;
  let vcgRevenue = zero;
  let optimum = zero;
  const gspLines: string[] = [];
  const vcgLines: string[] = [];
  for (let rank = 1; rank <= count; rank++) {
    const participant = gsp[rank - 1];
    const price = payments.gspPrice(gsp, rank);
    const payment = rate(rank).multiply(price);
    const utility = rate(rank).multiply(participant.value - price);
    gspRevenue = gspRevenue.add(payment);
    gspWelfare = gspWelfare.add(rate(rank).multiply(participant.value));
    gspLines.push(`GSP ${rank} ${participant.name} ctr ${rate(rank)} bid ${participant.bid} price ${price} payment ${payment} utility ${utility}`);
    const efficient = vcg[rank - 1];
    const vcgPayment = payments.slotVCG(vcg, rates, rank);
    const value = rate(rank).multiply(efficient.value);
    vcgRevenue = vcgRevenue.add(vcgPayment);
    optimum = optimum.add(value);
    vcgLines.push(`VCG ${rank} ${efficient.name} ctr ${rate(rank)} value ${efficient.value} payment ${vcgPayment} ` +
      `price ${vcgPayment.divide(rate(rank))} utility ${value.subtract(vcgPayment)}`);
  }
  const lines = [`SLOTS ${group.name} slots ${rates.length} advertisers ${gsp.length}`];
  for (const line of gspLines) lines.push(line);
  lines.push(`GSP_TOTAL revenue ${gspRevenue} welfare ${gspWelfare} efficiency ${gspWelfare.divide(optimum)}`);
  for (const line of vcgLines) lines.push(line);
  lines.push(`VCG_TOTAL revenue ${vcgRevenue} welfare ${optimum} efficiency 1`);
  let violations = 0;
  for (let rank = 2; rank <= Math.min(gsp.length, rates.length + 1); rank++) {
    const participant = gsp[rank - 1];
    const stay = rate(rank).multiply(participant.value - bidAt(rank + 1));
    const swap = rate(rank - 1).multiply(participant.value - bidAt(rank));
    const violated = stay.compare(swap) < 0;
    if (violated) violations++;
    lines.push(`ENVY ${rank} ${participant.name} stay ${stay} swap ${swap} ${violated ? 'violated' : 'ok'}`);
  }
  lines.push(violations === 0 ? 'ENVY_FREE yes' : `ENVY_FREE no violations ${violations}`);
  let deviations = 0;
  for (let rank = 1; rank <= gsp.length; rank++) {
    const participant = gsp[rank - 1];
    const current = rate(rank).multiply(participant.value - bidAt(rank + 1));
    for (let slot = 1; slot <= rates.length; slot++) {
      if (slot === rank) continue;
      const price = slot < rank ? bidAt(slot) : bidAt(slot + 1);
      const moving = rate(slot).multiply(participant.value - price);
      const gain = moving.subtract(current);
      if (gain.compare(0) > 0) {
        deviations++;
        lines.push(`DEVIATE ${participant.name} from ${rank} to ${slot} gain ${gain}`);
      }
    }
  }
  lines.push(deviations === 0 ? 'NASH yes' : `NASH no deviations ${deviations}`);
  const equilibrium = violations === 0 && deviations === 0;
  lines.push(`EQUILIBRIUM ${equilibrium ? 'yes' : 'no'}`);
  return {error: null, lines, envyFree: violations === 0, nash: deviations === 0, equilibrium,
    summary: [summaryRow(group.name, 'gsp', gspRevenue, gspWelfare, optimum), summaryRow(group.name, 'vcg', vcgRevenue, optimum, optimum)]};
}

function appendLines(target: string[], source: string[]): void {
  for (const line of source) target.push(line);
}

function main(): void {
  const input = io.readInputs();
  const {parameters} = input;
  const files: Record<string, string[]> = {'wdp.txt': [], 'vcg.txt': [], 'core_check.txt': [], 'ascending_log.txt': [],
    'single_item.txt': [], 'summary.csv': ['mechanism,revenue,welfare,efficiency']};
  const totals = {bids: 0, valid: 0, eligible: 0, nodes: 0, greedyOptimal: 0,
    vcg: 0, payAsBid: 0, greedy: 0, critical: 0, saa: 0, rounds: 0, capped: 0, exposed: 0, exposure: 0};
  const core: Record<string, number> = {checked: 0, skipped: 0, vcg: 0, greedy: 0, critical: 0, saa: 0};
  for (const name of parameters.run) {
    const auction = validateAuction(input.auctions.get(name)!, input.items, parameters);
    const result = analyzeAuction(auction, parameters);
    appendLines(files['wdp.txt'], wdpLines(result));
    appendLines(files['vcg.txt'], vcgLines(result));
    appendLines(files['ascending_log.txt'], result.saa.lines);
    const checked = coreLines(result, parameters.core_max_bidders);
    appendLines(files['core_check.txt'], checked.lines);
    if (checked.checked) {
      core.checked++;
      for (const outcome of outcomeNames) if (checked.membership![outcome]) core[outcome]++;
    } else core.skipped++;
    const {optimal, greedy, saa} = result;
    for (const [mechanism, revenue, welfare] of ([
      ['vcg', result.vcgRevenue, optimal.welfare], ['pay_as_bid', optimal.accepted, optimal.welfare],
      ['greedy', greedy.accepted, greedy.welfare], ['critical', result.criticalRevenue, greedy.welfare],
      ['saa', saa.revenue, saa.welfare],
    ] as [string, number, number][])) files['summary.csv'].push(summaryRow(name, mechanism, revenue, welfare, optimal.welfare));
    totals.bids += auction.totalBids;
    totals.valid += auction.valid.length;
    totals.eligible += auction.eligible.length;
    totals.nodes += result.search.stats.nodes;
    if (greedy.welfare === optimal.welfare) totals.greedyOptimal++;
    totals.vcg += result.vcgRevenue;
    totals.payAsBid += optimal.accepted;
    totals.greedy += greedy.accepted;
    totals.critical += result.criticalRevenue;
    totals.saa += saa.revenue;
    totals.rounds += saa.rounds;
    if (saa.reason === 'cap') totals.capped++;
    totals.exposed += saa.exposed;
    totals.exposure += saa.exposure;
  }
  files['wdp.txt'].push(`TOTAL auctions ${parameters.run.length} bids ${totals.bids} valid ${totals.valid} eligible ${totals.eligible} ` +
    `nodes ${totals.nodes} greedy_optimal ${totals.greedyOptimal}`);
  files['vcg.txt'].push(`OVERALL vcg ${totals.vcg} pay_as_bid ${totals.payAsBid} greedy ${totals.greedy} critical ${totals.critical} saa ${totals.saa}`);
  files['core_check.txt'].push(`SUMMARY checked ${core.checked} skipped ${core.skipped} vcg ${core.vcg} greedy ${core.greedy} critical ${core.critical} saa ${core.saa}`);
  files['ascending_log.txt'].push(`SUMMARY auctions ${parameters.run.length} rounds ${totals.rounds} capped ${totals.capped} exposed ${totals.exposed} exposure ${totals.exposure}`);
  const groups = {lots: 0, slots: 0, errors: 0, envyFree: 0, nash: 0, equilibria: 0};
  for (const group of input.groups) {
    const result = group.kind === 'lot' ? lotLines(group, parameters) : slotLines(group);
    if (group.kind === 'lot') groups.lots++;
    else groups.slots++;
    if (result.error !== null) groups.errors++;
    else if (group.kind === 'slots') {
      if (result.envyFree) groups.envyFree++;
      if (result.nash) groups.nash++;
      if (result.equilibrium) groups.equilibria++;
    }
    appendLines(files['single_item.txt'], result.lines);
    appendLines(files['summary.csv'], result.summary);
  }
  files['single_item.txt'].push(`SUMMARY lots ${groups.lots} slot_groups ${groups.slots} errors ${groups.errors} ` +
    `envy_free ${groups.envyFree} nash ${groups.nash} equilibria ${groups.equilibria}`);
  report.writeFiles(files);
}

main();
