const fs = require('node:fs');

const dropReasons = ['down', 'martian', 'rpf', 'invalid', 'acl_in', 'ttl', 'noroute', 'acl_out', 'exhausted'];
function addressText(address) {
    return [24, 16, 8, 0].map(shift => Math.floor(address / 2 ** shift) % 256).join('.');
}
function network(address, length) {
    const size = 2 ** (32 - length);
    return Math.floor(address / size) * size;
}
function contains(prefix, address) {
    return network(prefix.address, prefix.length) === network(address, prefix.length);
}
function parseAddress(text) {
    const fields = text.split('.');
    if (fields.length !== 4 || fields.some(field => !/^(?:0|[1-9][0-9]{0,2})$/.test(field) || Number(field) > 255)) throw new Error(`bad address ${text}`);
    return fields.reduce((value, field) => value * 256 + Number(field), 0);
}
function parsePrefix(text, checkHost = true) {
    const fields = text.split('/');
    let address;
    try {
        if (fields.length !== 2 || !/^(?:0|[1-9][0-9]?)$/.test(fields[1]) || Number(fields[1]) > 32) throw new Error();
        address = parseAddress(fields[0]);
    } catch {
        throw new Error(`bad prefix ${text}`);
    }
    const length = Number(fields[1]);
    if (checkHost && network(address, length) !== address) throw new Error(`host bits set in ${text}`);
    return { address, length };
}
function parsePorts(text) {
    if (text === 'ANY') return { low: 0, high: 65535, any: true };
    const values = text.split('-').map(Number);
    const low = values[0];
    const high = values[values.length - 1];
    if (high > 65535 || low > 65535 || low > high) throw new Error(`bad port range ${text}`);
    return { low, high, any: false };
}
function prefixText(prefix) {
    return prefix.length === 0 ? 'any' : `${addressText(prefix.address)}/${prefix.length}`;
}
function portsText(ports) {
    return ports.any ? 'any' : ports.low === ports.high ? String(ports.low) : `${ports.low}-${ports.high}`;
}
function routeText(route) {
    return `${route.type} ${addressText(route.address)}/${route.length}${route.hop === null ? '' : ` via ${addressText(route.hop)}`} dev ${route.output.name} metric ${route.metric}`;
}
function tupleText(tuple) {
    return `${addressText(tuple.source)}:${tuple.sport} > ${addressText(tuple.destination)}:${tuple.dport}`;
}
function sameTuple(left, right) {
    return left.protocol === right.protocol && left.source === right.source && left.sport === right.sport && left.destination === right.destination && left.dport === right.dport;
}
function compareText(left, right) {
    return left === right ? 0 : left < right ? -1 : 1;
}

class Router {
    interfaces = new Map();
    routes = [];
    staticNat = [];
    forwards = [];
    connections = [];
    timeouts = { TCP: 300, UDP: 60, ICMP: 30 };
    clock = 0;
    packetNumber = 0;
    connectionNumber = 0;
    routeOrder = 0;
    forwarded = 0;
    local = 0;
    errors = 0;
    drops = Object.fromEntries(dropReasons.map(reason => [reason, 0]));
    output = [];

