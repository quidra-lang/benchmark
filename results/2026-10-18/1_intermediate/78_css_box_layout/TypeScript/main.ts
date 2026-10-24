import * as fs from 'node:fs';

type Declaration = [string, string];
type Rect = [number, number, number, number];
interface Boxes { margin: Rect; border: Rect; padding: Rect; content: Rect }
interface StyleRule { selectors: string[]; declarations: Declaration[] }
interface GridItem { node: Element; column: number | null; row: number | null; cs: number; rs: number; contribution: number; aw: number; ax: number; gw: number }
interface Grid { columns: string[]; rows: string[]; items: GridItem[]; nc: number; nr: number }
interface FlexItem { node: Element; alignment: string; cross: number; base: number; hypothetical: number; outer: number; target: number; weight: number; frozen: boolean }

const initial = new Map<string, string>(Object.entries({
    display: 'block', position: 'static', 'box-sizing': 'content-box', width: 'auto', height: 'auto',
    'min-width': '0', 'min-height': '0', 'max-width': 'none', 'max-height': 'none',
    top: 'auto', right: 'auto', bottom: 'auto', left: 'auto', 'flex-direction': 'row', 'flex-wrap': 'nowrap',
    'justify-content': 'start', 'align-items': 'stretch', 'align-self': 'auto', 'row-gap': '0', 'column-gap': '0',
    order: '0', 'flex-grow': '0', 'flex-shrink': '1', 'flex-basis': 'auto',
    'grid-template-columns': 'none', 'grid-template-rows': 'none', 'grid-column': 'auto', 'grid-row': 'auto'
}));
const sides = ['top', 'right', 'bottom', 'left'];
for (const prefix of ['margin', 'padding', 'border']) for (const side of sides) initial.set(prefix + '-' + side, '0');
const known = new Set([...initial.keys(), 'margin', 'padding', 'border', 'gap']);
const enumerations = new Map<string, string[]>(Object.entries({
    display: ['block', 'flex', 'grid', 'none'], position: ['static', 'relative', 'absolute'],
    'box-sizing': ['content-box', 'border-box'], 'flex-direction': ['row', 'row-reverse', 'column', 'column-reverse'],
    'flex-wrap': ['nowrap', 'wrap'], 'justify-content': ['start', 'end', 'center', 'space-between', 'space-around', 'space-evenly'],
    'align-items': ['stretch', 'start', 'end', 'center'], 'align-self': ['auto', 'stretch', 'start', 'end', 'center']
}));
function uint(text: string): boolean { return /^[0-9]{1,3}$/.test(text); }
function positive(text: string): boolean { return uint(text) && Number(text) > 0; }
function signed(text: string): boolean { return uint(text.startsWith('-') ? text.slice(1) : text); }
function percentage(text: string): boolean { return text.endsWith('%') && uint(text.slice(0, -1)); }
function fraction(text: string): boolean { return text.endsWith('fr') && positive(text.slice(0, -2)); }
function gridValue(value: string): boolean {
    const words = value.split(' ');
    return value === 'auto' || words.length === 1 && positive(words[0]) || words.length === 2 && words[0] === 'span' && positive(words[1]) ||
        words.length === 3 && positive(words[0]) && words[1] === '/' && positive(words[2]) && Number(words[0]) < Number(words[2]) ||
        words.length === 4 && positive(words[0]) && words[1] === '/' && words[2] === 'span' && positive(words[3]);
}
function declarations(property: string, value: string): Declaration[] | null {
    if (!known.has(property)) return null;
    const words = value.split(' ');
    if (['margin', 'padding', 'border'].includes(property)) {
        if (words.length < 1 || words.length > 4 || !words.every(word => property === 'border' ? word === '0' || word === '1' : uint(word))) return null;
        const values = words.length === 1 ? [words[0], words[0], words[0], words[0]] : words.length === 2 ? [words[0], words[1], words[0], words[1]] : words.length === 3 ? [words[0], words[1], words[2], words[1]] : words;
        return sides.map((side, i): Declaration => [property + '-' + side, values[i]]);
    }
    if (property === 'gap') return words.length <= 2 && words.every(uint) ? [['row-gap', words[0]], ['column-gap', words[1] ?? words[0]]] : null;
    let valid: boolean;
    if (property.startsWith('grid-template-')) valid = value === 'none' || words.every(word => uint(word) || fraction(word) || word === 'auto');
    else if (property === 'grid-column' || property === 'grid-row') valid = gridValue(value);
    else if (words.length !== 1) valid = false;
    else if (enumerations.has(property)) valid = enumerations.get(property)!.includes(value);
    else if (property === 'width' || property === 'height' || property === 'flex-basis') valid = value === 'auto' || uint(value) || percentage(value);
    else if (property.startsWith('min-')) valid = uint(value) || percentage(value);
    else if (property.startsWith('max-')) valid = value === 'none' || uint(value) || percentage(value);
    else if (property.startsWith('border-')) valid = value === '0' || value === '1';
    else if (sides.includes(property)) valid = value === 'auto' || signed(value);
    else if (property === 'order') valid = signed(value);
    else valid = uint(value);
    return valid ? [[property, value]] : null;
}
function distribute(total: number, weights: number[]): number[] {
    const sum = weights.reduce((a, b) => a + b, 0);
    if (sum === 0) return weights.map(() => 0);
    const result = weights.map(weight => Math.floor(total * weight / sum));
    let remainder = total - result.reduce((a, b) => a + b, 0);
    for (let i = 0; i < weights.length && remainder > 0; i++) if (weights[i] > 0) { result[i]++; remainder--; }
    return result;
}
class Element {
    children: Element[] = [];
    overrides = new Map<string, string>();
    style = new Map<string, string>();
    shown = false;
    cw = 0; ch = 0; rx = 0; ry = 0; x = 0; y = 0;
    lines: string[] = [];
    containing: Element | null = null;
    constructor(public type: string, public id: string, public classes: string[], public text: string | null, public depth: number, public parent: Element | null, public index: number) {}
    value(property: string): string { return this.style.get(property)!; }
    number(property: string): number { return Number(this.value(property)); }
    side(prefix: string, side: string): number { return this.number(prefix + '-' + side); }
    frame(horizontal: boolean): number { return horizontal ? this.side('padding', 'left') + this.side('padding', 'right') + this.side('border', 'left') + this.side('border', 'right') : this.side('padding', 'top') + this.side('padding', 'bottom') + this.side('border', 'top') + this.side('border', 'bottom'); }
    margin(horizontal: boolean): number { return horizontal ? this.side('margin', 'left') + this.side('margin', 'right') : this.side('margin', 'top') + this.side('margin', 'bottom'); }
    borderWidth(): number { return this.cw + this.frame(true); }
    borderHeight(): number { return this.ch + this.frame(false); }
    flow(): Element[] { return this.children.filter(child => child.shown && child.value('position') !== 'absolute'); }
    items(): Element[] { return this.flow().sort((a, b) => a.number('order') - b.number('order') || a.index - b.index); }
    resolve(property: string, reference: number | null, horizontal: boolean): number | null {
        const value = this.value(property);
        if (value === 'auto' || value === 'none' || value.endsWith('%') && reference === null) return null;
        const size = value.endsWith('%') ? Math.floor(reference! * Number(value.slice(0, -1)) / 100) : Number(value);
        return this.value('box-sizing') === 'border-box' ? Math.max(0, size - this.frame(horizontal)) : size;
    }
    clamp(value: number, horizontal: boolean, reference: number | null): number {
        const suffix = horizontal ? 'width' : 'height', lower = this.resolve('min-' + suffix, reference, horizontal) ?? 0, upper = this.resolve('max-' + suffix, reference, horizontal);
        return Math.max(lower, upper === null ? value : Math.min(value, upper));
    }
    place(child: Element, x: number, y: number): void { child.rx = x + this.side('border', 'left') + this.side('padding', 'left'); child.ry = y + this.side('border', 'top') + this.side('padding', 'top'); }
}
const elements: Element[] = [], byId = new Map<string, Element>(), rules: StyleRule[] = [], output: string[] = [];
let width = 0, height = 0, maximumCache = new Map<Element, number>();
function align(parent: Element, child: Element): string { return child.value('align-self') === 'auto' ? parent.value('align-items') : child.value('align-self'); }
function contribution(element: Element): number { return element.clamp(element.resolve('width', null, true) ?? maximum(element), true, null) + element.frame(true) + element.margin(true); }
function placement(element: Element): Grid {
    const columns = element.value('grid-template-columns') === 'none' ? ['auto'] : element.value('grid-template-columns').split(' ');
    const rows = element.value('grid-template-rows') === 'none' ? [] : element.value('grid-template-rows').split(' ');
    function axis(value: string): [number | null, number] { const words = value.split(' '); return value === 'auto' ? [null, 1] : words[0] === 'span' ? [null, Number(words[1])] : [Number(words[0]), words.length === 1 ? 1 : words.length === 3 ? Number(words[2]) - Number(words[0]) : Number(words[3])]; }
    const items: GridItem[] = element.items().map(node => { const [column, cs] = axis(node.value('grid-column')), [row, rs] = axis(node.value('grid-row')); return { node, column, row, cs, rs, contribution: 0, aw: 0, ax: 0, gw: 0 }; });
    const nc = Math.max(columns.length, ...items.map(item => item.column === null ? item.cs : item.column + item.cs - 1)), occupied = new Set<string>();
    function overlaps(item: GridItem, r: number, c: number): boolean { for (let y = r; y < r + item.rs; y++) for (let x = c; x < c + item.cs; x++) if (occupied.has(y + ':' + x)) return true; return false; }
    function put(item: GridItem, r: number, c: number): void { item.row = r; item.column = c; for (let y = r; y < r + item.rs; y++) for (let x = c; x < c + item.cs; x++) occupied.add(y + ':' + x); }
    const pending = items.filter(item => item.row === null || item.column === null);
    for (const item of items) if (item.row !== null && item.column !== null) put(item, item.row, item.column);
    let cr = 1, cc = 1;
    for (const item of pending) {
        if (item.row !== null) {
            let column = 1;
            while (column <= nc - item.cs + 1 && overlaps(item, item.row, column)) column++;
            put(item, item.row, column <= nc - item.cs + 1 ? column : 1);
        } else if (item.column !== null) {
            if (item.column < cc) cr++;
            let row = cr; while (overlaps(item, row, item.column)) row++;
            put(item, row, item.column); cr = row; cc = item.column + item.cs;
        } else {
            let row = cr, column = cc;
            while (true) { if (column + item.cs - 1 > nc) { row++; column = 1; } else if (overlaps(item, row, column)) column++; else break; }
            put(item, row, column); cr = row; cc = column + item.cs;
        }
    }
    return { columns, rows, items, nc, nr: Math.max(rows.length, ...items.map(item => item.row! + item.rs - 1)) };
}
function trackSizes(explicit: string[], count: number, available: number | null, gap: number, items: GridItem[], horizontal: boolean, contributions: number[]): number[] {
    const tracks = [...explicit, ...Array<string>(Math.max(0, count - explicit.length)).fill('auto')];
    const sizes = tracks.map((track, i) => {
        if (uint(track)) return Number(track);
        if (fraction(track) && available !== null) return 0;
        return Math.max(0, ...items.map((item, j) => (horizontal ? item.column : item.row) === i + 1 && (horizontal ? item.cs : item.rs) === 1 ? contributions[j] : 0));
    });
    if (available !== null) {
        const remaining = available - sizes.reduce((a, b) => a + b, 0) - gap * Math.max(0, count - 1), hasFr = tracks.some(fraction);
        if (remaining > 0) {
            const weights = tracks.map(track => hasFr ? fraction(track) ? Number(track.slice(0, -2)) : 0 : track === 'auto' ? 1 : 0), shares = distribute(remaining, weights);
            sizes.forEach((_, i) => sizes[i] += shares[i]);
        }
    }
    return sizes;
}
function maximum(element: Element): number {
    if (maximumCache.has(element)) return maximumCache.get(element)!;
    let value: number;
    if (element.text !== null) value = element.text.length;
    else if (element.value('display') === 'grid') {
        const grid = placement(element), gap = element.number('column-gap');
        value = trackSizes(grid.columns, grid.nc, null, gap, grid.items, true, grid.items.map(item => contribution(item.node))).reduce((a, b) => a + b, 0) + gap * (grid.nc - 1);
    } else {
        const children = element.flow();
        value = element.value('display') === 'flex' && element.value('flex-direction').startsWith('row')
            ? children.reduce((sum, child) => sum + contribution(child), 0) + element.number('column-gap') * Math.max(0, children.length - 1)
            : Math.max(0, ...children.map(contribution));
    }
    maximumCache.set(element, value); return value;
}
function layout(element: Element, widthReference: number, heightReference: number | null, forcedWidth: number | null = null, forcedHeight: number | null = null): number {
    element.cw = forcedWidth ?? element.clamp(element.resolve('width', widthReference, true) ?? Math.max(0, widthReference - element.margin(true) - element.frame(true)), true, widthReference);
    let fixed = forcedHeight;
    if (fixed === null) { const resolved = element.resolve('height', heightReference, false); if (resolved !== null) fixed = element.clamp(resolved, false, heightReference); }
    let content = 0;
    element.lines = [];
    if (element.text !== null) {
        for (const word of element.text.split(' ')) {
            if (!element.lines.length || element.lines.at(-1)!.length + 1 + word.length > element.cw) element.lines.push(word);
            else element.lines[element.lines.length - 1] += ' ' + word;
        }
        content = element.lines.length;
    } else if (element.value('display') === 'flex') content = flex(element, fixed, heightReference);
    else if (element.value('display') === 'grid') content = gridLayout(element, fixed);
    else {
        let bottom = 0, previousMargin = 0;
        for (const child of element.flow()) {
            layout(child, element.cw, fixed);
            const top = bottom + Math.max(previousMargin, child.side('margin', 'top'));
            element.place(child, child.side('margin', 'left'), top);
            bottom = top + child.borderHeight(); previousMargin = child.side('margin', 'bottom');
        }
        content = bottom + previousMargin;
    }
    element.ch = fixed ?? element.clamp(content, false, heightReference);
    return content;
}
function flex(element: Element, k: number | null, heightReference: number | null): number {
    const horizontal = element.value('flex-direction').startsWith('row'), reverse = element.value('flex-direction').endsWith('reverse');
    const reference = horizontal ? element.cw : k, gap = element.number(horizontal ? 'column-gap' : 'row-gap'), lineGap = element.number('row-gap');
    const items: FlexItem[] = element.items().map(node => {
        const alignment = align(element, node); let cross = 0;
        if (!horizontal) {
            const available = Math.max(0, element.cw - node.margin(true) - node.frame(true));
            cross = node.clamp(node.value('width') !== 'auto' ? node.resolve('width', element.cw, true)! : alignment === 'stretch' ? available : Math.min(maximum(node), available), true, element.cw);
        }
        let base = node.resolve('flex-basis', reference, horizontal) ?? node.resolve(horizontal ? 'width' : 'height', reference, horizontal);
        if (base === null) base = horizontal ? maximum(node) : layout(node, element.cw, k, cross);
        const hypothetical = node.clamp(base, horizontal, reference), outer = node.frame(horizontal) + node.margin(horizontal);
        return { node, alignment, cross, base, hypothetical, outer, target: hypothetical, weight: 0, frozen: false };
    });
    const main = horizontal ? element.cw : k ?? element.clamp(items.reduce((sum, item) => sum + item.hypothetical + item.outer, 0) + gap * Math.max(0, items.length - 1), false, heightReference);
    const lines: FlexItem[][] = [];
    for (const item of items) {
        const last = lines.at(-1);
        if (last === undefined || horizontal && element.value('flex-wrap') === 'wrap' && last.reduce((sum, other) => sum + other.hypothetical + other.outer, 0) + gap * last.length + item.hypothetical + item.outer > main) lines.push([item]);
        else last.push(item);
    }
    let crossStart = 0;
    for (const line of lines) {
        const growing = line.reduce((sum, item) => sum + item.hypothetical + item.outer, 0) + gap * (line.length - 1) < main;
        for (const item of line) { item.weight = growing ? item.node.number('flex-grow') : item.node.number('flex-shrink') * item.base; item.frozen = item.weight === 0 || (growing ? item.base > item.hypothetical : item.base < item.hypothetical); }
        while (line.some(item => !item.frozen)) {
            const free = main - gap * (line.length - 1) - line.reduce((sum, item) => sum + (item.frozen ? item.target : item.base) + item.outer, 0);
            const shares = distribute(Math.max(0, growing ? free : -free), line.map(item => item.frozen ? 0 : item.weight));
            const violations = line.map((item, i) => { if (item.frozen) return 0; const tentative = item.base + (growing ? shares[i] : -shares[i]); item.target = item.node.clamp(tentative, horizontal, reference); return item.target - tentative; });
            const total = violations.reduce((a, b) => a + b, 0);
            line.forEach((item, i) => { if (total === 0 || (total > 0 ? violations[i] > 0 : violations[i] < 0)) item.frozen = true; });
        }
        if (horizontal) for (const item of line) { layout(item.node, element.cw, k, item.target); item.cross = item.node.ch; }
        const outerCross = Math.max(0, ...line.map(item => item.cross + item.node.frame(!horizontal) + item.node.margin(!horizontal)));
        const lineCross = horizontal ? lines.length === 1 ? k ?? element.clamp(outerCross, false, heightReference) : outerCross : element.cw;
        const remaining = main - line.reduce((sum, item) => sum + item.target + item.outer, 0) - gap * (line.length - 1), spaces = line.map(() => 0), justification = element.value('justify-content');
        if (remaining > 0) {
            if (justification === 'end') spaces[0] = remaining;
            else if (justification === 'center') spaces[0] = Math.floor(remaining / 2);
            else if (justification.startsWith('space-')) {
                const weights = Array.from({ length: line.length + 1 }, (_, i) => justification === 'space-evenly' ? 1 : i === 0 || i === line.length ? justification === 'space-between' ? 0 : 1 : justification === 'space-between' ? 1 : 2);
                const shares = distribute(remaining, weights); spaces.forEach((_, i) => spaces[i] = shares[i]);
            }
        }
        let cursor = 0;
        line.forEach((item, i) => {
            const node = item.node;
            if (horizontal && item.alignment === 'stretch' && node.value('height') === 'auto') { item.cross = node.clamp(Math.max(0, lineCross - node.margin(false) - node.frame(false)), false, k); layout(node, element.cw, k, item.target, item.cross); }
            else if (horizontal) { layout(node, element.cw, k, item.target); item.cross = node.ch; }
            else layout(node, element.cw, k, item.cross, item.target);
            const spare = lineCross - item.cross - node.frame(!horizontal) - node.margin(!horizontal), offset = spare > 0 ? item.alignment === 'end' ? spare : item.alignment === 'center' ? Math.floor(spare / 2) : 0 : 0;
            cursor += spaces[i];
            const startMargin = node.side('margin', horizontal ? reverse ? 'right' : 'left' : reverse ? 'bottom' : 'top');
            const mainPosition = reverse ? main - cursor - startMargin - (horizontal ? node.borderWidth() : node.borderHeight()) : cursor + startMargin;
            const crossPosition = crossStart + offset + node.side('margin', horizontal ? 'top' : 'left');
            element.place(node, horizontal ? mainPosition : crossPosition, horizontal ? crossPosition : mainPosition);
            cursor += item.target + item.outer + gap;
        });
        crossStart += lineCross + lineGap;
    }
    return horizontal ? lines.length ? crossStart - lineGap : 0 : main;
}
function area(sizes: number[], start: number, span: number, gap: number): { size: number; offset: number } { return { size: sizes.slice(start - 1, start - 1 + span).reduce((a, b) => a + b, 0) + gap * (span - 1), offset: sizes.slice(0, start - 1).reduce((a, b) => a + b, 0) + gap * (start - 1) }; }
function gridLayout(element: Element, k: number | null): number {
    const grid = placement(element), columnGap = element.number('column-gap'), rowGap = element.number('row-gap');
    const columns = trackSizes(grid.columns, grid.nc, element.cw, columnGap, grid.items, true, grid.items.map(item => contribution(item.node)));
    for (const item of grid.items) {
        const node = item.node, column = area(columns, item.column!, item.cs, columnGap);
        item.aw = column.size; item.ax = column.offset; item.gw = node.clamp(node.resolve('width', item.aw, true) ?? Math.max(0, item.aw - node.margin(true) - node.frame(true)), true, item.aw);
        layout(node, item.aw, null, item.gw); item.contribution = node.borderHeight() + node.margin(false);
    }
    const rows = trackSizes(grid.rows, grid.nr, k, rowGap, grid.items, false, grid.items.map(item => item.contribution));
    for (const item of grid.items) {
        const node = item.node, row = area(rows, item.row!, item.rs, rowGap), alignment = align(element, node);
        if (alignment === 'stretch' && node.value('height') === 'auto') layout(node, item.aw, row.size, item.gw, node.clamp(Math.max(0, row.size - node.margin(false) - node.frame(false)), false, row.size));
        else layout(node, item.aw, row.size, item.gw);
        const spare = row.size - node.borderHeight() - node.margin(false), offset = spare > 0 ? alignment === 'end' ? spare : alignment === 'center' ? Math.floor(spare / 2) : 0 : 0;
        element.place(node, item.ax + node.side('margin', 'left'), row.offset + offset + node.side('margin', 'top'));
    }
    return rows.reduce((a, b) => a + b, 0) + rowGap * Math.max(0, grid.nr - 1);
}
function relayout(): void {
    maximumCache = new Map<Element, number>();
    for (const node of elements) {
        node.style = new Map(initial); const ranks = new Map<string, number>();
        for (const rule of rules) {
            const matching = rule.selectors.filter(selector => selector[0] === '#' ? selector.slice(1) === node.id : selector[0] === '.' ? node.classes.includes(selector.slice(1)) : selector === node.type);
            if (!matching.length) continue;
            const rank = Math.max(...matching.map(selector => selector[0] === '#' ? 2 : selector[0] === '.' ? 1 : 0));
            for (const [property, value] of rule.declarations) if (!ranks.has(property) || rank >= ranks.get(property)!) { node.style.set(property, value); ranks.set(property, rank); }
        }
        for (const [property, value] of node.overrides) node.style.set(property, value);
        node.shown = node.value('display') !== 'none' && (node.parent === null || node.parent.shown); node.containing = null;
    }
    const root = elements[0];
    if (root.shown && root.value('position') !== 'absolute') { layout(root, width, height); root.rx = root.side('margin', 'left'); root.ry = root.side('margin', 'top'); }
    for (const node of elements) if (node.shown && node.value('position') === 'absolute') {
        let containing = node.parent;
        while (containing !== null && containing.value('position') === 'static') containing = containing.parent;
        node.containing = containing;
        const cbw = containing === null ? width : containing.cw + containing.side('padding', 'left') + containing.side('padding', 'right'), cbh = containing === null ? height : containing.ch + containing.side('padding', 'top') + containing.side('padding', 'bottom');
        const left = node.value('left') === 'auto' ? null : node.number('left'), right = node.value('right') === 'auto' ? null : node.number('right'), top = node.value('top') === 'auto' ? null : node.number('top'), bottom = node.value('bottom') === 'auto' ? null : node.number('bottom');
        const available = Math.max(0, cbw - (left ?? 0) - (right ?? 0) - node.margin(true) - node.frame(true));
        const fw = node.clamp(node.value('width') !== 'auto' ? node.resolve('width', cbw, true)! : left !== null && right !== null ? available : Math.min(maximum(node), available), true, cbw);
        const fh = node.value('height') === 'auto' && top !== null && bottom !== null ? node.clamp(Math.max(0, cbh - top - bottom - node.margin(false) - node.frame(false)), false, cbh) : null;
        layout(node, cbw, cbh, fw, fh);
        node.rx = left !== null ? left + node.side('margin', 'left') : right !== null ? cbw - right - node.side('margin', 'right') - node.borderWidth() : node.side('margin', 'left');
        node.ry = top !== null ? top + node.side('margin', 'top') : bottom !== null ? cbh - bottom - node.side('margin', 'bottom') - node.borderHeight() : node.side('margin', 'top');
    }
    for (const node of elements) if (node.shown) {
        const absolute = node.value('position') === 'absolute', reference = absolute ? node.containing : node.parent;
        node.x = (reference === null ? 0 : reference.x + (absolute ? reference.side('border', 'left') : 0)) + node.rx;
        node.y = (reference === null ? 0 : reference.y + (absolute ? reference.side('border', 'top') : 0)) + node.ry;
        if (node.value('position') === 'relative') { node.x += node.value('left') !== 'auto' ? node.number('left') : node.value('right') !== 'auto' ? -node.number('right') : 0; node.y += node.value('top') !== 'auto' ? node.number('top') : node.value('bottom') !== 'auto' ? -node.number('bottom') : 0; }
    }
}
function boxes(node: Element): Boxes {
    const border: Rect = [node.x, node.y, node.borderWidth(), node.borderHeight()], margin: Rect = [node.x - node.side('margin', 'left'), node.y - node.side('margin', 'top'), border[2] + node.margin(true), border[3] + node.margin(false)];
    const padding: Rect = [node.x + node.side('border', 'left'), node.y + node.side('border', 'top'), border[2] - node.side('border', 'left') - node.side('border', 'right'), border[3] - node.side('border', 'top') - node.side('border', 'bottom')];
    return { margin, border, padding, content: [padding[0] + node.side('padding', 'left'), padding[1] + node.side('padding', 'top'), node.cw, node.ch] };
}
function snapshot(): string[] { return elements.map(node => node.shown ? boxes(node).border.join(' ') : 'none'); }
function changed(before: string[]): string { return elements.filter((node, i) => before[i] !== (node.shown ? boxes(node).border.join(' ') : 'none')).map(node => node.id).join(' ') || 'no change'; }
function render(): void {
    const screen = Array.from({ length: height }, () => Array<string>(width).fill('.'));
    function paint(x: number, y: number, c: string): void { if (x >= 0 && x < width && y >= 0 && y < height) screen[y][x] = c; }
    for (const node of elements) if (node.shown) {
        const bw = node.borderWidth(), bh = node.borderHeight();
        for (let y = Math.max(0, node.y); y < Math.min(height, node.y + bh); y++) for (let x = Math.max(0, node.x); x < Math.min(width, node.x + bw); x++) {
            const horizontal = node.side('border', 'top') === 1 && y === node.y || node.side('border', 'bottom') === 1 && y === node.y + bh - 1, vertical = node.side('border', 'left') === 1 && x === node.x || node.side('border', 'right') === 1 && x === node.x + bw - 1;
            screen[y][x] = horizontal ? vertical ? '+' : '-' : vertical ? '|' : ' ';
        }
        if (node.text !== null) { const content = boxes(node).content; node.lines.forEach((line, i) => { for (let j = 0; j < line.length; j++) paint(content[0] + j, content[1] + i, line[j]); }); }
    }
    output.push(`render ${width}x${height}`, '#'.repeat(width + 2), ...screen.map(row => '#' + row.join('') + '#'), '#'.repeat(width + 2));
}
function execute(line: string): void {
    const [command, ...args] = line.split(' '), id = args[0];
    if (command === 'LAYOUT') { output.push(`layout ${width}x${height}`); for (const node of elements) output.push(' '.repeat(node.depth * 2) + node.id + ' ' + (node.shown ? boxes(node).border.join(' ') : 'none')); }
    else if (command === 'BOX') {
        const node = byId.get(id); if (node === undefined) { output.push('error: unknown element ' + id); return; }
        if (!node.shown) output.push(`box ${id}: none`); else { output.push('box ' + id); const result = boxes(node); for (const name of ['margin', 'border', 'padding', 'content'] as const) output.push(name + ' ' + result[name].join(' ')); }
    } else if (command === 'RENDER') render();
    else if (command === 'HIT') {
        const x = Number(args[0]), y = Number(args[1]);
        if (x >= width || y >= height) { output.push(`error: point ${x} ${y} outside viewport`); return; }
        const node = elements.filter(node => node.shown && x >= node.x && y >= node.y && x < node.x + node.borderWidth() && y < node.y + node.borderHeight()).at(-1), path: string[] = [];
        for (let current: Element | null | undefined = node; current !== undefined && current !== null; current = current.parent) path.push(current.id);
        output.push(`hit ${x} ${y}: ${path.length ? path.reverse().join(' > ') : 'none'}`);
    } else if (command === 'SET') {
        const node = byId.get(id), property = args[1], value = args.slice(2).join(' ');
        if (node === undefined) { output.push('error: unknown element ' + id); return; }
        if (!known.has(property)) { output.push('error: unknown property ' + property); return; }
        const expanded = declarations(property, value);
        if (expanded === null) { output.push(`error: invalid value for ${property}: ${value}`); return; }
        const before = snapshot(); for (const [key, item] of expanded) node.overrides.set(key, item); relayout(); output.push(`set ${id} ${property} ${value}: ${changed(before)}`);
    } else if (command === 'VIEWPORT') {
        const w = Number(args[0]), h = Number(args[1]);
        if (w < 1 || w > 80 || h < 1 || h > 40) { output.push(`error: invalid viewport ${w} ${h}`); return; }
        const before = snapshot(); width = w; height = h; relayout(); output.push(`viewport ${w} ${h}: ${changed(before)}`);
    } else if (command === 'OVERFLOW') {
        const overflowing = elements.filter(node => {
            if (!node.shown) return false;
            if (node.text !== null) return Math.max(0, ...node.lines.map(line => line.length)) > node.cw || node.lines.length > node.ch;
            const content = boxes(node).content;
            return node.flow().some(child => { const margin = boxes(child).margin; return margin[0] < content[0] || margin[1] < content[1] || margin[0] + margin[2] > content[0] + content[2] || margin[1] + margin[3] > content[1] + content[3]; });
        });
        output.push('overflow: ' + (overflowing.map(node => node.id).join(' ') || 'none'));
    } else output.push('error: unknown command ' + command);
}
const input = fs.readFileSync(0, 'utf8').split(/\r?\n/);
[width, height] = input[0].split(' ').map(Number);
let at = 1;
while (input[at] !== '---') {
    const line = input[at++], split = line.indexOf(' { '), expanded: Declaration[] = [];
    for (const item of line.slice(split + 3, -2).split('; ')) { const colon = item.indexOf(': '); expanded.push(...(declarations(item.slice(0, colon), item.slice(colon + 2)) ?? [])); }
    rules.push({ selectors: line.slice(0, split).split(', '), declarations: expanded });
}
at++;
const stack: Element[] = [];
while (input[at] !== '===') {
    const line = input[at++], depth = (line.length - line.trimStart().length) / 2, text = line.slice(depth * 2), space = text.indexOf(' '), head = space < 0 ? text : text.slice(0, space), hash = head.indexOf('#'), parts = head.slice(hash + 1).split('.');
    const parent = depth === 0 ? null : stack[depth - 1], node = new Element(head.slice(0, hash), parts[0], parts.slice(1), space < 0 ? null : text.slice(space + 2, -1), depth, parent, elements.length);
    if (parent !== null) parent.children.push(node); elements.push(node); byId.set(node.id, node); stack.length = depth; stack.push(node);
}
at++; relayout();
while (input[at] !== 'END') execute(input[at++]);
if (output.length) process.stdout.write(output.join('\n') + '\n');
