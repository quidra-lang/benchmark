'use strict';

const fs = require('node:fs');
const hexdump = require('./hexdump');
const network = require('./link_network');
const transport = require('./transport');
const dns = require('./dns_app');
const flows = require('./flows');

const FIELD_ORDER = [
  ['frame.number', 'integer'], ['frame.time', 'integer'], ['frame.len', 'integer'],
  ['frame.protocols', 'string'], ['frame.malformed', 'string'], ['frame.bad_checksum', 'presence'],
  ['eth.dst', 'MAC'], ['eth.src', 'MAC'], ['eth.type', 'hex4'],
  ['arp.opcode', 'integer'], ['arp.src.hw', 'MAC'], ['arp.src.ip', 'IPv4'], ['arp.dst.hw', 'MAC'], ['arp.dst.ip', 'IPv4'],
  ['ip.hdr_len', 'integer'], ['ip.tos', 'hex2'], ['ip.len', 'integer'], ['ip.id', 'hex4'],
  ['ip.flags.df', 'integer'], ['ip.flags.mf', 'integer'], ['ip.frag_offset', 'integer'],
  ['ip.ttl', 'integer'], ['ip.proto', 'integer'], ['ip.checksum', 'hex4'], ['ip.checksum.status', 'string'],
  ['ip.src', 'IPv4'], ['ip.dst', 'IPv4'], ['ip.fragment', 'presence'],
  ['icmp.type', 'integer'], ['icmp.code', 'integer'], ['icmp.checksum', 'hex4'],
  ['icmp.checksum.status', 'string'], ['icmp.id', 'integer'], ['icmp.seq', 'integer'],
  ['udp.srcport', 'integer'], ['udp.dstport', 'integer'], ['udp.length', 'integer'],
  ['udp.checksum', 'hex4'], ['udp.checksum.status', 'string'],
  ['tcp.srcport', 'integer'], ['tcp.dstport', 'integer'], ['tcp.stream', 'integer'],
  ['tcp.seq', 'integer'], ['tcp.seq_raw', 'integer'], ['tcp.ack', 'integer'], ['tcp.ack_raw', 'integer'],
  ['tcp.hdr_len', 'integer'], ['tcp.flags', 'hex2'], ['tcp.flags.fin', 'integer'], ['tcp.flags.syn', 'integer'],
  ['tcp.flags.rst', 'integer'], ['tcp.flags.psh', 'integer'], ['tcp.flags.ack', 'integer'], ['tcp.flags.urg', 'integer'],
  ['tcp.window', 'integer'], ['tcp.window.calc', 'integer'], ['tcp.checksum', 'hex4'],
  ['tcp.checksum.status', 'string'], ['tcp.urgent', 'integer'], ['tcp.option', 'string'],
  ['tcp.options.mss', 'integer'], ['tcp.options.wscale', 'integer'], ['tcp.options.malformed', 'presence'],
  ['tcp.len', 'integer'], ['tcp.analysis.retransmission', 'presence'], ['tcp.analysis.out_of_order', 'presence'],
  ['tcp.analysis.lost_segment', 'presence'], ['tcp.analysis.duplicate_ack', 'presence'],
  ['dns.id', 'hex4'], ['dns.flags', 'hex4'], ['dns.flags.response', 'integer'],
  ['dns.flags.opcode', 'integer'], ['dns.flags.rcode', 'integer'], ['dns.count.queries', 'integer'],
  ['dns.count.answers', 'integer'], ['dns.count.auth_rr', 'integer'], ['dns.count.add_rr', 'integer'],
  ['dns.qry.name', 'string'], ['dns.qry.type', 'integer'], ['dns.answer', 'string'],
  ['dns.authority', 'string'], ['dns.additional', 'string'], ['dns.a', 'IPv4'], ['data.len', 'integer']
];
const ALIASES = new Map([
  ['eth.addr', ['eth.dst', 'eth.src']], ['ip.addr', ['ip.src', 'ip.dst']],
  ['udp.port', ['udp.srcport', 'udp.dstport']], ['tcp.port', ['tcp.srcport', 'tcp.dstport']]
]);
const PROTOCOLS = ['eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns', 'data'];
const FIELD_TYPES = new Map(FIELD_ORDER);
for (const [name, members] of ALIASES) FIELD_TYPES.set(name, FIELD_TYPES.get(members[0]));
for (const name of PROTOCOLS) FIELD_TYPES.set(name, 'presence');
const CHECKSUMS = [['ip', 'IPv4'], ['icmp', 'ICMP'], ['udp', 'UDP'], ['tcp', 'TCP']];
const COMPARISONS = new Set(['==', '!=', '<', '>', '<=', '>=']);

