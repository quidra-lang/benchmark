export type FieldValue = number | string | true;
export type Fields = Map<string, FieldValue[]>;
export interface Dissection {
  fields: Fields;
  payload: number[];
}
export class Malformed extends Error {}
export function integer(bytes: number[], offset: number, count: number): number {
  let value = 0;
  for (let i = offset; i < offset + count; i++) value = value * 256 + bytes[i];
  return value;
}
export function numberField(fields: Fields, name: string): number | undefined {
  const value = fields.get(name)?.[0];
  return typeof value === 'number' ? value : undefined;
}
export function numeric(fields: Fields, name: string): number {
  const value = numberField(fields, name);
  if (value === undefined) throw new Error(`Missing numeric field ${name}`);
  return value;
}
export function stringField(fields: Fields, name: string): string | undefined {
  const value = fields.get(name)?.[0];
  return typeof value === 'string' ? value : undefined;
}
export const bit = (value: number, position: number) => Math.floor(value / 2 ** position) % 2;
export function checksum(bytes: number[]): string {
  let sum = 0;
  for (let i = 0; i < bytes.length; i += 2) sum += bytes[i] * 256 + (bytes[i + 1] ?? 0);
  while (sum > 65535) sum = (sum % 65536) + Math.floor(sum / 65536);
  return sum === 65535 ? 'good' : 'bad';
}
export const hex = (value: number, digits: number) =>
  '0x' + value.toString(16).padStart(digits, '0');
export function addressBytes(value: number, count: number): number[] {
  return Array.from({ length: count }, (_, i) => Math.floor(value / 256 ** (count - i - 1)) % 256);
}
export const ipv4 = (value: number) => addressBytes(value, 4).join('.');
export const mac = (value: number) =>
  addressBytes(value, 6)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join(':');
export function ethernet(bytes: number[]): Dissection {
  if (bytes.length < 14) throw new Malformed('eth: truncated');
  return {
    fields: new Map([
      ['eth.dst', [integer(bytes, 0, 6)]],
      ['eth.src', [integer(bytes, 6, 6)]],
      ['eth.type', [integer(bytes, 12, 2)]],
    ]),
    payload: bytes.slice(14),
  };
}
export function arp(bytes: number[]): Dissection {
  if (bytes.length < 28) throw new Malformed('arp: truncated');
  if (
    integer(bytes, 0, 2) !== 1 ||
    integer(bytes, 2, 2) !== 2048 ||
    bytes[4] !== 6 ||
    bytes[5] !== 4
  ) {
    throw new Malformed('arp: unsupported format');
  }
  return {
    fields: new Map([
      ['arp.opcode', [integer(bytes, 6, 2)]],
      ['arp.src.hw', [integer(bytes, 8, 6)]],
      ['arp.src.ip', [integer(bytes, 14, 4)]],
      ['arp.dst.hw', [integer(bytes, 18, 6)]],
      ['arp.dst.ip', [integer(bytes, 24, 4)]],
    ]),
    payload: [],
  };
}
export function ip(bytes: number[]): Dissection {
  if (bytes.length < 20) throw new Malformed('ip: truncated header');
  const version = Math.floor(bytes[0] / 16);
  if (version !== 4) throw new Malformed(`ip: bad version ${version}`);
  const header = (bytes[0] % 16) * 4;
  if (header < 20) throw new Malformed(`ip: bad header length ${header}`);
  if (bytes.length < header) throw new Malformed('ip: truncated header');
  const total = integer(bytes, 2, 2);
  if (total < header) throw new Malformed(`ip: bad total length ${total}`);
  if (total > bytes.length) {
    throw new Malformed(`ip: truncated (total length ${total}, available ${bytes.length})`);
  }
  const flags = integer(bytes, 6, 2);
  const fields: Fields = new Map<string, FieldValue[]>([
    ['ip.hdr_len', [header]],
    ['ip.tos', [bytes[1]]],
    ['ip.len', [total]],
    ['ip.id', [integer(bytes, 4, 2)]],
    ['ip.flags.df', [bit(flags, 14)]],
    ['ip.flags.mf', [bit(flags, 13)]],
    ['ip.frag_offset', [(flags % 8192) * 8]],
    ['ip.ttl', [bytes[8]]],
    ['ip.proto', [bytes[9]]],
    ['ip.checksum', [integer(bytes, 10, 2)]],
    ['ip.checksum.status', [checksum(bytes.slice(0, header))]],
    ['ip.src', [integer(bytes, 12, 4)]],
    ['ip.dst', [integer(bytes, 16, 4)]],
  ]);
  if (bit(flags, 13) || flags % 8192) fields.set('ip.fragment', [true]);
  return { fields, payload: bytes.slice(header, total) };
}
