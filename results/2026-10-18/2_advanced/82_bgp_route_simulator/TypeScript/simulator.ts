import type { Message, Session, Link, Attribute, Event, Params } from './types.ts';

import * as fs from 'node:fs';
import { addressValue } from './topology.ts';
export const deliveryCompare = (a: Message, b: Message): number => a.arrival - b.arrival || a.receiver - b.receiver || a.sender - b.sender || a.serial - b.serial;

export class MessageQueue {
  heap: Message[];
  serial: number;
  constructor() { this.heap = []; this.serial = 0; }
  get length(): number { return this.heap.length; }
  get nextTime(): number | null { return this.heap.length ? this.heap[0].arrival : null; }
  push(message: Message): void {
    let i = this.heap.length;
    this.heap.push(message);
    while (i > 0) {
      const parent = Math.floor((i - 1) / 2);
      if (deliveryCompare(this.heap[parent], message) <= 0) break;
      this.heap[i] = this.heap[parent]; i = parent;
    }
    this.heap[i] = message;
  }
  pop(): Message {
    const first = this.heap[0], last = this.heap.pop()!;
    if (this.heap.length) {
      let i = 0;
      while (2 * i + 1 < this.heap.length) {
        let child = 2 * i + 1;
        if (child + 1 < this.heap.length && deliveryCompare(this.heap[child + 1], this.heap[child]) < 0) child++;
        if (deliveryCompare(last, this.heap[child]) <= 0) break;
        this.heap[i] = this.heap[child]; i = child;
      }
      this.heap[i] = last;
    }
    return first;
  }
  send(time: number, session: Session, prefix: string, content: Attribute | null): Message {
    const message = { serial: ++this.serial, sender: session.owner.asn, receiver: session.neighbor,
      link: session.link, prefix, content, arrival: time + session.link.delay };
    this.push(message); return message;
  }
  takeTime(time: number): Message[] {
    const result = [];
    while (this.nextTime === time) result.push(this.pop());
    return result;
  }
  ordered(): Message[] { return this.heap.slice().sort(deliveryCompare); }
  removeLink(link: Link): Message[] {
    const removed = [], retained = [];
    for (const message of this.ordered()) (message.link === link ? removed : retained).push(message);
    this.heap = [];
    for (const message of retained) this.push(message);
    return removed;
  }
}

export function readEvents(path: string): Event[] {
  const events = [{ number: 0, time: 0, text: 'INITIAL', fields: ['INITIAL'], kind: 'INITIAL' }];
  for (const line of fs.readFileSync(path, 'ascii').split('\n').slice(0, -1)) {
    const separator = line.indexOf(' '), time = Number(line.slice(0, separator)), text = line.slice(separator + 1);
    const fields = text.split(' '), kind = fields[0] === 'LINK' || fields[0] === 'POLICY' ? fields[0] + '_' + fields[1] : fields[0];
    events.push({ number: events.length, time, text, fields, kind });
  }
  return events;
}

export function readParams(path: string): Params {
  const lines = fs.readFileSync(path, 'ascii').split('\n').slice(0, -1), values = lines[0].split(' ').slice(1).map(Number);
  return { preferences: { customer: values[0], peer: values[1], provider: values[2] }, cap: Number(lines[1].split(' ')[1]),
    traces: lines.slice(2).map((line, index) => { const [, asn, address] = line.split(' '); return { index, asn: Number(asn), address, value: addressValue(address) }; }) };
}