    iface(name) {
        const iface = this.interfaces.get(name);
        if (iface === undefined) throw new Error(`no interface ${name}`);
        return iface;
    }
    localInterface(address) {
        return [...this.interfaces.values()].find(iface => iface.address === address);
    }
    orderedInterfaces() {
        return [...this.interfaces.values()].sort((a, b) => compareText(a.name, b.name));
    }
    select(address) {
        let best = null;
        for (const route of this.routes) {
            if (!route.output.up || !contains(route, address)) continue;
            if (best === null || route.length > best.length || route.length === best.length && route.metric < best.metric) best = route;
        }
        return best;
    }
    evaluateAcl(iface, direction, tuple, established) {
        const acl = iface.acl[direction];
        if (acl.rules.length === 0) return null;
        for (const rule of [...acl.rules].sort((a, b) => a.sequence - b.sequence)) {
            if (rule.protocol !== 'ANY' && rule.protocol !== tuple.protocol) continue;
            if (!contains(rule.source, tuple.source) || !contains(rule.destination, tuple.destination)) continue;
            if ((rule.protocol === 'TCP' || rule.protocol === 'UDP') && (tuple.sport < rule.sports.low || tuple.sport > rule.sports.high || tuple.dport < rule.dports.low || tuple.dport > rule.dports.high)) continue;
            if (rule.established && !established) continue;
            rule.hits++;
            if (rule.action === 'PERMIT') return null;
            const prefix = `${iface.name} ${direction} ${rule.sequence}`;
            return rule.action === 'DENY' ? `DROP acl ${prefix}` : `REJECT acl ${prefix} ${tuple.protocol === 'TCP' ? 'tcp-reset' : 'icmp-prohibited'}`;
        }
        acl.denied++;
        return `DROP acl ${iface.name} ${direction} default`;
    }
    processPacket(input, tuple, flags, ttl) {
        const finish = (verdict, reason) => {
            if (reason === 'forwarded') this.forwarded++;
            else if (reason === 'local') this.local++;
            else {
                this.drops[reason]++;
                input.drop++;
            }
            return verdict;
        };
        if (!input.up) return finish('DROP down', 'down');
        const martian = (address) => address < 2 ** 24 || Math.floor(address / 2 ** 24) === 127 || address >= 224 * 2 ** 24;
        if (martian(tuple.source) || martian(tuple.destination) || this.localInterface(tuple.source) !== undefined) return finish('DROP martian', 'martian');
        if (input.rpf !== 'off') {
            const reverse = this.select(tuple.source);
            if (reverse === null || input.rpf === 'strict' && reverse.output !== input) return finish('DROP rpf', 'rpf');
        }
        const pureSyn = tuple.protocol === 'TCP' && flags === 'S';
        let connection = null;
        let direction = 'new';
        for (const candidate of this.connections) {
            if (sameTuple(tuple, candidate.original)) {
                connection = candidate;
                direction = 'orig';
                break;
            }
            if (sameTuple(tuple, candidate.reply)) {
                connection = candidate;
                direction = 'reply';
                break;
            }
        }
        if (connection !== null && connection.state === 'CLOSED' && pureSyn) {
            this.connections = this.connections.filter(candidate => candidate !== connection);
            connection = null;
            direction = 'new';
        }
        if (tuple.protocol === 'TCP' && connection === null && !pureSyn) return finish('DROP invalid', 'invalid');
        const inbound = this.evaluateAcl(input, 'in', tuple, connection !== null);
        if (inbound !== null) return finish(inbound, 'acl_in');
        let destination = tuple.destination;
        let dport = tuple.dport;
        let used = null;
        if (input.outside) {
            const mapping = this.staticNat.find(mapping => mapping.outside === destination);
            if (mapping !== undefined) destination = mapping.inside;
            else if (destination === input.address) {
                const forward = this.forwards.find(rule => rule.output === input && rule.protocol === tuple.protocol && rule.outport === dport);
                if (forward !== undefined) {
                    destination = forward.inside;
                    dport = forward.inport;
                } else {
                    used = input.pat.find(mapping => mapping.protocol === tuple.protocol && mapping.outport === dport) ?? null;
                    if (used !== null) {
                        destination = used.inside;
                        dport = used.inport;
                    }
                }
            }
        }
        const local = this.localInterface(destination);
        if (local !== undefined) return finish(`LOCAL ${local.name}`, 'local');
        if (ttl === 1) return finish('DROP ttl', 'ttl');
        const route = this.select(destination);
        if (route === null) return finish('DROP noroute', 'noroute');
        const output = route.output;
        const outbound = this.evaluateAcl(output, 'out', { ...tuple, destination, dport }, connection !== null);
        if (outbound !== null) return finish(outbound, 'acl_out');
        let source = tuple.source;
        let sport = tuple.sport;
        if (!input.outside && output.outside) {
            const mapping = this.staticNat.find(mapping => mapping.inside === source);
            if (mapping !== undefined) source = mapping.outside;
            else {
                const forward = this.forwards.find(rule => rule.output === output && rule.protocol === tuple.protocol && rule.inside === source && rule.inport === sport);
                if (forward !== undefined) {
                    source = output.address;
                    sport = forward.outport;
                } else if (output.pool !== null) {
                    used = output.pat.find(mapping => mapping.protocol === tuple.protocol && mapping.inside === source && mapping.inport === sport) ?? null;
                    if (used === null) {
                        let port = 20000;
                        while (port < 20000 + output.pool && (output.pat.some(mapping => mapping.outport === port) || this.forwards.some(rule => rule.output === output && rule.outport === port))) port++;
                        if (port === 20000 + output.pool) return finish('DROP exhausted', 'exhausted');
                        used = { protocol: tuple.protocol, inside: source, inport: sport, outport: port, used: this.clock };
                        output.pat.push(used);
                    }
                    source = output.address;
                    sport = used.outport;
                }
            }
        }
        if (used !== null) used.used = this.clock;
        if (connection === null) {
            connection = {
                number: ++this.connectionNumber, original: tuple,
                reply: { protocol: tuple.protocol, source: destination, sport: dport, destination: source, dport: sport },
                input, output, state: tuple.protocol === 'TCP' ? 'SYN_SENT' : 'UNREPLIED',
                origPackets: 0, replyPackets: 0, used: this.clock, origFin: false, replyFin: false,
            };
            this.connections.push(connection);
            direction = 'new';
        }
        if (direction === 'reply') connection.replyPackets++;
        else connection.origPackets++;
        connection.used = this.clock;
        if (tuple.protocol !== 'TCP') {
            if (direction === 'reply') connection.state = 'REPLIED';
        } else if (flags.includes('R')) connection.state = 'CLOSED';
        else {
            if (connection.state === 'SYN_SENT' && direction === 'reply' && flags.includes('S') && flags.includes('A')) connection.state = 'ESTABLISHED';
            if (flags.includes('F') && (connection.state === 'ESTABLISHED' || connection.state === 'FIN_WAIT')) {
                if (direction === 'reply') connection.replyFin = true;
                else connection.origFin = true;
                connection.state = connection.origFin && connection.replyFin ? 'CLOSED' : 'FIN_WAIT';
            }
        }
        output.tx++;
        route.hits++;
        let verdict = `FORWARD ${output.name} ${route.hop === null ? 'direct' : `via ${addressText(route.hop)}`} ttl=${ttl - 1}`;
        if (destination !== tuple.destination || dport !== tuple.dport) verdict += ` dnat=${addressText(destination)}:${dport}`;
        if (source !== tuple.source || sport !== tuple.sport) verdict += ` snat=${addressText(source)}:${sport}`;
        return finish(`${verdict} conn=${connection.number} ${direction}`, 'forwarded');
    }

