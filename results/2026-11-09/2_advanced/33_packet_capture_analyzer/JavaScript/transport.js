'use strict';

const { Malformed, uint, integerBytes, checksum } = require('./link_network');

function pseudoHeader(source, destination, protocol, length) {
  return [...integerBytes(source, 4), ...integerBytes(destination, 4), 0, protocol, ...integerBytes(length, 2)];
}

function icmp(bytes) {
  if (bytes.length < 8) throw new Malformed('icmp: truncated');
  const fields = {
    'icmp.type': [bytes[0]], 'icmp.code': [bytes[1]], 'icmp.checksum': [uint(bytes, 2)],
    'icmp.checksum.status': [checksum(bytes)]
  };
  if (bytes[0] === 0 || bytes[0] === 8) {
    fields['icmp.id'] = [uint(bytes, 4)];
    fields['icmp.seq'] = [uint(bytes, 6)];
  }
  return { fields, payload: bytes.slice(8) };
}

function udp(bytes, source, destination) {
  if (bytes.length < 8) throw new Malformed('udp: truncated');
  const length = uint(bytes, 4);
  if (length < 8 || length > bytes.length) throw new Malformed(`udp: bad length ${length}`);
  const stored = uint(bytes, 6);
  const status = stored === 0 ? 'none' : checksum(pseudoHeader(source, destination, 17, length).concat(bytes.slice(0, length)));
  return {
    fields: {
      'udp.srcport': [uint(bytes, 0)], 'udp.dstport': [uint(bytes, 2)], 'udp.length': [length],
      'udp.checksum': [stored], 'udp.checksum.status': [status]
    },
    payload: bytes.slice(8, length)
  };
}

function options(bytes, fields) {
  const allowed = new Map([[2, [4]], [3, [3]], [4, [2]], [5, [10, 18, 26, 34]], [8, [10]]]);
  const recorded = [];
  let index = 0;
  while (index < bytes.length) {
    const kind = bytes[index];
    if (kind === 0) {
      recorded.push('EOL');
      break;
    }
    if (kind === 1) {
      recorded.push('NOP');
      index++;
      continue;
    }
    const length = bytes[index + 1] ?? 0;
    if (length < 2 || index + length > bytes.length || (allowed.has(kind) && !allowed.get(kind).includes(length))) {
      fields['tcp.options.malformed'] = [true];
      break;
    }
    const body = bytes.slice(index + 2, index + length);
    let text;
    if (kind === 2) {
      const value = uint(body, 0);
      text = `MSS ${value}`;
      fields['tcp.options.mss'] = [value];
    } else if (kind === 3) {
      text = `WS ${body[0]}`;
      fields['tcp.options.wscale'] = [body[0]];
    } else if (kind === 4) {
      text = 'SACK_PERM';
    } else if (kind === 5) {
      text = 'SACK';
      for (let position = 0; position < body.length; position += 8) {
        text += ` ${uint(body, position, 4)}-${uint(body, position + 4, 4)}`;
      }
    } else if (kind === 8) {
      text = `TS ${uint(body, 0, 4)} ${uint(body, 4, 4)}`;
    } else {
      text = `kind ${kind} len ${length}`;
    }
    recorded.push(text);
    index += length;
  }
  if (recorded.length) fields['tcp.option'] = recorded;
}

function tcp(bytes, source, destination) {
  if (bytes.length < 20) throw new Malformed('tcp: truncated header');
  const header = Math.floor(bytes[12] / 16) * 4;
  if (header < 20) throw new Malformed(`tcp: bad header length ${header}`);
  if (header > bytes.length) throw new Malformed('tcp: truncated header');
  const flags = bytes[13];
  const fields = {
    'tcp.srcport': [uint(bytes, 0)], 'tcp.dstport': [uint(bytes, 2)], 'tcp.seq_raw': [uint(bytes, 4, 4)],
    'tcp.hdr_len': [header], 'tcp.flags': [flags], 'tcp.window': [uint(bytes, 14)],
    'tcp.checksum': [uint(bytes, 16)],
    'tcp.checksum.status': [checksum(pseudoHeader(source, destination, 6, bytes.length).concat(bytes))],
    'tcp.urgent': [uint(bytes, 18)], 'tcp.len': [bytes.length - header]
  };
  for (const [index, name] of ['fin', 'syn', 'rst', 'psh', 'ack', 'urg'].entries()) {
    fields[`tcp.flags.${name}`] = [Math.floor(flags / 2 ** index) % 2];
  }
  if (fields['tcp.flags.ack'][0] === 1) fields['tcp.ack_raw'] = [uint(bytes, 8, 4)];
  options(bytes.slice(20, header), fields);
  return { fields, payload: bytes.slice(header) };
}

module.exports = { icmp, udp, tcp };