function get(packet, field) {
  return packet.fields[field]?.[0];
}

function seconds(time) {
  return `${Math.floor(time / 1000000)}.${String(time % 1000000).padStart(6, '0')}`;
}

function notation(type, value) {
  if (type === 'hex2' || type === 'hex4') return '0x' + value.toString(16).padStart(type === 'hex2' ? 2 : 4, '0');
  if (type === 'MAC') return network.mac(value);
  if (type === 'IPv4') return network.ipv4(value);
  return String(value);
}

function dissectPacket(packet, firstTime) {
  packet.fields = {};
  packet.layers = [];
  packet.remaining = [];
  packet.dnsAnswers = [];
  let payload = packet.bytes;
  let layer = packet.reason === null ? 'eth' : null;
  while (layer !== null) {
    packet.layers.push(layer);
    let result;
    try {
      if (layer === 'eth') result = network.ethernet(payload);
      else if (layer === 'arp') result = network.arp(payload);
      else if (layer === 'ip') result = network.ip(payload);
      else if (layer === 'icmp') result = transport.icmp(payload);
      else if (layer === 'udp') result = transport.udp(payload, get(packet, 'ip.src'), get(packet, 'ip.dst'));
      else if (layer === 'tcp') result = transport.tcp(payload, get(packet, 'ip.src'), get(packet, 'ip.dst'));
      else result = dns.dissect(payload);
    } catch (error) {
      if (!(error instanceof network.Malformed)) throw error;
      packet.reason = error.message;
      break;
    }
    // A layer's fields become visible only after its entire dissection succeeds.
    Object.assign(packet.fields, result.fields);
    payload = result.payload;
    if (layer === 'eth') {
      const type = get(packet, 'eth.type');
      layer = type === 2054 ? 'arp' : type === 2048 ? 'ip' : null;
    } else if (layer === 'ip') {
      const protocol = get(packet, 'ip.proto');
      layer = get(packet, 'ip.fragment') !== undefined ? null
        : protocol === 1 ? 'icmp' : protocol === 17 ? 'udp' : protocol === 6 ? 'tcp' : null;
    } else if (layer === 'udp') {
      layer = get(packet, 'udp.srcport') === 53 || get(packet, 'udp.dstport') === 53 ? 'dns' : null;
    } else {
      if (layer === 'dns') packet.dnsAnswers = result.answers;
      layer = null;
    }
  }
  if (packet.reason === null && payload.length > 0) {
    packet.layers.push('data');
    packet.fields['data.len'] = [payload.length];
    packet.remaining = payload;
  }
  packet.fields['frame.number'] = [packet.number];
  packet.fields['frame.time'] = [packet.time - firstTime];
  packet.fields['frame.len'] = [packet.length];
  if (packet.layers.length) packet.fields['frame.protocols'] = [packet.layers.join(':')];
  if (packet.reason !== null) packet.fields['frame.malformed'] = [packet.reason];
  if (CHECKSUMS.some(([name]) => get(packet, `${name}.checksum.status`) === 'bad')) {
    packet.fields['frame.bad_checksum'] = [true];
  }
}