    command(words) {
        const command = words[0];
        if (command === 'IFACE') {
            const [name, text] = words.slice(1);
            if (this.interfaces.has(name)) throw new Error(`duplicate interface ${name}`);
            const prefix = parsePrefix(text, false);
            if (prefix.length < 8 || prefix.length > 30) throw new Error(`bad prefix ${text}`);
            const net = network(prefix.address, prefix.length);
            if (prefix.address === net || prefix.address === net + 2 ** (32 - prefix.length) - 1) throw new Error(`bad host address ${text}`);
            for (const iface of this.interfaces.values()) {
                const length = Math.min(prefix.length, iface.length);
                if (network(prefix.address, length) === network(iface.address, length)) throw new Error(`subnet overlaps ${iface.name}`);
            }
            const iface = { name, ...prefix, up: true, outside: false, pool: null, rpf: 'off', rx: 0, tx: 0, drop: 0, acl: { in: { rules: [], denied: 0 }, out: { rules: [], denied: 0 } }, pat: [] };
            this.interfaces.set(name, iface);
            this.routes.push({ type: 'C', address: net, length: prefix.length, output: iface, hop: null, metric: 0, hits: 0, order: this.routeOrder++ });
            this.output.push(`ok iface ${name} ${text} network ${addressText(net)}/${prefix.length}`);
        } else if (command === 'UP' || command === 'DOWN') {
            const iface = this.iface(words[1]);
            const up = command === 'UP';
            if (iface.up === up) throw new Error(`interface ${iface.name} already ${up ? 'up' : 'down'}`);
            iface.up = up;
            this.output.push(`ok ${command.toLowerCase()} ${iface.name}`);
        } else if (command === 'ROUTE') {
            const prefix = parsePrefix(words[1]);
            let output;
            let hop = null;
            if (words[2] === 'VIA') hop = parseAddress(words[3]);
            else output = this.iface(words[3]);
            const metric = Number(words[4]);
            if (metric < 1 || metric > 255) throw new Error(`bad metric ${words[4]}`);
            if (hop !== null) {
                if (this.localInterface(hop) !== undefined) throw new Error(`nexthop ${words[3]} is local`);
                output = [...this.interfaces.values()].find(iface => contains(iface, hop));
                if (output === undefined) throw new Error(`nexthop ${words[3]} unreachable`);
            }
            if (this.routes.some(route => route.type === 'S' && route.address === prefix.address && route.length === prefix.length && route.output === output && route.hop === hop)) throw new Error(`duplicate route ${words[1]}`);
            const route = { type: 'S', ...prefix, output: output, hop, metric, hits: 0, order: this.routeOrder++ };
            this.routes.push(route);
            this.output.push(`ok route ${routeText(route)}`);
        } else if (command === 'NOROUTE') {
            const prefix = parsePrefix(words[1]);
            const matches = (route) => route.type === 'S' && route.address === prefix.address && route.length === prefix.length;
            const removed = this.routes.filter(matches).length;
            if (removed === 0) throw new Error(`no static route ${words[1]}`);
            this.routes = this.routes.filter(route => !matches(route));
            this.output.push(`ok noroute ${words[1]} removed=${removed}`);
        } else if (command === 'LOOKUP') {
            const route = this.select(parseAddress(words[1]));
            this.output.push(`lookup ${words[1]} ${route === null ? 'none' : routeText(route)}`);
        } else if (command === 'ACL') {
            const iface = this.iface(words[1]);
            const direction = words[2].toLowerCase();
            const sequence = Number(words[3]);
            if (sequence < 1 || sequence > 9999) throw new Error(`bad sequence ${words[3]}`);
            const source = words[6] === 'ANY' ? { address: 0, length: 0 } : parsePrefix(words[6]);
            const sports = parsePorts(words[7]);
            const destination = words[8] === 'ANY' ? { address: 0, length: 0 } : parsePrefix(words[8]);
            const dports = parsePorts(words[9]);
            if ((words[5] === 'ICMP' || words[5] === 'ANY') && (!sports.any || !dports.any)) throw new Error(`ports not allowed for ${words[5]}`);
            const acl = iface.acl[direction];
            if (acl.rules.some(rule => rule.sequence === sequence)) throw new Error(`duplicate sequence ${words[3]}`);
            acl.rules.push({ sequence, action: words[4], protocol: words[5], source, sports, destination, dports, established: words.length === 11, hits: 0 });
            this.output.push(`ok acl ${iface.name} ${direction} ${words[3]}`);
        } else if (command === 'NOACL') {
            const iface = this.iface(words[1]);
            const direction = words[2].toLowerCase();
            const acl = iface.acl[direction];
            const rule = acl.rules.find(rule => rule.sequence === Number(words[3]));
            if (rule === undefined) throw new Error(`no rule ${words[3]} on ${iface.name} ${direction}`);
            acl.rules = acl.rules.filter(candidate => candidate !== rule);
            this.output.push(`ok noacl ${iface.name} ${direction} ${words[3]} hits=${rule.hits}`);
        } else if (command === 'NAT') this.natCommand(words);
        else if (command === 'RPF') {
            const iface = this.iface(words[1]);
            iface.rpf = words[2].toLowerCase();
            this.output.push(`ok rpf ${iface.name} ${iface.rpf}`);
        } else if (command === 'TIMEOUT') {
            const seconds = Number(words[2]);
            if (seconds < 1 || seconds > 86400) throw new Error(`bad timeout ${words[2]}`);
            this.timeouts[words[1]] = seconds;
            this.output.push(`ok timeout ${words[1]} ${words[2]}`);
        } else if (command === 'TICK') {
            const seconds = Number(words[1]);
            if (seconds < 1 || seconds > 86400) throw new Error(`bad tick ${words[1]}`);
            this.clock += seconds;
            const before = this.connections.length;
            this.connections = this.connections.filter(connection => {
                const protocol = connection.original.protocol;
                const timeout = protocol !== 'TCP' || connection.state === 'ESTABLISHED' ? this.timeouts[protocol] : connection.state === 'CLOSED' ? 10 : 60;
                return this.clock - connection.used < timeout;
            });
            let removed = 0;
            for (const iface of this.interfaces.values()) {
                const count = iface.pat.length;
                iface.pat = iface.pat.filter(mapping => this.clock - mapping.used < this.timeouts[mapping.protocol]);
                removed += count - iface.pat.length;
            }
            this.output.push(`ok tick time=${this.clock} expired conns=${before - this.connections.length} nat=${removed}`);
        } else if (command === 'PACKET') {
            const iface = this.iface(words[1]);
            const protocol = words[2];
            const flags = words[3];
            if (protocol !== 'TCP' && flags !== '-') throw new Error(`flags not allowed for ${protocol}`);
            if (protocol === 'TCP' && flags !== '-' && (!/^[SAFR]+$/.test(flags) || new Set(flags).size !== flags.length)) throw new Error(`bad flags ${flags}`);
            const source = parseAddress(words[4]);
            const sport = Number(words[5]);
            if (sport > 65535) throw new Error(`bad port ${words[5]}`);
            const destination = parseAddress(words[6]);
            const dport = Number(words[7]);
            if (dport > 65535) throw new Error(`bad port ${words[7]}`);
            const ttl = Number(words[8]);
            if (ttl < 1 || ttl > 255) throw new Error(`bad ttl ${words[8]}`);
            this.packetNumber++;
            iface.rx++;
            const verdict = this.processPacket(iface, { protocol, source, sport, destination, dport }, flags, ttl);
            this.output.push(`#${this.packetNumber} ${protocol} ${flags} ${words[4]}:${words[5]} > ${words[6]}:${words[7]} ${verdict}`);
        } else if (command === 'SHOW') this.show(words[1]);
        else if (command === 'CLEAR') {
            if (words[1] === 'CONNS') {
                const mappings = [...this.interfaces.values()].reduce((total, iface) => total + iface.pat.length, 0);
                this.output.push(`ok clear conns=${this.connections.length} nat=${mappings}`);
                this.connections = [];
                for (const iface of this.interfaces.values()) iface.pat = [];
            } else {
                this.forwarded = this.local = this.errors = 0;
                for (const reason of dropReasons) this.drops[reason] = 0;
                for (const route of this.routes) route.hits = 0;
                for (const iface of this.interfaces.values()) {
                    iface.rx = iface.tx = iface.drop = 0;
                    for (const acl of Object.values(iface.acl)) {
                        acl.denied = 0;
                        for (const rule of acl.rules) rule.hits = 0;
                    }
                }
                this.output.push('ok clear counters');
            }
        }
    }

