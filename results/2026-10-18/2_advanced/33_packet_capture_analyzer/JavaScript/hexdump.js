'use strict';

const fs = require('node:fs');

function readCapture(filename) {
  const packets = [];
  let packet;
  function finish() {
    if (!packet) return;
    if (packet.reason === null && packet.bytes.length !== packet.length) {
      packet.reason = `dump: length mismatch (header ${packet.length}, data ${packet.bytes.length})`;
    }
    packets.push(packet);
  }
  const lines = fs.readFileSync(filename, 'ascii').split('\n');
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    if (line.startsWith('PACKET ')) {
      finish();
      const [, number, time, length] = line.split(' ');
      packet = { number: Number(number), time: Number(time), length: Number(length), bytes: [], reason: null };
    } else if (line !== '' && packet.reason === null) {
      const match = /^([0-9a-f]{4})  ([0-9a-f]{2}(?: [0-9a-f]{2}){0,15})$/.exec(line);
      if (!match) {
        packet.reason = `dump: bad line ${index + 1}`;
      } else if (Number.parseInt(match[1], 16) !== packet.bytes.length) {
        packet.reason = `dump: offset mismatch at line ${index + 1}`;
      } else {
        packet.bytes.push(...match[2].split(' ').map(byte => Number.parseInt(byte, 16)));
      }
    }
  }
  finish();
  return packets;
}

function dumpLines(bytes) {
  const lines = [];
  for (let offset = 0; offset < bytes.length; offset += 16) {
    const piece = bytes.slice(offset, offset + 16);
    const hex = piece.map(byte => byte.toString(16).padStart(2, '0')).join(' ').padEnd(47, ' ');
    const characters = piece.map(byte => byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.').join('');
    lines.push(`${offset.toString(16).padStart(4, '0')}  ${hex}  |${characters}|`);
  }
  return lines;
}

module.exports = { readCapture, dumpLines };