function tcpInfo(packet) {
  let prefix = '';
  if (packet.mark === 'retransmission') prefix = '[TCP Retransmission] ';
  else if (packet.mark === 'out_of_order') prefix = '[TCP Out-Of-Order] ';
  else if (packet.mark === 'lost_segment') prefix = '[TCP Previous segment not captured] ';
  else if (packet.mark === 'duplicate_ack') prefix = `[TCP Dup ACK ${packet.duplicateAck.original}#${packet.duplicateAck.count}] `;
  const flagNames = ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECE', 'CWR'];
  const flags = flagNames.filter((name, index) => Math.floor(get(packet, 'tcp.flags') / 2 ** index) % 2 === 1);
  let text = `${prefix}${get(packet, 'tcp.srcport')} -> ${get(packet, 'tcp.dstport')} [${flags.length ? flags.join(', ') : '<None>'}] Seq=${get(packet, 'tcp.seq')}`;
  if (get(packet, 'tcp.flags.ack') === 1) text += ` Ack=${get(packet, 'tcp.ack')}`;
  text += ` Win=${get(packet, 'tcp.window.calc')} Len=${get(packet, 'tcp.len')}`;
  for (const option of packet.fields['tcp.option'] ?? []) {
    const parts = option.split(' ');
    if (parts[0] === 'MSS') text += ` MSS=${parts[1]}`;
    else if (parts[0] === 'WS') text += ` WS=${2 ** Number(parts[1])}`;
    else if (parts[0] === 'SACK_PERM') text += ' SACK_PERM';
    else if (parts[0] === 'TS') text += ` TSval=${parts[1]} TSecr=${parts[2]}`;
  }
  return text;
}

function dnsInfo(packet) {
  let text = get(packet, 'dns.flags.response') === 1 ? 'Response' : 'Query';
  text += ` ${notation('hex4', get(packet, 'dns.id'))}`;
  const rcode = get(packet, 'dns.flags.rcode');
  if (rcode !== 0) text += ` ${dns.rcodeName(rcode)}`;
  const names = packet.fields['dns.qry.name'] ?? [];
  const types = packet.fields['dns.qry.type'] ?? [];
  for (let index = 0; index < names.length; index++) text += ` ${dns.typeName(types[index])} ${names[index]}`;
  for (const answer of packet.dnsAnswers) text += ` ${dns.typeName(answer.type)} ${answer.text}`;
  return text;
}

function summaryLine(packet) {
  const value = name => notation(FIELD_TYPES.get(name), get(packet, name));
  let source = '-';
  let destination = '-';
  if (get(packet, 'ip.src') !== undefined) {
    source = value('ip.src');
    destination = value('ip.dst');
  } else if (get(packet, 'eth.src') !== undefined) {
    source = value('eth.src');
    destination = value('eth.dst');
  }
  const lastLayer = packet.layers.filter(name => name !== 'data').at(-1);
  const protocol = { eth: 'ETH', arp: 'ARP', ip: 'IPv4', icmp: 'ICMP', udp: 'UDP', tcp: 'TCP', dns: 'DNS' }[lastLayer] ?? 'DUMP';
  let info = packet.reason;
  if (info === null) {
    if (lastLayer === 'eth') info = `EtherType ${value('eth.type')}`;
    else if (lastLayer === 'arp') {
      const opcode = get(packet, 'arp.opcode');
      info = opcode === 1 ? `Who has ${value('arp.dst.ip')}? Tell ${value('arp.src.ip')}`
        : opcode === 2 ? `${value('arp.src.ip')} is at ${value('arp.src.hw')}` : `Opcode ${opcode}`;
    } else if (lastLayer === 'ip') {
      info = get(packet, 'ip.fragment') === undefined ? `Protocol ${value('ip.proto')}`
        : `Fragment id=${value('ip.id')} off=${value('ip.frag_offset')}${get(packet, 'ip.flags.mf') === 1 ? ' MF' : ''}`;
    } else if (lastLayer === 'icmp') {
      const type = get(packet, 'icmp.type');
      info = type === 0 || type === 8 ? `Echo ${type === 8 ? 'request' : 'reply'} id=${value('icmp.id')} seq=${value('icmp.seq')}`
        : `Type ${type} code ${value('icmp.code')}`;
    } else if (lastLayer === 'udp') info = `${value('udp.srcport')} -> ${value('udp.dstport')} Len=${get(packet, 'udp.length') - 8}`;
    else if (lastLayer === 'tcp') info = tcpInfo(packet);
    else if (lastLayer === 'dns') info = dnsInfo(packet);
  }
  if (get(packet, 'tcp.options.malformed') !== undefined) info += ' [bad TCP options]';
  for (const [name, label] of CHECKSUMS) {
    if (get(packet, `${name}.checksum.status`) === 'bad') info += ` [bad ${label} checksum]`;
  }
  return `${packet.number} ${seconds(get(packet, 'frame.time'))} ${source} -> ${destination} ${protocol} ${packet.length} ${info}`;
}

