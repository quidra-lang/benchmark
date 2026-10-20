import type { Packet } from './main.ts';
import { ipv4, numberField, numeric } from './link_network.ts';

export type Mark = 'retransmission' | 'out_of_order' | 'lost_segment' | 'duplicate_ack';
export const marks: Mark[] = ['retransmission', 'out_of_order', 'lost_segment', 'duplicate_ack'];
export type SideName = 'client' | 'server';
interface Endpoint { address: number; port?: number }
interface Side {
  endpoint: Endpoint; isn?: number; mss?: number; wscale?: number; base?: number; expected?: number; advanced: number;
  intervals: Set<string>; previousAck?: { ack: number; window: number; packet: number; count: number };
  packets: number; payload: number; counts: Record<Mark, number>;
}
type State = 'SYN_SENT' | 'SYN_RECEIVED' | 'ESTABLISHED' | 'FIN_WAIT' | 'CLOSING' | 'CLOSED' | 'RESET';
export interface Stream {
  number: number; client: Side; server: Side; state: State; history: { state: State; packet: number }[];
  start: number; end: number; packets: number; bytes: number; syn?: number; synAck?: number; ack?: number;
  events: { packet: number; side: SideName; mark: Mark; seq: number; length: number }[]; firstClose?: SideName; secondFin?: number;
}
const endpointKey = (endpoint: Endpoint) => `${endpoint.address}:${endpoint.port ?? '-'}`;
const pairKey = (a: Endpoint, b: Endpoint) => [endpointKey(a), endpointKey(b)].sort().join('|');
export const endpointNotation = (endpoint: Endpoint) => ipv4(endpoint.address) + (endpoint.port === undefined ? '' : ':' + endpoint.port);
const mod32 = (value: number) => (value + 4294967296) % 4294967296;
function side(endpoint: Endpoint): Side {
  return { endpoint, advanced: 0, intervals: new Set(), packets: 0, payload: 0,
    counts: { retransmission: 0, out_of_order: 0, lost_segment: 0, duplicate_ack: 0 } };
}
export function trackTcp(packets: Packet[]): Stream[] {
  const streams: Stream[] = [], latest = new Map<string, Stream>();
  for (const packet of packets) {
    const f = packet.fields;
    if (!f.has('tcp.srcport')) continue;
    const source = { address: numeric(f, 'ip.src'), port: numeric(f, 'tcp.srcport') }, destination = { address: numeric(f, 'ip.dst'), port: numeric(f, 'tcp.dstport') };
    const seq = numeric(f, 'tcp.seq_raw'), ack = numberField(f, 'tcp.ack_raw'), window = numeric(f, 'tcp.window'), payload = numeric(f, 'tcp.len');
    const syn = numeric(f, 'tcp.flags.syn') === 1, fin = numeric(f, 'tcp.flags.fin') === 1, rst = numeric(f, 'tcp.flags.rst') === 1, hasAck = ack !== undefined;
    const key = pairKey(source, destination);
    let stream = latest.get(key);
    const recordSyn = (target: Stream, name: SideName) => {
      const s = target[name]; s.isn = seq; s.mss = numberField(f, 'tcp.options.mss'); s.wscale = numberField(f, 'tcp.options.wscale');
      if (name === 'client') target.syn = packet.number; else target.synAck = packet.number;
    };
    if (!stream || ((stream.state === 'CLOSED' || stream.state === 'RESET') && syn && !hasAck)) {
      const state: State = syn ? hasAck ? 'SYN_RECEIVED' : 'SYN_SENT' : 'ESTABLISHED';
      stream = { number: streams.length, client: side(syn && hasAck ? destination : source), server: side(syn && hasAck ? source : destination), state,
        history: [{ state, packet: packet.number }], start: packet.time, end: packet.time, packets: 0, bytes: 0, events: [] };
      if (syn) recordSyn(stream, hasAck ? 'server' : 'client');
      streams.push(stream); latest.set(key, stream);
    }
    f.set('tcp.stream', [stream.number]);
    const name: SideName = endpointKey(source) === endpointKey(stream.client.endpoint) ? 'client' : 'server';
    const thisSide = stream[name], other = stream[name === 'client' ? 'server' : 'client'];
    thisSide.base ??= seq;
    if (hasAck) other.base ??= ack;
    const relative = mod32(seq - thisSide.base);
    f.set('tcp.seq', [relative]);
    if (ack !== undefined && other.base !== undefined) f.set('tcp.ack', [mod32(ack - other.base)]);
    const length = payload + (syn ? 1 : 0) + (fin ? 1 : 0);
    let mark: Mark | undefined;
    if (length > 0) {
      const expected = thisSide.expected;
      if (expected !== undefined && relative > expected) mark = 'lost_segment';
      else if (expected !== undefined && relative < expected) mark = thisSide.intervals.has(`${relative},${length}`) ? 'retransmission' : packet.time - thisSide.advanced < 3000 ? 'out_of_order' : 'retransmission';
      thisSide.intervals.add(`${relative},${length}`);
      if (expected === undefined || relative + length > expected) { thisSide.expected = relative + length; thisSide.advanced = packet.time; }
    } else if (ack !== undefined && !rst) {
      const previous = thisSide.previousAck;
      if (previous && ack === previous.ack && window === previous.window) {
        mark = 'duplicate_ack'; previous.count++; packet.duplicateAck = { original: previous.packet, count: previous.count };
      }
    }
    if (ack !== undefined && mark !== 'duplicate_ack') thisSide.previousAck = { ack, window, packet: packet.number, count: 0 };
    if (mark) {
      f.set(`tcp.analysis.${mark}`, [true]); thisSide.counts[mark]++;
      stream.events.push({ packet: packet.number, side: name, mark, seq: relative, length });
    }
    f.set('tcp.window.calc', [stream.client.wscale !== undefined && stream.server.wscale !== undefined && !syn ? window * 2 ** (thisSide.wscale ?? 0) : window]);
    let state = stream.state;
    if (rst) { if (state !== 'CLOSED' && state !== 'RESET') state = 'RESET'; }
    else if (state === 'SYN_SENT' && name === 'server' && syn && ack !== undefined && stream.client.isn !== undefined && ack === mod32(stream.client.isn + 1)) {
      state = 'SYN_RECEIVED'; recordSyn(stream, 'server');
    } else if (state === 'SYN_RECEIVED' && name === 'client' && !syn && ack !== undefined && stream.server.isn !== undefined && ack === mod32(stream.server.isn + 1)) {
      state = 'ESTABLISHED'; stream.ack = packet.number;
    } else if (state === 'ESTABLISHED' && fin) { state = 'FIN_WAIT'; stream.firstClose = name; }
    else if (state === 'FIN_WAIT' && fin && name !== stream.firstClose) { state = 'CLOSING'; stream.secondFin = mod32(seq + payload + 1); }
    else if (state === 'CLOSING' && name === stream.firstClose && ack !== undefined && ack === stream.secondFin) state = 'CLOSED';
    if (state !== stream.state) { stream.state = state; stream.history.push({ state, packet: packet.number }); }
    thisSide.packets++; thisSide.payload += payload; stream.packets++; stream.bytes += packet.length; stream.end = packet.time;
  }
  return streams;
}
export interface Conversation {
  kind: 'ipv4' | 'tcp' | 'udp'; a: Endpoint; b: Endpoint; first: number; start: number; end: number;
  packetsAB: number; bytesAB: number; packetsBA: number; bytesBA: number;
}
export interface EndpointTotals { address: number; txPackets: number; txBytes: number; rxPackets: number; rxBytes: number }
export function aggregate(packets: Packet[]): { conversations: Conversation[]; endpoints: EndpointTotals[] } {
  const conversations = new Map<string, Conversation>(), endpoints = new Map<number, EndpointTotals>();
  for (const packet of packets) {
    const f = packet.fields;
    if (!f.has('ip.src')) continue;
    const src = numeric(f, 'ip.src'), dst = numeric(f, 'ip.dst');
    for (const [address, sent] of [[src, true], [dst, false]] as const) {
      const totals = endpoints.get(address) ?? { address, txPackets: 0, txBytes: 0, rxPackets: 0, rxBytes: 0 };
      if (sent) { totals.txPackets++; totals.txBytes += packet.length; } else { totals.rxPackets++; totals.rxBytes += packet.length; }
      endpoints.set(address, totals);
    }
    const add = (kind: Conversation['kind'], source: Endpoint, destination: Endpoint, identity: string) => {
      const key = kind + ':' + identity;
      let conversation = conversations.get(key);
      if (!conversation) {
        conversation = { kind, a: source, b: destination, first: packet.number, start: packet.time, end: packet.time, packetsAB: 0, bytesAB: 0, packetsBA: 0, bytesBA: 0 };
        conversations.set(key, conversation);
      }
      if (endpointKey(source) === endpointKey(conversation.a)) { conversation.packetsAB++; conversation.bytesAB += packet.length; }
      else { conversation.packetsBA++; conversation.bytesBA += packet.length; }
      conversation.end = packet.time;
    };
    const source = { address: src }, destination = { address: dst };
    add('ipv4', source, destination, pairKey(source, destination));
    if (f.has('tcp.stream')) add('tcp', { address: src, port: numeric(f, 'tcp.srcport') }, { address: dst, port: numeric(f, 'tcp.dstport') }, String(numeric(f, 'tcp.stream')));
    if (f.has('udp.srcport')) {
      const a = { address: src, port: numeric(f, 'udp.srcport') }, b = { address: dst, port: numeric(f, 'udp.dstport') };
      add('udp', a, b, pairKey(a, b));
    }
  }
  const kindOrder = { ipv4: 0, tcp: 1, udp: 2 };
  return { conversations: [...conversations.values()].sort((a, b) => b.bytesAB + b.bytesBA - a.bytesAB - a.bytesBA || b.packetsAB + b.packetsBA - a.packetsAB - a.packetsBA || kindOrder[a.kind] - kindOrder[b.kind] || a.first - b.first),
    endpoints: [...endpoints.values()].sort((a, b) => b.txBytes + b.rxBytes - a.txBytes - a.rxBytes || b.txPackets + b.rxPackets - a.txPackets - a.rxPackets || a.address - b.address) };
}
