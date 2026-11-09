'use strict';

const MARKS = ['retransmission', 'out_of_order', 'lost_segment', 'duplicate_ack'];
const MODULUS = 4294967296;

function get(packet, field) {
  return packet.fields[field]?.[0];
}

function endpointKey(endpoint) {
  return endpoint.join(':');
}

function pairKey(first, second) {
  return [endpointKey(first), endpointKey(second)].sort().join('|');
}

function newSide() {
  return {
    isn: null, mss: null, ws: null, base: null, expected: null, advanced: null,
    intervals: new Set(), previousAck: null, packets: 0, payload: 0,
    counts: Object.fromEntries(MARKS.map(mark => [mark, 0]))
  };
}

function recordSyn(stream, side, packet) {
  const target = stream.sides[side];
  target.isn = get(packet, 'tcp.seq_raw');
  target.mss = get(packet, 'tcp.options.mss') ?? null;
  target.ws = get(packet, 'tcp.options.wscale') ?? null;
  stream.handshake[side === 'client' ? 'syn' : 'syn_ack'] = packet.number;
}

function relative(value, base) {
  const difference = value - base;
  return (difference < 0 ? difference + MODULUS : difference) % MODULUS;
}

function trackTcp(packets) {
  const streams = [];
  const latest = new Map();
  for (const packet of packets) {
    if (get(packet, 'tcp.srcport') === undefined) continue;
    const source = [get(packet, 'ip.src'), get(packet, 'tcp.srcport')];
    const destination = [get(packet, 'ip.dst'), get(packet, 'tcp.dstport')];
    const syn = get(packet, 'tcp.flags.syn') === 1;
    const ackSet = get(packet, 'tcp.flags.ack') === 1;
    const fin = get(packet, 'tcp.flags.fin') === 1;
    const rst = get(packet, 'tcp.flags.rst') === 1;
    const seq = get(packet, 'tcp.seq_raw');
    const ack = get(packet, 'tcp.ack_raw');
    const key = pairKey(source, destination);
    let stream = latest.get(key);
    if (!stream || ((stream.state === 'CLOSED' || stream.state === 'RESET') && syn && !ackSet)) {
      const state = syn ? (ackSet ? 'SYN_RECEIVED' : 'SYN_SENT') : 'ESTABLISHED';
      stream = {
        number: streams.length, client: syn && ackSet ? destination : source,
        server: syn && ackSet ? source : destination, state, history: [[state, packet.number]],
        start: packet.time, end: packet.time, packets: 0, bytes: 0,
        handshake: { syn: null, syn_ack: null, ack: null }, events: [], firstCloser: null, f2: null,
        sides: { client: newSide(), server: newSide() }
      };
      if (syn) recordSyn(stream, ackSet ? 'server' : 'client', packet);
      streams.push(stream);
      latest.set(key, stream);
    }
    packet.fields['tcp.stream'] = [stream.number];
    const sideName = endpointKey(source) === endpointKey(stream.client) ? 'client' : 'server';
    const side = stream.sides[sideName];
    const other = stream.sides[sideName === 'client' ? 'server' : 'client'];
    if (side.base === null) side.base = seq;
    if (ackSet && other.base === null) other.base = ack;
    const r = relative(seq, side.base);
    packet.fields['tcp.seq'] = [r];
    if (ackSet) packet.fields['tcp.ack'] = [relative(ack, other.base)];

    const length = get(packet, 'tcp.len');
    const n = length + Number(syn) + Number(fin);
    const window = get(packet, 'tcp.window');
    let mark = null;
    if (n >= 1) {
      const interval = `${r}:${n}`;
      if (side.expected !== null && r > side.expected) mark = 'lost_segment';
      if (side.expected !== null && r < side.expected) {
        mark = side.intervals.has(interval) || packet.time - side.advanced >= 3000 ? 'retransmission' : 'out_of_order';
      }
      side.intervals.add(interval);
      if (side.expected === null || r + n > side.expected) {
        side.expected = r + n;
        side.advanced = packet.time;
      }
    } else if (ackSet && !rst && side.previousAck !== null) {
      if (ack === side.previousAck.ack && window === side.previousAck.window) {
        mark = 'duplicate_ack';
        side.previousAck.count++;
        packet.duplicateAck = { original: side.previousAck.original, count: side.previousAck.count };
      }
    }
    if (ackSet && mark !== 'duplicate_ack') side.previousAck = { ack, window, original: packet.number, count: 0 };
    packet.mark = mark;
    if (mark !== null) {
      packet.fields[`tcp.analysis.${mark}`] = [true];
      side.counts[mark]++;
      stream.events.push([packet.number, sideName, mark, r, n]);
    }
    packet.fields['tcp.window.calc'] = [side.ws !== null && other.ws !== null && !syn ? window * 2 ** side.ws : window];

    let nextState = stream.state;
    if (rst) {
      if (stream.state !== 'CLOSED' && stream.state !== 'RESET') nextState = 'RESET';
    } else if (stream.state === 'SYN_SENT' && sideName === 'server' && syn && ackSet && ack === (stream.sides.client.isn + 1) % MODULUS) {
      nextState = 'SYN_RECEIVED';
      recordSyn(stream, 'server', packet);
    } else if (stream.state === 'SYN_RECEIVED' && sideName === 'client' && ackSet && !syn && ack === (stream.sides.server.isn + 1) % MODULUS) {
      nextState = 'ESTABLISHED';
      stream.handshake.ack = packet.number;
    } else if (stream.state === 'ESTABLISHED' && fin) {
      nextState = 'FIN_WAIT';
      stream.firstCloser = sideName;
    } else if (stream.state === 'FIN_WAIT' && fin && sideName !== stream.firstCloser) {
      nextState = 'CLOSING';
      stream.f2 = (seq + length + 1) % MODULUS;
    } else if (stream.state === 'CLOSING' && sideName === stream.firstCloser && ackSet && ack === stream.f2) {
      nextState = 'CLOSED';
    }
    if (nextState !== stream.state) {
      stream.state = nextState;
      stream.history.push([nextState, packet.number]);
    }
    side.packets++;
    side.payload += length;
    stream.packets++;
    stream.bytes += packet.length;
    stream.end = packet.time;
  }
  return streams;
}

