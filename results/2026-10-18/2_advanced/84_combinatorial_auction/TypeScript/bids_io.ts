import { readFileSync } from 'node:fs';
import type { Item, Bidder, RawAuction, Group, Parameters, InputData } from './types.ts';

function lines(name: string): string[] {
  return readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
}

export class Bid {
  number: number; bidder: Bidder; items: Item[]; amount: number;
  xor: boolean; mask: number; reserve: number; size: number;
  constructor(number: number, bidder: Bidder, items: Item[], amount: number) {
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

export function readInputs(): InputData {
  const items = lines('items.txt').map((line, number) => {
    const [name, reserve] = line.split(' ');
    return {name, reserve: Number(reserve), number, bit: 1 << number};
  });
  const auctions = new Map<string, RawAuction>();
  let auction: RawAuction | null = null;
  for (const line of lines('bids.txt')) {
    const [kind, name, ...values] = line.split(' ');
    if (kind === 'auction') {
      auction = {name, offered: values, lines: []};
      auctions.set(name, auction);
    } else auction!.lines.push({name, language: values[0], bids: values.slice(1)});
  }
  const groups: Group[] = [];
  let group: Group | null = null;
  for (const line of lines('single_item.txt')) {
    const [kind, name, ...values] = line.split(' ');
    if (kind === 'lot' || kind === 'slots') {
      group = {kind, name, arguments: values, participants: []};
      groups.push(group);
    } else {
      group!.participants.push({name, value: Number(values[0]), bid: Number(values[1]), order: group!.participants.length});
    }
  }
  const parameters = {} as Parameters & Record<string, number | string[]>;
  for (const line of lines('params.txt')) {
    const [key, ...values] = line.split(' ');
    parameters[key] = key === 'run' ? values : Number(values[0]);
  }
  return {items, auctions, groups, parameters};
}

