'use strict';
const fs = require('node:fs');
const PUNCTUATION = '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';
const WHITESPACE = ' \n';
const TOC_MARKER = '\x00toc\x00';
const htmlEscapes = {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'};
function escapeHtml(text) { return text.replace(/[&<>"]/g, char => htmlEscapes[char]); }
function stripTags(text) { return text.replace(/<[^>]*>/g, ''); }
function normalize(text) { return text.toLowerCase().replace(/[ \n]+/g, ' ').trim(); }
function skipSpace(text, at) {
    while (at < text.length && WHITESPACE.includes(text[at])) at++;
    return at;
}
function escapedRead(text, at, stops) {
    let value = '';
    while (at < text.length && !stops.includes(text[at])) {
        if (text[at] === '\\' && at + 1 < text.length && PUNCTUATION.includes(text[at + 1])) at++;
        value += text[at++];
    }
    return {value, end: at};
}
function runEnd(text, at) {
    const char = text[at++];
    while (at < text.length && text[at] === char) at++;
    return at;
}
function openingFence(line) {
    if (!line.startsWith('`') && !line.startsWith('~')) return null;
    const end = runEnd(line, 0), fence = line.slice(0, end), info = line.slice(end).trim();
    if (end < 3 || (line[0] === '`' && info.includes('`'))) return null;
    return {fence, info};
}
function atxHeading(line) {
    const match = /^(#{1,6})(?: |$)/.exec(line);
    if (!match) return null;
    let text = line.slice(match[1].length).trim();
    const trimmed = text.replace(/#+$/, '');
    if (!trimmed || trimmed.endsWith(' ')) text = trimmed.trim();
    return {kind: 'heading', level: match[1].length, text};
}
function isRule(line) { return /^(?:-{3,}|\*{3,}|_{3,})$/.test(line.replace(/ /g, '')); }
function listMarker(line) {
    if (isRule(line)) return null;
    const match = /^(?:([-*+])|([0-9]{1,9})([.)])) +/.exec(line);
    if (!match) return null;
    return {marker: match[1] || match[3], ordered: match[2] !== undefined,
        start: match[2] === undefined ? 1 : Number(match[2]), content: line.slice(match[0].length)};
}
function interruptsParagraph(line) {
    return !line.startsWith(' ') && (openingFence(line) !== null || atxHeading(line) !== null
        || isRule(line) || line.startsWith('>') || listMarker(line) !== null);
}
function splitCells(line) {
    let text = line.trim();
    if (text.startsWith('|')) text = text.slice(1);
    const cells = [''];
    let finalSeparator = false;
    for (let at = 0; at < text.length;) {
        const char = text[at++];
        finalSeparator = false;
        if (char === '\\' && at < text.length) {
            cells[cells.length - 1] += (text[at] === '|' ? '' : '\\') + text[at++];
        } else if (char === '|') {
            cells.push('');
            finalSeparator = true;
        } else cells[cells.length - 1] += char;
    }
    if (finalSeparator) cells.pop();
    return cells.map(cell => cell.trim());
}

class BlockParser {
    constructor() {
        this.references = new Map();
        this.footnotes = new Map();
    }
    definition(line) {
        const footnote = /^\[\^([A-Za-z0-9_-]+)\]:(.*)$/.exec(line);
        if (footnote && footnote[2].trim()) {
            const name = footnote[1].toLowerCase();
            if (!this.footnotes.has(name)) this.footnotes.set(name, footnote[2].trim());
            return true;
        }
        if (!line.startsWith('[')) return false;
        const close = line.indexOf(']');
        if (close < 0 || line[close + 1] !== ':') return false;
        const label = line.slice(1, close);
        if (label.includes('[') || !label.trim() || label.startsWith('^')) return false;
        const url = escapedRead(line, skipSpace(line, close + 2), ' ');
        if (!url.value) return false;
        const at = skipSpace(line, url.end);
        let title = null;
        if (at < line.length) {
            if (at === url.end || !'"\''.includes(line[at])) return false;
            const quoted = escapedRead(line, at + 1, line[at]);
            if (quoted.end !== line.length - 1) return false;
            title = quoted.value;
        }
        const name = normalize(label);
        if (!this.references.has(name)) this.references.set(name, {url: url.value, title});
        return true;
    }
    parse(lines) {
        const blocks = [];
        let at = 0;
        while (at < lines.length) {
            const line = lines[at];
            if (line === '') { at++; continue; }
            if (line.startsWith('    ')) {
                let end = at;
                while (end < lines.length && (lines[end] === '' || lines[end].startsWith('    '))) end++;
                while (lines[end - 1] === '') end--;
                blocks.push({kind: 'code', language: '', lines: lines.slice(at, end).map(row => row.slice(4))});
                at = end;
                continue;
            }
            if (!line.startsWith(' ')) {
                const fence = openingFence(line);
                if (fence !== null) {
                    const code = [];
                    at++;
                    while (at < lines.length) {
                        const row = lines[at++];
                        if (row.length >= fence.fence.length && [...row].every(char => char === fence.fence[0])) break;
                        code.push(row);
                    }
                    blocks.push({kind: 'code', language: fence.info.split(' ')[0], lines: code});
                    continue;
                }
                const heading = atxHeading(line);
                if (heading !== null) { blocks.push(heading); at++; continue; }
                if (isRule(line)) { blocks.push({kind: 'rule'}); at++; continue; }
                if (line.startsWith('>')) {
                    const content = [];
                    while (at < lines.length && lines[at].startsWith('>')) content.push(lines[at++].slice(1).replace(/^ /, ''));
                    const alert = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$/.exec(content[0]);
                    blocks.push(alert ? {kind: 'alert', alert: alert[1], blocks: this.parse(content.slice(1))}
                        : {kind: 'quote', blocks: this.parse(content)});
                    continue;
                }
                let marker = listMarker(line);
                if (marker !== null) {
                    const first = marker, items = [];
                    while (true) {
                        const content = [marker.content];
                        at++;
                        while (at < lines.length && lines[at].startsWith('  ')) content.push(lines[at++].slice(2));
                        items.push(this.parse(content));
                        let next = at;
                        while (next < lines.length && lines[next] === '') next++;
                        const following = next < lines.length ? listMarker(lines[next]) : null;
                        if (following === null || following.marker !== first.marker || following.ordered !== first.ordered) break;
                        marker = following;
                        at = next;
                    }
                    blocks.push({kind: 'list', ordered: first.ordered, start: first.start, items});
                    continue;
                }
                if (this.definition(line)) { at++; continue; }
                if (at + 1 < lines.length && line.includes('|') && lines[at + 1].includes('|')) {
                    const header = splitCells(line), delimiters = splitCells(lines[at + 1]);
                    if (header.length === delimiters.length && delimiters.every(cell => /^:?-+:?$/.test(cell))) {
                        const alignments = delimiters.map(cell => cell.startsWith(':')
                            ? (cell.endsWith(':') ? 'center' : 'left') : cell.endsWith(':') ? 'right' : '');
                        const rows = [];
                        at += 2;
                        while (at < lines.length && lines[at] !== '' && lines[at].includes('|')) {
                            const cells = splitCells(lines[at++]).slice(0, header.length);
                            while (cells.length < header.length) cells.push('');
                            rows.push(cells);
                        }
                        blocks.push({kind: 'table', alignments, header, rows});
                        continue;
                    }
                }
            }
            const text = [line.replace(/^ +/, '')];
            let level = 0;
            at++;
            while (at < lines.length && lines[at] !== '') {
                const row = lines[at];
                if (/^(?:={3,}|-{3,})$/.test(row)) { level = row[0] === '=' ? 1 : 2; at++; break; }
                if (interruptsParagraph(row)) break;
                text.push(row.replace(/^ +/, ''));
                at++;
            }
            const combined = text.join('\n');
            blocks.push(level ? {kind: 'heading', level, text: combined}
                : combined === '[TOC]' ? {kind: 'toc'} : {kind: 'paragraph', text: combined});
        }
        return blocks;
    }
}

function backtickCloser(text, at, length) {
    while ((at = text.indexOf('`', at)) !== -1) {
        const end = runEnd(text, at);
        if (end - at === length) return at;
        at = end;
    }
    return -1;
}
function closingBracket(text, at) {
    let depth = 0;
    while (at < text.length) {
        const char = text[at];
        if (char === '\\') { at += 2; continue; }
        if (char === '`') {
            const end = runEnd(text, at), close = backtickCloser(text, end, end - at);
            at = close === -1 ? end : close + end - at;
            continue;
        }
        if (char === '[') depth++;
        else if (char === ']' && --depth === 0) return at;
        at++;
    }
    return -1;
}
function emphasis(pieces, start, end) {
    let html = '';
    for (let at = start; at < end; at++) {
        const piece = pieces[at];
        if (typeof piece === 'string') { html += piece; continue; }
        let close = at + 1;
        if (piece.canOpen) {
            while (close < end) {
                const candidate = pieces[close];
                if (typeof candidate !== 'string' && candidate.char === piece.char
                    && candidate.length === piece.length && candidate.canClose) break;
                close++;
            }
        } else close = end;
        if (close === end) { html += piece.char.repeat(piece.length); continue; }
        const tags = piece.char === '~' ? ['<del>', '</del>']
            : piece.length === 1 ? ['<em>', '</em>'] : piece.length === 2 ? ['<strong>', '</strong>']
            : ['<em><strong>', '</strong></em>'];
        html += tags[0] + emphasis(pieces, at + 1, close) + tags[1];
        at = close;
    }
    return html;
}

class Renderer {
    constructor(references, footnotes) {
        this.references = references;
        this.footnotes = footnotes;
        this.usedIds = new Set();
        this.headings = [];
        this.numberedNotes = new Map();
    }
    destination(text, at, label) {
        if (text[at] === '[') {
            const close = text.indexOf(']', at + 1);
            if (close !== -1 && !text.slice(at + 1, close).includes('[')) {
                const name = normalize(text.slice(at + 1, close) || label), reference = this.references.get(name);
                return reference === undefined ? null : {reference, end: close + 1};
            }
        } else if (text[at] === '(') {
            const url = escapedRead(text, skipSpace(text, at + 1), ' \n)');
            let next = skipSpace(text, url.end), title = null, valid = true;
            if (next > url.end && next < text.length && '"\''.includes(text[next])) {
                const quoted = escapedRead(text, next + 1, text[next]);
                if (quoted.end === text.length) valid = false;
                else { title = quoted.value; next = skipSpace(text, quoted.end + 1); }
            }
            if (valid && text[next] === ')') return {reference: {url: url.value, title}, end: next + 1};
        }
        const reference = this.references.get(normalize(label));
        return reference === undefined ? null : {reference, end: at};
    }
    bracket(text, at, links, notes) {
        if (links && notes && text.startsWith('[^', at)) {
            const close = text.indexOf(']', at + 2), name = text.slice(at + 2, close).toLowerCase();
            if (close !== -1 && this.footnotes.has(name)) return {html: this.footnoteReference(name), end: close + 1};
        }
        const image = text[at] === '!';
        if (!image && !links) return null;
        const opening = at + (image ? 1 : 0), close = closingBracket(text, opening);
        if (close === -1) return null;
        const label = text.slice(opening + 1, close), destination = this.destination(text, close + 1, label);
        if (destination === null) return null;
        const reference = destination.reference, content = this.inline(label, false, false);
        const title = reference.title === null ? '' : ` title="${escapeHtml(reference.title)}"`;
        const url = escapeHtml(reference.url);
        const html = image ? `<img src="${url}" alt="${stripTags(content)}"${title} />`
            : `<a href="${url}"${title}>${content}</a>`;
        return {html, end: destination.end};
    }
    inline(text, links = true, notes = true) {
        const pieces = [];
        let at = 0;
        while (at < text.length) {
            const char = text[at], following = text[at + 1];
            if (char === '\\') {
                if (following !== undefined && PUNCTUATION.includes(following)) { pieces.push(escapeHtml(following)); at += 2; }
                else if (following === '\n') { pieces.push('<br />\n'); at += 2; }
                else { pieces.push('\\'); at++; }
                continue;
            }
            if (char === '`') {
                const end = runEnd(text, at), close = backtickCloser(text, end, end - at);
                if (close === -1) { pieces.push(text.slice(at, end)); at = end; }
                else {
                    let code = text.slice(end, close).replace(/\n/g, ' ');
                    if (code.startsWith(' ') && code.endsWith(' ') && /[^ ]/.test(code)) code = code.slice(1, -1);
                    pieces.push(`<code>${escapeHtml(code)}</code>`);
                    at = close + end - at;
                }
                continue;
            }
            if (links && char === '<') {
                const close = text.indexOf('>', at + 1);
                if (close !== -1) {
                    const target = text.slice(at + 1, close);
                    let href = '';
                    const clean = !/[ \n<]/.test(target);
                    if (clean && /^(?:http:\/\/.+|https:\/\/.+)$/.test(target)) href = target;
                    else if (clean && /^[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(target)) href = 'mailto:' + target;
                    if (href) { pieces.push(`<a href="${escapeHtml(href)}">${escapeHtml(target)}</a>`); at = close + 1; continue; }
                }
            }
            if (links && (text.startsWith('http://', at) || text.startsWith('https://', at))
                && (at === 0 || ' \n*_~('.includes(text[at - 1]))) {
                let end = at;
                while (end < text.length && !' \n<'.includes(text[end])) end++;
                while (end > at && '.,:;!?*_~)'.includes(text[end - 1])) end--;
                const url = text.slice(at, end);
                if (url !== 'http://' && url !== 'https://') { pieces.push(`<a href="${escapeHtml(url)}">${escapeHtml(url)}</a>`); at = end; continue; }
            }
            if (char === '[' || (char === '!' && following === '[')) {
                const result = this.bracket(text, at, links, notes);
                if (result !== null) { pieces.push(result.html); at = result.end; continue; }
                pieces.push(char); at++; continue;
            }
            if ('*_~'.includes(char)) {
                const end = runEnd(text, at), length = end - at;
                const before = at === 0 ? ' ' : text[at - 1], after = end === text.length ? ' ' : text[end];
                let canOpen = !WHITESPACE.includes(after), canClose = !WHITESPACE.includes(before);
                if (char === '_' && /^[A-Za-z0-9]$/.test(before) && /^[A-Za-z0-9]$/.test(after)) canOpen = canClose = false;
                if ((char !== '~' && length <= 3) || (char === '~' && length === 2)) pieces.push({char, length, canOpen, canClose});
                else pieces.push(char.repeat(length));
                at = end;
                continue;
            }
            pieces.push(escapeHtml(char)); at++;
        }
        return emphasis(pieces, 0, pieces.length);
    }
    blocks(blocks) { return blocks.map(block => this.block(block) + '\n').join(''); }
    block(block) {
        switch (block.kind) {
            case 'heading': return this.heading(block.level, block.text);
            case 'paragraph': return `<p>${this.inline(block.text)}</p>`;
            case 'rule': return '<hr />';
            case 'toc': return TOC_MARKER;
            case 'code': {
                const attribute = block.language ? ` class="language-${escapeHtml(block.language)}"` : '';
                return `<pre><code${attribute}>${block.lines.map(line => escapeHtml(line) + '\n').join('')}</code></pre>`;
            }
            case 'quote': return `<blockquote>\n${this.blocks(block.blocks)}</blockquote>`;
            case 'alert': {
                const kind = block.alert.toLowerCase(), title = kind[0].toUpperCase() + kind.slice(1);
                return `<div class="alert alert-${kind}">\n<p class="alert-title">${title}</p>\n${this.blocks(block.blocks)}</div>`;
            }
            case 'list': {
                const tag = block.ordered ? 'ol' : 'ul', attribute = block.ordered && block.start !== 1 ? ` start="${block.start}"` : '';
                return `<${tag}${attribute}>\n${block.items.map(item => this.item(item) + '\n').join('')}</${tag}>`;
            }
            case 'table': {
                let html = '<table>\n<thead>\n<tr>\n' + this.tableCells('th', block.alignments, block.header) + '</tr>\n</thead>\n';
                if (block.rows.length) html += '<tbody>\n' + block.rows.map(row => '<tr>\n' + this.tableCells('td', block.alignments, row) + '</tr>\n').join('') + '</tbody>\n';
                return html + '</table>';
            }
        }
    }
    heading(level, text) {
        const start = text.lastIndexOf(' {#');
        let id;
        if (text.endsWith('}') && start !== -1 && !text.slice(start + 3, -1).includes('\n') && /^[A-Za-z0-9_-]+$/.test(text.slice(start + 3, -1))) {
            id = text.slice(start + 3, -1);
            text = text.slice(0, start).replace(/ +$/, '');
        } else {
            const base = text.toLowerCase().replace(/[^a-z0-9_ \n-]/g, '').replace(/[ \n]/g, '-') || 'heading';
            id = base;
            for (let suffix = 1; this.usedIds.has(id); suffix++) id = `${base}-${suffix}`;
        }
        this.usedIds.add(id);
        const html = this.inline(text);
        this.headings.push({level, id, label: stripTags(html), children: []});
        return `<h${level} id="${id}">${html}</h${level}>`;
    }
    item(blocks) {
        let html = '<li>';
        blocks.forEach((block, index) => {
            if (block.kind === 'paragraph') {
                let text = block.text;
                if (index === 0 && text.length > 4 && /^(?:\[ \]|\[x\]|\[X\]) /.test(text)) {
                    html += text[1] === ' ' ? '<input type="checkbox" disabled="" /> ' : '<input type="checkbox" checked="" disabled="" /> ';
                    text = text.slice(4);
                }
                html += this.inline(text);
            } else {
                if (!html.endsWith('\n')) html += '\n';
                html += this.block(block) + '\n';
            }
        });
        return html + '</li>';
    }
    tableCells(tag, alignments, cells) {
        return cells.map((cell, index) => {
            const style = alignments[index] ? ` style="text-align:${alignments[index]}"` : '';
            return `<${tag}${style}>${this.inline(cell)}</${tag}>\n`;
        }).join('');
    }
    tocList(entries) {
        return '<ul>\n' + entries.map(entry => `<li><a href="#${entry.id}">${entry.label}</a>`
            + (entry.children.length ? '\n' + this.tocList(entry.children) + '\n' : '') + '</li>\n').join('') + '</ul>';
    }
    tableOfContents() {
        if (!this.headings.length) return '<nav class="toc">\n</nav>';
        const roots = [], parents = [];
        for (const heading of this.headings) {
            while (parents.length && parents[parents.length - 1].level >= heading.level) parents.pop();
            (parents.length ? parents[parents.length - 1].children : roots).push(heading);
            parents.push(heading);
        }
        return '<nav class="toc">\n' + this.tocList(roots) + '\n</nav>';
    }
    referenceId(number, count) { return `fnref-${number}` + (count === 1 ? '' : `-${count}`); }
    footnoteReference(name) {
        if (!this.numberedNotes.has(name)) this.numberedNotes.set(name, {number: this.numberedNotes.size + 1, count: 0});
        const note = this.numberedNotes.get(name);
        note.count++;
        return `<sup id="${this.referenceId(note.number, note.count)}"><a href="#fn-${note.number}">${note.number}</a></sup>`;
    }
    footnoteList() {
        let html = '<section class="footnotes">\n<ol>\n';
        for (const [name, note] of this.numberedNotes) {
            const body = this.inline(this.footnotes.get(name), true, false), backlinks = [];
            for (let count = 1; count <= note.count; count++) backlinks.push(`<a href="#${this.referenceId(note.number, count)}">&#8617;</a>`);
            html += `<li id="fn-${note.number}">${body} ${backlinks.join(' ')}</li>\n`;
        }
        return html + '</ol>\n</section>\n';
    }
    document(blocks) {
        const html = this.blocks(blocks), toc = this.tableOfContents();
        return html.split(TOC_MARKER).join(toc) + (this.numberedNotes.size ? this.footnoteList() : '');
    }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
const parser = new BlockParser();
const blocks = parser.parse(lines.slice(0, lines.indexOf('@@END@@')));
process.stdout.write(new Renderer(parser.references, parser.footnotes).document(blocks));
