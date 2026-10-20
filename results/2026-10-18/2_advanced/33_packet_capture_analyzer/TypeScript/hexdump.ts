import { readFileSync } from 'node:fs';

export interface Capture { number: number; time: number; length: number; bytes: number[]; error?: string }
export function readCapture(): Capture[] {
  const packets: Capture[] = [];
  let current: Capture | undefined;
  const finish = () => {
    if (current && !current.error && current.bytes.length !== current.length) current.error = `dump: length mismatch (header ${current.length}, data ${current.bytes.length})`;
  };
  readFileSync('input/capture.txt', 'ascii').slice(0, -1).split('\n').forEach((line, i) => {
    if (line.startsWith('PACKET ')) {
      finish(); const parts = line.split(' ');
      current = { number: +parts[1], time: +parts[2], length: +parts[3], bytes: [] }; packets.push(current);
    } else if (line && current && !current.error) {
      if (!/^[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}$/.test(line)) current.error = `dump: bad line ${i + 1}`;
      else if (parseInt(line.slice(0, 4), 16) !== current.bytes.length) current.error = `dump: offset mismatch at line ${i + 1}`;
      else current.bytes.push(...line.slice(6).split(' ').map(byte => parseInt(byte, 16)));
    }
  });
  finish(); return packets;
}
export function dumpLines(bytes: number[]): string[] {
  const lines: string[] = [];
  for (let offset = 0; offset < bytes.length; offset += 16) {
    const piece = bytes.slice(offset, offset + 16);
    const hex = piece.map(byte => byte.toString(16).padStart(2, '0')).join(' ').padEnd(47);
    const characters = piece.map(byte => byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.').join('');
    lines.push(`${offset.toString(16).padStart(4, '0')}  ${hex}  |${characters}|`);
  }
  return lines;
}