class FilterError extends Error {}

function tokenize(expression) {
  const tokens = [];
  const keywords = new Map([['and', '&&'], ['or', '||'], ['not', '!']]);
  const pairs = new Set(['==', '!=', '<=', '>=', '&&', '||']);
  const wordCharacter = /[A-Za-z0-9._:]/;
  let index = 0;
  while (index < expression.length) {
    const character = expression[index];
    if (character === ' ') {
      index++;
      continue;
    }
    const column = index + 1;
    const pair = expression.slice(index, index + 2);
    if (pairs.has(pair)) {
      tokens.push({ kind: pair, text: pair, column });
      index += 2;
    } else if ('()!<>'.includes(character)) {
      tokens.push({ kind: character, text: character, column });
      index++;
    } else if (character === '"') {
      const end = expression.indexOf('"', index + 1);
      if (end < 0) throw new FilterError(`unterminated string at column ${column}`);
      tokens.push({ kind: 'string', text: expression.slice(index, end + 1), column });
      index = end + 1;
    } else if (wordCharacter.test(character)) {
      const start = index;
      while (index < expression.length && wordCharacter.test(expression[index])) index++;
      const text = expression.slice(start, index);
      tokens.push({ kind: keywords.get(text) ?? 'word', text, column });
    } else {
      throw new FilterError(`invalid character '${character}' at column ${column}`);
    }
  }
  return tokens;
}

function convertValue(token, type, field) {
  if (type === 'string' && token.kind === 'string') return token.text.slice(1, -1);
  if (token.kind === 'word') {
    if ((type === 'integer' || type === 'hex2' || type === 'hex4') && /^(?:[0-9]{1,15}|0x[0-9a-fA-F]{1,12})$/.test(token.text)) {
      return Number(token.text);
    }
    if (type === 'IPv4') {
      const parts = token.text.split('.');
      if (parts.length === 4 && parts.every(part => /^[0-9]{1,3}$/.test(part) && Number(part) <= 255)) {
        let value = 0;
        for (const part of parts) value = value * 256 + Number(part);
        return value;
      }
    }
    if (type === 'MAC') {
      const parts = token.text.split(':');
      if (parts.length === 6 && parts.every(part => /^[0-9a-fA-F]{2}$/.test(part))) {
        let value = 0;
        for (const part of parts) value = value * 256 + Number.parseInt(part, 16);
        return value;
      }
    }
  }
  throw new FilterError(`invalid value ${token.text} for ${field}`);
}

