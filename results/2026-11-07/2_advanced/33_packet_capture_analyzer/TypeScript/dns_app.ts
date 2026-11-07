import { bit, integer, ipv4, Malformed, type Dissection, type Fields } from './link_network.ts';

const typeNames = new Map([
  [1, 'A'],
  [2, 'NS'],
  [5, 'CNAME'],
  [6, 'SOA'],
  [12, 'PTR'],
  [15, 'MX'],
  [16, 'TXT'],
  [28, 'AAAA'],
]);
export const typeName = (type: number) => typeNames.get(type) ?? `TYPE${type}`;
export const rcodeName = (rcode: number) =>
  ['NoError', 'FormErr', 'ServFail', 'NXDomain', 'NotImp', 'Refused'][rcode] ?? `RCODE${rcode}`;
export interface DnsAnswer {
  type: number;
  data: string;
}
export interface DnsDissection extends Dissection {
  answers: DnsAnswer[];
}
function ipv6(bytes: number[]): string {
  const groups = Array.from({ length: 8 }, (_, i) => integer(bytes, i * 2, 2));
  let bestStart = -1;
  let bestLength = 1;
  for (let i = 0; i < 8;) {
    if (groups[i] !== 0) {
      i++;
      continue;
    }
    const start = i;
    while (i < 8 && groups[i] === 0) i++;
    if (i - start > bestLength) {
      bestStart = start;
      bestLength = i - start;
    }
  }
  const text = groups.map((group) => group.toString(16));
  return bestStart < 0
    ? text.join(':')
    : text.slice(0, bestStart).join(':') + '::' + text.slice(bestStart + bestLength).join(':');
}
export function dns(bytes: number[]): DnsDissection {
  const requireBytes = (position: number, length: number) => {
    if (position + length > bytes.length) throw new Malformed('dns: truncated');
  };
  const read = (position: number, length: number) => {
    requireBytes(position, length);
    return integer(bytes, position, length);
  };
  const name = (start: number): { text: string; end: number } => {
    let position = start;
    let pointers = 0;
    let end: number | undefined;
    const labels: string[] = [];
    while (true) {
      const c = read(position, 1);
      if (c === 0) return { text: labels.join('.') || '<root>', end: end ?? position + 1 };
      if (c >= 192) {
        const d = read(position + 1, 1);
        end ??= position + 2;
        if (++pointers > 16) throw new Malformed('dns: compression loop');
        position = (c - 192) * 256 + d;
        if (position >= bytes.length) throw new Malformed('dns: pointer out of range');
      } else if (c >= 64) throw new Malformed('dns: bad label type');
      else {
        requireBytes(position + 1, c);
        labels.push(
          bytes
            .slice(position + 1, position + c + 1)
            .map((byte) =>
              byte >= 33 && byte <= 126 && byte !== 46 && byte !== 92
                ? String.fromCharCode(byte)
                : '\\' + String(byte).padStart(3, '0'),
            )
            .join(''),
        );
        position += c + 1;
      }
    }
  };
  requireBytes(0, 12);
  const flags = read(2, 2);
  const counts = [read(4, 2), read(6, 2), read(8, 2), read(10, 2)];
  const fields: Fields = new Map([
    ['dns.id', [read(0, 2)]],
    ['dns.flags', [flags]],
    ['dns.flags.response', [bit(flags, 15)]],
    ['dns.flags.opcode', [Math.floor(flags / 2048) % 16]],
    ['dns.flags.rcode', [flags % 16]],
    ['dns.count.queries', [counts[0]]],
    ['dns.count.answers', [counts[1]]],
    ['dns.count.auth_rr', [counts[2]]],
    ['dns.count.add_rr', [counts[3]]],
  ]);
  const append = (field: string, value: string | number) => {
    const values = fields.get(field) ?? [];
    values.push(value);
    fields.set(field, values);
  };
  let position = 12;
  for (let i = 0; i < counts[0]; i++) {
    const question = name(position);
    position = question.end;
    requireBytes(position, 4);
    append('dns.qry.name', question.text);
    append('dns.qry.type', read(position, 2));
    position += 4;
  }
  const answers: DnsAnswer[] = [];
  for (let section = 1; section <= 3; section++) {
    for (let i = 0; i < counts[section]; i++) {
      const owner = name(position);
      position = owner.end;
      requireBytes(position, 10);
      const type = read(position, 2);
      const rrClass = read(position + 2, 2);
      const ttl = read(position + 4, 4);
      const length = read(position + 8, 2);
      const start = position + 10;
      requireBytes(start, length);
      let data: string;
      let end: number;
      if (type === 1) {
        data = ipv4(read(start, 4));
        end = start + 4;
      } else if (type === 28) {
        requireBytes(start, 16);
        data = ipv6(bytes.slice(start, start + 16));
        end = start + 16;
      } else if ([2, 5, 12].includes(type)) {
        const result = name(start);
        data = result.text;
        end = result.end;
      } else if (type === 15) {
        const preference = read(start, 2);
        const result = name(start + 2);
        data = `${preference} ${result.text}`;
        end = result.end;
      } else if (type === 6) {
        const first = name(start);
        const second = name(first.end);
        const values: number[] = [];
        for (let j = 0; j < 5; j++) values.push(read(second.end + j * 4, 4));
        data = `${first.text} ${second.text} ${values.join(' ')}`;
        end = second.end + 20;
      } else {
        data = `${length} bytes`;
        end = start + length;
      }
      if (end !== start + length) throw new Malformed('dns: bad rdata length');
      append(
        ['', 'dns.answer', 'dns.authority', 'dns.additional'][section],
        `${owner.text} ${typeName(type)} ${rrClass === 1 ? 'IN' : `CLASS${rrClass}`} ${ttl} ${data}`,
      );
      if (section === 1) {
        answers.push({ type, data });
        if (type === 1) append('dns.a', read(start, 4));
      }
      position = start + length;
    }
  }
  return { fields, payload: [], answers };
}
