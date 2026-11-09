'use strict';

const fs = require('node:fs');
const { words, parseFields, firstFields, removeComments, unstructured, valueWithParameters } = require('./headers');
const { parseAddresses } = require('./addresses');
const { base64Body, quotedPrintable } = require('./mime');
const { parseDate, formatDate } = require('./dates');
const { buildThreads } = require('./threader');

const CHECKED_HEADERS = [
    'From', 'To', 'Cc', 'Subject', 'Date', 'Message-ID', 'In-Reply-To', 'References',
    'MIME-Version', 'Content-Type', 'Content-Transfer-Encoding', 'Content-Disposition',
];
const ID_FORBIDDEN = new Set([60, 62, 40, 41, 34, 92]);

function readLines(path) {
    const text = fs.readFileSync(path, 'ascii');
    return text === '' ? [] : text.slice(0, -1).split('\n');
}

function stripTrailing(text) {
    return text.replace(/[ \t]+$/, '');
}

function readMailbox() {
    const messages = [];
    let current = null;
    readLines('input/mailbox.mbox').forEach((text, index) => {
        if (text.startsWith('From ')) {
            current = [];
            messages.push(current);
        } else {
            const adjusted = /^>+From /.test(text) ? text.slice(1) : text;
            current.push({ number: index + 1, text: adjusted });
        }
    });
    return messages.map((lines, index) => {
        if (lines.at(-1)?.text === '') lines.pop();
        return { number: index + 1, lines };
    });
}

function separate(lines) {
    const divider = lines.findIndex(line => line.text === '');
    const header = divider === -1 ? lines : lines.slice(0, divider);
    const body = divider === -1 ? [] : lines.slice(divider + 1);
    return { ...parseFields(header), body };
}

function wellFormedID(text) {
    if (text.length < 3 || !text.startsWith('<') || !text.endsWith('>')) return false;
    const inside = text.slice(1, -1);
    const at = inside.indexOf('@');
    if (at <= 0 || at !== inside.lastIndexOf('@') || at === inside.length - 1) return false;
    for (const character of inside) {
        const code = character.charCodeAt(0);
        if (code < 33 || code > 126 || ID_FORBIDDEN.has(code)) return false;
    }
    return true;
}

function extractIDs(text) {
    const ids = [];
    let position = 0;
    while (position < text.length) {
        const first = text.indexOf('<', position);
        if (first === -1) break;
        const last = text.indexOf('>', first + 1);
        if (last === -1) break;
        const id = text.slice(first, last + 1);
        if (wellFormedID(id)) ids.push(id);
        position = last + 1;
    }
    return ids;
}

function addHeaderProblems(invalid, problems) {
    for (const number of invalid) problems.push(`bad header line ${number}`);
}

function parseEntity(number, fields, body, enabled, problems) {
    const values = firstFields(fields);
    const entity = {
        number, type: 'text', subtype: 'plain', parameters: new Map(),
        disposition: null, filename: null, children: null, content: '',
    };
    if (enabled && values.has('content-type')) {
        const parsed = valueWithParameters(values.get('content-type'), true);
        if (parsed === null) problems.push(`bad Content-Type in part ${number}`);
        else {
            entity.type = parsed.type;
            entity.subtype = parsed.subtype;
            entity.parameters = parsed.parameters;
        }
    }
    if (enabled && values.has('content-disposition')) {
        const parsed = valueWithParameters(values.get('content-disposition'), false);
        if (parsed === null) problems.push(`bad Content-Disposition in part ${number}`);
        else {
            entity.disposition = parsed.type;
            entity.filename = parsed.parameters.get('filename') ?? null;
        }
    }
    if (entity.filename === null || entity.filename === '') entity.filename = entity.parameters.get('name') ?? null;
    if (entity.type === 'text' && entity.parameters.has('charset')) {
        const charset = entity.parameters.get('charset').toLowerCase();
        if (charset !== 'us-ascii') problems.push(`unsupported charset "${charset}" in part ${number}`);
    }
    if (enabled && entity.type === 'multipart') {
        const boundary = entity.parameters.get('boundary');
        if (boundary === undefined || boundary === '') {
            problems.push(`missing boundary in part ${number}`);
        } else {
            entity.children = [];
            const parts = [];
            let closed = false;
            for (const line of body) {
                const text = stripTrailing(line.text);
                if (text === `--${boundary}--`) {
                    closed = true;
                    break;
                }
                if (text === `--${boundary}`) parts.push([]);
                else if (parts.length > 0) parts.at(-1).push(line);
            }
            if (parts.length === 0) problems.push(`no parts in part ${number}`);
            else if (!closed) problems.push(`unterminated multipart in part ${number}`);
            parts.forEach((lines, index) => {
                const part = separate(lines);
                addHeaderProblems(part.invalid, problems);
                entity.children.push(parseEntity(`${number}.${index + 1}`, part.fields, part.body, true, problems));
            });
            return entity;
        }
    }
    const original = body.map(line => line.text).join('\n');
    const encoding = enabled && values.has('content-transfer-encoding')
        ? values.get('content-transfer-encoding').toLowerCase() : '7bit';
    if (encoding === 'base64') {
        const content = base64Body(original);
        if (content === null) problems.push(`bad base64 in part ${number}`);
        entity.content = content ?? '';
    } else if (encoding === 'quoted-printable') {
        const decoded = quotedPrintable(original);
        entity.content = decoded.content;
        if (decoded.error) problems.push(`bad quoted-printable in part ${number}`);
    } else {
        entity.content = original;
        if (!['7bit', '8bit', 'binary'].includes(encoding)) problems.push(`unknown encoding "${encoding}" in part ${number}`);
    }
    return entity;
}

