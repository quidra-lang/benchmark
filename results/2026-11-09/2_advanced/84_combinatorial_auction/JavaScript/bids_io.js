'use strict';

const fs = require('node:fs');

function lines(name) {
  return fs.readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
}

class Bid {
  constructor(number, bidder, items, amount) {
    this.number = number;
    this.bidder = bidder;
    this.items = items;
    this.amount = amount;
    this.xor = bidder.language === 'XOR';
    this.mask = 0;
    this.reserve = 0;
    for (const item of items) {
      this.mask |= item.bit;
      this.reserve += item.reserve;
    }
    this.size = items.length;
  }
}

function readInputs() {
  const items = lines('items.txt').map((line, number) => {
    const [name, reserve] = line.split(' ');
    return {name, reserve: Number(reserve), number, bit: 1 << number};
  });
  const auctions = new Map();
  let auction;
  for (const line of lines('bids.txt')) {
    const [kind, name, ...values] = line.split(' ');
    if (kind === 'auction') {
      auction = {name, offered: values, lines: []};
      auctions.set(name, auction);
    } else auction.lines.push({name, language: values[0], bids: values.slice(1)});
  }
  const groups = [];
  let group;
  for (const line of lines('single_item.txt')) {
    const [kind, name, ...values] = line.split(' ');
    if (kind === 'lot' || kind === 'slots') {
      group = {kind, name, arguments: values, participants: []};
      groups.push(group);
    } else {
      group.participants.push({name, value: Number(values[0]), bid: Number(values[1]), order: group.participants.length});
    }
  }
  const parameters = {};
  for (const line of lines('params.txt')) {
    const [key, ...values] = line.split(' ');
    parameters[key] = key === 'run' ? values : Number(values[0]);
  }
  return {items, auctions, groups, parameters};
}

module.exports = {Bid, readInputs};