    natCommand(words) {
        if (words[1] === 'STATIC') {
            const inside = parseAddress(words[2]);
            const outside = parseAddress(words[3]);
            if (this.localInterface(inside) !== undefined) throw new Error(`address ${words[2]} is local`);
            if (this.localInterface(outside) !== undefined) throw new Error(`address ${words[3]} is local`);
            if (this.staticNat.some(mapping => mapping.inside === inside)) throw new Error(`duplicate static ${words[2]}`);
            if (this.staticNat.some(mapping => mapping.outside === outside)) throw new Error(`duplicate static ${words[3]}`);
            this.staticNat.push({ inside, outside });
            this.output.push(`ok nat static ${words[2]} ${words[3]}`);
            return;
        }
        const iface = this.iface(words[2]);
        if (words[1] === 'OUTSIDE') {
            if (iface.outside) throw new Error(`interface ${iface.name} already outside`);
            iface.outside = true;
            this.output.push(`ok nat outside ${iface.name}`);
        } else if (words[1] === 'PAT') {
            const count = Number(words[3]);
            if (count < 1 || count > 1000) throw new Error(`bad pool size ${words[3]}`);
            if (iface.pool !== null) throw new Error(`pat already on ${iface.name}`);
            iface.pool = count;
            iface.outside = true;
            this.output.push(`ok nat pat ${iface.name} ${addressText(iface.address)} 20000-${20000 + count - 1}`);
        } else {
            const protocol = words[3];
            const outport = Number(words[4]);
            if (outport < 1 || outport > 65535) throw new Error(`bad port ${words[4]}`);
            const inside = parseAddress(words[5]);
            const inport = Number(words[6]);
            if (inport < 1 || inport > 65535) throw new Error(`bad port ${words[6]}`);
            if (!iface.outside) throw new Error(`interface ${iface.name} not outside`);
            if (this.localInterface(inside) !== undefined) throw new Error(`address ${words[5]} is local`);
            if (this.forwards.some(rule => rule.output === iface && rule.protocol === protocol && rule.outport === outport)) throw new Error(`duplicate forward ${iface.name} ${protocol} ${words[4]}`);
            this.forwards.push({ output: iface, protocol, outport, inside, inport });
            this.output.push(`ok nat forward ${iface.name} ${protocol} ${words[4]} ${words[5]}:${words[6]}`);
        }
    }

