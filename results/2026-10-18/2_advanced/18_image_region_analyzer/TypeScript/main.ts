import { readFileSync } from 'node:fs';
import { readImages, type Image } from './pgm_reader.ts';
import { histogram, otsu, isodata } from './threshold.ts';
import { label, bitQuadEuler, DIRECTIONS, complement, type Connectivity, type Offset } from './labeling.ts';
import { applyMorphology, neighborhood, transitions, thin } from './morphology.ts';
import { ratio, compare, decimal, floorRatio, hullArea, writeReports, type Rational } from './report.ts';

interface Setting { connectivity: Connectivity; threshold: string; polarity: string; operations: string[] }
interface Parameters { top: number; sweep: number; isotropy: Rational; bayMinimum: number; elements: Map<string, Offset[]>; images: Map<string, Setting> }
interface Condition { feature: string; operator: string; raw: string; value: Rational | string }
interface NamedRule { name: string; conditions: Condition[] }
interface Rules { filters: Condition[]; classes: NamedRule[]; flags: NamedRule[]; classNames: string[] }
interface Point { x: number; y: number }
interface Box { x0: number; y0: number; x1: number; y1: number }
interface Hole extends Box { number: number; owner: number; pixels: number[] }
interface Region extends Box {
    number: number; pixels: number[]; parent: number | null; depth: number;
    features: Record<string, Rational>; orientation: string; codes: number[]; hullDoubleArea: number;
    skeletonPixels: Set<number>; kept: boolean; droppedBy: number | null; className: string; flags: string[];
    neighbor: number | null; distance2: Rational | null;
}
interface Result {
    image: Image; setting: Setting; threshold: number; method: string; before: Uint8Array; mask: Uint8Array;
    thresholds: string[]; labels: Int32Array; provisional: number; holeLabels: Int32Array; holes: Hole[];
    regions: Region[]; kept: Region[]; four: number; eight: number; bitquad: number;
}
const ORIENTATIONS = ['none', 'horizontal', 'vertical', 'falling', 'rising'];
const SYMBOLS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const HEADER = 'image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes';
const lines = (path: string) => readFileSync(path, 'ascii').split('\n').filter(line => line.length > 0).map(line => line.split(' '));
function parseRatio(word: string): Rational { const [n, d = '1'] = word.split('/'); return ratio(Number(n), Number(d)); }
function readParameters(): Parameters {
    const rows = lines('input/params.txt');
    const options: Parameters = { top: Number(rows[0][1]), sweep: Number(rows[1][1]), isotropy: parseRatio(rows[2][1]), bayMinimum: Number(rows[3][1]), elements: new Map(), images: new Map() };
    for (const row of rows.slice(4)) {
        if (row[0] === 'element') {
            const w = Number(row[2]), h = Number(row[3]), ox = Number(row[4]), oy = Number(row[5]), offsets: Offset[] = [];
            for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (row[6 + y][x] === '#') offsets.push([x - ox, y - oy]);
            options.elements.set(row[1], offsets);
        } else options.images.set(row[1], { connectivity: row[2] === '4' ? 4 : 8, threshold: row[3], polarity: row[4], operations: row.slice(5) });
    }
    return options;
}
function readRules(): Rules {
    const rules: Rules = { filters: [], classes: [], flags: [], classNames: [] };
    for (const row of lines('input/rules.txt')) {
        const conditions: Condition[] = [];
        for (let i = row[0] === 'filter' ? 1 : 2; i < row.length; i += 3) conditions.push({ feature: row[i], operator: row[i + 1], raw: row[i + 2], value: row[i] === 'orientation' ? row[i + 2] : parseRatio(row[i + 2]) });
        if (row[0] === 'filter') rules.filters.push(conditions[0]);
        else {
            const rule = { name: row[1], conditions };
            (row[0] === 'class' ? rules.classes : rules.flags).push(rule);
            if (row[0] === 'class' && !rules.classNames.includes(rule.name)) rules.classNames.push(rule.name);
        }
    }
    rules.classNames.push('other');
    return rules;
}
function point(i: number, w: number): Point { return { x: i % w, y: floorRatio(i, w) }; }
function inside(image: Image, x: number, y: number): boolean { return x >= 0 && y >= 0 && x < image.width && y < image.height; }
function labelAt(labels: Int32Array, image: Image, x: number, y: number): number { return inside(image, x, y) ? labels[y * image.width + x] : 0; }
function bounds(pixels: number[], image: Image): Box {
    let x0 = image.width, y0 = image.height, x1 = -1, y1 = -1;
    for (const i of pixels) { const { x, y } = point(i, image.width); x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    return { x0, y0, x1, y1 };
}
function touchesEdge(box: Box, image: Image): boolean { return box.x0 === 0 || box.y0 === 0 || box.x1 === image.width - 1 || box.y1 === image.height - 1; }
function countMask(mask: Uint8Array): number { return mask.reduce((a, b) => a + b, 0); }
function binarize(image: Image, t: number, polarity: string): Uint8Array { return Uint8Array.from(image.pixels, value => Number(polarity === 'bright' ? value > t : value <= t)); }
function fillHoles(mask: Uint8Array, image: Image, c: Connectivity): Uint8Array {
    const result = new Uint8Array(mask);
    for (const pixels of label(Uint8Array.from(mask, p => 1 - p), image.width, image.height, complement(c)).components) {
        if (!touchesEdge(bounds(pixels, image), image)) for (const i of pixels) result[i] = 1;
    }
    return result;
}
function topology(mask: Uint8Array, labels: Int32Array, components: number[][], image: Image, c: Connectivity): { regions: Region[]; holes: Hole[]; holeLabels: Int32Array } {
    const holes: Hole[] = [], holeLabels = new Int32Array(mask.length);
    const regions = components.map((pixels, i): Region => ({ number: i + 1, pixels, ...bounds(pixels, image), parent: null, depth: 0, features: {}, orientation: 'none', codes: [], hullDoubleArea: 0, skeletonPixels: new Set(), kept: false, droppedBy: null, className: 'other', flags: [], neighbor: null, distance2: null }));
    for (const pixels of label(Uint8Array.from(mask, p => 1 - p), image.width, image.height, complement(c)).components) {
        const box = bounds(pixels, image);
        if (touchesEdge(box, image)) continue;
        const owner = labels[pixels[0] - image.width], number = holes.length + 1;
        holes.push({ number, owner, pixels, ...box });
        for (const i of pixels) holeLabels[i] = number;
    }
    for (const region of regions) {
        const first = region.pixels[0], hole = first >= image.width ? holeLabels[first - image.width] : 0;
        if (hole) { region.parent = holes[hole - 1].owner; region.depth = regions[region.parent - 1].depth + 1; }
    }
    return { regions, holes, holeLabels };
}
function containmentTree(regions: Region[]): string {
    function tree(region: Region): string {
        const children = regions.filter(child => child.parent === region.number);
        return `${region.number}${children.length ? `(${children.map(tree).join(' ')})` : ''}`;
    }
    return regions.filter(r => r.parent === null).map(tree).join(' ');
}
function chainCode(region: Region, labels: Int32Array, image: Image, c: Connectivity): number[] {
    const start = point(region.pixels[0], image.width), directions = DIRECTIONS[c], codes: number[] = [];
    let current = start, previous = start, first: Point | undefined, dir = c - 1;
    while (true) {
        const s = c === 4 ? (dir + 3) % 4 : (dir + (dir % 2 === 0 ? 7 : 6)) % 8;
        let next: Point | undefined;
        for (let offset = 0; offset < c; offset++) {
            const d = (s + offset) % c, [dx, dy] = directions[d];
            if (labelAt(labels, image, current.x + dx, current.y + dy) === region.number) { dir = d; next = { x: current.x + dx, y: current.y + dy }; break; }
        }
        if (!next) return [];
        previous = current; current = next;
        if (first && current.x === first.x && current.y === first.y && previous.x === start.x && previous.y === start.y) return codes;
        codes.push(dir);
        if (!first) first = current;
    }
}
function cross(a: Point, b: Point, p: Point): number { return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x); }
function convexHull(pixels: number[], image: Image): Point[] {
    const unique = new Map<string, Point>();
    for (const i of pixels) { const { x, y } = point(i, image.width); for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) unique.set(`${x + dx},${y + dy}`, { x: x + dx, y: y + dy }); }
    const points = [...unique.values()].sort((a, b) => a.x - b.x || a.y - b.y);
    function half(points: Point[]): Point[] {
        const hull: Point[] = [];
        for (const p of points) { while (hull.length >= 2 && cross(hull[hull.length - 2], hull[hull.length - 1], p) <= 0) hull.pop(); hull.push(p); }
        return hull.slice(0, -1);
    }
    return [...half(points), ...half([...points].reverse())];
}
function measureRegion(region: Region, result: Result, options: Parameters): void {
    const { image, labels, holeLabels, setting, holes } = result, f = region.features, a = region.pixels.length;
    const integer = (name: string, value: number) => { f[name] = ratio(value); };
    const width = region.x1 - region.x0 + 1, height = region.y1 - region.y0 + 1;
    integer('area', a); integer('width', width); integer('height', height); integer('border', Number(touchesEdge(region, image))); integer('depth', region.depth);
    let sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0, si = 0, sii = 0, minimum = image.maxval, maximum = 0, perimeter = 0, runs = 0, lr = 0, tb = 0;
    const background = new Set<number>();
    for (const i of region.pixels) {
        const { x, y } = point(i, image.width), value = image.pixels[i];
        sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y; si += value; sii += value * value;
        minimum = Math.min(minimum, value); maximum = Math.max(maximum, value);
        if (DIRECTIONS[complement(setting.connectivity)].some(([dx, dy]) => labelAt(labels, image, x + dx, y + dy) !== region.number)) perimeter++;
        if (labelAt(labels, image, x - 1, y) !== region.number) runs++;
        if (labelAt(labels, image, region.x0 + region.x1 - x, y) === region.number) lr++;
        if (labelAt(labels, image, x, region.y0 + region.y1 - y) === region.number) tb++;
        for (const [dx, dy] of DIRECTIONS[8]) if (inside(image, x + dx, y + dy) && !labels[(y + dy) * image.width + x + dx]) background.add((y + dy) * image.width + x + dx);
    }
    let backgroundSum = 0;
    for (const i of background) backgroundSum += image.pixels[i];
    f.cx = ratio(sx, a); f.cy = ratio(sy, a); f.mean = ratio(si, a); f.variance = ratio(a * sii - si * si, a * a);
    integer('min', minimum); integer('max', maximum); f.contrast = background.size ? ratio(si * background.size - backgroundSum * a, a * background.size) : ratio(0);
    integer('perimeter', perimeter); integer('runs', runs);
    region.codes = chainCode(region, labels, image, setting.connectivity);
    const chain = region.codes.length, straight = setting.connectivity === 4 ? chain : region.codes.filter(d => d % 2 === 0).length, diagonal = chain - straight;
    integer('chain', chain); integer('straight', straight); integer('diagonal', diagonal);
    integer('turns', region.codes.filter((d, i) => d !== region.codes[(i + chain - 1) % chain]).length);
    f.compactness = ratio((5 * straight + 7 * diagonal) ** 2, 25 * a);
    const owned = holes.filter(hole => hole.owner === region.number);
    integer('holes', owned.length); integer('hole_area', owned.reduce((sum, hole) => sum + hole.pixels.length, 0)); integer('euler', 1 - owned.length);
    const m20 = a * sxx - sx * sx, m02 = a * syy - sy * sy, m11 = a * sxy - sx * sy, u = m20 - m02, v = 2 * m11;
    f.var_x = ratio(m20, a * a); f.var_y = ratio(m02, a * a); f.cov_xy = ratio(m11, a * a); f.hu1 = ratio(m20 + m02, a ** 3);
    f.anisotropy = m20 + m02 ? ratio(Math.abs(u) + Math.abs(v), m20 + m02) : ratio(0);
    region.orientation = compare(f.anisotropy, options.isotropy) <= 0 ? 'none' : Math.abs(v) >= Math.abs(u) ? v > 0 ? 'falling' : 'rising' : u > 0 ? 'horizontal' : 'vertical';
    f.extent = ratio(a, width * height); f.mirror_lr = ratio(lr, a); f.mirror_tb = ratio(tb, a);
    const hull = convexHull(region.pixels, image);
    let doubledArea = 0, feret2 = 0;
    let width2: Rational | undefined;
    for (let i = 0; i < hull.length; i++) {
        const p = hull[i], q = hull[(i + 1) % hull.length];
        doubledArea += p.x * q.y - q.x * p.y;
        let z = 0;
        for (const r of hull) { z = Math.max(z, Math.abs(cross(p, q, r))); feret2 = Math.max(feret2, (p.x - r.x) ** 2 + (p.y - r.y) ** 2); }
        const candidate = ratio(z * z, (p.x - q.x) ** 2 + (p.y - q.y) ** 2);
        if (!width2 || compare(candidate, width2) < 0) width2 = candidate;
    }
    if (!width2) throw new Error('A region has no hull');
    region.hullDoubleArea = Math.abs(doubledArea); f.solidity = ratio(2 * a, region.hullDoubleArea); integer('feret2', feret2); f.width2 = width2; f.elongation = ratio(feret2 * width2.d, width2.n);
    const concavity = new Uint8Array(labels.length);
    for (let y = region.y0; y <= region.y1; y++) for (let x = region.x0; x <= region.x1; x++) {
        const i = y * image.width + x;
        if (labels[i] || holeLabels[i]) continue;
        const center = { x: 2 * x + 1, y: 2 * y + 1 };
        if (hull.every((p, k) => { const q = hull[(k + 1) % hull.length]; return cross({ x: 2 * p.x, y: 2 * p.y }, { x: 2 * q.x, y: 2 * q.y }, center) >= 0; })) concavity[i] = 1;
    }
    integer('bay_area', countMask(concavity)); integer('bays', label(concavity, image.width, image.height, complement(setting.connectivity)).components.filter(pixels => pixels.length >= options.bayMinimum).length);
    const mask = new Uint8Array(labels.length);
    for (const i of region.pixels) mask[i] = 1;
    const skeleton = thin(mask, image.width, image.height);
    let endpoints = 0, branches = 0;
    for (const i of region.pixels) if (skeleton[i]) {
        region.skeletonPixels.add(i);
        const { x, y } = point(i, image.width), crossing = transitions(neighborhood(skeleton, x, y, image.width, image.height));
        if (crossing === 1) endpoints++;
        if (crossing >= 3) branches++;
    }
    integer('skeleton', region.skeletonPixels.size); integer('endpoints', endpoints); integer('branches', branches);
}
function satisfies(region: Region, condition: Condition): boolean {
    const comparison = typeof condition.value === 'string' ? Number(region.orientation !== condition.value) : compare(region.features[condition.feature], condition.value);
    switch (condition.operator) { case '<': return comparison < 0; case '<=': return comparison <= 0; case '>': return comparison > 0; case '>=': return comparison >= 0; case '=': return comparison === 0; case '!=': return comparison !== 0; default: throw new Error('Unknown operator'); }
}
function applyRules(regions: Region[], rules: Rules): void {
    for (const r of regions) {
        const dropped = rules.filters.findIndex(condition => !satisfies(r, condition));
        r.kept = dropped < 0; r.droppedBy = dropped < 0 ? null : dropped;
        if (!r.kept) continue;
        r.className = rules.classes.find(rule => rule.conditions.every(condition => satisfies(r, condition)))?.name ?? 'other';
        r.flags = rules.flags.filter(rule => rule.conditions.every(condition => satisfies(r, condition))).map(rule => rule.name);
    }
    const kept = regions.filter(r => r.kept);
    for (const r of kept) {
        let best: number | undefined;
        for (const s of kept) if (s !== r) {
            const distance = (r.x0 + r.x1 - s.x0 - s.x1) ** 2 + (r.y0 + r.y1 - s.y0 - s.y1) ** 2;
            if (best === undefined || distance < best) { best = distance; r.neighbor = s.number; }
        }
        r.distance2 = best === undefined ? null : ratio(best, 4);
    }
}
function processImage(image: Image, options: Parameters, rules: Rules): Result {
    const setting = options.images.get(image.name);
    if (!setting) throw new Error('Missing image setting');
    const stats = histogram(image), o = otsu(stats), iso = isodata(stats);
    const method = ['otsu', 'isodata'].includes(setting.threshold) ? setting.threshold : 'fixed';
    const threshold = method === 'otsu' ? o.threshold : method === 'isodata' ? iso.threshold : Number(setting.threshold);
    const before = binarize(image, threshold, setting.polarity);
    const thresholds = [`image ${image.name} size ${image.width} ${image.height} maxval ${image.maxval}`, `histogram pixels ${stats.count} min ${stats.minimum} max ${stats.maximum} mean ${decimal(stats.sum, stats.count, 2)} median ${stats.median} mode ${stats.mode} levels ${stats.levels}`, `bins ${stats.binWidth} ${stats.bins.join(' ')}`, `otsu threshold ${o.threshold} upper ${o.upper} candidates ${o.candidates.length}`];
    o.candidates.slice(0, options.top).forEach((candidate, i) => {
        const { below, above, sumBelow, sumAbove } = candidate;
        thresholds.push(`rank ${i + 1} t ${candidate.threshold} below ${below} above ${above} mean_below ${decimal(sumBelow, below, 2)} mean_above ${decimal(sumAbove, above, 2)} gap ${decimal(sumAbove * below - sumBelow * above, below * above, 2)}`);
    });
    thresholds.push(`isodata threshold ${iso.threshold} iterations ${iso.iterations}`, `threshold ${threshold} ${method} ${setting.polarity} foreground ${countMask(before)}`);
    let mask = before;
    for (const operation of setting.operations) {
        if (operation === 'fill') mask = fillHoles(mask, image, setting.connectivity);
        else {
            const [kind, name] = operation.split(':'), element = options.elements.get(name);
            if (!element || !(kind === 'erode' || kind === 'dilate' || kind === 'open' || kind === 'close')) throw new Error('Invalid morphology');
            mask = applyMorphology(mask, image.width, image.height, element, kind);
        }
        thresholds.push(`morph ${operation} foreground ${countMask(mask)}`);
    }
    for (let t = options.sweep; t < image.maxval; t += options.sweep) { const binary = binarize(image, t, setting.polarity); thresholds.push(`sweep ${t} foreground ${countMask(binary)} regions ${label(binary, image.width, image.height, setting.connectivity).components.length}`); }
    const connected = label(mask, image.width, image.height, setting.connectivity), structure = topology(mask, connected.labels, connected.components, image, setting.connectivity);
    const result: Result = { image, setting, threshold, method, before, mask, thresholds, labels: connected.labels, provisional: connected.provisional, ...structure, kept: [], four: label(mask, image.width, image.height, 4).components.length, eight: label(mask, image.width, image.height, 8).components.length, bitquad: bitQuadEuler(mask, image.width, image.height, setting.connectivity) };
    for (const r of result.regions) measureRegion(r, result, options);
    applyRules(result.regions, rules); result.kept = result.regions.filter(r => r.kept);
    return result;
}
function mapLines(result: Result): string[] {
    const { image, before, mask, labels, holeLabels, regions } = result, maps: string[][] = [[], [], []];
    for (let y = 0; y < image.height; y++) {
        const rows = ['', '', ''];
        for (let x = 0; x < image.width; x++) {
            const i = y * image.width + x, number = labels[i];
            rows[0] += before[i] ? mask[i] ? '#' : '-' : mask[i] ? '+' : '.';
            if (!number) { const s = holeLabels[i] ? ':' : '.'; rows[1] += s; rows[2] += s; }
            else { const r = regions[number - 1], s = r.kept ? SYMBOLS[number % 62] : '#'; rows[1] += s; rows[2] += r.skeletonPixels.has(i) ? s : '+'; }
        }
        rows.forEach((row, i) => maps[i].push(row));
    }
    return maps.flatMap((rows, i) => [`${['morphology', 'labels', 'skeleton'][i]} ${image.name} ${image.width} ${image.height}`, ...rows]);
}
function regionLine(image: Image, r: Region): string {
    const n = (name: string) => r.features[name].n, d = (name: string, digits: number) => decimal(r.features[name].n, r.features[name].d, digits);
    return [image.name, r.number, r.className, r.flags.join('+') || '-', n('area'), r.x0, r.y0, r.x1, r.y1, d('cx', 3), d('cy', 3), d('mean', 2), d('variance', 2), n('min'), n('max'), d('contrast', 2), n('border'), n('perimeter'), n('chain'), n('straight'), n('diagonal'), n('turns'), d('compactness', 3), n('runs'), n('holes'), n('hole_area'), n('euler'), r.parent ?? '-', r.depth, d('var_x', 3), d('var_y', 3), d('cov_xy', 3), d('hu1', 4), r.orientation, d('anisotropy', 3), d('extent', 3), d('mirror_lr', 3), d('mirror_tb', 3), hullArea(r.hullDoubleArea), d('solidity', 3), n('feret2'), d('width2', 3), d('elongation', 3), n('bays'), n('bay_area'), n('skeleton'), n('endpoints'), n('branches'), r.neighbor ?? '-', r.distance2 ? decimal(r.distance2.n, r.distance2.d, 2) : '-', r.codes.join('') || '-'].join(',');
}
function orientations(regions: Region[]): string { return ['orientations', ...ORIENTATIONS.flatMap(name => [name, regions.filter(r => r.orientation === name).length])].join(' '); }
function imageSummary(result: Result, rules: Rules): string[] {
    const { image, setting, regions, holes, kept } = result, foreground = countMask(result.mask), background = image.pixels.length - foreground;
    const output = [`image ${image.name}`, `threshold ${result.threshold} ${result.method} ${setting.polarity} conn ${setting.connectivity}`, `foreground ${countMask(result.before)} ${foreground}`, `regions ${regions.length} provisional ${result.provisional} kept ${kept.length} dropped ${regions.length - kept.length}`, `connectivity four ${result.four} eight ${result.eight}`, `holes ${holes.length} hole_pixels ${holes.reduce((s, h) => s + h.pixels.length, 0)} euler ${regions.length - holes.length} bitquad ${result.bitquad}`];
    for (const h of holes) output.push(`hole ${h.number} owner ${h.owner} area ${h.pixels.length} box ${h.x0} ${h.y0} ${h.x1} ${h.y1}`);
    output.push(`depth_max ${Math.max(0, ...regions.map(r => r.depth))}`, ['tree', containmentTree(regions)].filter(Boolean).join(' '));
    let si = 0, sb = 0;
    image.pixels.forEach((p, i) => { if (result.mask[i]) si += p; else sb += p; });
    output.push(`intensity foreground ${foreground ? decimal(si, foreground, 2) : '-'} background ${background ? decimal(sb, background, 2) : '-'}`);
    const area = kept.reduce((s, r) => s + r.pixels.length, 0), largest = [...kept].sort((a, b) => b.pixels.length - a.pixels.length || a.number - b.number)[0], smallest = [...kept].sort((a, b) => a.pixels.length - b.pixels.length || a.number - b.number)[0];
    output.push(kept.length ? `area total ${area} mean ${decimal(area, kept.length, 2)} largest ${largest.number} ${largest.pixels.length} smallest ${smallest.number} ${smallest.pixels.length}` : 'area total 0 mean - largest - smallest -');
    output.push(['classes', ...rules.classNames.flatMap(name => [name, kept.filter(r => r.className === name).length])].join(' '), orientations(kept), ['flags', ...rules.flags.flatMap(rule => [rule.name, kept.filter(r => r.flags.includes(rule.name)).length])].join(' '));
    return output;
}
function overallSummary(results: Result[], rules: Rules): string[] {
    const regions = results.flatMap(r => r.regions), kept = regions.filter(r => r.kept), holes = results.reduce((sum, r) => sum + r.holes.length, 0);
    const output = ['overall', `images ${results.length}`, `regions ${regions.length} kept ${kept.length} dropped ${regions.length - kept.length}`, `holes ${holes} euler ${regions.length - holes}`];
    rules.filters.forEach((c, i) => output.push(`filter ${i + 1} ${c.feature} ${c.operator} ${c.raw} dropped ${regions.filter(r => r.droppedBy === i).length}`));
    for (const name of rules.classNames) {
        const members = kept.filter(r => r.className === name), area = members.reduce((s, r) => s + r.pixels.length, 0);
        output.push(`class ${name} count ${members.length} area ${area} mean ${members.length ? decimal(area, members.length, 2) : '-'}`);
    }
    for (const rule of rules.flags) output.push(`flag ${rule.name} count ${kept.filter(r => r.flags.includes(rule.name)).length}`);
    output.push(orientations(kept));
    let largest: { image: string; region: Region } | undefined;
    for (const result of results) for (const r of result.kept) if (!largest || r.pixels.length > largest.region.pixels.length) largest = { image: result.image.name, region: r };
    output.push(largest ? `largest ${largest.image} ${largest.region.number} ${largest.region.pixels.length}` : 'largest -');
    return output;
}
function main(): void {
    const options = readParameters(), rules = readRules(), results = readImages().map(image => processImage(image, options, rules));
    writeReports({ 'thresholds.txt': results.flatMap(r => r.thresholds), 'labels.txt': results.flatMap(mapLines), 'regions.csv': [HEADER, ...results.flatMap(result => result.kept.map(r => regionLine(result.image, r)))], 'summary.txt': [...results.flatMap(r => imageSummary(r, rules)), ...overallSummary(results, rules)] });
}
main();
