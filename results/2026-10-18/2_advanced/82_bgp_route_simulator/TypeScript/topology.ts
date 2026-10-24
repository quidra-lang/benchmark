import { readFileSync } from 'node:fs';
import type { Prefix, Topology, Link, Session, AutonomousSystem, Relationship, Origin, NeighborRole } from './types.ts';

const prefixCache = new Map<string, Prefix>();

export function addressValue(text: string): number {
  return text.split('.').reduce((value, part) => value * 256 + Number(part), 0);
}

export function prefixValue(text: string): Prefix {
  if (!prefixCache.has(text)) {
    const [address, length] = text.split('/');
    prefixCache.set(text, { text, address, value: addressValue(address), length: Number(length), unit: 2 ** (32 - Number(length)) });
  }
  return prefixCache.get(text)!;
}

export function prefixCompare(a: string, b: string): number {
  const first = prefixValue(a), second = prefixValue(b);
  return first.value - second.value || first.length - second.length;
}

export const contains = (prefix: Prefix, address: number): boolean => Math.floor(address / prefix.unit) === Math.floor(prefix.value / prefix.unit);
export const otherEnd = (link: Link, asn: number): number => asn === link.a ? link.b : link.a;
export const role = (link: Link, asn: number): NeighborRole => link.relationship === 'P2P' ? 'peer' : asn === link.a ? 'customer' : 'provider';
export const direction = (link: Link, asn: number): string => ({ customer: 'D', peer: 'P', provider: 'U' })[role(link, asn)];

export function readTopology(path: string): Topology {
  const ases = new Map<number, AutonomousSystem>();
  const links: Link[] = [];
  const linkByName = new Map<string, Link>();
  const initial: Topology['initial'] = [];
  for (const line of readFileSync(path, 'ascii').split('\n').slice(0, -1)) {
    const [kind, ...fields] = line.split(' ');
    if (kind === 'AS') {
      const asn = Number(fields[0]);
      ases.set(asn, { asn, routerId: addressValue(fields[1]), sessions: [], origination: new Map(), rib: new Map(), changes: 0 });
    } else if (kind === 'LINK') {
      const [name, a, b, relationship, delay, mrai] = fields;
      const link: Link = { name, a: Number(a), b: Number(b), relationship: relationship as Relationship, delay: Number(delay), mrai: Number(mrai),
        number: links.length, up: true, downs: 0, sessions: new Map<number, Session>() };
      links.push(link); linkByName.set(name, link);
      for (const asn of [link.a, link.b]) {
        const session: Session = { owner: ases.get(asn)!, neighbor: otherEnd(link, asn), link, input: new Map(), output: new Map(),
          pending: new Set(), timer: null, sent: 0, received: 0 };
        ases.get(asn)!.sessions.push(session); link.sessions.set(asn, session);
      }
    } else {
      const [asn, prefix, origin, ...communities] = fields;
      initial.push({ asn: Number(asn), prefix, origin: origin as Origin, communities });
    }
  }
  const asOrder = Array.from(ases.values()).sort((a, b) => a.asn - b.asn);
  return { ases, asOrder, links, linkByName, initial, sessions: asOrder.flatMap(as => as.sessions) };
}

export function connectingLink(topology: Topology, first: number, second: number): Link {
  return topology.ases.get(first)!.sessions.find(session => session.neighbor === second)!.link;
}

