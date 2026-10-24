import * as fs from 'node:fs';

type Piece = { kind: string; value: string };
type Route = { name: string; methods: Set<string>; pattern: string; pieces: Piece[]; role: string; types: string[] | null; order: number; selected: number };
type Redirect = { from: string; to: string; prefix: boolean; code: number };
type Client = { level: number; last: number; allowed: number; limited: number };
type Pair = [string, string];
type Response = { code: number; body: string; headers: Map<string, string>; head: boolean };
type AcceptElement = { range: string; weight: number; specificity: number };

const validName = /^[a-z][a-z0-9_]{0,19}$/;
const roleName = /^[a-z]{1,16}$/;
const mediaType = /^[a-z0-9.+-]+\/[a-z0-9.+-]+$/;
const unreserved = /^[A-Za-z0-9._~-]$/;
const methods = new Set(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
const requestMethods = new Set([...methods, 'HEAD', 'OPTIONS']);
const headerOrder = ['Location', 'Allow', 'Retry-After', 'WWW-Authenticate', 'Access-Control-Allow-Origin', 'Access-Control-Allow-Methods', 'Vary', 'ETag', 'Content-Type', 'Content-Length'];
const reasons: Record<number, string> = { 200: 'OK', 204: 'No Content', 301: 'Moved Permanently', 302: 'Found', 304: 'Not Modified', 307: 'Temporary Redirect', 308: 'Permanent Redirect', 400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed', 406: 'Not Acceptable', 412: 'Precondition Failed', 429: 'Too Many Requests', 501: 'Not Implemented' };
const strip = (text: string): string => text.replace(/^ +| +$/g, '');
const compareText = (a: string, b: string): number => a === b ? 0 : a < b ? -1 : 1;

function segment(text: string): boolean {
    return /^[A-Za-z0-9._~-]+$/.test(text) && text !== '.' && text !== '..';
}
function canonicalPath(text: string): boolean {
    return text === '/' || text.startsWith('/') && text.slice(1).split('/').every(segment);
}
function rulePath(text: string): { base: string; prefix: boolean } | null {
    if (canonicalPath(text)) return { base: text, prefix: false };
    if (text.endsWith('/*') && text.slice(0, -2) !== '/' && canonicalPath(text.slice(0, -2))) return { base: text.slice(0, -2), prefix: true };
    return null;
}
function parsePattern(pattern: string): Piece[] | null {
    if (pattern === '/') return [];
    if (!pattern.startsWith('/')) return null;
    const texts = pattern.slice(1).split('/');
    const pieces: Piece[] = [];
    const names = new Set<string>();
    for (let index = 0; index < texts.length; index++) {
        const text = texts[index];
        if (segment(text)) {
            pieces.push({ kind: 'literal', value: text });
            continue;
        }
        const parameter = /^\{([a-z][a-z0-9_]{0,19})(?::(int|slug))?\}$/.exec(text);
        const wildcard = /^\{\*([a-z][a-z0-9_]{0,19})\}$/.exec(text);
        if (parameter === null && wildcard === null) return null;
        const name = parameter === null ? wildcard![1] : parameter[1];
        const kind = parameter === null ? 'wildcard' : parameter[2] ?? 'parameter';
        if (names.has(name) || kind === 'wildcard' && index !== texts.length - 1) return null;
        names.add(name);
        pieces.push({ kind, value: name });
    }
    return pieces;
}
function compareRoutes(a: Route, b: Route): number {
    const count = (route: Route, kinds: string[]): number => route.pieces.filter(piece => kinds.includes(piece.kind)).length;
    return count(b, ['literal']) - count(a, ['literal']) || count(b, ['int', 'slug']) - count(a, ['int', 'slug']) || count(a, ['wildcard']) - count(b, ['wildcard']) || a.order - b.order;
}
function encode(text: string): string {
    return [...text].map(char => unreserved.test(char) ? char : '%' + char.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')).join('');
}
function decode(text: string): string {
    return text.replace(/%([0-9A-Fa-f]{2})/g, (_, digits: string) => String.fromCharCode(parseInt(digits, 16)));
}
function validEscapes(text: string): boolean {
    for (let index = 0; index < text.length; index++) {
        if (text[index] !== '%') continue;
        const digits = text.slice(index + 1, index + 3);
        if (!/^[0-9A-Fa-f]{2}$/.test(digits)) return false;
        const code = parseInt(digits, 16);
        if (code < 32 || code > 126) return false;
        index += 2;
    }
    return true;
}
function normalizePath(path: string): string {
    const decoded = path.replace(/%([0-9A-Fa-f]{2})/g, (escape, digits: string) => {
        const char = String.fromCharCode(parseInt(digits, 16));
        return unreserved.test(char) ? char : escape.toUpperCase();
    });
    const pieces: string[] = [];
    for (const piece of decoded.slice(1).split('/')) {
        if (piece === '' || piece === '.') continue;
        if (piece === '..') pieces.pop();
        else pieces.push(piece);
    }
    return '/' + pieces.join('/');
}
function matchRoute(route: Route, segments: string[]): boolean {
    const wildcard = route.pieces.some(piece => piece.kind === 'wildcard');
    const length = route.pieces.length - (wildcard ? 1 : 0);
    if (wildcard ? segments.length < length : segments.length !== length) return false;
    for (let index = 0; index < length; index++) {
        const piece = route.pieces[index];
        const value = segments[index];
        if (piece.kind === 'literal' && piece.value !== value) return false;
        if (piece.kind === 'int' && !/^[0-9]{1,9}$/.test(value)) return false;
        if (piece.kind === 'slug' && !/^[a-z0-9-]+$/.test(value)) return false;
    }
    return true;
}
function parameterPairs(route: Route, segments: string[]): Pair[] {
    const pairs: Pair[] = [];
    route.pieces.forEach((piece, index) => {
        if (piece.kind === 'literal') return;
        const value = piece.kind === 'wildcard' ? segments.slice(index).map(decode).join('/') : piece.kind === 'int' ? String(Number(segments[index])) : piece.kind === 'slug' ? segments[index] : decode(segments[index]);
        pairs.push([piece.value, value]);
    });
    return pairs.sort((a, b) => compareText(a[0], b[0]));
}
function queryPairs(query: string | null): Pair[] {
    if (query === null) return [];
    return query.split('&').filter(part => part !== '').map<Pair>(part => {
        const separator = part.indexOf('=');
        const name = separator < 0 ? part : part.slice(0, separator);
        const value = separator < 0 ? '' : part.slice(separator + 1);
        return [decode(name.replace(/\+/g, ' ')), decode(value.replace(/\+/g, ' '))];
    });
}
function cookiePairs(cookie: string | undefined): Pair[] {
    const pairs = new Map<string, string>();
    if (cookie !== undefined) {
        for (const part of cookie.split(';').map(strip)) {
            const separator = part.indexOf('=');
            if (separator <= 0) continue;
            const name = part.slice(0, separator);
            if (!pairs.has(name)) pairs.set(name, part.slice(separator + 1));
        }
    }
    return [...pairs].sort((a, b) => compareText(a[0], b[0]));
}
function buildBody(route: Route, type: string, params: Pair[], query: Pair[], cookies: Pair[]): string {
    const quote = (value: string): string => JSON.stringify(value);
    if (type === 'application/json') {
        const object = (pairs: Pair[]): string => '{' + pairs.map(([name, value]) => `${quote(name)}:${quote(value)}`).join(',') + '}';
        return `{"route":${quote(route.name)},"params":${object(params)},"query":[${query.map(([name, value]) => `[${quote(name)},${quote(value)}]`).join(',')}],"cookies":${object(cookies)}}`;
    }
    if (type === 'text/html') {
        const escapes: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
        const html = (value: string): string => value.replace(/[&<>"]/g, char => escapes[char]);
        let result = `<dl><dt>route</dt><dd>${html(route.name)}</dd>`;
        for (const [label, pairs] of [['param', params], ['query', query], ['cookie', cookies]] as [string, Pair[]][]) {
            for (const [name, value] of pairs) result += `<dt>${label} ${html(name)}</dt><dd>${html(value)}</dd>`;
        }
        return result + '</dl>';
    }
    const list = (pairs: Pair[]): string => pairs.length === 0 ? '-' : pairs.map(([name, value]) => `${encode(name)}=${encode(value)}`).join('&');
    return `route=${route.name} params=${list(params)} query=${list(query)} cookies=${list(cookies)}`;
}
function etag(body: string): string {
    let a = 1;
    let b = 0;
    for (const char of body) {
        a = (a + char.charCodeAt(0)) % 65521;
        b = (b + a) % 65521;
    }
    return '"' + b.toString(16).padStart(4, '0') + a.toString(16).padStart(4, '0') + '"';
}
function negotiate(types: string[], accept: string | undefined): string | null {
    if (accept === undefined) return types[0];
    const elements: AcceptElement[] = [];
    for (const element of accept.split(',')) {
        const [first, ...parameters] = element.split(';').map(strip);
        const range = first.toLowerCase();
        let specificity: number;
        if (range === '*/*') specificity = 1;
        else if (/^[a-z0-9.+-]+\/\*$/.test(range)) specificity = 2;
        else if (mediaType.test(range)) specificity = 3;
        else continue;
        let weight = 1000;
        let valid = true;
        for (const parameter of parameters) {
            const separator = parameter.indexOf('=');
            if (separator < 0 || strip(parameter.slice(0, separator)).toLowerCase() !== 'q') continue;
            const q = strip(parameter.slice(separator + 1));
            if (!/^(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)$/.test(q)) valid = false;
            else weight = Math.round(Number(q) * 1000);
            break;
        }
        if (valid) elements.push({ range, weight, specificity });
    }
    let best: string | null = null;
    let bestWeight = 0;
    for (const type of types) {
        let specificity = 0;
        let weight = 0;
        for (const element of elements) {
            const fits = element.range === '*/*' || element.range === type || element.specificity === 2 && element.range.slice(0, -1) === type.split('/')[0] + '/';
            if (fits && element.specificity > specificity) {
                specificity = element.specificity;
                weight = element.weight;
            }
        }
        if (weight > bestWeight) {
            best = type;
            bestWeight = weight;
        }
    }
    return best;
}

class HttpRouter {
    routes: Route[] = [];
    byName = new Map<string, Route>();
    tokens = new Map<string, string>();
    redirects: Redirect[] = [];
    origins = new Set<string>();
    limit: { capacity: number; seconds: number } | null = null;
    clients = new Map<string, Client>();
    statuses = new Map<number, number>();
    errors = 0;
    requestCount = 0;
    urlOk = 0;
    urlError = 0;
    output: string[] = [];
    table: Route[] = [];

    configure(words: string[]): void {
        const [command, ...args] = words;
        const arities: Record<string, number[]> = { ROUTE: [3, 5], TOKEN: [2], REDIRECT: [3], ORIGIN: [1], LIMIT: [2] };
        if (!Object.hasOwn(arities, command) && command !== 'TYPES') throw new Error(`unknown command ${command}`);
        if (command === 'TYPES' ? args.length < 2 : !arities[command].includes(args.length)) throw new Error('wrong number of arguments');
        if (command === 'ROUTE') {
            const [name, methodText, pattern] = args;
            if (!validName.test(name)) throw new Error(`bad route name ${name}`);
            if (this.byName.has(name)) throw new Error(`duplicate route ${name}`);
            const methodList = methodText.split(',');
            if (methodList.some(method => !methods.has(method)) || new Set(methodList).size !== methodList.length) throw new Error(`bad methods ${methodText}`);
            const pieces = parsePattern(pattern);
            if (pieces === null) throw new Error(`bad pattern ${pattern}`);
            if (args.length === 5 && args[3] !== 'ROLE') throw new Error(`unknown option ${args[3]}`);
            if (args.length === 5 && !roleName.test(args[4])) throw new Error(`bad role ${args[4]}`);
            const route: Route = { name, methods: new Set(methodList), pattern, pieces, role: args.length === 5 ? args[4] : 'none', types: null, order: this.routes.length, selected: 0 };
            this.routes.push(route);
            this.byName.set(name, route);
        } else if (command === 'TOKEN') {
            const [value, role] = args;
            if (!/^[A-Za-z0-9._-]{1,32}$/.test(value)) throw new Error(`bad token ${value}`);
            if (this.tokens.has(value)) throw new Error(`duplicate token ${value}`);
            if (!roleName.test(role)) throw new Error(`bad role ${role}`);
            this.tokens.set(value, role);
        } else if (command === 'REDIRECT') {
            const from = rulePath(args[0]);
            if (from === null) throw new Error(`bad path ${args[0]}`);
            const to = rulePath(args[1]);
            if (to === null) throw new Error(`bad path ${args[1]}`);
            if (from.prefix !== to.prefix) throw new Error('wildcard mismatch');
            if (!['301', '302', '307', '308'].includes(args[2])) throw new Error(`bad redirect code ${args[2]}`);
            if (this.redirects.some(rule => rule.from === from.base && rule.prefix === from.prefix)) throw new Error(`duplicate redirect ${args[0]}`);
            this.redirects.push({ from: from.base, to: to.base, prefix: from.prefix, code: Number(args[2]) });
        } else if (command === 'ORIGIN') {
            if (!/^https?:\/\/[a-z0-9.:-]+$/.test(args[0])) throw new Error(`bad origin ${args[0]}`);
            if (this.origins.has(args[0])) throw new Error(`duplicate origin ${args[0]}`);
            this.origins.add(args[0]);
        } else if (command === 'LIMIT') {
            if (!/^[1-9][0-9]*$/.test(args[0]) || Number(args[0]) > 100 || !/^[1-9][0-9]*$/.test(args[1]) || Number(args[1]) > 3600) throw new Error('bad limit');
            if (this.limit !== null) throw new Error('duplicate limit');
            this.limit = { capacity: Number(args[0]), seconds: Number(args[1]) };
        } else {
            const route = this.byName.get(args[0]);
            if (route === undefined) throw new Error(`unknown route ${args[0]}`);
            if (route.types !== null) throw new Error(`duplicate types ${args[0]}`);
            const types: string[] = [];
            for (const type of args.slice(1)) {
                if (!mediaType.test(type)) throw new Error(`bad media type ${type}`);
                if (types.includes(type)) throw new Error(`duplicate media type ${type}`);
                types.push(type);
            }
            route.types = types;
        }
    }

    finishConfiguration(): void {
        this.output.push(`CONFIG routes=${this.routes.length} tokens=${this.tokens.size} redirects=${this.redirects.length} origins=${this.origins.size} limit=${this.limit === null ? 'none' : `${this.limit.capacity}/${this.limit.seconds}`} errors=${this.errors}`);
        for (const route of this.routes) if (route.types === null) route.types = ['application/json'];
        this.table = [...this.routes].sort(compareRoutes);
        this.table.forEach((route, index) => {
            const methodSet = new Set(route.methods);
            if (methodSet.has('GET')) methodSet.add('HEAD');
            this.output.push(`TABLE ${index + 1} ${route.name} ${[...methodSet].sort().join(',')} ${route.pattern} role=${route.role === 'none' ? '-' : route.role} types=${route.types!.join(',')}`);
        });
    }

    request(line: string, headerLines: string[]): Response {
        const headers = new Map<string, string>();
        let head = false;
        let cors = false;
        const finish = (code: number, body = '', extra: Pair[] = [], type = 'text/plain'): Response => {
            const responseHeaders = new Map(extra);
            const origin = headers.get('origin');
            if (cors && origin !== undefined && this.origins.has(origin)) {
                responseHeaders.set('Access-Control-Allow-Origin', origin);
                if (code === 204 && headers.has('access-control-request-method')) responseHeaders.set('Access-Control-Allow-Methods', responseHeaders.get('Allow')!);
            }
            if (code !== 204 && code !== 304) {
                responseHeaders.set('Content-Type', code === 200 ? type : 'text/plain');
                responseHeaders.set('Content-Length', String(body.length));
            }
            return { code, body, headers: responseHeaders, head };
        };
        const parts = line.split(' ');
        if (parts.length !== 3 || !/^[A-Z]{1,16}$/.test(parts[0]) || !parts[1].startsWith('/') || parts[1].includes('#') || parts[2] !== 'HTTP/1.1') return finish(400, 'bad request: request line');
        const [method, target] = parts;
        head = method === 'HEAD';
        if (!validEscapes(target)) return finish(400, 'bad request: percent escape');
        for (let index = 0; index < headerLines.length; index++) {
            const header = headerLines[index];
            const separator = header.indexOf(':');
            if (separator < 0 || !/^[A-Za-z0-9-]+$/.test(header.slice(0, separator))) return finish(400, `bad request: header line ${index + 1}`);
            const name = header.slice(0, separator).toLowerCase();
            if (headers.has(name)) return finish(400, `bad request: duplicate header ${name}`);
            headers.set(name, strip(header.slice(separator + 1)));
        }
        cors = true;
        if (!requestMethods.has(method)) return finish(501, `not implemented: ${method}`);
        if (!headers.has('host') || headers.get('host') === '') return finish(400, 'bad request: missing host');
        let effective = method;
        if (headers.has('x-http-method-override')) {
            const override = headers.get('x-http-method-override')!;
            if (method !== 'POST' || !['PUT', 'PATCH', 'DELETE'].includes(override)) return finish(400, 'bad request: method override');
            effective = override;
        }
        const clientName = headers.get('x-client');
        if (clientName !== undefined && clientName !== '') {
            const time = Number(headers.get('x-time'));
            let client = this.clients.get(clientName);
            if (client === undefined) {
                client = { level: this.limit === null ? 0 : this.limit.capacity * this.limit.seconds, last: time, allowed: 0, limited: 0 };
                this.clients.set(clientName, client);
            }
            if (this.limit !== null) {
                const { capacity, seconds } = this.limit;
                client.level = Math.min(capacity * seconds, client.level + (time - client.last) * capacity);
                client.last = time;
                if (client.level < seconds) {
                    client.limited++;
                    return finish(429, `too many requests: client ${clientName}`, [['Retry-After', String(Math.ceil((seconds - client.level) / capacity))]]);
                }
                client.level -= seconds;
            }
            client.allowed++;
        }
        const question = target.indexOf('?');
        const path = question < 0 ? target : target.slice(0, question);
        const query = question < 0 ? null : target.slice(question + 1);
        const suffix = question < 0 ? '' : target.slice(question);
        const normalized = normalizePath(path);
        if (normalized !== path) return finish(308, `redirect to ${normalized}${suffix}`, [['Location', normalized + suffix]]);
        for (const rule of this.redirects) {
            if (path === rule.from || rule.prefix && path.startsWith(rule.from + '/')) {
                const destination = rule.to + path.slice(rule.from.length) + suffix;
                return finish(rule.code, `redirect to ${destination}`, [['Location', destination]]);
            }
        }
        const segments = path === '/' ? [] : path.slice(1).split('/');
        const matching = this.table.filter(route => matchRoute(route, segments));
        if (matching.length === 0) return finish(404, `not found: ${path}`);
        const allowed = new Set<string>(['OPTIONS']);
        for (const route of matching) for (const method of route.methods) allowed.add(method);
        if (allowed.has('GET')) allowed.add('HEAD');
        const allow = [...allowed].sort().join(', ');
        if (effective === 'OPTIONS') return finish(204, '', [['Allow', allow]]);
        const lookup = effective === 'HEAD' ? 'GET' : effective;
        const selected = matching.find(route => route.methods.has(lookup));
        if (selected === undefined) return finish(405, `method not allowed: ${effective}`, [['Allow', allow]]);
        selected.selected++;
        if (selected.role !== 'none') {
            if (!headers.has('authorization')) return finish(401, 'unauthorized: missing token', [['WWW-Authenticate', 'Bearer realm="api"']]);
            const authorization = headers.get('authorization')!;
            const space = authorization.indexOf(' ');
            const scheme = space < 0 ? authorization : authorization.slice(0, space);
            const token = space < 0 ? '' : authorization.slice(space + 1);
            if (scheme.toLowerCase() !== 'bearer' || !this.tokens.has(token)) return finish(401, 'unauthorized: invalid token', [['WWW-Authenticate', 'Bearer realm="api", error="invalid_token"']]);
            const role = this.tokens.get(token)!;
            if (role !== selected.role && role !== 'admin') return finish(403, `forbidden: requires role ${selected.role}`);
        }
        const types = selected.types!;
        const extra: Pair[] = types.length > 1 ? [['Vary', 'Accept']] : [];
        const type = negotiate(types, headers.get('accept'));
        if (type === null) return finish(406, `not acceptable: ${types.join(', ')}`, extra);
        const body = buildBody(selected, type, parameterPairs(selected, segments), queryPairs(query), cookiePairs(headers.get('cookie')));
        const tag = etag(body);
        const condition = headers.get('if-none-match');
        if (condition !== undefined && condition.split(',').map(strip).map(value => value.startsWith('W/') ? value.slice(2) : value).some(value => value === '*' || value === tag)) {
            if (lookup === 'GET') return finish(304, '', [...extra, ['ETag', tag]]);
            return finish(412, `precondition failed: ${tag}`, extra);
        }
        return finish(200, body, [...extra, ['ETag', tag]], type);
    }

    urlFor(words: string[]): string {
        const name = words[1];
        const route = this.byName.get(name);
        if (route === undefined) throw new Error(`unknown route ${name}`);
        const parameterNames = new Set(route.pieces.filter(piece => piece.kind !== 'literal').map(piece => piece.value));
        const parameters = new Map<string, string>();
        const query: Pair[] = [];
        for (const argument of words.slice(2)) {
            const separator = argument.indexOf('=');
            if (separator <= 0) throw new Error(`bad argument ${argument}`);
            const key = argument.slice(0, separator);
            const value = argument.slice(separator + 1);
            if (parameterNames.has(key)) {
                if (parameters.has(key)) throw new Error(`duplicate parameter ${key}`);
                parameters.set(key, value);
            } else query.push([key, value]);
        }
        const segments: string[] = [];
        for (const piece of route.pieces) {
            if (piece.kind === 'literal') {
                segments.push(piece.value);
                continue;
            }
            const value = parameters.get(piece.value);
            if (piece.kind !== 'wildcard' && value === undefined) throw new Error(`missing parameter ${piece.value}`);
            const text = value ?? '';
            let valid: boolean;
            if (piece.kind === 'parameter') valid = text !== '' && text !== '.' && text !== '..';
            else if (piece.kind === 'int') valid = /^[0-9]{1,9}$/.test(text);
            else if (piece.kind === 'slug') valid = /^[a-z0-9-]+$/.test(text);
            else valid = text === '' || text.split('/').every(part => part !== '' && part !== '.' && part !== '..');
            if (!valid) throw new Error(`bad value for ${piece.value}`);
            if (piece.kind === 'wildcard') {
                if (text !== '') segments.push(...text.split('/').map(encode));
            } else segments.push(encode(text));
        }
        const suffix = query.length === 0 ? '' : '?' + query.map(([key, value]) => `${encode(key)}=${encode(value)}`).join('&');
        return `URLFOR ${name} /${segments.join('/')}${suffix}`;
    }

    emitResponse(response: Response): void {
        this.requestCount++;
        this.statuses.set(response.code, (this.statuses.get(response.code) ?? 0) + 1);
        this.output.push(`REQUEST ${this.requestCount}`, `HTTP/1.1 ${response.code} ${reasons[response.code]}`);
        for (const name of headerOrder) if (response.headers.has(name)) this.output.push(`${name}: ${response.headers.get(name)!}`);
        if (!response.head && response.code !== 204 && response.code !== 304) this.output.push(response.body);
    }

    run(lines: string[]): void {
        let position = 0;
        while (lines[position] !== 'REQUESTS') {
            try {
                this.configure(lines[position].split(' '));
            } catch (error) {
                this.errors++;
                this.output.push(`CONFIG ERROR ${position + 1}: ${(error as Error).message}`);
            }
            position++;
        }
        position++;
        this.finishConfiguration();
        while (lines[position] !== 'END') {
            const line = lines[position++];
            if (line.startsWith('URLFOR ')) {
                try {
                    this.output.push(this.urlFor(line.split(' ')));
                    this.urlOk++;
                } catch (error) {
                    this.urlError++;
                    this.output.push(`URLFOR ERROR ${(error as Error).message}`);
                }
            } else {
                const headers: string[] = [];
                while (lines[position] !== '') headers.push(lines[position++]);
                position++;
                this.emitResponse(this.request(line, headers));
            }
        }
        this.output.push(`SUMMARY requests=${this.requestCount} urlfor_ok=${this.urlOk} urlfor_error=${this.urlError}`);
        for (const code of [...this.statuses.keys()].sort((a, b) => a - b)) this.output.push(`STATUS ${code} ${this.statuses.get(code)!}`);
        for (const route of this.routes) this.output.push(`ROUTE ${route.name} ${route.selected}`);
        for (const name of [...this.clients.keys()].sort()) {
            const client = this.clients.get(name)!;
            this.output.push(`CLIENT ${name} allowed=${client.allowed} limited=${client.limited}`);
        }
    }
}

const router = new HttpRouter();
router.run(fs.readFileSync(0, 'utf8').split('\n'));
process.stdout.write(router.output.join('\n') + '\n');
