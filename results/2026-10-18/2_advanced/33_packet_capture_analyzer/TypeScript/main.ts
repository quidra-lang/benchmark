import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dns, rcodeName, typeName, type DnsAnswer } from './dns_app.ts';
import { aggregate, endpointNotation, marks, trackTcp } from './flows.ts';
import { dumpLines, readCapture, type Capture } from './hexdump.ts';
import {
  arp,
  bit,
  ethernet,
  hex,
  ip,
  ipv4,
  mac,
  Malformed,
  numeric,
  stringField,
  type Dissection,
  type Fields,
  type FieldValue,
} from './link_network.ts';
import { flagNames, icmp, tcp, udp } from './transport.ts';

export interface Packet extends Capture {
  fields: Fields;
  layers: string[];
  remaining: number[];
  reason?: string;
  dnsAnswers: DnsAnswer[];
  duplicateAck?: { original: number; count: number };
}
type FieldType = 'integer' | 'hex2' | 'hex4' | 'IPv4' | 'MAC' | 'string' | 'presence';
interface FieldDefinition {
  name: string;
  type: FieldType;
  alias?: [string, string];
  protocol?: boolean;
}
const types: Record<string, FieldType> = {
  i: 'integer',
  h2: 'hex2',
  h4: 'hex4',
  ip: 'IPv4',
  mac: 'MAC',
  s: 'string',
  p: 'presence',
};
const schema = [
  ['frame', 'number:i time:i len:i protocols:s malformed:s bad_checksum:p'],
  ['eth', 'dst:mac src:mac type:h4'],
  ['arp', 'opcode:i src.hw:mac src.ip:ip dst.hw:mac dst.ip:ip'],
  [
    'ip',
    'hdr_len:i tos:h2 len:i id:h4 flags.df:i flags.mf:i frag_offset:i ttl:i proto:i checksum:h4 checksum.status:s src:ip dst:ip fragment:p',
  ],
  ['icmp', 'type:i code:i checksum:h4 checksum.status:s id:i seq:i'],
  ['udp', 'srcport:i dstport:i length:i checksum:h4 checksum.status:s'],
  [
    'tcp',
    'srcport:i dstport:i stream:i seq:i seq_raw:i ack:i ack_raw:i hdr_len:i flags:h2 flags.fin:i flags.syn:i flags.rst:i flags.psh:i flags.ack:i flags.urg:i window:i window.calc:i checksum:h4 checksum.status:s urgent:i option:s options.mss:i options.wscale:i options.malformed:p len:i analysis.retransmission:p analysis.out_of_order:p analysis.lost_segment:p analysis.duplicate_ack:p',
  ],
  [
    'dns',
    'id:h4 flags:h4 flags.response:i flags.opcode:i flags.rcode:i count.queries:i count.answers:i count.auth_rr:i count.add_rr:i qry.name:s qry.type:i answer:s authority:s additional:s a:ip',
  ],
  ['data', 'len:i'],
];
const fieldOrder: FieldDefinition[] = schema.flatMap(([prefix, fields]) =>
  fields.split(' ').map((field) => {
    const [name, type] = field.split(':');
    return { name: prefix + '.' + name, type: types[type] };
  }),
);
const definitions = new Map(fieldOrder.map((definition) => [definition.name, definition]));
const aliases: FieldDefinition[] = [
  { name: 'eth.addr', type: 'MAC', alias: ['eth.dst', 'eth.src'] },
  { name: 'ip.addr', type: 'IPv4', alias: ['ip.src', 'ip.dst'] },
  { name: 'udp.port', type: 'integer', alias: ['udp.srcport', 'udp.dstport'] },
  { name: 'tcp.port', type: 'integer', alias: ['tcp.srcport', 'tcp.dstport'] },
];
for (const definition of aliases) definitions.set(definition.name, definition);
for (const layer of ['eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns', 'data']) {
  definitions.set(layer, { name: layer, type: 'presence', protocol: true });
}
const seconds = (time: number) =>
  `${Math.floor(time / 1000000)}.${String(time % 1000000).padStart(6, '0')}`;
