'use strict';

function bitCount(mask) {
  let count = 0;
  while (mask !== 0) {
    mask &= mask - 1;
    count++;
  }
  return count;
}

function candidates(bidder) {
  const result = [];
  for (let number = 1; number < 2 ** bidder.valid.length; number++) {
    if (bidder.language === 'XOR' && bitCount(number) !== 1) continue;
    let mask = 0;
    let value = 0;
    let valid = true;
    for (let index = 0; index < bidder.valid.length; index++) {
      if ((number & (1 << index)) === 0) continue;
      const bid = bidder.valid[index];
      if ((mask & bid.mask) !== 0) {
        valid = false;
        break;
      }
      mask |= bid.mask;
      value += bid.amount;
    }
    if (valid) result.push({number, mask, value, size: bitCount(mask)});
  }
  return result;
}

function valueOf(candidates, mask) {
  let value = 0;
  for (const candidate of candidates) {
    if ((candidate.mask & mask) === candidate.mask) value = Math.max(value, candidate.value);
  }
  return value;
}

function english(participants, reserve, increment) {
  let price = reserve;
  let steps = 0;
  const drops = participants.map(() => null);
  const remainingAt = current => {
    for (const participant of participants) {
      if (participant.value < current && drops[participant.order] === null) drops[participant.order] = current;
    }
    return participants.filter(participant => participant.value >= current);
  };
  let remaining = remainingAt(price);
  if (remaining.length === 0) return {winner: null, price: 0, steps, drops};
  while (remaining.length > 1) {
    const previous = remaining;
    price += increment;
    steps++;
    remaining = remainingAt(price);
    if (remaining.length === 0) return {winner: previous[0], price: price - increment, steps, drops};
  }
  return {winner: remaining[0], price, steps, drops};
}

function dutch(participants, reserve, start, decrement) {
  let price = start;
  let steps = 0;
  while (price >= reserve) {
    let winner = null;
    for (const participant of participants) {
      if (participant.bid >= price && (winner === null || participant.bid > winner.bid)) winner = participant;
    }
    if (winner !== null) return {winner, price, steps};
    price -= decrement;
    steps++;
  }
  return {winner: null, price: 0, steps};
}

module.exports = {bitCount, candidates, valueOf, english, dutch};
