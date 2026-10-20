'use strict';

const fs = require('node:fs');
const prefixCache = new Map();

function addressValue(text) {
  return text.split('.').reduce((value, part) => value * 256 + Number(part), 0);
}

function prefixValue(text) {
  if (!prefixCache.has(text)) {
    const [address, length] = text.split('/');
    prefixCache.set(text, { text, address, value: addressValue(address), length: Number(length), unit: 2 ** (32 - Number(length)) });
  }
  return prefixCache.get(text);
}

function prefixCompare(a, b) {
  const first = prefixValue(a), second = prefixValue(b);
  return first.value - second.value || first.length - second.length;
}

const contains = (prefix, address) => Math.floor(address / prefix.unit) === Math.floor(prefix.value / prefix.unit);
const otherEnd = (link, asn) => asn === link.a ? link.b : link.a;
const role = (link, asn) => link.relationship === 'P2P' ? 'peer' : asn === link.a ? 'customer' : 'provider';
const direction = (link, asn) => ({ customer: 'D', peer: 'P', provider: 'U' })[role(link, asn)];

function readTopology(path) {
  const ases = new Map(), links = [], linkByName = new Map(), initial = [];
  for (const line of fs.readFileSync(path, 'ascii').split('\n').slice(0, -1)) {
    const [kind, ...fields] = line.split(' ');
    if (kind === 'AS') {
      const asn = Number(fields[0]);
      ases.set(asn, { asn, routerId: addressValue(fields[1]), sessions: [], origination: new Map(), rib: new Map(), changes: 0 });
    } else if (kind === 'LINK') {
      const [name, a, b, relationship, delay, mrai] = fields;
      const link = { name, a: Number(a), b: Number(b), relationship, delay: Number(delay), mrai: Number(mrai),
        number: links.length, up: true, downs: 0, sessions: new Map() };
      links.push(link); linkByName.set(name, link);
      for (const asn of [link.a, link.b]) {
        const session = { owner: ases.get(asn), neighbor: otherEnd(link, asn), link, input: new Map(), output: new Map(),
          pending: new Set(), timer: null, sent: 0, received: 0 };
        ases.get(asn).sessions.push(session); link.sessions.set(asn, session);
      }
    } else {
      const [asn, prefix, origin, ...communities] = fields;
      initial.push({ asn: Number(asn), prefix, origin, communities });
    }
  }
  const asOrder = Array.from(ases.values()).sort((a, b) => a.asn - b.asn);
  return { ases, asOrder, links, linkByName, initial, sessions: asOrder.flatMap(as => as.sessions) };
}

function connectingLink(topology, first, second) {
  return topology.ases.get(first).sessions.find(session => session.neighbor === second).link;
}

module.exports = { addressValue, prefixValue, prefixCompare, contains, otherEnd, role, direction, readTopology, connectingLink };
