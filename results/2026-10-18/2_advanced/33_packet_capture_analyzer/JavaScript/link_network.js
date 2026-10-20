'use strict';

class Malformed extends Error {}

function uint(bytes, offset, count = 2) {
  let value = 0;
  for (let index = offset; index < offset + count; index++) value = value * 256 + bytes[index];
  return value;
}

function integerBytes(value, count) {
  const bytes = [];
  for (let index = count - 1; index >= 0; index--) bytes.push(Math.floor(value / 256 ** index) % 256);
  return bytes;
}

function checksum(bytes) {
  let total = 0;
  for (let index = 0; index < bytes.length; index += 2) {
    total += bytes[index] * 256 + (bytes[index + 1] ?? 0);
  }
  while (total > 65535) total = total % 65536 + Math.floor(total / 65536);
  return total === 65535 ? 'good' : 'bad';
}

function mac(value) {
  return integerBytes(value, 6).map(byte => byte.toString(16).padStart(2, '0')).join(':');
}

function ipv4(value) {
  return integerBytes(value, 4).join('.');
}

function ethernet(bytes) {
  if (bytes.length < 14) throw new Malformed('eth: truncated');
  return {
    fields: { 'eth.dst': [uint(bytes, 0, 6)], 'eth.src': [uint(bytes, 6, 6)], 'eth.type': [uint(bytes, 12)] },
    payload: bytes.slice(14)
  };
}

function arp(bytes) {
  if (bytes.length < 28) throw new Malformed('arp: truncated');
  if (uint(bytes, 0) !== 1 || uint(bytes, 2) !== 2048 || bytes[4] !== 6 || bytes[5] !== 4) {
    throw new Malformed('arp: unsupported format');
  }
  return {
    fields: {
      'arp.opcode': [uint(bytes, 6)], 'arp.src.hw': [uint(bytes, 8, 6)], 'arp.src.ip': [uint(bytes, 14, 4)],
      'arp.dst.hw': [uint(bytes, 18, 6)], 'arp.dst.ip': [uint(bytes, 24, 4)]
    },
    payload: []
  };
}

function ip(bytes) {
  if (bytes.length < 20) throw new Malformed('ip: truncated header');
  const version = Math.floor(bytes[0] / 16);
  if (version !== 4) throw new Malformed(`ip: bad version ${version}`);
  const header = bytes[0] % 16 * 4;
  if (header < 20) throw new Malformed(`ip: bad header length ${header}`);
  if (bytes.length < header) throw new Malformed('ip: truncated header');
  const length = uint(bytes, 2);
  if (length < header) throw new Malformed(`ip: bad total length ${length}`);
  if (length > bytes.length) throw new Malformed(`ip: truncated (total length ${length}, available ${bytes.length})`);
  const flags = uint(bytes, 6);
  const more = Math.floor(flags / 8192) % 2;
  const offset = flags % 8192 * 8;
  const fields = {
    'ip.hdr_len': [header], 'ip.tos': [bytes[1]], 'ip.len': [length], 'ip.id': [uint(bytes, 4)],
    'ip.flags.df': [Math.floor(flags / 16384) % 2], 'ip.flags.mf': [more], 'ip.frag_offset': [offset],
    'ip.ttl': [bytes[8]], 'ip.proto': [bytes[9]], 'ip.checksum': [uint(bytes, 10)],
    'ip.checksum.status': [checksum(bytes.slice(0, header))],
    'ip.src': [uint(bytes, 12, 4)], 'ip.dst': [uint(bytes, 16, 4)]
  };
  if (more === 1 || offset !== 0) fields['ip.fragment'] = [true];
  return { fields, payload: bytes.slice(header, length) };
}

module.exports = { Malformed, uint, integerBytes, checksum, mac, ipv4, ethernet, arp, ip };