function parseFilter(source) {
  const tokens = tokenize(source);
  let index = 0;
  function take() {
    if (index === tokens.length) throw new FilterError('unexpected end of filter');
    return tokens[index++];
  }
  function unexpected(token) {
    throw new FilterError(`unexpected '${token.text}' at column ${token.column}`);
  }
  function expression() {
    let node = product();
    while (tokens[index]?.kind === '||') {
      index++;
      node = { kind: 'or', left: node, right: product() };
    }
    return node;
  }
  function product() {
    let node = negation();
    while (tokens[index]?.kind === '&&') {
      index++;
      node = { kind: 'and', left: node, right: negation() };
    }
    return node;
  }
  function negation() {
    if (tokens[index]?.kind === '!') {
      index++;
      return { kind: 'not', child: negation() };
    }
    const token = take();
    if (token.kind === '(') {
      const node = expression();
      const close = take();
      if (close.kind !== ')') unexpected(close);
      return node;
    }
    if (token.kind !== 'word') unexpected(token);
    const field = token.text;
    if (!FIELD_TYPES.has(field)) throw new FilterError(`unknown field ${field}`);
    const type = FIELD_TYPES.get(field);
    if (!COMPARISONS.has(tokens[index]?.kind)) return { kind: 'test', field, operator: null };
    const operator = take().kind;
    if (type === 'presence' || (type === 'string' && operator !== '==' && operator !== '!=')) {
      throw new FilterError(`operator ${operator} not allowed for ${field}`);
    }
    const literal = take();
    if (literal.kind !== 'word' && literal.kind !== 'string') unexpected(literal);
    return { kind: 'test', field, operator, value: convertValue(literal, type, field) };
  }
  const result = expression();
  if (index < tokens.length) unexpected(tokens[index]);
  return result;
}

function fieldValues(packet, field) {
  if (ALIASES.has(field)) return ALIASES.get(field).flatMap(name => packet.fields[name] ?? []);
  if (PROTOCOLS.includes(field)) return packet.layers.includes(field) ? [true] : [];
  return packet.fields[field] ?? [];
}

function matches(node, packet) {
  if (node.kind === 'or') return matches(node.left, packet) || matches(node.right, packet);
  if (node.kind === 'and') return matches(node.left, packet) && matches(node.right, packet);
  if (node.kind === 'not') return !matches(node.child, packet);
  const values = fieldValues(packet, node.field);
  if (node.operator === null) return values.length > 0;
  if (values.length === 0) return false;
  if (node.operator === '!=') return values.every(value => value !== node.value);
  return values.some(value => {
    if (node.operator === '==') return value === node.value;
    if (node.operator === '<') return value < node.value;
    if (node.operator === '>') return value > node.value;
    if (node.operator === '<=') return value <= node.value;
    return value >= node.value;
  });
}

function readRequests(filename) {
  const filters = [];
  const details = [];
  for (const line of fs.readFileSync(filename, 'ascii').split('\n')) {
    if (line === '' || line.startsWith('#')) continue;
    if (line.startsWith('FILTER ')) filters.push(line.slice(7));
    else details.push(Number(line.slice(7)));
  }
  return { filters, details };
}

function summaryLines(packets, filters) {
  const lines = packets.map(packet => packet.summary);
  for (const filter of filters) {
    lines.push('', `filter ${filter}`);
    let expression;
    try {
      expression = parseFilter(filter);
    } catch (error) {
      if (!(error instanceof FilterError)) throw error;
      lines.push(`error: ${error.message}`);
      continue;
    }
    let count = 0;
    for (const packet of packets) {
      if (matches(expression, packet)) {
        lines.push(packet.summary);
        count++;
      }
    }
    lines.push(`matched ${count} of ${packets.length}`);
  }
  return lines;
}

function detailLines(packets, requests) {
  const lines = [];
  for (const number of requests) {
    if (lines.length) lines.push('');
    if (number < 1 || number > packets.length) {
      lines.push(`packet ${number} not found`);
      continue;
    }
    const packet = packets[number - 1];
    lines.push(`packet ${packet.number}`);
    for (const layer of ['frame', ...packet.layers]) {
      lines.push(layer);
      for (const [name, type] of FIELD_ORDER) {
        if (!name.startsWith(layer + '.')) continue;
        for (const value of packet.fields[name] ?? []) {
          lines.push(type === 'presence' ? `  ${name}` : `  ${name} = ${notation(type, value)}`);
        }
      }
      if (layer === 'data') lines.push(...hexdump.dumpLines(packet.remaining).map(line => '  ' + line));
    }
  }
  return lines;
}

