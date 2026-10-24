import * as fs from 'node:fs';

type DnsRecord = { owner: string; ttl: number; type: string; data: string[]; address?: number; groups?: number[]; preference?: number; minimum?: number };
type Zone = { origin: string; server: number; line: number; records: DnsRecord[] };
type Reply = { kind: string; answer: DnsRecord[]; authority: DnsRecord[]; additional: DnsRecord[]; cut?: string; reason?: string };
type CacheEntry = { name: string; type: string; kind: string; records: DnsRecord[]; expiry: number };
type Resolution = { status: string; answer: DnsRecord[] };
const types = ['A', 'NS', 'CNAME', 'SOA', 'PTR', 'MX', 'TXT', 'AAAA'];
const kinds = ['ANSWER', 'CNAME', 'REFERRAL', 'NODATA', 'NXDOMAIN', 'LAME', 'TIMEOUT'];
const integerWord = /^(?:0|[1-9][0-9]{0,8})$/;
const labels = (name: string): string[] => name === '.' ? [] : name.slice(0, -1).split('.');
const below = (name: string, ancestor: string): boolean => ancestor === '.' || name === ancestor || name.endsWith('.' + ancestor);
const ancestors = (name: string): string[] => { const parts = labels(name); return parts.map((_, i) => parts.slice(i).join('.') + '.').concat('.'); };
const compareText = (a: string, b: string): number => a === b ? 0 : a < b ? -1 : 1;
function nameOrder(a: string, b: string): number {
    const left = labels(a).reverse(); const right = labels(b).reverse();
    for (let i = 0; i < Math.min(left.length, right.length); i++) { const order = compareText(left[i], right[i]); if (order !== 0) return order; }
    return left.length - right.length;
}
function parseName(word: string, wildcard = false, origin: string | null = null): string {
    if (origin !== null && word === '@') return origin;
    if (word === '.') return '.';
    const absolute = word.endsWith('.');
    const parts = (absolute ? word.slice(0, -1) : word).split('.');
    if (parts.some((part, i) => !(wildcard && i === 0 && part === '*') && !/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(part))) throw new Error(`bad name ${word}`);
    const name = parts.join('.').toLowerCase() + '.';
    return origin !== null && !absolute && origin !== '.' ? name + origin : name;
}
function ipv4(word: string): number {
    const parts = word.split('.');
    if (parts.length !== 4 || parts.some(part => !/^(?:0|[1-9][0-9]{0,2})$/.test(part) || Number(part) > 255)) throw new Error(`bad address ${word}`);
    return parts.reduce((value, part) => value * 256 + Number(part), 0);
}
function addressText(value: number): string { return [24, 16, 8, 0].map(shift => Math.floor(value / 2 ** shift) % 256).join('.'); }
function ipv6(word: string): number[] {
    const halves = word.split('::');
    if (halves.length > 2) throw new Error(`bad address ${word}`);
    const left = halves[0] === '' ? [] : halves[0].split(':');
    const right = halves.length === 2 && halves[1] !== '' ? halves[1].split(':') : [];
    if ([...left, ...right].some(group => !/^[0-9A-Fa-f]{1,4}$/.test(group)) || (halves.length === 1 ? left.length !== 8 : left.length + right.length > 7)) throw new Error(`bad address ${word}`);
    return [...left.map(group => parseInt(group, 16)), ...Array<number>(halves.length === 2 ? 8 - left.length - right.length : 0).fill(0), ...right.map(group => parseInt(group, 16))];
}
function ipv6Text(groups: number[]): string {
    let best = -1; let length = 0;
    for (let start = 0; start < 8;) {
        if (groups[start] !== 0) { start++; continue; }
        let end = start; while (end < 8 && groups[end] === 0) end++;
        if (end - start >= 2 && end - start > length) { best = start; length = end - start; }
        start = end;
    }
    const words = groups.map(group => group.toString(16));
    return best < 0 ? words.join(':') : words.slice(0, best).join(':') + '::' + words.slice(best + length).join(':');
}
function ttl(word: string): number {
    let result = 0;
    if (integerWord.test(word)) result = Number(word);
    else {
        const units = 'wdhms'; const seconds = [604800, 86400, 3600, 60, 1];
        let position = 0; let previous = -1;
        for (const match of word.matchAll(/(0|[1-9][0-9]{0,2})([wdhms])/gi)) {
            const unit = units.indexOf(match[2].toLowerCase());
            if (match.index !== position || unit <= previous) throw new Error(`bad ttl ${word}`);
            result += Number(match[1]) * seconds[unit]; previous = unit; position += match[0].length;
        }
        if (position !== word.length || position === 0) throw new Error(`bad ttl ${word}`);
    }
    if (result < 1 || result > 604800) throw new Error(`bad ttl ${word}`);
    return result;
}
function checkType(type: string): void { if (!types.includes(type)) throw new Error(`bad type ${type}`); }
function dataOrder(a: DnsRecord, b: DnsRecord): number {
    if (a.type === 'A') return a.address! - b.address!;
    if (a.type === 'AAAA') { for (let i = 0; i < 8; i++) if (a.groups![i] !== b.groups![i]) return a.groups![i] - b.groups![i]; return 0; }
    if (['NS', 'CNAME', 'PTR'].includes(a.type)) return nameOrder(a.data[0], b.data[0]);
    if (a.type === 'MX') return a.preference! - b.preference! || nameOrder(a.data[1], b.data[1]);
    return compareText(a.data.join(' '), b.data.join(' '));
}
function recordOrder(a: DnsRecord, b: DnsRecord): number { return nameOrder(a.owner, b.owner) || types.indexOf(a.type) - types.indexOf(b.type) || dataOrder(a, b); }
function recordText(record: DnsRecord): string { return `${record.owner} ${record.ttl} ${record.type} ${record.data.join(' ')}`; }
function reply(kind: string, answer: DnsRecord[] = [], authority: DnsRecord[] = [], additional: DnsRecord[] = []): Reply { return { kind, answer, authority, additional }; }
function replyText(response: Reply): string { return response.kind === 'REFERRAL' ? `REFERRAL ${response.cut}` : response.kind === 'CNAME' ? `CNAME ${response.answer[0].data[0]}` : response.kind; }
const cacheKey = (name: string, type: string): string => name + ' ' + type;

