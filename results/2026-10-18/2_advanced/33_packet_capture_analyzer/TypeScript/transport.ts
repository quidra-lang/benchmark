import { addressBytes, bit, checksum, integer, Malformed, type Dissection, type Fields, type FieldValue } from './link_network.ts';

export const flagNames = ['FIN', 'SYN', 'RST', 'PSH', 'ACK', 'URG', 'ECE', 'CWR'];
function pseudoHeader(source: number, destination: number, protocol: number, length: number): number[] {
  return [...addressBytes(source, 4), ...addressBytes(destination, 4), 0, protocol, ...addressBytes(length, 2)];
}
export function icmp(bytes: number[]): Dissection {
  if (bytes.length < 8) throw new Malformed('icmp: truncated');
  const fields: Fields = new Map<string, FieldValue[]>([['icmp.type', [bytes[0]]], ['icmp.code', [bytes[1]]], ['icmp.checksum', [integer(bytes, 2, 2)]], ['icmp.checksum.status', [checksum(bytes)]]]);
  if (bytes[0] === 0 || bytes[0] === 8) { fields.set('icmp.id', [integer(bytes, 4, 2)]); fields.set('icmp.seq', [integer(bytes, 6, 2)]); }
  return { fields, payload: bytes.slice(8) };
}
export function udp(bytes: number[], source: number, destination: number): Dissection {
  if (bytes.length < 8) throw new Malformed('udp: truncated');
  const length = integer(bytes, 4, 2);
  if (length < 8 || length > bytes.length) throw new Malformed(`udp: bad length ${length}`);
  const check = integer(bytes, 6, 2);
  const fields: Fields = new Map<string, FieldValue[]>([['udp.srcport', [integer(bytes, 0, 2)]], ['udp.dstport', [integer(bytes, 2, 2)]], ['udp.length', [length]],
    ['udp.checksum', [check]], ['udp.checksum.status', [check === 0 ? 'none' : checksum([...pseudoHeader(source, destination, 17, length), ...bytes.slice(0, length)])]]]);
  return { fields, payload: bytes.slice(8, length) };
}
export function tcp(bytes: number[], source: number, destination: number): Dissection {
  if (bytes.length < 20) throw new Malformed('tcp: truncated header');
  const header = Math.floor(bytes[12] / 16) * 4;
  if (header < 20) throw new Malformed(`tcp: bad header length ${header}`);
  if (header > bytes.length) throw new Malformed('tcp: truncated header');
  const flags = bytes[13];
  const fields: Fields = new Map<string, FieldValue[]>([['tcp.srcport', [integer(bytes, 0, 2)]], ['tcp.dstport', [integer(bytes, 2, 2)]], ['tcp.seq_raw', [integer(bytes, 4, 4)]],
    ['tcp.hdr_len', [header]], ['tcp.flags', [flags]], ['tcp.window', [integer(bytes, 14, 2)]], ['tcp.checksum', [integer(bytes, 16, 2)]],
    ['tcp.checksum.status', [checksum([...pseudoHeader(source, destination, 6, bytes.length), ...bytes])]], ['tcp.urgent', [integer(bytes, 18, 2)]], ['tcp.len', [bytes.length - header]]]);
  flagNames.slice(0, 6).forEach((flag, i) => fields.set(`tcp.flags.${flag.toLowerCase()}`, [bit(flags, i)]));
  if (bit(flags, 4)) fields.set('tcp.ack_raw', [integer(bytes, 8, 4)]);
  const options: string[] = [], optionBytes = bytes.slice(20, header);
  const lengths = new Map<number, number[]>([[2, [4]], [3, [3]], [4, [2]], [5, [10, 18, 26, 34]], [8, [10]]]);
  for (let i = 0; i < optionBytes.length;) {
    const kind = optionBytes[i];
    if (kind === 0) { options.push('EOL'); break; }
    if (kind === 1) { options.push('NOP'); i++; continue; }
    const length = optionBytes[i + 1] ?? 0;
    if (length < 2 || i + length > optionBytes.length || (lengths.has(kind) && !lengths.get(kind)!.includes(length))) { fields.set('tcp.options.malformed', [true]); break; }
    const body = optionBytes.slice(i + 2, i + length);
    if (kind === 2) { const value = integer(body, 0, 2); options.push(`MSS ${value}`); fields.set('tcp.options.mss', [value]); }
    else if (kind === 3) { options.push(`WS ${body[0]}`); fields.set('tcp.options.wscale', [body[0]]); }
    else if (kind === 4) options.push('SACK_PERM');
    else if (kind === 5) { let option = 'SACK'; for (let j = 0; j < body.length; j += 8) option += ` ${integer(body, j, 4)}-${integer(body, j + 4, 4)}`; options.push(option); }
    else if (kind === 8) options.push(`TS ${integer(body, 0, 4)} ${integer(body, 4, 4)}`);
    else options.push(`kind ${kind} len ${length}`);
    i += length;
  }
  if (options.length) fields.set('tcp.option', options);
  return { fields, payload: bytes.slice(header) };
}