function dnsTransactions(packets) {
  const pending = [];
  const transactions = [];
  const names = new Map();
  const rcodes = Array(16).fill(0);
  let queries = 0;
  let responses = 0;
  for (const packet of packets) {
    if (get(packet, 'dns.id') === undefined) continue;
    if (get(packet, 'dns.flags.response') === 0) {
      queries++;
      pending.push(packet);
      for (const name of packet.fields['dns.qry.name'] ?? []) names.set(name, (names.get(name) ?? 0) + 1);
    } else {
      responses++;
      rcodes[get(packet, 'dns.flags.rcode')]++;
      const index = pending.findIndex(query => get(query, 'dns.id') === get(packet, 'dns.id')
        && get(query, 'ip.src') === get(packet, 'ip.dst') && get(query, 'udp.srcport') === get(packet, 'udp.dstport')
        && get(query, 'ip.dst') === get(packet, 'ip.src') && get(query, 'udp.dstport') === get(packet, 'udp.srcport'));
      if (index >= 0) {
        const [query] = pending.splice(index, 1);
        transactions.push(packet.time - query.time);
      }
    }
  }
  return { queries, responses, pending, transactions, names, rcodes };
}

function protocolLines(packets, dnsStats) {
  const hierarchy = Object.fromEntries(PROTOCOLS.map(name => [name, { packets: 0, bytes: 0 }]));
  const checksums = Object.fromEntries(CHECKSUMS.map(([name]) => [name, { good: 0, bad: 0, none: 0 }]));
  const malformed = Object.fromEntries(['dump', ...PROTOCOLS.filter(name => name !== 'data')].map(name => [name, 0]));
  const marks = Object.fromEntries(flows.MARKS.map(name => [name, 0]));
  let bytes = 0;
  for (const packet of packets) {
    bytes += packet.length;
    for (const layer of packet.layers) {
      hierarchy[layer].packets++;
      hierarchy[layer].bytes += packet.length;
    }
    for (const [name] of CHECKSUMS) {
      const status = get(packet, `${name}.checksum.status`);
      if (status !== undefined) checksums[name][status]++;
    }
    if (packet.reason !== null) malformed[packet.layers.at(-1) ?? 'dump']++;
    if (packet.mark) marks[packet.mark]++;
  }
  const lines = [`packets ${packets.length}`, `bytes ${bytes}`, `duration ${seconds(packets.at(-1).time - packets[0].time)}`, 'hierarchy'];
  for (const [name, indent] of [['eth', 0], ['arp', 2], ['ip', 2], ['icmp', 4], ['udp', 4], ['dns', 6], ['tcp', 4]]) {
    const item = hierarchy[name];
    lines.push(`${' '.repeat(indent)}${name} ${item.packets} ${item.bytes}`);
  }
  lines.push('checksums');
  for (const [name] of CHECKSUMS) {
    const counts = checksums[name];
    lines.push(`${name} good ${counts.good} bad ${counts.bad}${name === 'udp' ? ` none ${counts.none}` : ''}`);
  }
  lines.push('malformed');
  for (const name of ['dump', 'eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns']) lines.push(`${name} ${malformed[name]}`);
  lines.push('tcp analysis');
  for (const name of flows.MARKS) lines.push(`${name} ${marks[name]}`);
  lines.push('dns', `queries ${dnsStats.queries}`, `responses ${dnsStats.responses}`, `transactions ${dnsStats.transactions.length}`, `unanswered ${dnsStats.pending.length}`);
  if (dnsStats.transactions.length) {
    let minimum = dnsStats.transactions[0];
    let maximum = minimum;
    for (const time of dnsStats.transactions) {
      minimum = Math.min(minimum, time);
      maximum = Math.max(maximum, time);
    }
    lines.push(`response_time min ${seconds(minimum)} max ${seconds(maximum)}`);
  } else lines.push('response_time -');
  for (let code = 0; code < 16; code++) {
    if (dnsStats.rcodes[code]) lines.push(`rcode ${dns.rcodeName(code)} ${dnsStats.rcodes[code]}`);
  }
  lines.push('names');
  const names = [...dnsStats.names].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  for (const [name, count] of names) lines.push(`${name} ${count}`);
  return lines;
}