class Resolver {
    roots: number[] = [];
    zones: Zone[] = [];
    current: Zone | null = null;
    down = new Set<number>();
    settings: Record<string, number> = { MINTTL: 1, MAXTTL: 86400, NEGTTL: 3600 };
    clock = 0;
    cache = new Map<string, CacheEntry>();
    queries = new Map<number, number[]>();
    hits = 0;
    resolutions: Record<string, number> = { NOERROR: 0, NODATA: 0, NXDOMAIN: 0, SERVFAIL: 0 };
    output: string[] = [];

    zoneLine(words: string[], line: number): void {
        if (words[0] === 'ROOT') {
            const addresses: number[] = [];
            for (const word of words.slice(1)) { const address = ipv4(word); if (this.roots.includes(address) || addresses.includes(address)) throw new Error(`duplicate root ${word}`); addresses.push(address); }
            this.roots.push(...addresses); return;
        }
        if (words[0] === 'ZONE') {
            this.current = null;
            const origin = parseName(words[1]); const server = ipv4(words[2]);
            if (this.zones.some(zone => zone.origin === origin && zone.server === server)) throw new Error(`duplicate zone ${origin} at ${words[2]}`);
            this.current = { origin, server, line, records: [] }; this.zones.push(this.current); return;
        }
        const zone = this.current;
        if (zone === null) throw new Error('no current zone');
        const owner = parseName(words[0], true, zone.origin);
        if (!below(owner, zone.origin)) throw new Error('out of zone ' + owner);
        const seconds = ttl(words[1]); const type = words[2]; checkType(type);
        const fields = words.slice(3);
        const required = type === 'MX' ? 2 : type === 'SOA' ? 7 : 1;
        if (type !== 'TXT' && fields.length !== required) throw new Error('wrong field count');
        const record: DnsRecord = { owner, ttl: seconds, type, data: [] };
        const name = (word: string): string => parseName(word, false, zone.origin);
        if (type === 'A') { record.address = ipv4(fields[0]); record.data = [addressText(record.address)]; }
        else if (type === 'AAAA') { record.groups = ipv6(fields[0]); record.data = [ipv6Text(record.groups)]; }
        else if (['NS', 'CNAME', 'PTR'].includes(type)) record.data = [name(fields[0])];
        else if (type === 'MX') {
            if (!integerWord.test(fields[0]) || Number(fields[0]) > 65535) throw new Error('bad preference ' + fields[0]);
            record.preference = Number(fields[0]); record.data = [String(record.preference), name(fields[1])];
        } else if (type === 'TXT') {
            const text = fields.join(' ');
            if (text.length < 2 || !text.startsWith('"') || !text.endsWith('"') || text.slice(1, -1).includes('"')) throw new Error('bad text ' + text);
            record.data = [text];
        } else {
            record.data = [name(fields[0]), name(fields[1])];
            for (const field of fields.slice(2, 6)) { if (!integerWord.test(field)) throw new Error('bad number ' + field); record.data.push(String(Number(field))); }
            if (!integerWord.test(fields[6]) || Number(fields[6]) < 1 || Number(fields[6]) > 86400) throw new Error('bad minimum ' + fields[6]);
            record.minimum = Number(fields[6]); record.data.push(String(record.minimum));
        }
        if (type === 'NS' && labels(owner)[0] === '*') throw new Error('ns at wildcard');
        if (type === 'SOA' && owner !== zone.origin) throw new Error('soa not at origin');
        if (type === 'SOA' && zone.records.some(record => record.type === 'SOA')) throw new Error('duplicate soa');
        if (zone.records.some(previous => previous.owner === owner && previous.type === type && JSON.stringify(previous.data) === JSON.stringify(record.data))) throw new Error('duplicate record');
        if (zone.records.some(previous => previous.owner === owner && (type === 'CNAME' || previous.type === 'CNAME'))) throw new Error('cname conflict ' + owner);
        zone.records.push(record);
    }
    finishZones(): void {
        const valid: Zone[] = [];
        for (const zone of this.zones) {
            if (!zone.records.some(record => record.type === 'SOA')) this.output.push(`error line ${zone.line}: zone ${zone.origin} at ${addressText(zone.server)} has no soa`);
            else { valid.push(zone); this.output.push(`zone ${zone.origin} at ${addressText(zone.server)} records=${zone.records.length}`); }
        }
        this.zones = valid;
        this.output.push(`loaded roots=${this.roots.length} zones=${valid.length} records=${valid.reduce((sum, zone) => sum + zone.records.length, 0)}`);
    }
    authoritative(server: number, name: string, type: string, cut: string): Reply {
        if (this.down.has(server) || !this.zones.some(zone => zone.server === server)) return reply('TIMEOUT');
        const candidates = this.zones.filter(zone => zone.server === server && below(name, zone.origin)).sort((a, b) => labels(b.origin).length - labels(a.origin).length);
        const zone = candidates[0];
        if (zone === undefined || labels(zone.origin).length < labels(cut).length) return reply('LAME');
        const soa = zone.records.find(record => record.type === 'SOA')!;
        const delegation = ancestors(name).reverse().find(ancestor => ancestor !== zone.origin && below(ancestor, zone.origin) && zone.records.some(record => record.owner === ancestor && record.type === 'NS'));
        if (delegation !== undefined) {
            const authority = zone.records.filter(record => record.owner === delegation && record.type === 'NS').sort(dataOrder);
            const additional = authority.flatMap(record => zone.records.filter(glue => glue.owner === record.data[0] && glue.type === 'A').sort(dataOrder));
            return { ...reply('REFERRAL', [], authority, additional), cut: delegation };
        }
        const exists = (candidate: string): boolean => zone.records.some(record => below(record.owner, candidate));
        let records = zone.records.filter(record => record.owner === name);
        if (records.length === 0) {
            if (exists(name)) return reply('NODATA', [], [soa]);
            const ancestor = ancestors(name).slice(1).find(exists)!;
            const wildcard = ancestor === '.' ? '*.' : '*.' + ancestor;
            records = zone.records.filter(record => record.owner === wildcard);
            if (records.length === 0) return reply('NXDOMAIN', [], [soa]);
        }
        const answers = records.filter(record => record.type === type).sort(dataOrder).map(record => ({ ...record, owner: name }));
        if (answers.length > 0) return reply('ANSWER', answers);
        const cname = records.find(record => record.type === 'CNAME');
        if (type !== 'CNAME' && cname !== undefined) return reply('CNAME', [{ ...cname, owner: name }]);
        return reply('NODATA', [], [soa]);
    }
    ask(server: number, name: string, type: string, cut: string): Reply {
        const response = this.authoritative(server, name, type, cut);
        const counts = this.queries.get(server) ?? Array<number>(kinds.length).fill(0);
        counts[kinds.indexOf(response.kind)]++; this.queries.set(server, counts); return response;
    }
    positive(records: DnsRecord[]): DnsRecord[] {
        const seconds = Math.min(this.settings.MAXTTL, Math.max(this.settings.MINTTL, Math.min(...records.map(record => record.ttl))));
        this.cache.set(cacheKey(records[0].owner, records[0].type), { name: records[0].owner, type: records[0].type, kind: 'POS', records: [...records].sort(dataOrder), expiry: this.clock + seconds });
        return records.map(record => ({ ...record, ttl: seconds }));
    }
    trace(depth: number, text: string): void { this.output.push(' '.repeat(2 * (depth + 1)) + text); }
    queryServers(name: string, type: string, cut: string, nameservers: string[] | null, depth: number, stack: string[]): Reply | null {
        const query = (server: number): Reply | null => {
            const response = this.ask(server, name, type, cut);
            this.trace(depth, `ASK ${addressText(server)} ${name} ${type} -> ${replyText(response)}`);
            return response.kind === 'LAME' || response.kind === 'TIMEOUT' ? null : response;
        };
        if (nameservers === null) { for (const server of this.roots) { const response = query(server); if (response !== null) return response; } return null; }
        for (const host of [...nameservers].sort(nameOrder)) {
            const cached = this.cache.get(cacheKey(host, 'A'));
            let addresses: number[] = [];
            if (cached?.kind === 'POS') addresses = cached.records.map(record => record.address!);
            else if (stack.includes(cacheKey(host, 'A'))) this.trace(depth, `GLUELESS ${host} -> LOOP`);
            else {
                this.trace(depth, `GLUELESS ${host}`);
                const resolution = this.resolve(host, 'A', depth + 1, stack);
                if (resolution.status === 'NOERROR') addresses = resolution.answer.filter(record => record.type === 'A').map(record => record.address!);
            }
            for (const server of [...new Set(addresses)].sort((a, b) => a - b)) { const response = query(server); if (response !== null) return response; }
        }
        return null;
    }
    lookup(name: string, type: string, depth: number, stack: string[]): Reply {
        const hit = (response: Reply, text: string): Reply => { this.hits++; this.trace(depth, `CACHE HIT ${name} ${type} -> ${text}`); return response; };
        const exact = this.cache.get(cacheKey(name, type));
        if (exact !== undefined) return hit(exact.kind === 'POS' ? reply('ANSWER', exact.records.map(record => ({ ...record, ttl: exact.expiry - this.clock }))) : reply(exact.kind), exact.kind === 'POS' ? 'ANSWER' : exact.kind);
        if ([...this.cache.values()].some(entry => entry.kind === 'NXDOMAIN' && below(name, entry.name))) return hit(reply('NXDOMAIN'), 'NXDOMAIN');
        const cname = this.cache.get(cacheKey(name, 'CNAME'));
        if (type !== 'CNAME' && cname?.kind === 'POS') return hit(reply('CNAME', cname.records.map(record => ({ ...record, ttl: cname.expiry - this.clock }))), `CNAME ${cname.records[0].data[0]}`);
        const ns = ancestors(name).map(ancestor => this.cache.get(cacheKey(ancestor, 'NS'))).find(entry => entry?.kind === 'POS');
        let cut = ns?.name ?? '.';
        let nameservers = ns === undefined ? null : ns.records.map(record => record.data[0]);
        if (ns !== undefined) { this.hits++; this.trace(depth, `CACHE HIT ${name} ${type} -> REFERRAL ${cut}`); }
        while (true) {
            const response = this.queryServers(name, type, cut, nameservers, depth, stack);
            if (response === null) return { ...reply('SERVFAIL'), reason: 'no server for ' + cut };
            if (response.kind === 'REFERRAL') {
                this.positive(response.authority);
                const groups = new Map<string, DnsRecord[]>();
                for (const record of response.additional) { const group = groups.get(record.owner) ?? []; group.push(record); groups.set(record.owner, group); }
                for (const group of groups.values()) this.positive(group);
                cut = response.cut!; nameservers = response.authority.map(record => record.data[0]);
            } else if (response.kind === 'ANSWER' || response.kind === 'CNAME') return { ...response, answer: this.positive(response.answer) };
            else {
                const soa = response.authority[0]; const seconds = Math.min(soa.ttl, soa.minimum!, this.settings.NEGTTL);
                this.cache.set(cacheKey(name, type), { name, type, kind: response.kind, records: [], expiry: this.clock + seconds }); return response;
            }
        }
    }
    resolve(name: string, type: string, depth = 0, stack: string[] = []): Resolution {
        stack.push(cacheKey(name, type));
        const chain: DnsRecord[] = []; const seen = new Set([name]); let current = name;
        let status = ''; let answer: DnsRecord[] = [];
        while (true) {
            const result = this.lookup(current, type, depth, stack);
            if (result.kind === 'CNAME') {
                const record = result.answer[0]; chain.push(record); const target = record.data[0];
                if (seen.has(target)) { status = 'SERVFAIL cname loop'; break; }
                if (chain.length === 9) { status = 'SERVFAIL cname chain too long'; break; }
                seen.add(target); current = target;
            } else {
                status = result.kind === 'ANSWER' ? 'NOERROR' : result.kind === 'SERVFAIL' ? 'SERVFAIL ' + result.reason : result.kind;
                if (!status.startsWith('SERVFAIL')) answer = [...chain, ...(result.kind === 'ANSWER' ? result.answer : [])];
                break;
            }
        }
        stack.pop(); this.resolutions[status.split(' ')[0]]++; return { status, answer };
    }
    emitResolution(result: Resolution): void { for (const record of result.answer) this.output.push('answer ' + recordText(record)); this.output.push('status ' + result.status); }
    addresses(host: string): string {
        const a = this.resolve(host, 'A'); const aaaa = this.resolve(host, 'AAAA');
        const addresses = [...(a.status === 'NOERROR' ? a.answer.filter(record => record.type === 'A') : []), ...(aaaa.status === 'NOERROR' ? aaaa.answer.filter(record => record.type === 'AAAA') : [])].map(record => record.data[0]);
        return addresses.length === 0 ? 'no address' : addresses.join(' ');
    }
    command(words: string[]): void {
        const command = words[0];
        if (command === 'RESOLVE' || command === 'MX') {
            const name = parseName(words[1], true); const type = command === 'MX' ? 'MX' : words[2]; checkType(type);
            this.output.push(command === 'MX' ? `mx ${name}` : `resolve ${name} ${type}`);
            const result = this.resolve(name, type); this.emitResolution(result);
            if (command === 'MX') {
                if (result.status === 'NOERROR') for (const record of result.answer.filter(record => record.type === 'MX')) {
                    const host = record.data[1]; this.output.push(host === '.' ? `exchange ${record.preference} . -> null` : `exchange ${record.preference} ${host} -> ${this.addresses(host)}`);
                } else if (result.status === 'NODATA') {
                    const aliases = result.answer.filter(record => record.type === 'CNAME'); const host = aliases.length === 0 ? name : aliases[aliases.length - 1].data[0];
                    this.output.push(`implicit ${host} -> ${this.addresses(host)}`);
                }
            }
        } else if (command === 'REVERSE') {
            let address: string; let name: string;
            if (words[1].includes(':')) { const groups = ipv6(words[1]); address = ipv6Text(groups); name = [...groups.map(group => group.toString(16).padStart(4, '0')).join('')].reverse().join('.') + '.ip6.arpa.'; }
            else { address = addressText(ipv4(words[1])); name = address.split('.').reverse().join('.') + '.in-addr.arpa.'; }
            this.output.push(`reverse ${address} ${name}`); this.emitResolution(this.resolve(name, 'PTR'));
        } else if (command === 'QUERY' || command === 'DUMP') {
            const server = ipv4(words[1]); const name = parseName(words[2], command === 'QUERY');
            if (command === 'QUERY') {
                checkType(words[3]); const result = this.ask(server, name, words[3], '.');
                this.output.push(`query ${addressText(server)} ${name} ${words[3]} -> ${replyText(result)}`);
                for (const record of result.answer) this.output.push('answer ' + recordText(record));
                for (const record of result.authority) this.output.push('authority ' + recordText(record));
                for (const record of result.additional) this.output.push('additional ' + recordText(record));
            } else {
                const zone = this.zones.find(zone => zone.server === server && zone.origin === name);
                if (this.down.has(server) || !this.zones.some(zone => zone.server === server)) this.output.push(`dump ${addressText(server)} ${name} -> TIMEOUT`);
                else if (zone === undefined) this.output.push(`dump ${addressText(server)} ${name} -> REFUSED`);
                else { this.output.push(`dump ${addressText(server)} ${name} records=${zone.records.length}`); for (const record of [...zone.records].sort(recordOrder)) this.output.push('  ' + recordText(record)); }
            }
        } else if (command === 'DOWN' || command === 'UP') {
            const address = ipv4(words[1]);
            if (command === 'DOWN' && this.down.has(address)) throw new Error(`server ${words[1]} already down`);
            if (command === 'UP' && !this.down.has(address)) throw new Error(`server ${words[1]} not down`);
            if (command === 'DOWN') this.down.add(address); else this.down.delete(address);
            this.output.push(command.toLowerCase() + ' ' + addressText(address));
        } else if (command === 'SET') {
            if (!Object.hasOwn(this.settings, words[1])) throw new Error('bad setting ' + words[1]);
            if (!integerWord.test(words[2]) || Number(words[2]) < 1 || Number(words[2]) > 604800) throw new Error('bad value ' + words[2]);
            const value = Number(words[2]); const minimum = words[1] === 'MINTTL' ? value : this.settings.MINTTL; const maximum = words[1] === 'MAXTTL' ? value : this.settings.MAXTTL;
            if (minimum > maximum) throw new Error('minttl above maxttl');
            this.settings[words[1]] = value; this.output.push(`set ${words[1]}=${value}`);
        } else if (command === 'TIME') {
            if (!integerWord.test(words[1]) || Number(words[1]) < 1 || Number(words[1]) > 1000000) throw new Error('bad time ' + words[1]);
            this.clock += Number(words[1]); let expired = 0;
            for (const [key, entry] of this.cache) if (entry.expiry <= this.clock) { this.cache.delete(key); expired++; }
            this.output.push(`time now=${this.clock} expired=${expired}`);
        } else if (command === 'CACHE' || command === 'FLUSH') {
            const name = words.length === 1 ? '.' : parseName(words[1]);
            const entries = [...this.cache.values()].filter(entry => below(entry.name, name)).sort((a, b) => nameOrder(a.name, b.name) || types.indexOf(a.type) - types.indexOf(b.type));
            if (command === 'FLUSH') { for (const entry of entries) this.cache.delete(cacheKey(entry.name, entry.type)); this.output.push(`flush removed=${entries.length}`); }
            else {
                this.output.push(`cache entries=${entries.length}`);
                for (const entry of entries) {
                    if (entry.kind === 'POS') for (const record of entry.records) this.output.push('  ' + recordText({ ...record, ttl: entry.expiry - this.clock }));
                    else this.output.push(`  ${entry.name} ${entry.expiry - this.clock} ${entry.type} ${entry.kind}`);
                }
            }
        } else {
            const queryCount = [...this.queries.values()].reduce((sum, counts) => sum + counts.reduce((a, b) => a + b, 0), 0);
            this.output.push(`stats queries=${queryCount} hits=${this.hits}`);
            for (const [server, counts] of [...this.queries].sort((a, b) => a[0] - b[0])) this.output.push(`  ${addressText(server)} sent=${counts.reduce((a, b) => a + b, 0)} ` + kinds.map((kind, index) => `${kind.toLowerCase()}=${counts[index]}`).join(' '));
            this.output.push(`resolutions noerror=${this.resolutions.NOERROR} nodata=${this.resolutions.NODATA} nxdomain=${this.resolutions.NXDOMAIN} servfail=${this.resolutions.SERVFAIL}`);
        }
    }
    run(lines: string[]): void {
        let position = 0;
        while (lines[position] !== 'END ZONES') {
            try { this.zoneLine(lines[position].split(' '), position + 1); } catch (error) { this.output.push(`error line ${position + 1}: ${(error as Error).message}`); }
            position++;
        }
        position++; this.finishZones();
        while (lines[position] !== 'END') {
            try { this.command(lines[position].split(' ')); } catch (error) { this.output.push(`error line ${position + 1}: ${(error as Error).message}`); }
            position++;
        }
    }
}
const resolver = new Resolver();
resolver.run(fs.readFileSync(0, 'utf8').split('\n'));
process.stdout.write(resolver.output.join('\n') + '\n');