function parseSender(values, problems) {
    if (!values.has('from')) {
        problems.push('missing From');
        return null;
    }
    const parsed = parseAddresses(values.get('from'));
    if (parsed === null || parsed.addresses.length !== 1 || parsed.addresses[0].group) {
        problems.push('bad From');
        return null;
    }
    if (parsed.encodedError) problems.push('bad encoded word in From');
    return parsed.addresses[0];
}

function parseRecipients(values, name, problems) {
    if (!values.has(name.toLowerCase())) return [];
    const parsed = parseAddresses(values.get(name.toLowerCase()));
    if (parsed === null) {
        problems.push(`bad ${name}`);
        return [];
    }
    if (parsed.encodedError) problems.push(`bad encoded word in ${name}`);
    return parsed.addresses.flatMap(address => address.group
        ? address.mailboxes.map(mailbox => mailbox.address) : [address.address]);
}

function checkMessage(raw, usedIDs) {
    const { fields, invalid, body } = separate(raw.lines);
    const values = firstFields(fields);
    const problems = [];
    addHeaderProblems(invalid, problems);
    const counts = new Map();
    for (const field of fields) counts.set(field.name, (counts.get(field.name) ?? 0) + 1);
    for (const name of CHECKED_HEADERS) {
        if ((counts.get(name.toLowerCase()) ?? 0) >= 2) problems.push(`duplicate ${name}`);
    }
    const sender = parseSender(values, problems);
    const to = parseRecipients(values, 'To', problems);
    const cc = parseRecipients(values, 'Cc', problems);
    const decodedSubject = unstructured(values.get('subject') ?? '');
    const subject = decodedSubject.value;
    if (decodedSubject.error) problems.push('bad encoded word in Subject');
    let baseSubject = subject;
    let reply = false;
    while (baseSubject.slice(0, 3).toLowerCase() === 're:') {
        baseSubject = baseSubject.slice(3).replace(/^ +/, '');
        reply = true;
    }
    let date = null;
    if (!values.has('date')) problems.push('missing Date');
    else {
        const parsed = parseDate(values.get('date'));
        if (parsed.error !== null) problems.push(parsed.error);
        else date = parsed.seconds;
    }
    let id = '';
    if (!values.has('message-id')) problems.push('missing Message-ID');
    else {
        const candidate = values.get('message-id');
        if (!wellFormedID(candidate)) problems.push('bad Message-ID');
        else if (usedIDs.has(candidate)) problems.push(`Message-ID already used by message ${usedIDs.get(candidate)}`);
        else {
            id = candidate;
            usedIDs.set(id, raw.number);
        }
    }
    const references = extractIDs(values.get('references') ?? '');
    const replies = extractIDs(values.get('in-reply-to') ?? '');
    if (replies.length > 0 && references.at(-1) !== replies[0]) references.push(replies[0]);
    let enabled = false;
    if (values.has('mime-version')) {
        const version = removeComments(values.get('mime-version'));
        enabled = version !== null && version.replace(/[ \t]/g, '') === '1.0';
        if (!enabled) problems.push('bad MIME-Version');
    }
    const entity = parseEntity('1', fields, body, enabled, problems);
    const key = [date === null ? 1 : 0, date ?? 0, id, raw.number];
    return { number: raw.number, sender, to, cc, subject, baseSubject, reply, date, id, references, entity, key, problems };
}