    show(what) {
        const interfaces = this.orderedInterfaces();
        if (what === 'IFACES') {
            this.output.push(`show ifaces count=${interfaces.length}`);
            for (const iface of interfaces) this.output.push(`${iface.name} ${addressText(iface.address)}/${iface.length} ${iface.up ? 'up' : 'down'} ${iface.outside ? 'outside' : 'inside'} rpf=${iface.rpf}${iface.pool === null ? '' : ` pat=${iface.pat.length}/${iface.pool}`}`);
        } else if (what === 'ROUTES') {
            this.output.push(`show routes count=${this.routes.length}`);
            for (const route of [...this.routes].sort((a, b) => a.address - b.address || a.length - b.length || a.metric - b.metric || a.order - b.order)) this.output.push(`${routeText(route)} hits=${route.hits}${route.output.up ? '' : ' inactive'}`);
        } else if (what === 'ACL') {
            this.output.push(`show acl count=${interfaces.reduce((total, iface) => total + iface.acl.in.rules.length + iface.acl.out.rules.length, 0)}`);
            for (const iface of interfaces) {
                for (const direction of ['in', 'out']) {
                    const acl = iface.acl[direction];
                    if (acl.rules.length === 0) continue;
                    for (const rule of [...acl.rules].sort((a, b) => a.sequence - b.sequence)) this.output.push(`acl ${iface.name} ${direction} ${rule.sequence} ${rule.action} ${rule.protocol} ${prefixText(rule.source)} ${portsText(rule.sports)} ${prefixText(rule.destination)} ${portsText(rule.dports)}${rule.established ? ' established' : ''} hits=${rule.hits}`);
                    this.output.push(`acl ${iface.name} ${direction} default DENY hits=${acl.denied}`);
                }
            }
        } else if (what === 'NAT') {
            const count = interfaces.reduce((total, iface) => total + iface.pat.length, 0);
            this.output.push(`show nat static=${this.staticNat.length} forward=${this.forwards.length} pat=${count}`);
            for (const mapping of [...this.staticNat].sort((a, b) => a.inside - b.inside)) this.output.push(`static ${addressText(mapping.inside)} ${addressText(mapping.outside)}`);
            for (const rule of [...this.forwards].sort((a, b) => compareText(a.output.name, b.output.name) || a.outport - b.outport || compareText(a.protocol, b.protocol))) this.output.push(`forward ${rule.output.name} ${rule.protocol} ${rule.outport} ${addressText(rule.inside)}:${rule.inport}`);
            for (const iface of interfaces) for (const mapping of [...iface.pat].sort((a, b) => a.outport - b.outport)) this.output.push(`pat ${iface.name} ${mapping.outport} ${mapping.protocol} ${addressText(mapping.inside)}:${mapping.inport} idle=${this.clock - mapping.used}`);
        } else if (what === 'CONNS') {
            this.output.push(`show conns count=${this.connections.length}`);
            for (const connection of this.connections) this.output.push(`conn ${connection.number} ${connection.original.protocol} ${tupleText(connection.original)} reply ${tupleText(connection.reply)} in=${connection.input.name} out=${connection.output.name} state=${connection.state} pkts=${connection.origPackets}/${connection.replyPackets} idle=${this.clock - connection.used}`);
        } else {
            const dropped = dropReasons.reduce((total, reason) => total + this.drops[reason], 0);
            this.output.push(`show counters packets=${this.forwarded + this.local + dropped} forwarded=${this.forwarded} local=${this.local} dropped=${dropped} errors=${this.errors}`);
            this.output.push('drops ' + dropReasons.map(reason => `${reason}=${this.drops[reason]}`).join(' '));
            for (const iface of interfaces) this.output.push(`iface ${iface.name} rx=${iface.rx} tx=${iface.tx} drop=${iface.drop}`);
        }
    }

    run(lines) {
        const count = Number(lines[0]);
        for (const line of lines.slice(1, count + 1)) {
            try {
                this.command(line.split(' '));
            } catch (error) {
                this.errors++;
                this.output.push(`error: ${error.message}`);
            }
        }
    }
}

const router = new Router();
router.run(fs.readFileSync(0, 'utf8').split('\n'));
process.stdout.write(router.output.join('\n') + '\n');
