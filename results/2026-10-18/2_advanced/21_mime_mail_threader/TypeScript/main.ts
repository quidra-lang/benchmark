import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { addresses, type Mailbox } from './addresses.ts';
import { formatDate, parseDate } from './dates.ts';
import {
  field,
  parameters,
  parseHeaders,
  removeComments,
  unstructured,
  type Field,
  type SourceLine,
} from './headers.ts';
import { base64Body, quotedPrintable } from './mime.ts';
import { buildThreads, type Container, type ThreadMessage } from './threader.ts';

interface Entity {
  number: string;
  type: string;
  subtype: string;
  parameters: Map<string, string>;
  disposition?: string;
  filename?: string;
  children?: Entity[];
  content: string;
}
interface Message extends ThreadMessage {
  problems: string[];
  sender?: Mailbox;
  to: string[];
  cc: string[];
  subject: string;
  seconds?: number;
  entity: Entity;
  thread: number;
  depth: number;
  parent?: Message;
}
const trailing = (text: string) => text.replace(/[ \t]+$/, '');
function inputLines(path: string): string[] {
  return readFileSync(path, 'ascii').slice(0, -1).split('\n');
}
function sections(lines: SourceLine[]): { headers: SourceLine[]; body: SourceLine[] } {
  const blank = lines.findIndex((line) => line.text === '');
  return blank < 0
    ? { headers: lines, body: [] }
    : { headers: lines.slice(0, blank), body: lines.slice(blank + 1) };
}
function wellFormedId(text: string): boolean {
  if (text.length < 3 || text[0] !== '<' || !text.endsWith('>')) return false;
  const inside = text.slice(1, -1);
  const at = inside.indexOf('@');
  return (
    at > 0 &&
    at < inside.length - 1 &&
    inside.indexOf('@', at + 1) < 0 &&
    !/[^\x21-\x7e]|[<>()"\\]/.test(inside)
  );
}
function extractIds(text: string): string[] {
  const ids: string[] = [];
  let start = text.indexOf('<');
  while (start >= 0) {
    const end = text.indexOf('>', start + 1);
    if (end < 0) break;
    const id = text.slice(start, end + 1);
    if (wellFormedId(id)) ids.push(id);
    start = text.indexOf('<', end + 1);
  }
  return ids;
}
function parseEntity(
  number: string,
  fields: Field[],
  body: SourceLine[],
  enabled: boolean,
  problems: string[],
): Entity {
  const entity: Entity = {
    number,
    type: 'text',
    subtype: 'plain',
    parameters: new Map(),
    content: '',
  };
  const contentType = field(fields, 'content-type');
  const disposition = field(fields, 'content-disposition');
  if (enabled && contentType !== undefined) {
    const parsed = parameters(contentType, true);
    if (!parsed) problems.push(`bad Content-Type in part ${number}`);
    else {
      entity.type = parsed.type;
      entity.subtype = parsed.subtype;
      entity.parameters = parsed.parameters;
    }
  }
  if (enabled && disposition !== undefined) {
    const parsed = parameters(disposition, false);
    if (!parsed) problems.push(`bad Content-Disposition in part ${number}`);
    else {
      entity.disposition = parsed.type;
      entity.filename = parsed.parameters.get('filename');
    }
  }
  if (!entity.filename) entity.filename = entity.parameters.get('name');
  const charset = entity.parameters.get('charset');
  if (entity.type === 'text' && charset !== undefined && charset.toLowerCase() !== 'us-ascii') {
    problems.push(`unsupported charset "${charset.toLowerCase()}" in part ${number}`);
  }
  if (enabled && entity.type === 'multipart') {
    const boundary = entity.parameters.get('boundary');
    if (!boundary) problems.push(`missing boundary in part ${number}`);
    else {
      const parts: SourceLine[][] = [];
      let closed = false;
      for (const line of body) {
        const text = trailing(line.text);
        if (text === `--${boundary}--`) {
          closed = true;
          break;
        }
        if (text === `--${boundary}`) parts.push([]);
        else if (parts.length) parts[parts.length - 1].push(line);
      }
      if (!parts.length) problems.push(`no parts in part ${number}`);
      else if (!closed) problems.push(`unterminated multipart in part ${number}`);
      entity.children = parts.map((lines, i) => {
        const split = sections(lines);
        const header = parseHeaders(split.headers);
        for (const line of header.invalid) problems.push(`bad header line ${line}`);
        return parseEntity(`${number}.${i + 1}`, header.fields, split.body, true, problems);
      });
      return entity;
    }
  }
  const original = body.map((line) => line.text).join('\n');
  const encoding = enabled
    ? (field(fields, 'content-transfer-encoding') ?? '7bit').toLowerCase()
    : '7bit';
  if (encoding === 'base64') {
    const content = base64Body(original);
    if (content === undefined) problems.push(`bad base64 in part ${number}`);
    entity.content = content ?? '';
  } else if (encoding === 'quoted-printable') {
    const decoded = quotedPrintable(original);
    entity.content = decoded.text;
    if (decoded.error) problems.push(`bad quoted-printable in part ${number}`);
  } else {
    entity.content = original;
    if (!['7bit', '8bit', 'binary'].includes(encoding)) {
      problems.push(`unknown encoding "${encoding}" in part ${number}`);
    }
  }
  return entity;
}
const rawMessages: SourceLine[][] = [];
inputLines('input/mailbox.mbox').forEach((text, i) => {
  if (text.startsWith('From ')) rawMessages.push([]);
  else {
    rawMessages[rawMessages.length - 1].push({
      text: text.replace(/^>(>*From )/, '$1'),
      number: i + 1,
    });
  }
});
const ids = new Map<string, Message>();
const messages: Message[] = [];
const duplicateNames = [
  'From',
  'To',
  'Cc',
  'Subject',
  'Date',
  'Message-ID',
  'In-Reply-To',
  'References',
  'MIME-Version',
  'Content-Type',
  'Content-Transfer-Encoding',
  'Content-Disposition',
];
for (const raw of rawMessages) {
  if (raw.at(-1)?.text === '') raw.pop();
  const split = sections(raw);
  const header = parseHeaders(split.headers);
  const fields = header.fields;
  const problems = header.invalid.map((line) => `bad header line ${line}`);
  for (const name of duplicateNames) {
    if (fields.filter((f) => f.name === name.toLowerCase()).length >= 2) {
      problems.push(`duplicate ${name}`);
    }
  }
  let sender: Mailbox | undefined;
  const from = field(fields, 'from');
  if (from === undefined) problems.push('missing From');
  else {
    const parsed = addresses(from);
    const first = parsed?.addresses[0];
    if (!parsed || parsed.addresses.length !== 1 || first?.kind !== 'mailbox') {
      problems.push('bad From');
    } else {
      sender = first;
      if (parsed.error) problems.push('bad encoded word in From');
    }
  }
  const recipients = (name: string): string[] => {
    const value = field(fields, name);
    if (value === undefined) return [];
    const parsed = addresses(value);
    if (!parsed) {
      problems.push(`bad ${name}`);
      return [];
    }
    if (parsed.error) problems.push(`bad encoded word in ${name}`);
    return parsed.addresses.flatMap((address) =>
      address.kind === 'group' ? address.members.map((m) => m.address) : [address.address],
    );
  };
  const to = recipients('To');
  const cc = recipients('Cc');
  const decodedSubject = unstructured(field(fields, 'subject') ?? '');
  const subject = decodedSubject.text;
  if (decodedSubject.error) problems.push('bad encoded word in Subject');
  let baseSubject = subject;
  let reply = false;
  while (baseSubject.slice(0, 3).toLowerCase() === 're:') {
    baseSubject = baseSubject.slice(3).replace(/^ +/, '');
    reply = true;
  }
  let seconds: number | undefined;
  const date = field(fields, 'date');
  if (date === undefined) problems.push('missing Date');
  else {
    const parsed = parseDate(date);
    if ('problem' in parsed) problems.push(parsed.problem);
    else seconds = parsed.seconds;
  }
  const number = messages.length + 1;
  const rawId = field(fields, 'message-id');
  let id = '';
  if (rawId === undefined) problems.push('missing Message-ID');
  else if (!wellFormedId(rawId)) problems.push('bad Message-ID');
  else if (ids.has(rawId)) {
    problems.push(`Message-ID already used by message ${ids.get(rawId)!.number}`);
  } else id = rawId;
  const references = extractIds(field(fields, 'references') ?? '');
  const inReplyTo = extractIds(field(fields, 'in-reply-to') ?? '');
  if (inReplyTo.length && references.at(-1) !== inReplyTo[0]) references.push(inReplyTo[0]);
  let enabled = false;
  const mimeVersion = field(fields, 'mime-version');
  if (mimeVersion !== undefined) {
    const value = removeComments(mimeVersion);
    enabled = value !== undefined && value.replace(/[ \t]/g, '') === '1.0';
    if (!enabled) problems.push('bad MIME-Version');
  }
  const entity = parseEntity('1', fields, split.body, enabled, problems);
  const message: Message = {
    number,
    id,
    sender,
    to,
    cc,
    subject,
    baseSubject,
    reply,
    seconds,
    references,
    entity,
    problems,
    key: [seconds === undefined ? 1 : 0, seconds ?? 0, id, number],
    thread: 0,
    depth: 0,
  };
  messages.push(message);
  if (id) ids.set(id, message);
}
const roots = buildThreads(messages);
function position(c: Container<Message>, thread: number, depth: number): void {
  if (c.message) {
    c.message.thread = thread;
    c.message.depth = depth;
    c.message.parent = c.parent?.message;
  }
  for (const child of c.children) position(child, thread, depth + 1);
}
roots.forEach((root, i) => position(root, i + 1, 0));
for (const message of messages) {
  const parent = message.parent;
  if (
    parent &&
    message.seconds !== undefined &&
    parent.seconds !== undefined &&
    message.seconds < parent.seconds
  ) {
    message.problems.push(`dated before parent message ${parent.number}`);
  }
}
function collectText(entity: Entity, html: boolean): Entity[] {
  if (entity.children === undefined) {
    if (entity.disposition === 'attachment') return [];
    return entity.type === 'text' &&
      (entity.subtype === 'plain' || (html && entity.subtype === 'html'))
      ? [entity]
      : [];
  }
  if (entity.subtype === 'alternative') {
    for (const allowed of [false, true]) {
      for (const child of entity.children) {
        const parts = collectText(child, allowed);
        if (parts.length) return parts;
      }
    }
    return [];
  }
  return entity.children.flatMap((child) => collectText(child, html));
}
function wrap(text: string, prefix: string): string[] {
  const words = text.split(/[ \t]+/).filter(Boolean);
  const lines: string[] = [];
  let current = '';
  for (const word of words) {
    if (current && current.length + 1 + word.length > 72) {
      lines.push(prefix + current);
      current = word;
    } else current += (current ? ' ' : '') + word;
  }
  lines.push(prefix + current);
  return lines;
}
const quotePrefix = (depth: number) => (depth ? '>'.repeat(depth) + ' ' : '');
function flowed(entity: Entity): string[] {
  if (!entity.content) return [];
  const logical: { depth: number; text: string; flows: boolean }[] = [];
  for (const line of entity.content.split('\n')) {
    const depth = line.match(/^>*/)![0].length;
    const text = line.slice(depth).replace(/^ /, '');
    const flows = text.endsWith(' ') && text !== '-- ';
    const previous = logical.at(-1);
    if (previous?.flows && previous.depth === depth) {
      if (entity.parameters.get('delsp')?.toLowerCase() === 'yes') {
        previous.text = previous.text.slice(0, -1);
      }
      previous.text += text;
      previous.flows = flows;
    } else logical.push({ depth, text, flows });
  }
  return logical.flatMap((line) => wrap(line.text, quotePrefix(line.depth)));
}
function characterReferences(text: string): string {
  const named: Record<string, string> = {
    amp: '&',
    lt: '<',
    gt: '>',
    quot: '"',
    apos: "'",
    nbsp: ' ',
  };
  let output = '';
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '&') {
      const end = text.indexOf(';', i + 1);
      if (end >= 0) {
        const name = text.slice(i + 1, end);
        let replacement = Object.hasOwn(named, name) ? named[name] : undefined;
        if (/^#[0-9]{1,3}$/.test(name)) {
          const value = +name.slice(1);
          if (value >= 32 && value <= 126) replacement = String.fromCharCode(value);
        }
        if (replacement !== undefined) {
          output += replacement;
          i = end;
          continue;
        }
      }
    }
    output += text[i];
  }
  return output;
}
function htmlLines(content: string): string[] {
  let depth = 0;
  let text = '';
  let hide: string | undefined;
  const logical: { depth: number; text: string }[] = [];
  const paragraphTags = new Set([
    'p',
    'div',
    'ul',
    'ol',
    'table',
    'tr',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  ]);
  for (let i = 0; i < content.length; i++) {
    const close = content[i] === '<' ? content.indexOf('>', i + 1) : -1;
    if (close < 0) {
      if (hide === undefined) text += content[i];
      continue;
    }
    const inside = content.slice(i + 1, close);
    const end = inside.startsWith('/');
    const tag = (end ? inside.slice(1) : inside).match(/^[A-Za-z0-9]*/)![0].toLowerCase();
    i = close;
    if (hide !== undefined) {
      if (end && tag === hide) hide = undefined;
      continue;
    }
    if (!end && ['head', 'style', 'script'].includes(tag)) hide = tag;
    else if (tag === 'br' || (!end && tag === 'li')) {
      logical.push({ depth, text });
      text = !end && tag === 'li' ? '* ' : '';
    } else if (paragraphTags.has(tag)) {
      logical.push({ depth, text }, { depth, text: '' });
      text = '';
      if (tag === 'blockquote') depth = end ? Math.max(0, depth - 1) : depth + 1;
    }
  }
  logical.push({ depth, text });
  const output: string[] = [];
  for (const line of logical) {
    const collapsed = line.text.replace(/[ \t\n]+/g, ' ').replace(/^ +| +$/g, '');
    const converted = characterReferences(collapsed).replace(/^ +| +$/g, '');
    if (converted) output.push(...wrap(converted, quotePrefix(line.depth)));
    else if (output.length && output.at(-1) !== '') output.push('');
  }
  while (output.at(-1) === '') output.pop();
  return output;
}
function display(entity: Entity): {
  format: string;
  lines: string[];
  quoted: number;
  signature: number;
} {
  const format =
    entity.subtype === 'html'
      ? 'html'
      : entity.parameters.get('format')?.toLowerCase() === 'flowed'
        ? 'flowed'
        : 'plain';
  const lines = (
    format === 'html'
      ? htmlLines(entity.content)
      : format === 'flowed'
        ? flowed(entity)
        : entity.content
          ? entity.content.split('\n')
          : []
  ).map(trailing);
  const signatureStart = lines.lastIndexOf('--');
  return {
    format,
    lines,
    quoted: lines.filter((line) => line.startsWith('>')).length,
    signature: signatureStart < 0 ? 0 : lines.length - signatureStart - 1,
  };
}
const dateNotation = (m: Message) => (m.seconds === undefined ? 'invalid' : formatDate(m.seconds));
const subjectNotation = (subject: string) => subject || '(no subject)';
function entityLines(entity: Entity): string[] {
  const line = `part ${entity.number} ${entity.type}/${entity.subtype}`;
  if (entity.children !== undefined) return [line, ...entity.children.flatMap(entityLines)];
  return [
    line +
      ` ${entity.content.length}` +
      (entity.disposition ? ' ' + entity.disposition : '') +
      (entity.filename ? ` "${entity.filename}"` : ''),
  ];
}
const messageBlocks = messages.map((m) => [
  `message ${m.number}`,
  `id ${m.id || '-'}`,
  `date ${dateNotation(m)}`,
  `from ${m.sender ? (m.sender.name ? `${m.sender.name} <${m.sender.address}>` : m.sender.address) : '-'}`,
  `to ${m.to.join(', ') || '-'}`,
  `cc ${m.cc.join(', ') || '-'}`,
  `subject ${subjectNotation(m.subject)}`,
  `refs ${m.references.join(' ') || '-'}`,
  `thread ${m.thread} depth ${m.depth} parent ${m.parent?.number ?? '-'}`,
  ...entityLines(m.entity),
]);
const bodyBlocks = inputLines('input/requests.txt').map((id) => {
  const lines = [`request ${id}`];
  const message = ids.get(id);
  if (!message) return [...lines, 'not found'];
  const parts = collectText(message.entity, true);
  lines.push(`message ${message.number} text parts ${parts.length}`);
  for (const part of parts) {
    const shown = display(part);
    lines.push(
      `part ${part.number} ${shown.format} lines ${shown.lines.length} quoted ${shown.quoted} signature ${shown.signature}`,
      ...shown.lines.map((line) => (line ? '| ' + line : '|')),
    );
  }
  return lines;
});
const threadBlocks = roots.map((root, i) => {
  const held: Message[] = [];
  let maximumDepth = 0;
  const treeLines: string[] = [];
  const render = (c: Container<Message>, depth: number, stem: string, prefix: string): void => {
    maximumDepth = Math.max(maximumDepth, depth);
    const m = c.message;
    if (m) held.push(m);
    const notation = m
      ? `[${m.number}] ${dateNotation(m)} ${m.sender?.address ?? '-'} ${subjectNotation(m.subject)}`
      : c.subject !== undefined
        ? `[subject] ${c.subject}`
        : `[missing] ${c.id}`;
    treeLines.push(prefix + notation);
    c.children.forEach((child, index) => {
      const last = index === c.children.length - 1;
      render(child, depth + 1, stem + (last ? '   ' : '|  '), stem + (last ? '`- ' : '+- '));
    });
  };
  render(root, 0, '', '');
  const dates = held.flatMap((m) => (m.seconds === undefined ? [] : [m.seconds]));
  const subject =
    root.subject ?? root.message?.baseSubject ?? root.children[0].message!.baseSubject;
  return [
    `thread ${i + 1} messages ${held.length} depth ${maximumDepth} senders ${new Set(held.flatMap((m) => (m.sender ? [m.sender.address] : []))).size}`,
    dates.length
      ? `span ${formatDate(Math.min(...dates))} .. ${formatDate(Math.max(...dates))}`
      : 'span -',
    `subject ${subjectNotation(subject)}`,
    ...treeLines,
  ];
});
interface SenderStats {
  address: string;
  name: string;
  count: number;
  threads: Set<number>;
  first?: number;
  last?: number;
}
const senders = new Map<string, SenderStats>();
for (const m of messages) {
  if (!m.sender) continue;
  const address = m.sender.address;
  const stats: SenderStats = senders.get(address) ?? {
    address,
    name: '',
    count: 0,
    threads: new Set<number>(),
  };
  stats.count++;
  stats.threads.add(m.thread);
  if (m.sender.name) stats.name = m.sender.name;
  if (m.seconds !== undefined) {
    stats.first = stats.first === undefined ? m.seconds : Math.min(stats.first, m.seconds);
    stats.last = stats.last === undefined ? m.seconds : Math.max(stats.last, m.seconds);
  }
  senders.set(address, stats);
}
const senderLines = ['address,name,messages,threads,first,last'];
for (const s of [...senders.values()].sort(
  (a, b) => b.count - a.count || (a.address < b.address ? -1 : a.address > b.address ? 1 : 0),
)) {
  const name = /[,"]/.test(s.name) ? `"${s.name.replaceAll('"', '""')}"` : s.name;
  senderLines.push(
    `${s.address},${name},${s.count},${s.threads.size},${s.first === undefined ? '-' : formatDate(s.first)},${s.last === undefined ? '-' : formatDate(s.last)}`,
  );
}
const malformed = [
  `messages ${messages.length} malformed ${messages.filter((m) => m.problems.length > 0).length} problems ${messages.reduce((sum, m) => sum + m.problems.length, 0)}`,
  ...messages.flatMap((m) => m.problems.map((problem) => `message ${m.number}: ${problem}`)),
];
mkdirSync('output', { recursive: true });
const blocks = (values: string[][]) =>
  values.map((lines) => lines.join('\n')).join('\n\n') + (values.length ? '\n' : '');
writeFileSync('output/threads.txt', blocks(threadBlocks), 'ascii');
writeFileSync('output/messages.txt', blocks(messageBlocks), 'ascii');
writeFileSync('output/bodies.txt', blocks(bodyBlocks), 'ascii');
writeFileSync('output/senders.csv', senderLines.join('\n') + '\n', 'ascii');
writeFileSync('output/malformed.txt', malformed.join('\n') + '\n', 'ascii');