function collectTextParts(entity, allowHTML) {
    if (entity.children === null) {
        if (entity.disposition === 'attachment') return [];
        if (entity.type === 'text' && (entity.subtype === 'plain' || (entity.subtype === 'html' && allowHTML))) return [entity];
        return [];
    }
    if (entity.subtype === 'alternative') {
        for (const allowed of [false, true]) {
            for (const child of entity.children) {
                const parts = collectTextParts(child, allowed);
                if (parts.length > 0) return parts;
            }
        }
        return [];
    }
    return entity.children.flatMap(child => collectTextParts(child, allowHTML));
}

function quotePrefix(depth) {
    return depth === 0 ? '' : '>'.repeat(depth) + ' ';
}

function wrap(text, prefix) {
    const lines = [];
    let current = '';
    for (const word of words(text)) {
        if (current !== '' && current.length + 1 + word.length > 72) {
            lines.push(prefix + current);
            current = word;
        } else current += (current === '' ? '' : ' ') + word;
    }
    lines.push(prefix + current);
    return lines;
}

function flowedLines(entity) {
    if (entity.content === '') return [];
    const logical = [];
    const deleteSpace = (entity.parameters.get('delsp') ?? '').toLowerCase() === 'yes';
    for (const line of entity.content.split('\n')) {
        let depth = 0;
        while (line[depth] === '>') depth++;
        let text = line.slice(depth);
        if (text.startsWith(' ')) text = text.slice(1);
        const flows = text.endsWith(' ') && text !== '-- ';
        const previous = logical.at(-1);
        if (previous !== undefined && previous.flows && previous.depth === depth) {
            if (deleteSpace) previous.text = previous.text.slice(0, -1);
            previous.text += text;
            previous.flows = flows;
        } else logical.push({ depth, text, flows });
    }
    return logical.flatMap(line => wrap(line.text, quotePrefix(line.depth)));
}

function characterReferences(text) {
    const named = new Map([['amp', '&'], ['lt', '<'], ['gt', '>'], ['quot', '"'], ['apos', "'"], ['nbsp', ' ']]);
    let result = '';
    for (let index = 0; index < text.length;) {
        if (text[index] === '&') {
            const end = text.indexOf(';', index + 1);
            if (end !== -1) {
                const name = text.slice(index + 1, end);
                let replacement = named.get(name);
                if (replacement === undefined && /^#[0-9]{1,3}$/.test(name)) {
                    const value = Number(name.slice(1));
                    if (value >= 32 && value <= 126) replacement = String.fromCharCode(value);
                }
                if (replacement !== undefined) {
                    result += replacement;
                    index = end + 1;
                    continue;
                }
            }
        }
        result += text[index++];
    }
    return result;
}