function endpointNotation(endpoint) {
  return `${network.ipv4(endpoint[0])}:${endpoint[1]}`;
}

function conversationLines(conversations, firstTime) {
  const lines = ['type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration'];
  for (const item of conversations) {
    const format = item.kind === 'ipv4' ? network.ipv4 : endpointNotation;
    lines.push([item.kind, format(item.a), format(item.b), item.packets, item.bytes,
      item.abPackets, item.abBytes, item.baPackets, item.baBytes, seconds(item.start - firstTime), seconds(item.end - item.start)].join(','));
  }
  return lines;
}

function endpointLines(endpoints) {
  const lines = ['address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes'];
  for (const item of endpoints) {
    lines.push([network.ipv4(item.address), item.packets, item.bytes, item.txPackets, item.txBytes, item.rxPackets, item.rxBytes].join(','));
  }
  return lines;
}

function streamLines(streams, packets) {
  const lines = [];
  for (const stream of streams) {
    if (lines.length) lines.push('');
    lines.push(`stream ${stream.number} ${endpointNotation(stream.client)} -> ${endpointNotation(stream.server)}`);
    lines.push(`packets ${stream.packets} bytes ${stream.bytes} start ${seconds(stream.start - packets[0].time)} duration ${seconds(stream.end - stream.start)}`);
    lines.push(`states ${stream.history.map(([state, number]) => `${state} ${number}`).join(', ')}`);
    const handshake = stream.handshake;
    const rtt = handshake.syn !== null && handshake.ack !== null ? seconds(packets[handshake.ack - 1].time - packets[handshake.syn - 1].time) : '-';
    lines.push(`handshake syn ${handshake.syn ?? '-'} syn_ack ${handshake.syn_ack ?? '-'} ack ${handshake.ack ?? '-'} rtt ${rtt}`);
    const client = stream.sides.client;
    const server = stream.sides.server;
    lines.push(`options client mss ${client.mss ?? '-'} wscale ${client.ws ?? '-'} server mss ${server.mss ?? '-'} wscale ${server.ws ?? '-'}`);
    for (const name of ['client', 'server']) {
      const side = stream.sides[name];
      lines.push(`${name} packets ${side.packets} payload ${side.payload} ${flows.MARKS.map(mark => `${mark} ${side.counts[mark]}`).join(' ')}`);
    }
    for (const [number, name, mark, seq, length] of stream.events) lines.push(`event ${number} ${name} ${mark} seq ${seq} len ${length}`);
  }
  return lines;
}

function writeLines(filename, lines) {
  fs.writeFileSync(`output/${filename}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

function main() {
  const packets = hexdump.readCapture('input/capture.txt');
  const requests = readRequests('input/filters.txt');
  for (const packet of packets) dissectPacket(packet, packets[0].time);
  const streams = flows.trackTcp(packets);
  const tables = flows.aggregate(packets);
  const dnsStats = dnsTransactions(packets);
  for (const packet of packets) packet.summary = summaryLine(packet);
  fs.mkdirSync('output', { recursive: true });
  writeLines('summary.txt', summaryLines(packets, requests.filters));
  writeLines('details.txt', detailLines(packets, requests.details));
  writeLines('conversations.csv', conversationLines(tables.conversations, packets[0].time));
  writeLines('endpoints.csv', endpointLines(tables.endpoints));
  writeLines('protocol_stats.txt', protocolLines(packets, dnsStats));
  writeLines('tcp_streams.txt', streamLines(streams, packets));
}

if (require.main === module) main();
