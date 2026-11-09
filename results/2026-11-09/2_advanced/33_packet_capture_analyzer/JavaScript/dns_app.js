'use strict';

const { Malformed, uint, ipv4 } = require('./link_network');

const TYPE_NAMES = new Map([[1, 'A'], [2, 'NS'], [5, 'CNAME'], [6, 'SOA'], [12, 'PTR'], [15, 'MX'], [16, 'TXT'], [28, 'AAAA']]);

function typeName(type) {
  return TYPE_NAMES.get(type) ?? `TYPE${type}`;
}

function rcodeName(code) {
  return ['NoError', 'FormErr', 'ServFail', 'NXDomain', 'NotImp', 'Refused'][code] ?? `RCODE${code}`;
}

function ipv6(bytes) {
  const groups = [];
  for (let index = 0; index < 16; index += 2) groups.push(uint(bytes, index));
  let bestStart = -1;
  let bestLength = 1;
  for (let index = 0; index < groups.length;) {
    if (groups[index] !== 0) {
      index++;
      continue;
    }
    let end = index;
    while (end < groups.length && groups[end] === 0) end++;
    if (end - index > bestLength) {
      bestStart = index;
      bestLength = end - index;
    }
    index = end;
  }
  const text = groups.map(value => value.toString(16));
  if (bestStart < 0) return text.join(':');
  return `${text.slice(0, bestStart).join(':')}::${text.slice(bestStart + bestLength).join(':')}`;
}

function dissect(message) {
  function requireBytes(position, count) {
    if (position < 0 || position + count > message.length) throw new Malformed('dns: truncated');
  }
  function read(position, count = 2) {
    requireBytes(position, count);
    return uint(message, position, count);
  }
  function name(position) {
    const labels = [];
    let after = null;
    let pointers = 0;
    while (true) {
      const length = read(position, 1);
      if (length === 0) {
        if (after === null) after = position + 1;
        return { text: labels.length ? labels.join('.') : '<root>', after };
      }
      if (length >= 192) {
        const low = read(position + 1, 1);
        if (after === null) after = position + 2;
        pointers++;
        if (pointers > 16) throw new Malformed('dns: compression loop');
        const target = (length - 192) * 256 + low;
        if (target >= message.length) throw new Malformed('dns: pointer out of range');
        position = target;
      } else if (length >= 64) {
        throw new Malformed('dns: bad label type');
      } else {
        requireBytes(position + 1, length);
        let label = '';
        for (let index = position + 1; index <= position + length; index++) {
          const byte = message[index];
          label += byte >= 33 && byte <= 126 && byte !== 46 && byte !== 92
            ? String.fromCharCode(byte) : '\\' + String(byte).padStart(3, '0');
        }
        labels.push(label);
        position += length + 1;
      }
    }
  }
  function rdata(type, start, length) {
    if (type === 1) {
      const address = read(start, 4);
      return { text: ipv4(address), after: start + 4, address };
    }
    if (type === 28) {
      requireBytes(start, 16);
      return { text: ipv6(message.slice(start, start + 16)), after: start + 16 };
    }
    if (type === 2 || type === 5 || type === 12) return name(start);
    if (type === 15) {
      const preference = read(start);
      const target = name(start + 2);
      return { text: `${preference} ${target.text}`, after: target.after };
    }
    if (type === 6) {
      const primary = name(start);
      const mailbox = name(primary.after);
      const parts = [primary.text, mailbox.text];
      let position = mailbox.after;
      for (let index = 0; index < 5; index++) {
        parts.push(String(read(position, 4)));
        position += 4;
      }
      return { text: parts.join(' '), after: position };
    }
    return { text: `${length} bytes`, after: start + length };
  }
  function append(field, value) {
    (fields[field] ??= []).push(value);
  }

  requireBytes(0, 12);
  const flags = read(2);
  const questions = read(4);
  const counts = [read(6), read(8), read(10)];
  const fields = {
    'dns.id': [read(0)], 'dns.flags': [flags], 'dns.flags.response': [Math.floor(flags / 32768) % 2],
    'dns.flags.opcode': [Math.floor(flags / 2048) % 16], 'dns.flags.rcode': [flags % 16],
    'dns.count.queries': [questions], 'dns.count.answers': [counts[0]],
    'dns.count.auth_rr': [counts[1]], 'dns.count.add_rr': [counts[2]]
  };
  const answers = [];
  let position = 12;
  for (let index = 0; index < questions; index++) {
    const question = name(position);
    requireBytes(question.after, 4);
    append('dns.qry.name', question.text);
    append('dns.qry.type', read(question.after));
    position = question.after + 4;
  }
  for (let section = 0; section < 3; section++) {
    const field = ['dns.answer', 'dns.authority', 'dns.additional'][section];
    for (let index = 0; index < counts[section]; index++) {
      const owner = name(position);
      requireBytes(owner.after, 10);
      const type = read(owner.after);
      const recordClass = read(owner.after + 2);
      const ttl = read(owner.after + 4, 4);
      const length = read(owner.after + 8);
      const start = owner.after + 10;
      requireBytes(start, length);
      const value = rdata(type, start, length);
      if (value.after !== start + length) throw new Malformed('dns: bad rdata length');
      const className = recordClass === 1 ? 'IN' : `CLASS${recordClass}`;
      append(field, `${owner.text} ${typeName(type)} ${className} ${ttl} ${value.text}`);
      if (section === 0) {
        answers.push({ type, text: value.text });
        if (type === 1) append('dns.a', value.address);
      }
      position = start + length;
    }
  }
  return { fields, payload: [], answers };
}

module.exports = { dissect, typeName, rcodeName };