function htmlLines(content) {
    const paragraphTags = new Set(['p', 'div', 'ul', 'ol', 'table', 'tr', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6']);
    const hiddenTags = new Set(['head', 'style', 'script']);
    const logical = [];
    let depth = 0;
    let text = '';
    let hide = null;
    for (let index = 0; index < content.length;) {
        const end = content[index] === '<' ? content.indexOf('>', index + 1) : -1;
        if (end === -1) {
            if (hide === null) text += content[index];
            index++;
            continue;
        }
        const inside = content.slice(index + 1, end);
        const closing = inside.startsWith('/');
        const name = /^[A-Za-z0-9]*/.exec(closing ? inside.slice(1) : inside)[0].toLowerCase();
        index = end + 1;
        if (hide !== null) {
            if (closing && name === hide) hide = null;
            continue;
        }
        if (!closing && hiddenTags.has(name)) hide = name;
        else if (name === 'br' || (name === 'li' && !closing)) {
            logical.push({ depth, text });
            text = name === 'li' ? '* ' : '';
        } else if (paragraphTags.has(name)) {
            logical.push({ depth, text }, { depth, text: '' });
            text = '';
            if (name === 'blockquote') depth = closing ? Math.max(0, depth - 1) : depth + 1;
        }
    }
    logical.push({ depth, text });
    const display = [];
    for (const line of logical) {
        const collapsed = line.text.replace(/[ \t\n]+/g, ' ').replace(/^ +| +$/g, '');
        const decoded = characterReferences(collapsed).replace(/^ +| +$/g, '');
        if (decoded !== '') {
            for (const wrapped of wrap(decoded, quotePrefix(line.depth))) display.push(wrapped);
        } else if (display.length > 0 && display.at(-1) !== '') display.push('');
    }
    while (display.at(-1) === '') display.pop();
    return display;
}

function displayPart(entity) {
    let format;
    let display;
    if (entity.subtype === 'html') {
        format = 'html';
        display = htmlLines(entity.content);
    } else if ((entity.parameters.get('format') ?? '').toLowerCase() === 'flowed') {
        format = 'flowed';
        display = flowedLines(entity);
    } else {
        format = 'plain';
        display = entity.content === '' ? [] : entity.content.split('\n');
    }
    const lines = display.map(stripTrailing);
    let quoted = 0;
    let signatureStart = -1;
    lines.forEach((line, index) => {
        if (line.startsWith('>')) quoted++;
        if (line === '--') signatureStart = index;
    });
    const signature = signatureStart === -1 ? 0 : lines.length - signatureStart - 1;
    return { number: entity.number, format, lines, quoted, signature };
}

function positionThreads(roots) {
    return roots.map((root, index) => {
        const number = index + 1;
        const containers = [];
        const messages = [];
        const senders = new Set();
        const stack = [{ container: root, depth: 0, prefix: '', stem: '' }];
        let maximumDepth = 0;
        let first = null;
        let last = null;
        while (stack.length > 0) {
            const entry = stack.pop();
            const { container, depth, stem } = entry;
            containers.push(entry);
            maximumDepth = Math.max(maximumDepth, depth);
            if (container.message !== null) {
                const message = container.message;
                message.thread = number;
                message.depth = depth;
                message.parent = container.parent?.message ?? null;
                messages.push(message);
                if (message.sender !== null) senders.add(message.sender.address);
                if (message.date !== null) {
                    first = first === null ? message.date : Math.min(first, message.date);
                    last = last === null ? message.date : Math.max(last, message.date);
                }
            }
            for (let child = container.children.length - 1; child >= 0; child--) {
                const final = child === container.children.length - 1;
                stack.push({
                    container: container.children[child], depth: depth + 1,
                    prefix: stem + (final ? '`- ' : '+- '), stem: stem + (final ? '   ' : '|  '),
                });
            }
        }
        const subject = root.subject ?? (root.message ?? root.children[0].message).baseSubject;
        return { number, containers, messages, senders, depth: maximumDepth, first, last, subject };
    });
}

function checkParentDates(messages) {
    for (const message of messages) {
        if (message.parent !== null && message.date !== null && message.parent.date !== null
            && message.date < message.parent.date) {
            message.problems.push(`dated before parent message ${message.parent.number}`);
        }
    }
}

function subjectNotation(subject) {
    return subject === '' ? '(no subject)' : subject;
}

function dateNotation(message) {
    return message.date === null ? 'invalid' : formatDate(message.date);
}

function separateBlocks(blocks) {
    const lines = [];
    blocks.forEach((block, index) => {
        if (index > 0) lines.push('');
        for (const line of block) lines.push(line);
    });
    return lines;
}

function threadReport(threads) {
    return separateBlocks(threads.map(thread => {
        const span = thread.first === null ? 'span -' : `span ${formatDate(thread.first)} .. ${formatDate(thread.last)}`;
        const lines = [
            `thread ${thread.number} messages ${thread.messages.length} depth ${thread.depth} senders ${thread.senders.size}`,
            span, `subject ${subjectNotation(thread.subject)}`,
        ];
        for (const { container, prefix } of thread.containers) {
            let notation;
            if (container.message !== null) {
                const message = container.message;
                notation = `[${message.number}] ${dateNotation(message)} ${message.sender?.address ?? '-'} ${subjectNotation(message.subject)}`;
            } else if (container.subject !== null) notation = `[subject] ${container.subject}`;
            else notation = `[missing] ${container.id}`;
            lines.push(prefix + notation);
        }
        return lines;
    }));
}

function entityLines(root) {
    const lines = [];
    const stack = [root];
    while (stack.length > 0) {
        const entity = stack.pop();
        let line = `part ${entity.number} ${entity.type}/${entity.subtype}`;
        if (entity.children === null) {
            line += ` ${entity.content.length}`;
            if (entity.disposition !== null) line += ` ${entity.disposition}`;
            if (entity.filename !== null && entity.filename !== '') line += ` "${entity.filename}"`;
        } else {
            for (let index = entity.children.length - 1; index >= 0; index--) stack.push(entity.children[index]);
        }
        lines.push(line);
    }
    return lines;
}

function messageReport(messages) {
    return separateBlocks(messages.map(message => {
        let sender = '-';
        if (message.sender !== null) {
            sender = message.sender.name === '' ? message.sender.address
                : `${message.sender.name} <${message.sender.address}>`;
        }
        return [
            `message ${message.number}`, `id ${message.id || '-'}`, `date ${dateNotation(message)}`,
            `from ${sender}`, `to ${message.to.join(', ') || '-'}`, `cc ${message.cc.join(', ') || '-'}`,
            `subject ${subjectNotation(message.subject)}`, `refs ${message.references.join(' ') || '-'}`,
            `thread ${message.thread} depth ${message.depth} parent ${message.parent?.number ?? '-'}`,
            ...entityLines(message.entity),
        ];
    }));
}

function bodyReport(requests, messages) {
    const byID = new Map(messages.filter(message => message.id !== '').map(message => [message.id, message]));
    return separateBlocks(requests.map(id => {
        const lines = [`request ${id}`];
        const message = byID.get(id);
        if (message === undefined) {
            lines.push('not found');
            return lines;
        }
        if (message.displayParts === undefined) message.displayParts = collectTextParts(message.entity, true).map(displayPart);
        lines.push(`message ${message.number} text parts ${message.displayParts.length}`);
        for (const part of message.displayParts) {
            lines.push(`part ${part.number} ${part.format} lines ${part.lines.length} quoted ${part.quoted} signature ${part.signature}`);
            for (const line of part.lines) lines.push(line === '' ? '|' : `| ${line}`);
        }
        return lines;
    }));
}

function senderReport(messages) {
    const senders = new Map();
    for (const message of messages) {
        if (message.sender === null) continue;
        const { address, name } = message.sender;
        if (!senders.has(address)) senders.set(address, { address, name: '', count: 0, threads: new Set(), first: null, last: null });
        const sender = senders.get(address);
        sender.count++;
        sender.threads.add(message.thread);
        if (name !== '') sender.name = name;
        if (message.date !== null) {
            sender.first = sender.first === null ? message.date : Math.min(sender.first, message.date);
            sender.last = sender.last === null ? message.date : Math.max(sender.last, message.date);
        }
    }
    const ordered = [...senders.values()].sort((a, b) => b.count - a.count
        || (a.address < b.address ? -1 : a.address > b.address ? 1 : 0));
    const lines = ['address,name,messages,threads,first,last'];
    for (const sender of ordered) {
        const name = /[",]/.test(sender.name) ? '"' + sender.name.replace(/"/g, '""') + '"' : sender.name;
        const first = sender.first === null ? '-' : formatDate(sender.first);
        const last = sender.last === null ? '-' : formatDate(sender.last);
        lines.push(`${sender.address},${name},${sender.count},${sender.threads.size},${first},${last}`);
    }
    return lines;
}

function malformedReport(messages) {
    let malformed = 0;
    let problems = 0;
    for (const message of messages) {
        if (message.problems.length > 0) malformed++;
        problems += message.problems.length;
    }
    const lines = [`messages ${messages.length} malformed ${malformed} problems ${problems}`];
    for (const message of messages) {
        for (const problem of message.problems) lines.push(`message ${message.number}: ${problem}`);
    }
    return lines;
}

function main() {
    const usedIDs = new Map();
    const messages = readMailbox().map(message => checkMessage(message, usedIDs));
    const threads = positionThreads(buildThreads(messages));
    checkParentDates(messages);
    const reports = {
        'threads.txt': threadReport(threads),
        'messages.txt': messageReport(messages),
        'bodies.txt': bodyReport(readLines('input/requests.txt'), messages),
        'senders.csv': senderReport(messages),
        'malformed.txt': malformedReport(messages),
    };
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(reports)) fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

if (require.main === module) main();