function aggregate(packets) {
  const conversations = new Map();
  const endpoints = new Map();
  function addConversation(kind, key, source, destination, packet) {
    const id = `${kind}|${key}`;
    let item = conversations.get(id);
    if (!item) {
      item = {
        kind, a: source, b: destination, first: packet.number, start: packet.time,
        end: packet.time, packets: 0, bytes: 0, abPackets: 0, abBytes: 0, baPackets: 0, baBytes: 0
      };
      conversations.set(id, item);
    }
    const forward = kind === 'ipv4' ? source === item.a : endpointKey(source) === endpointKey(item.a);
    item[forward ? 'abPackets' : 'baPackets']++;
    item[forward ? 'abBytes' : 'baBytes'] += packet.length;
    item.packets++;
    item.bytes += packet.length;
    item.end = packet.time;
  }
  function addEndpoint(address, direction, length) {
    let item = endpoints.get(address);
    if (!item) {
      item = { address, packets: 0, bytes: 0, txPackets: 0, txBytes: 0, rxPackets: 0, rxBytes: 0 };
      endpoints.set(address, item);
    }
    item[`${direction}Packets`]++;
    item[`${direction}Bytes`] += length;
    item.packets++;
    item.bytes += length;
  }
  for (const packet of packets) {
    const source = get(packet, 'ip.src');
    if (source === undefined) continue;
    const destination = get(packet, 'ip.dst');
    addConversation('ipv4', [Math.min(source, destination), Math.max(source, destination)].join(':'), source, destination, packet);
    addEndpoint(source, 'tx', packet.length);
    addEndpoint(destination, 'rx', packet.length);
    if (get(packet, 'tcp.stream') !== undefined) {
      addConversation('tcp', get(packet, 'tcp.stream'), [source, get(packet, 'tcp.srcport')], [destination, get(packet, 'tcp.dstport')], packet);
    }
    if (get(packet, 'udp.srcport') !== undefined) {
      const first = [source, get(packet, 'udp.srcport')];
      const second = [destination, get(packet, 'udp.dstport')];
      addConversation('udp', pairKey(first, second), first, second, packet);
    }
  }
  const kinds = { ipv4: 0, tcp: 1, udp: 2 };
  return {
    conversations: [...conversations.values()].sort((a, b) => b.bytes - a.bytes || b.packets - a.packets || kinds[a.kind] - kinds[b.kind] || a.first - b.first),
    endpoints: [...endpoints.values()].sort((a, b) => b.bytes - a.bytes || b.packets - a.packets || a.address - b.address)
  };
}

module.exports = { MARKS, trackTcp, aggregate };