function notation(type: FieldType, value: FieldValue): string {
  if (typeof value === 'string') return value;
  if (typeof value !== 'number') return '';
  if (type === 'hex2') return hex(value, 2);
  if (type === 'hex4') return hex(value, 4);
  if (type === 'IPv4') return ipv4(value);
  if (type === 'MAC') return mac(value);
  return String(value);
}
const capture = readCapture();
const firstTime = capture[0].time;
const packets: Packet[] = capture.map((source) => {
  const packet: Packet = {
    ...source,
    fields: new Map(),
    layers: [],
    remaining: [],
    dnsAnswers: [],
    reason: source.error,
  };
  const layer = (name: string, dissect: () => Dissection) => {
    packet.layers.push(name);
    const result = dissect();
    for (const [name, values] of result.fields) packet.fields.set(name, values);
    return result.payload;
  };
  if (!packet.reason) {
    try {
      let payload = layer('eth', () => ethernet(packet.bytes));
      const etherType = numeric(packet.fields, 'eth.type');
      if (etherType === 2054) payload = layer('arp', () => arp(payload));
      else if (etherType === 2048) {
        payload = layer('ip', () => ip(payload));
        if (!packet.fields.has('ip.fragment')) {
          const protocol = numeric(packet.fields, 'ip.proto');
          const src = numeric(packet.fields, 'ip.src');
          const dst = numeric(packet.fields, 'ip.dst');
          if (protocol === 1) payload = layer('icmp', () => icmp(payload));
          else if (protocol === 6) payload = layer('tcp', () => tcp(payload, src, dst));
          else if (protocol === 17) {
            payload = layer('udp', () => udp(payload, src, dst));
            if (
              numeric(packet.fields, 'udp.srcport') === 53 ||
              numeric(packet.fields, 'udp.dstport') === 53
            ) {
              payload = layer('dns', () => {
                const result = dns(payload);
                packet.dnsAnswers = result.answers;
                return result;
              });
            }
          }
        }
      }
      if (payload.length) {
        packet.layers.push('data');
        packet.fields.set('data.len', [payload.length]);
        packet.remaining = payload;
      }
    } catch (error) {
      if (!(error instanceof Malformed)) throw error;
      packet.reason = error.message;
      packet.remaining = [];
    }
  }
  const fields = packet.fields;
  fields.set('frame.number', [packet.number]);
  fields.set('frame.time', [packet.time - firstTime]);
  fields.set('frame.len', [packet.length]);
  if (packet.layers.length) fields.set('frame.protocols', [packet.layers.join(':')]);
  if (packet.reason) fields.set('frame.malformed', [packet.reason]);
  if (
    ['ip', 'icmp', 'udp', 'tcp'].some(
      (layer) => stringField(fields, `${layer}.checksum.status`) === 'bad',
    )
  ) {
    fields.set('frame.bad_checksum', [true]);
  }
  return packet;
});
const streams = trackTcp(packets);
function summary(packet: Packet): string {
  const f = packet.fields;
  const num = (name: string) => numeric(f, name);
  const values = (name: string) => f.get(name) ?? [];
  const source = f.has('ip.src')
    ? ipv4(num('ip.src'))
    : f.has('eth.src')
      ? mac(num('eth.src'))
      : '-';
  const destination = f.has('ip.dst')
    ? ipv4(num('ip.dst'))
    : f.has('eth.dst')
      ? mac(num('eth.dst'))
      : '-';
  const layer = packet.layers.filter((name) => name !== 'data').at(-1);
  const protocols: Record<string, string> = {
    eth: 'ETH',
    arp: 'ARP',
    ip: 'IPv4',
    icmp: 'ICMP',
    udp: 'UDP',
    tcp: 'TCP',
    dns: 'DNS',
  };
  const protocol = layer ? protocols[layer] : 'DUMP';
  let info = packet.reason ?? '';
  if (!packet.reason) {
    if (protocol === 'ETH') info = `EtherType ${hex(num('eth.type'), 4)}`;
    else if (protocol === 'ARP') {
      info =
        num('arp.opcode') === 1
          ? `Who has ${ipv4(num('arp.dst.ip'))}? Tell ${ipv4(num('arp.src.ip'))}`
          : num('arp.opcode') === 2
            ? `${ipv4(num('arp.src.ip'))} is at ${mac(num('arp.src.hw'))}`
            : `Opcode ${num('arp.opcode')}`;
    } else if (protocol === 'IPv4') {
      info = f.has('ip.fragment')
        ? `Fragment id=${hex(num('ip.id'), 4)} off=${num('ip.frag_offset')}${num('ip.flags.mf') ? ' MF' : ''}`
        : `Protocol ${num('ip.proto')}`;
    } else if (protocol === 'ICMP') {
      info =
        num('icmp.type') === 0 || num('icmp.type') === 8
          ? `Echo ${num('icmp.type') === 8 ? 'request' : 'reply'} id=${num('icmp.id')} seq=${num('icmp.seq')}`
          : `Type ${num('icmp.type')} code ${num('icmp.code')}`;
    } else if (protocol === 'UDP') {
      info = `${num('udp.srcport')} -> ${num('udp.dstport')} Len=${num('udp.length') - 8}`;
    } else if (protocol === 'TCP') {
      let mark = '';
      if (f.has('tcp.analysis.retransmission')) mark = '[TCP Retransmission] ';
      else if (f.has('tcp.analysis.out_of_order')) mark = '[TCP Out-Of-Order] ';
      else if (f.has('tcp.analysis.lost_segment')) mark = '[TCP Previous segment not captured] ';
      else if (packet.duplicateAck) {
        mark = `[TCP Dup ACK ${packet.duplicateAck.original}#${packet.duplicateAck.count}] `;
      }
      const flags = flagNames.filter((_, i) => bit(num('tcp.flags'), i)).join(', ') || '<None>';
      info = `${mark}${num('tcp.srcport')} -> ${num('tcp.dstport')} [${flags}] Seq=${num('tcp.seq')}`;
      if (f.has('tcp.ack')) info += ` Ack=${num('tcp.ack')}`;
      info += ` Win=${num('tcp.window.calc')} Len=${num('tcp.len')}`;
      for (const option of values('tcp.option')) {
        if (typeof option !== 'string') continue;
        const [kind, a, b] = option.split(' ');
        if (kind === 'MSS') info += ` MSS=${a}`;
        else if (kind === 'WS') info += ` WS=${2 ** +a}`;
        else if (kind === 'SACK_PERM') info += ' SACK_PERM';
        else if (kind === 'TS') info += ` TSval=${a} TSecr=${b}`;
      }
    } else if (protocol === 'DNS') {
      info = `${num('dns.flags.response') ? 'Response' : 'Query'} ${hex(num('dns.id'), 4)}`;
      if (num('dns.flags.rcode')) info += ' ' + rcodeName(num('dns.flags.rcode'));
      const names = values('dns.qry.name');
      const questionTypes = values('dns.qry.type');
      names.forEach((name, i) => {
        const type = questionTypes[i];
        if (typeof type === 'number') info += ` ${typeName(type)} ${name}`;
      });
      for (const answer of packet.dnsAnswers) info += ` ${typeName(answer.type)} ${answer.data}`;
    }
  }
  if (f.has('tcp.options.malformed')) info += ' [bad TCP options]';
  for (const [layer, name] of [
    ['ip', 'IPv4'],
    ['icmp', 'ICMP'],
    ['udp', 'UDP'],
    ['tcp', 'TCP'],
  ]) {
    if (stringField(f, `${layer}.checksum.status`) === 'bad') info += ` [bad ${name} checksum]`;
  }
  return `${packet.number} ${seconds(packet.time - firstTime)} ${source} -> ${destination} ${protocol} ${packet.length} ${info}`;
}
interface Token {
  kind: string;
  text: string;
  column: number;
}
class FilterError extends Error {}
type Predicate = (packet: Packet) => boolean;
function filter(expression: string): Predicate {
  const tokens: Token[] = [];
  for (let i = 0; i < expression.length;) {
    const c = expression[i];
    const column = i + 1;
    const pair = expression.slice(i, i + 2);
    if (c === ' ') {
      i++;
      continue;
    }
    if (['==', '!=', '<=', '>=', '&&', '||'].includes(pair)) {
      tokens.push({ kind: pair, text: pair, column });
      i += 2;
    } else if ('()!<>'.includes(c)) {
      tokens.push({ kind: c, text: c, column });
      i++;
    } else if (c === '"') {
      const end = expression.indexOf('"', i + 1);
      if (end < 0) throw new FilterError(`unterminated string at column ${column}`);
      tokens.push({ kind: 'string', text: expression.slice(i, end + 1), column });
      i = end + 1;
    } else if (/[A-Za-z0-9._:]/.test(c)) {
      const start = i;
      while (i < expression.length && /[A-Za-z0-9._:]/.test(expression[i])) i++;
      const text = expression.slice(start, i);
      const keywords: Record<string, string> = { and: '&&', or: '||', not: '!' };
      const kind = Object.hasOwn(keywords, text) ? keywords[text] : 'word';
      tokens.push({ kind, text, column });
    } else throw new FilterError(`invalid character '${c}' at column ${column}`);
  }
  let index = 0;
  const unexpected = (token: Token): never => {
    throw new FilterError(`unexpected '${token.text}' at column ${token.column}`);
  };
  const take = (): Token => {
    const token = tokens[index++];
    if (!token) throw new FilterError('unexpected end of filter');
    return token;
  };
  const convert = (token: Token, type: FieldType): string | number | undefined => {
    if (type === 'string') return token.kind === 'string' ? token.text.slice(1, -1) : undefined;
    if (token.kind !== 'word') return undefined;
    const text = token.text;
    if (type === 'integer' || type === 'hex2' || type === 'hex4') {
      if (/^[0-9]{1,15}$/.test(text)) return +text;
      if (/^0x[0-9a-fA-F]{1,12}$/.test(text)) return parseInt(text.slice(2), 16);
    } else if (type === 'IPv4') {
      const parts = text.split('.');
      if (parts.length === 4 && parts.every((part) => /^[0-9]{1,3}$/.test(part) && +part <= 255)) {
        return parts.reduce((value, part) => value * 256 + +part, 0);
      }
    } else if (type === 'MAC') {
      const parts = text.split(':');
      if (parts.length === 6 && parts.every((part) => /^[0-9a-fA-F]{2}$/.test(part))) {
        return parts.reduce((value, part) => value * 256 + parseInt(part, 16), 0);
      }
    }
    return undefined;
  };
  const values = (packet: Packet, definition: FieldDefinition): FieldValue[] =>
    definition.protocol
      ? packet.layers.includes(definition.name)
        ? [true]
        : []
      : definition.alias
        ? definition.alias.flatMap((name) => packet.fields.get(name) ?? [])
        : (packet.fields.get(definition.name) ?? []);
  const test = (token: Token): Predicate => {
    const definition = definitions.get(token.text);
    if (!definition) throw new FilterError(`unknown field ${token.text}`);
    const operator = tokens[index]?.kind;
    if (operator === undefined || !['==', '!=', '<', '>', '<=', '>='].includes(operator)) {
      return (packet) => values(packet, definition).length > 0;
    }
    take();
    if (
      definition.type === 'presence' ||
      (definition.type === 'string' && operator !== '==' && operator !== '!=')
    ) {
      throw new FilterError(`operator ${operator} not allowed for ${definition.name}`);
    }
    const valueToken = take();
    if (valueToken.kind !== 'word' && valueToken.kind !== 'string') unexpected(valueToken);
    const converted = convert(valueToken, definition.type);
    if (converted === undefined) {
      throw new FilterError(`invalid value ${valueToken.text} for ${definition.name}`);
    }
    return (packet) => {
      const list = values(packet, definition);
      if (!list.length) return false;
      if (operator === '!=') return list.every((value) => value !== converted);
      return list.some((value) => {
        if (operator === '==') return value === converted;
        if (typeof value !== 'number' || typeof converted !== 'number') return false;
        if (operator === '<') return value < converted;
        if (operator === '>') return value > converted;
        if (operator === '<=') return value <= converted;
        return value >= converted;
      });
    };
  };
  const negation = (): Predicate => {
    if (tokens[index]?.kind === '!') {
      take();
      const inner = negation();
      return (packet) => !inner(packet);
    }
    const token = take();
    if (token.kind === '(') {
      const inner = expressionParser();
      const close = take();
      if (close.kind !== ')') unexpected(close);
      return inner;
    }
    if (token.kind === 'word') return test(token);
    return unexpected(token);
  };
  const product = (): Predicate => {
    let result = negation();
    while (tokens[index]?.kind === '&&') {
      take();
      const left = result;
      const right = negation();
      result = (packet) => left(packet) && right(packet);
    }
    return result;
  };
  const expressionParser = (): Predicate => {
    let result = product();
    while (tokens[index]?.kind === '||') {
      take();
      const left = result;
      const right = product();
      result = (packet) => left(packet) || right(packet);
    }
    return result;
  };
  const result = expressionParser();
  if (index < tokens.length) unexpected(tokens[index]);
  return result;
}
function details(number: number): string[] {
  const packet = packets[number - 1];
  if (!packet) return [`packet ${number} not found`];
  const lines = [`packet ${number}`];
  for (const layer of ['frame', ...packet.layers]) {
    lines.push(layer);
    for (const definition of fieldOrder) {
      if (definition.name.startsWith(layer + '.')) {
        for (const value of packet.fields.get(definition.name) ?? []) {
          lines.push(
            `  ${definition.name}` +
              (definition.type === 'presence' ? '' : ' = ' + notation(definition.type, value)),
          );
        }
      }
    }
    if (layer === 'data') lines.push(...dumpLines(packet.remaining).map((line) => '  ' + line));
  }
  return lines;
}
const summaryLines = packets.map(summary);
const detailBlocks: string[][] = [];
for (const request of readFileSync('input/filters.txt', 'ascii').slice(0, -1).split('\n')) {
  if (request.startsWith('FILTER ')) {
    const expression = request.slice(7);
    summaryLines.push('', 'filter ' + expression);
    try {
      const predicate = filter(expression);
      const matched = packets.filter(predicate);
      summaryLines.push(...matched.map(summary), `matched ${matched.length} of ${packets.length}`);
    } catch (error) {
      if (!(error instanceof FilterError)) throw error;
      summaryLines.push('error: ' + error.message);
    }
  } else if (request.startsWith('DETAIL ')) detailBlocks.push(details(+request.slice(7)));
}
const { conversations, endpoints } = aggregate(packets);
const conversationLines = [
  'type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration',
  ...conversations.map(
    (c) =>
      `${c.kind},${endpointNotation(c.a)},${endpointNotation(c.b)},${c.packetsAB + c.packetsBA},${c.bytesAB + c.bytesBA},${c.packetsAB},${c.bytesAB},${c.packetsBA},${c.bytesBA},${seconds(c.start - firstTime)},${seconds(c.end - c.start)}`,
  ),
];
const endpointLines = [
  'address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes',
  ...endpoints.map(
    (e) =>
      `${ipv4(e.address)},${e.txPackets + e.rxPackets},${e.txBytes + e.rxBytes},${e.txPackets},${e.txBytes},${e.rxPackets},${e.rxBytes}`,
  ),
];
const pending: Packet[] = [];
const responseTimes: number[] = [];
const nameCounts = new Map<string, number>();
const rcodes = new Map<number, number>();
let queries = 0;
let responses = 0;
for (const packet of packets) {
  const f = packet.fields;
  if (!f.has('dns.id')) continue;
  if (numeric(f, 'dns.flags.response') === 0) {
    queries++;
    pending.push(packet);
    for (const name of f.get('dns.qry.name') ?? []) {
      if (typeof name === 'string') nameCounts.set(name, (nameCounts.get(name) ?? 0) + 1);
    }
  } else {
    responses++;
    const rcode = numeric(f, 'dns.flags.rcode');
    rcodes.set(rcode, (rcodes.get(rcode) ?? 0) + 1);
    const index = pending.findIndex(
      (query) =>
        numeric(query.fields, 'dns.id') === numeric(f, 'dns.id') &&
        numeric(query.fields, 'ip.src') === numeric(f, 'ip.dst') &&
        numeric(query.fields, 'ip.dst') === numeric(f, 'ip.src') &&
        numeric(query.fields, 'udp.srcport') === numeric(f, 'udp.dstport') &&
        numeric(query.fields, 'udp.dstport') === numeric(f, 'udp.srcport'),
    );
    if (index >= 0) responseTimes.push(packet.time - pending.splice(index, 1)[0].time);
  }
}
const stats = [
  `packets ${packets.length}`,
  `bytes ${packets.reduce((sum, p) => sum + p.length, 0)}`,
  `duration ${seconds(packets[packets.length - 1].time - firstTime)}`,
  'hierarchy',
];
for (const [layer, indent] of [
  ['eth', 0],
  ['arp', 2],
  ['ip', 2],
  ['icmp', 4],
  ['udp', 4],
  ['dns', 6],
  ['tcp', 4],
] as const) {
  const included = packets.filter((p) => p.layers.includes(layer));
  stats.push(
    `${' '.repeat(indent)}${layer} ${included.length} ${included.reduce((sum, p) => sum + p.length, 0)}`,
  );
}
stats.push('checksums');
for (const layer of ['ip', 'icmp', 'udp', 'tcp']) {
  const count = (status: string) =>
    packets.filter((p) => stringField(p.fields, layer + '.checksum.status') === status).length;
  stats.push(
    `${layer} good ${count('good')} bad ${count('bad')}${layer === 'udp' ? ` none ${count('none')}` : ''}`,
  );
}
stats.push('malformed');
for (const layer of ['dump', 'eth', 'arp', 'ip', 'icmp', 'udp', 'tcp', 'dns']) {
  stats.push(
    `${layer} ${packets.filter((p) => (layer === 'dump' ? p.error !== undefined : p.error === undefined && p.reason !== undefined && p.layers.at(-1) === layer)).length}`,
  );
}
stats.push(
  'tcp analysis',
  ...marks.map(
    (mark) => `${mark} ${packets.filter((p) => p.fields.has('tcp.analysis.' + mark)).length}`,
  ),
  'dns',
  `queries ${queries}`,
  `responses ${responses}`,
  `transactions ${responseTimes.length}`,
  `unanswered ${pending.length}`,
  responseTimes.length
    ? `response_time min ${seconds(Math.min(...responseTimes))} max ${seconds(Math.max(...responseTimes))}`
    : 'response_time -',
);
for (const [rcode, count] of [...rcodes].sort((a, b) => a[0] - b[0])) {
  stats.push(`rcode ${rcodeName(rcode)} ${count}`);
}
stats.push(
  'names',
  ...[...nameCounts]
    .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([name, count]) => `${name} ${count}`),
);
const streamBlocks = streams.map((stream) => {
  const rtt =
    stream.syn !== undefined && stream.ack !== undefined
      ? seconds(packets[stream.ack - 1].time - packets[stream.syn - 1].time)
      : '-';
  const lines = [
    `stream ${stream.number} ${endpointNotation(stream.client.endpoint)} -> ${endpointNotation(stream.server.endpoint)}`,
    `packets ${stream.packets} bytes ${stream.bytes} start ${seconds(stream.start - firstTime)} duration ${seconds(stream.end - stream.start)}`,
    `states ${stream.history.map((entry) => `${entry.state} ${entry.packet}`).join(', ')}`,
    `handshake syn ${stream.syn ?? '-'} syn_ack ${stream.synAck ?? '-'} ack ${stream.ack ?? '-'} rtt ${rtt}`,
    `options client mss ${stream.client.mss ?? '-'} wscale ${stream.client.wscale ?? '-'} server mss ${stream.server.mss ?? '-'} wscale ${stream.server.wscale ?? '-'}`,
  ];
  for (const name of ['client', 'server'] as const) {
    const side = stream[name];
    lines.push(
      `${name} packets ${side.packets} payload ${side.payload} ${marks.map((mark) => `${mark} ${side.counts[mark]}`).join(' ')}`,
    );
  }
  lines.push(
    ...stream.events.map(
      (event) =>
        `event ${event.packet} ${event.side} ${event.mark} seq ${event.seq} len ${event.length}`,
    ),
  );
  return lines;
});
mkdirSync('output', { recursive: true });
const write = (name: string, lines: string[]) =>
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
const joinBlocks = (blocks: string[][]) =>
  blocks.flatMap((block, i) => (i ? ['', ...block] : block));
write('summary.txt', summaryLines);
write('details.txt', joinBlocks(detailBlocks));
write('conversations.csv', conversationLines);
write('endpoints.csv', endpointLines);
write('protocol_stats.txt', stats);
write('tcp_streams.txt', joinBlocks(streamBlocks));
