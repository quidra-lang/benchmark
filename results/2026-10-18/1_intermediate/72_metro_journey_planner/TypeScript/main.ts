import * as fs from 'node:fs';

interface Station { id: string; zone: number; name: string; transfer: number; closed: boolean; walks: Map<string, number> }
interface Line { id: string; first: number; last: number; headway: number; stops: string[]; offsets: number[]; delay: number; suspended: boolean }
interface Direction { line: Line; order: number; stops: string[]; offsets: number[] }
interface Ride { kind: 'ride'; line: string; terminal: string; from: string; departure: number; to: string; arrival: number; stops: number }
interface Walk { kind: 'walk'; from: string; departure: number; to: string; arrival: number }
interface Stay { kind: 'stay'; station: string; departure: number; arrival: number }
type Leg = Ride | Walk | Stay;
interface Label { time: number; journey: Leg[] }
interface Tariff { discount: number; window: number; prices: number[] }
interface Event { time: number; line: string; order: number; terminal: string; start: string }
const stations = new Map<string, Station>();
const lines = new Map<string, Line>();
const closed = new Set<string>();
const output: string[] = [];
let tariff: Tariff | null = null;
function fail(message: string): never { throw new Error(`ERROR ${message}`); }
function compare(a: string, b: string): number { return a < b ? -1 : a > b ? 1 : 0; }
function time(word: string): number { const [h, m] = word.split(':').map(Number); return h * 60 + m; }
function clock(value: number): string { return `${Math.floor(value / 60).toString().padStart(2, '0')}:${(value % 60).toString().padStart(2, '0')}`; }
function pair(a: string, b: string): string { return a < b ? `${a}-${b}` : `${b}-${a}`; }
function station(id: string): Station {
    const result = stations.get(id);
    if (!result) fail(`unknown station ${id}`);
    return result;
}
function line(id: string): Line {
    const result = lines.get(id);
    if (!result) fail(`unknown line ${id}`);
    return result;
}
function openStation(id: string): void { if (stations.get(id)!.closed) fail(`station ${id} is closed`); }
function common(origin: string, destination: string): void {
    station(origin); station(destination);
    if (origin === destination) fail('origin and destination are the same');
    openStation(origin); openStation(destination);
}
function orderedLines(): Line[] { return [...lines.values()].sort((a, b) => compare(a.id, b.id)); }
function directions(item: Line): Direction[] {
    const total = item.offsets[item.offsets.length - 1];
    return [{ line: item, order: 0, stops: item.stops, offsets: item.offsets },
        { line: item, order: 1, stops: [...item.stops].reverse(), offsets: [...item.offsets].reverse().map(offset => total - offset) }];
}
function trips(item: Line): number { return Math.floor((item.last - item.first) / item.headway) + 1; }
function nextTrain(direction: Direction, at: number, ready: number): number | null {
    const item = direction.line;
    const q = Math.max(0, Math.ceil((ready - item.first - item.delay - direction.offsets[at]) / item.headway));
    return q < trips(item) ? q : null;
}
function trainTime(direction: Direction, q: number, at: number): number {
    return direction.line.first + direction.line.delay + q * direction.line.headway + direction.offsets[at];
}
function ride(direction: Direction, boarding: number, alighting: number, q: number): Ride {
    return { kind: 'ride', line: direction.line.id, terminal: direction.stops[direction.stops.length - 1],
        from: direction.stops[boarding], departure: trainTime(direction, q, boarding),
        to: direction.stops[alighting], arrival: trainTime(direction, q, alighting), stops: alighting - boarding };
}
function update(labels: Map<string, Label>, id: string, candidate: Label): boolean {
    const old = labels.get(id);
    if (!old || old.time > candidate.time) { labels.set(id, candidate); return true; }
    return false;
}
function earliest(origin: string, departure: number): Map<string, Label> {
    const labels = new Map<string, Label>([[origin, { time: departure, journey: [] }]]), settled = new Set<string>();
    const service = orderedLines();
    while (true) {
        const choices = [...labels.keys()].filter(id => !settled.has(id));
        if (!choices.length) return labels;
        choices.sort((a, b) => labels.get(a)!.time - labels.get(b)!.time || compare(a, b));
        const u = choices[0], label = labels.get(u)!, s = stations.get(u)!;
        settled.add(u);
        const ready = label.time + (u === origin ? 0 : s.transfer);
        for (const item of service) if (!item.suspended && item.stops.includes(u)) {
            for (const direction of directions(item)) {
                const i = direction.stops.indexOf(u), last = direction.stops.length - 1;
                if (i === last) continue;
                const q = nextTrain(direction, i, ready);
                if (q === null) continue;
                for (let j = i + 1; j <= last; j++) {
                    const v = direction.stops[j];
                    if (closed.has(pair(direction.stops[j - 1], v))) break;
                    if (stations.get(v)!.closed) continue;
                    const leg = ride(direction, i, j, q);
                    update(labels, v, { time: leg.arrival, journey: [...label.journey, leg] });
                }
            }
        }
        for (const v of [...s.walks.keys()].sort()) {
            const arrival = label.time + s.walks.get(v)!;
            if (!stations.get(v)!.closed && arrival <= 1440) {
                const leg: Walk = { kind: 'walk', from: u, departure: label.time, to: v, arrival };
                update(labels, v, { time: arrival, journey: [...label.journey, leg] });
            }
        }
    }
}
function walkStep(labels: Map<string, Label>, sources: Set<string>, marked: Set<string>): void {
    const recorded = new Map<string, Label>([...sources].map((id): [string, Label] => [id, labels.get(id)!]));
    for (const u of [...sources].sort()) {
        const label = recorded.get(u)!, s = stations.get(u)!;
        for (const v of [...s.walks.keys()].sort()) {
            const arrival = label.time + s.walks.get(v)!;
            if (stations.get(v)!.closed || arrival > 1440) continue;
            const leg: Walk = { kind: 'walk', from: u, departure: label.time, to: v, arrival };
            if (update(labels, v, { time: arrival, journey: [...label.journey, leg] })) marked.add(v);
        }
    }
}
function rounds(origin: string, departure: number): Map<string, Label>[] {
    let labels = new Map<string, Label>([[origin, { time: departure, journey: [] }]]), marked = new Set([origin]);
    walkStep(labels, new Set([origin]), marked);
    const result = [labels], service = orderedLines();
    while (marked.size) {
        const previous = labels, previousMarked = marked;
        labels = new Map(previous); marked = new Set();
        const walking = new Set<string>();
        for (const item of service) if (!item.suspended) {
            for (const direction of directions(item)) {
                let boarded: number | null = null, boarding = 0;
                let journey: Leg[] = [];
                for (let j = 0; j < direction.stops.length; j++) {
                    const v = direction.stops[j];
                    if (j && closed.has(pair(direction.stops[j - 1], v))) boarded = null;
                    if (stations.get(v)!.closed) continue;
                    if (boarded !== null) {
                        const leg = ride(direction, boarding, j, boarded);
                        if (update(labels, v, { time: leg.arrival, journey: [...journey, leg] })) {
                            walking.add(v); marked.add(v);
                        }
                    }
                    if (j + 1 < direction.stops.length && previousMarked.has(v)) {
                        const old = previous.get(v)!, ready = old.time + (v === origin ? 0 : stations.get(v)!.transfer);
                        const q = nextTrain(direction, j, ready);
                        if (q !== null && (boarded === null || q < boarded)) { boarded = q; boarding = j; journey = old.journey; }
                    }
                }
            }
        }
        walkStep(labels, walking, marked);
        result.push(labels);
    }
    return result;
}
function printJourney(heading: string, departure: number, label: Label): void {
    const rides = label.journey.filter(leg => leg.kind === 'ride').length, walks = label.journey.filter(leg => leg.kind === 'walk').length;
    output.push(`${heading} ${clock(departure)} -> ${clock(label.time)} total ${label.time - departure} rides ${rides} walks ${walks}`);
    let previous = departure;
    for (const leg of label.journey) {
        if (leg.kind === 'ride') output.push(`RIDE ${leg.line} toward ${leg.terminal} ${leg.from} ${clock(leg.departure)} -> ${leg.to} ${clock(leg.arrival)} wait ${leg.departure - previous} stops ${leg.stops}`);
        else if (leg.kind === 'walk') output.push(`WALK ${leg.from} ${clock(leg.departure)} -> ${leg.to} ${clock(leg.arrival)}`);
        else output.push(`STAY ${leg.station} ${clock(leg.departure)} -> ${clock(leg.arrival)}`);
        previous = leg.arrival;
    }
}
function printFare(origin: string, destination: string, word: string, fareClass: string, label: Label): void {
    const tickets: string[] = [];
    let total = 0, previous: Ride | null = null;
    const half = (value: number): number => Math.ceil(value / 20) * 10;
    for (const leg of label.journey) if (leg.kind === 'ride') {
        const item = lines.get(leg.line)!, direction = directions(item).find(d => d.stops[d.stops.length - 1] === leg.terminal)!;
        const start = direction.stops.indexOf(leg.from), end = direction.stops.indexOf(leg.to);
        const zones = new Set(direction.stops.slice(start, end + 1).map(id => stations.get(id)!.zone)).size;
        const base = tariff!.prices[Math.min(zones, tariff!.prices.length) - 1], price = fareClass === 'CHILD' ? half(base) : base;
        const cap = fareClass === 'CHILD' ? half(tariff!.discount) : tariff!.discount;
        const discount = previous && leg.departure - previous.arrival <= tariff!.window ? Math.min(cap, price) : 0;
        const payment = price - discount;
        total += payment;
        tickets.push(`TICKET ${leg.line} ${leg.from} ${leg.to} zones ${zones} price ${price} discount ${discount} pay ${payment}`);
        previous = leg;
    }
    output.push(`FARE ${origin} ${destination} ${word} ${fareClass} rides ${tickets.length} total ${total}`, ...tickets);
}
function execute(commandLine: string): void {
    const [command, ...args] = commandLine.split(' '), a = args[0], b = args[1];
    switch (command) {
        case 'STATION':
            if (stations.has(a)) fail(`station ${a} already exists`);
            stations.set(a, { id: a, zone: Number(b), name: args[2], transfer: 0, closed: false, walks: new Map() });
            output.push(`STATION ${a} zone ${b} ${args[2]}`);
            break;
        case 'LINE': {
            if (lines.has(a)) fail(`line ${a} already exists`);
            const stops: string[] = [], offsets = [0];
            for (let i = 4; i < args.length; i += 2) stops.push(args[i]);
            for (const id of stops) station(id);
            const seen = new Set<string>();
            for (const id of stops) { if (seen.has(id)) fail(`station ${id} appears twice on line ${a}`); seen.add(id); }
            for (let i = 5; i < args.length; i += 2) offsets.push(offsets[offsets.length - 1] + Number(args[i]));
            const first = time(b), last = time(args[2]), headway = Number(args[3]), total = offsets[offsets.length - 1];
            if (first > last) fail(`line ${a} first departure is after last departure`);
            if (last + total > 1440) fail(`line ${a} runs past 24:00`);
            const item: Line = { id: a, first, last, headway, stops, offsets, delay: 0, suspended: false };
            lines.set(a, item);
            output.push(`LINE ${a} stops ${stops.length} time ${total} trips ${trips(item)}`);
            break;
        }
        case 'TRANSFER': station(a).transfer = Number(b); output.push(`TRANSFER ${a} ${b}`); break;
        case 'WALK': {
            const x = station(a), y = station(b), duration = Number(args[2]);
            if (a === b) fail(`walk from ${a} to itself`);
            const old = x.walks.get(b);
            x.walks.set(b, duration); y.walks.set(a, duration);
            output.push(`WALK ${a} ${b} ${duration}${old === undefined ? '' : ` was ${old}`}`);
            break;
        }
        case 'TARIFF': {
            const prices = args.slice(2).map(Number);
            if (prices.some((price, i) => i > 0 && price < prices[i - 1])) fail('tariff prices must not decrease');
            tariff = { discount: Number(a), window: Number(b), prices };
            output.push(`TARIFF zones ${prices.length} discount ${a} window ${b}`);
            break;
        }
        case 'CLOSE': case 'OPEN': {
            const s = station(a), closing = command === 'CLOSE';
            if (args.length === 1) {
                if (s.closed === closing) fail(`station ${a} is ${closing ? 'already closed' : 'not closed'}`);
                s.closed = closing;
                output.push(`${command} ${a}`);
            } else {
                station(b);
                const key = pair(a, b);
                const affected = orderedLines().filter(item => item.stops.some((id, i) => i > 0 && pair(item.stops[i - 1], id) === key));
                if (closing && !affected.length) fail(`no segment ${a}-${b}`);
                if (closed.has(key) === closing) fail(`segment ${a}-${b} is ${closing ? 'already closed' : 'not closed'}`);
                if (closing) closed.add(key); else closed.delete(key);
                output.push(`${command} ${a}-${b}${closing ? ` lines ${affected.map(item => item.id).join(' ')}` : ''}`);
            }
            break;
        }
        case 'DELAY': {
            const item = line(a), delay = Number(b);
            if (item.last + delay + item.offsets[item.offsets.length - 1] > 1440) fail(`line ${a} runs past 24:00`);
            item.delay = delay; output.push(`DELAY ${a} ${delay}`);
            break;
        }
        case 'SUSPEND': case 'RESUME': {
            const item = line(a), suspended = command === 'SUSPEND';
            if (item.suspended === suspended) fail(`line ${a} is ${suspended ? 'already suspended' : 'not suspended'}`);
            item.suspended = suspended; output.push(`${command} ${a}`);
            break;
        }
        case 'ROUTE': case 'FEWEST': case 'PARETO': case 'FARE': case 'LASTTRAIN': case 'ARRIVEBY': case 'PROFILE': {
            common(a, b);
            if (command === 'FARE') {
                if (args[3] !== 'ADULT' && args[3] !== 'CHILD') fail(`unknown fare class ${args[3]}`);
                if (!tariff) fail('no tariff');
            }
            if (command === 'PROFILE' && time(args[2]) > time(args[3])) fail(`empty interval ${args[2]} ${args[3]}`);
            if (command === 'LASTTRAIN' || command === 'ARRIVEBY') {
                const deadline = command === 'LASTTRAIN' ? 1440 : time(args[2]);
                const heading = `${command} ${a} ${b}${command === 'ARRIVEBY' ? ` by ${args[2]}` : ''}`;
                let found = false;
                for (let departure = deadline - 1; departure >= 0; departure--) {
                    const label = earliest(a, departure).get(b);
                    if (label && label.time <= deadline) { printJourney(heading, departure, label); found = true; break; }
                }
                if (!found) output.push(`${heading} none`);
            } else if (command === 'PROFILE') {
                const start = time(args[2]), end = time(args[3]), arrivals: (number | undefined)[] = [];
                for (let departure = start; departure <= end; departure++) arrivals.push(earliest(a, departure).get(b)?.time);
                const selected: number[] = [];
                for (let i = 0; i < arrivals.length; i++) if (arrivals[i] !== undefined &&
                    (i === arrivals.length - 1 || arrivals[i + 1] === undefined || arrivals[i]! < arrivals[i + 1]!)) selected.push(i);
                output.push(`PROFILE ${a} ${b} ${args[2]} ${args[3]} count ${selected.length}`);
                for (const i of selected) output.push(`${clock(start + i)} -> ${clock(arrivals[i]!)} total ${arrivals[i]! - start - i}`);
            } else if (command === 'FEWEST' || command === 'PARETO') {
                const departure = time(args[2]), all = rounds(a, departure);
                if (command === 'FEWEST') {
                    const k = all.findIndex(labels => labels.has(b));
                    if (k < 0) output.push(`FEWEST ${a} ${b} ${args[2]} unreachable`);
                    else printJourney(`FEWEST ${a} ${b} trips ${k}`, departure, all[k].get(b)!);
                } else {
                    const selected = all.map((labels, k) => k).filter(k => all[k].has(b) && (!k || !all[k - 1].has(b) || all[k - 1].get(b)!.time > all[k].get(b)!.time));
                    output.push(`PARETO ${a} ${b} ${args[2]} options ${selected.length}`);
                    for (const k of selected) printJourney(`OPTION trips ${k}`, departure, all[k].get(b)!);
                }
            } else {
                const departure = time(args[2]), label = earliest(a, departure).get(b);
                if (!label) output.push(`${command} ${a} ${b} ${args[2]}${command === 'FARE' ? ` ${args[3]}` : ''} unreachable`);
                else if (command === 'FARE') printFare(a, b, args[2], args[3], label);
                else printJourney(`ROUTE ${a} ${b}`, departure, label);
            }
            break;
        }
        case 'VIA': {
            const via = b, destination = args[2];
            station(a); station(via); station(destination);
            if (a === destination) fail('origin and destination are the same');
            if (via === a || via === destination) fail(`via station ${via} must differ from origin and destination`);
            openStation(a); openStation(via); openStation(destination);
            const departure = time(args[3]), first = earliest(a, departure).get(via);
            const ready = first ? first.time + stations.get(via)!.transfer : 0;
            const second = first ? earliest(via, ready).get(destination) : undefined;
            if (!first || !second) output.push(`VIA ${a} ${via} ${destination} ${args[3]} unreachable`);
            else {
                const stay: Stay = { kind: 'stay', station: via, departure: first.time, arrival: ready };
                printJourney(`VIA ${a} ${via} ${destination}`, departure, { time: second.time, journey: [...first.journey, stay, ...second.journey] });
            }
            break;
        }
        case 'REACH': {
            station(a); openStation(a);
            const departure = time(b), labels = earliest(a, departure), limit = departure + Number(args[2]);
            const reached = [...labels.keys()].filter(id => labels.get(id)!.time <= limit).sort((x, y) => labels.get(x)!.time - labels.get(y)!.time || compare(x, y));
            output.push(`REACH ${a} ${b} ${args[2]} count ${reached.length}`);
            for (const id of reached) {
                const label = labels.get(id)!;
                output.push(`${id} ${stations.get(id)!.name} ${clock(label.time)} ${label.time - departure} rides ${label.journey.filter(leg => leg.kind === 'ride').length}`);
            }
            break;
        }
        case 'TIMETABLE': {
            const s = station(a), item = line(b), toward = args[2];
            if (!item.stops.includes(a)) fail(`station ${a} is not on line ${b}`);
            if (toward !== item.stops[0] && toward !== item.stops[item.stops.length - 1]) fail(`${toward} is not a terminal of line ${b}`);
            if (a === toward) fail(`no departures from ${a} toward ${toward}`);
            if (item.suspended) fail(`line ${b} is suspended`);
            if (s.closed) fail(`station ${a} is closed`);
            const direction = directions(item).find(d => d.stops[d.stops.length - 1] === toward)!, at = direction.stops.indexOf(a);
            const q = nextTrain(direction, at, time(args[3])), times: string[] = [];
            if (q !== null) for (let i = q; i < trips(item) && times.length < Number(args[4]); i++) times.push(clock(trainTime(direction, i, at)));
            output.push(`TIMETABLE ${a} ${b} toward ${toward} ${args[3]} next ${times.length}${times.length ? ` ${times.join(' ')}` : ''}`);
            break;
        }
        case 'DEPARTURES': case 'ARRIVALS': {
            station(a); openStation(a);
            const events: Event[] = [];
            for (const item of orderedLines()) if (!item.suspended && item.stops.includes(a)) for (const direction of directions(item)) {
                const at = direction.stops.indexOf(a), last = direction.stops.length - 1;
                if (command === 'DEPARTURES' ? at === last : at === 0) continue;
                const q = nextTrain(direction, at, time(b));
                if (q !== null) for (let i = q; i < trips(item); i++) events.push({ time: trainTime(direction, i, at), line: item.id, order: direction.order, terminal: direction.stops[last], start: direction.stops[0] });
            }
            events.sort((x, y) => x.time - y.time || compare(x.line, y.line) || x.order - y.order);
            const selected = events.slice(0, Number(args[2]));
            output.push(`${command} ${a} ${b} count ${selected.length}`);
            for (const event of selected) output.push(`${clock(event.time)} ${event.line} ${command === 'DEPARTURES' ? `toward ${event.terminal}` : `from ${event.start}`}`);
            break;
        }
        case 'TRIP': {
            const item = line(a);
            if (b !== item.stops[0] && b !== item.stops[item.stops.length - 1]) fail(`${b} is not a terminal of line ${a}`);
            if (item.suspended) fail(`line ${a} is suspended`);
            const direction = directions(item).find(d => d.stops[d.stops.length - 1] === b)!, q = nextTrain(direction, 0, time(args[2]));
            if (q === null) output.push(`TRIP ${a} toward ${b} ${args[2]} none`);
            else {
                output.push(`TRIP ${a} toward ${b} ${args[2]} trip ${q + 1} departs ${clock(trainTime(direction, q, 0))}`);
                direction.stops.forEach((id, j) => output.push(`${clock(trainTime(direction, q, j))} ${id}${stations.get(id)!.closed ? ' closed' : ''}${j && closed.has(pair(direction.stops[j - 1], id)) ? ' blocked' : ''}`));
            }
            break;
        }
        case 'SHOWLINE': {
            const item = line(a);
            output.push(`SHOWLINE ${a} ${item.suspended ? 'suspended' : 'running'} first ${clock(item.first)} last ${clock(item.last)} headway ${item.headway} delay ${item.delay} trips ${trips(item)}`);
            item.stops.forEach((id, i) => output.push(`${item.offsets[i]} ${id} zone ${stations.get(id)!.zone}${stations.get(id)!.closed ? ' closed' : ''}${i && closed.has(pair(item.stops[i - 1], id)) ? ' blocked' : ''}`));
            break;
        }
        case 'INFO': {
            const s = station(a), service = orderedLines().filter(item => item.stops.includes(a)), neighbors = [...s.walks.keys()].sort();
            output.push(`INFO ${a} ${s.name} zone ${s.zone} transfer ${s.transfer} ${s.closed ? 'closed' : 'open'}`,
                `LINES ${service.length ? service.map(item => item.id).join(' ') : 'none'}`,
                `WALKS ${neighbors.length ? neighbors.map(id => `${id} ${s.walks.get(id)!}`).join(' ') : 'none'}`);
            break;
        }
        case 'STATUS': {
            const walkCount = [...stations.values()].reduce((sum, s) => sum + s.walks.size, 0) / 2;
            output.push(`STATUS stations ${stations.size} lines ${lines.size} walks ${walkCount}`);
            for (const id of [...stations.keys()].sort()) if (stations.get(id)!.closed) output.push(`CLOSED ${id}`);
            const segments = [...closed].sort((x, y) => { const a = x.split('-'), b = y.split('-'); return compare(a[0], b[0]) || compare(a[1], b[1]); });
            for (const segment of segments) output.push(`CLOSED ${segment}`);
            for (const item of orderedLines()) if (item.suspended) output.push(`SUSPENDED ${item.id}`);
            for (const item of orderedLines()) if (item.delay) output.push(`DELAYED ${item.id} ${item.delay}`);
            break;
        }
    }
}
const input = fs.readFileSync(0, 'utf8').split(/\r?\n/), count = Number(input[0]);
for (const command of input.slice(1, count + 1)) {
    try { execute(command); }
    catch (error) { output.push((error as Error).message); }
}
if (output.length) process.stdout.write(output.join('\n') + '\n');
