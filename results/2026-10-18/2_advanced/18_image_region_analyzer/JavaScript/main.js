'use strict';

const fs = require('node:fs');
const { readImages } = require('./pgm_reader');
const { histogram, otsu, isodata } = require('./threshold');
const { applyMorphology, neighborhood, transitions, thin } = require('./morphology');
const { DIRECTIONS, label, bitQuadEuler } = require('./labeling');
const { decimal, hullArea, writeReports } = require('./report');

const ORIENTATIONS = ['none', 'horizontal', 'vertical', 'falling', 'rising'];
const SYMBOLS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const REGION_HEADER = 'image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes';

function rational(n, d = 1) {
    return { n, d };
}

function parseRational(text) {
    const fields = text.split('/').map(Number);
    return rational(fields[0], fields.length === 1 ? 1 : fields[1]);
}

function compareRationals(first, second) {
    const left = first.n * second.d;
    const right = second.n * first.d;
    return left < right ? -1 : left > right ? 1 : 0;
}

function formatted(value, digits) {
    return decimal(value.n, value.d, digits);
}

function readLines(path) {
    const text = fs.readFileSync(path, 'ascii');
    return text.length === 0 ? [] : text.slice(0, -1).split('\n');
}

function readParameters() {
    const lines = readLines('input/params.txt').map(line => line.split(' '));
    const options = {
        top: Number(lines[0][1]),
        sweep: Number(lines[1][1]),
        isotropy: parseRational(lines[2][1]),
        bayMinimum: Number(lines[3][1]),
        elements: new Map(),
        images: new Map(),
    };
    for (const fields of lines.slice(4)) {
        if (fields[0] === 'element') {
            const width = Number(fields[2]);
            const height = Number(fields[3]);
            const ox = Number(fields[4]);
            const oy = Number(fields[5]);
            const offsets = [];
            for (let y = 0; y < height; y++) {
                for (let x = 0; x < width; x++) {
                    if (fields[6 + y][x] === '#') offsets.push([x - ox, y - oy]);
                }
            }
            options.elements.set(fields[1], offsets);
        } else {
            options.images.set(fields[1], {
                connectivity: Number(fields[2]), threshold: fields[3],
                polarity: fields[4], operations: fields.slice(5),
            });
        }
    }
    return options;
}

function readConditions(fields) {
    const conditions = [];
    for (let index = 0; index < fields.length; index += 3) {
        const [feature, operator, raw] = fields.slice(index, index + 3);
        const value = feature === 'orientation' ? raw : parseRational(raw);
        conditions.push({ feature, operator, raw, value });
    }
    return conditions;
}

function readRules() {
    const filters = [];
    const classes = [];
    const flags = [];
    const classNames = [];
    for (const line of readLines('input/rules.txt')) {
        const fields = line.split(' ');
        if (fields[0] === 'filter') {
            filters.push(readConditions(fields.slice(1))[0]);
        } else {
            const rule = { name: fields[1], conditions: readConditions(fields.slice(2)) };
            if (fields[0] === 'class') {
                classes.push(rule);
                if (!classNames.includes(rule.name)) classNames.push(rule.name);
            } else {
                flags.push(rule);
            }
        }
    }
    classNames.push('other');
    return { filters, classes, flags, classNames };
}

function pixelPoint(index, width) {
    const x = index % width;
    return { x, y: (index - x) / width };
}

function inside(image, x, y) {
    return x >= 0 && x < image.width && y >= 0 && y < image.height;
}

function labelAt(labels, image, x, y) {
    return inside(image, x, y) ? labels[y * image.width + x] : 0;
}

function onEdge(index, image) {
    const { x, y } = pixelPoint(index, image.width);
    return x === 0 || x === image.width - 1 || y === 0 || y === image.height - 1;
}

function bounds(pixels, image) {
    let x0 = image.width;
    let y0 = image.height;
    let x1 = -1;
    let y1 = -1;
    for (const index of pixels) {
        const { x, y } = pixelPoint(index, image.width);
        x0 = Math.min(x0, x);
        y0 = Math.min(y0, y);
        x1 = Math.max(x1, x);
        y1 = Math.max(y1, y);
    }
    return { x0, y0, x1, y1 };
}

function countMask(mask) {
    let count = 0;
    for (const value of mask) count += value;
    return count;
}

function binarize(image, threshold, polarity) {
    return Uint8Array.from(image.pixels, value => Number(polarity === 'bright' ? value > threshold : value <= threshold));
}

function fillHoles(mask, image, connectivity) {
    const background = Uint8Array.from(mask, value => 1 - value);
    const components = label(background, image.width, image.height, 12 - connectivity).components;
    const result = new Uint8Array(mask);
    for (const pixels of components) {
        if (pixels.some(index => onEdge(index, image))) continue;
        for (const index of pixels) result[index] = 1;
    }
    return result;
}

function topology(mask, connected, image, connectivity) {
    const regions = connected.components.map((pixels, index) => ({
        number: index + 1, pixels, holes: 0, hole_area: 0,
        parent: null, depth: 0, children: [],
    }));
    const background = Uint8Array.from(mask, value => 1 - value);
    const components = label(background, image.width, image.height, 12 - connectivity).components;
    const holes = [];
    const holeLabels = new Int32Array(mask.length);
    for (const pixels of components) {
        if (pixels.some(index => onEdge(index, image))) continue;
        const number = holes.length + 1;
        const owner = connected.labels[pixels[0] - image.width];
        const hole = { number, owner, pixels, ...bounds(pixels, image) };
        holes.push(hole);
        for (const index of pixels) holeLabels[index] = number;
        regions[owner - 1].holes++;
        regions[owner - 1].hole_area += pixels.length;
    }
    for (const region of regions) {
        const first = region.pixels[0];
        if (first < image.width) continue;
        const holeNumber = holeLabels[first - image.width];
        if (holeNumber !== 0) {
            region.parent = holes[holeNumber - 1].owner;
            const parent = regions[region.parent - 1];
            region.depth = parent.depth + 1;
            parent.children.push(region.number);
        }
    }
    return { regions, holes, holeLabels };
}

function containmentTree(regions) {
    function notation(region) {
        if (region.children.length === 0) return String(region.number);
        const children = region.children.map(number => notation(regions[number - 1])).join(' ');
        return `${region.number}(${children})`;
    }
    return regions.filter(region => region.parent === null).map(notation).join(' ');
}

function chainCode(region, labels, image, connectivity) {
    const directions = DIRECTIONS[connectivity];
    const count = directions.length;
    const origin = region.pixels[0];
    let current = origin;
    let firstStep = null;
    let previousDirection = count - 1;
    const codes = [];
    while (true) {
        const { x, y } = pixelPoint(current, image.width);
        const offset = connectivity === 4 ? 3 : previousDirection % 2 === 0 ? 7 : 6;
        const start = (previousDirection + offset) % count;
        let next = null;
        let direction = -1;
        for (let attempt = 0; attempt < count; attempt++) {
            const candidate = (start + attempt) % count;
            const [dx, dy] = directions[candidate];
            if (labelAt(labels, image, x + dx, y + dy) === region.number) {
                next = (y + dy) * image.width + x + dx;
                direction = candidate;
                break;
            }
        }
        if (next === null) return [];
        const previous = current;
        current = next;
        previousDirection = direction;
        codes.push(direction);
        if (codes.length === 1) firstStep = current;
        else if (current === firstStep && previous === origin) {
            codes.pop();
            return codes;
        }
    }
}

function cross(a, b, p) {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

function convexHull(pixels, image) {
    const cornerWidth = image.width + 1;
    const corners = new Set();
    for (const index of pixels) {
        const { x, y } = pixelPoint(index, image.width);
        corners.add(y * cornerWidth + x);
        corners.add(y * cornerWidth + x + 1);
        corners.add((y + 1) * cornerWidth + x);
        corners.add((y + 1) * cornerWidth + x + 1);
    }
    const points = [...corners].map(index => pixelPoint(index, cornerWidth));
    points.sort((a, b) => a.x - b.x || a.y - b.y);
    const lower = [];
    for (const point of points) {
        while (lower.length >= 2 && cross(lower.at(-2), lower.at(-1), point) <= 0) lower.pop();
        lower.push(point);
    }
    const upper = [];
    for (let index = points.length - 1; index >= 0; index--) {
        const point = points[index];
        while (upper.length >= 2 && cross(upper.at(-2), upper.at(-1), point) <= 0) upper.pop();
        upper.push(point);
    }
    return lower.slice(0, -1).concat(upper.slice(0, -1));
}

function hullMeasurements(hull) {
    let doubledArea = 0;
    let feret2 = 0;
    let width2 = null;
    for (let index = 0; index < hull.length; index++) {
        const a = hull[index];
        const b = hull[(index + 1) % hull.length];
        doubledArea += a.x * b.y - b.x * a.y;
        let distance = 0;
        for (const point of hull) distance = Math.max(distance, Math.abs(cross(a, b, point)));
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const candidate = rational(distance * distance, dx * dx + dy * dy);
        if (width2 === null || compareRationals(candidate, width2) < 0) width2 = candidate;
        for (let other = index + 1; other < hull.length; other++) {
            const x = hull[other].x - a.x;
            const y = hull[other].y - a.y;
            feret2 = Math.max(feret2, x * x + y * y);
        }
    }
    return { doubledArea: Math.abs(doubledArea), feret2, width2 };
}

function centerInHull(hull, x, y) {
    for (let index = 0; index < hull.length; index++) {
        const a = hull[index];
        const b = hull[(index + 1) % hull.length];
        const value = (b.x - a.x) * (2 * y + 1 - 2 * a.y)
            - (b.y - a.y) * (2 * x + 1 - 2 * a.x);
        if (value < 0) return false;
    }
    return true;
}

function measureHull(region, labels, holeLabels, image, connectivity, minimumBay) {
    const hull = convexHull(region.pixels, image);
    const measures = hullMeasurements(hull);
    region.hullDoubleArea = measures.doubledArea;
    region.solidity = rational(2 * region.area, measures.doubledArea);
    region.feret2 = measures.feret2;
    region.width2 = measures.width2;
    region.elongation = rational(measures.feret2 * measures.width2.d, measures.width2.n);
    const concavity = new Uint8Array(labels.length);
    let area = 0;
    for (let y = region.y0; y <= region.y1; y++) {
        for (let x = region.x0; x <= region.x1; x++) {
            const index = y * image.width + x;
            if (labels[index] !== 0 || holeLabels[index] !== 0 || !centerInHull(hull, x, y)) continue;
            concavity[index] = 1;
            area++;
        }
    }
    const bays = label(concavity, image.width, image.height, 12 - connectivity).components;
    region.bays = bays.filter(pixels => pixels.length >= minimumBay).length;
    region.bay_area = area;
}

function measureSkeleton(region, image) {
    const mask = new Uint8Array(image.pixels.length);
    for (const index of region.pixels) mask[index] = 1;
    const skeleton = thin(mask, image.width, image.height);
    const pixels = new Set();
    let endpoints = 0;
    let branches = 0;
    for (const index of region.pixels) {
        if (!skeleton[index]) continue;
        pixels.add(index);
        const { x, y } = pixelPoint(index, image.width);
        const crossing = transitions(neighborhood(skeleton, x, y, image.width, image.height));
        if (crossing === 1) endpoints++;
        if (crossing >= 3) branches++;
    }
    region.skeletonPixels = pixels;
    region.skeleton = pixels.size;
    region.endpoints = endpoints;
    region.branches = branches;
}

function measureRegion(region, result, options) {
    const { image, labels, holeLabels, setting } = result;
    Object.assign(region, bounds(region.pixels, image));
    const area = region.pixels.length;
    region.area = area;
    region.width = region.x1 - region.x0 + 1;
    region.height = region.y1 - region.y0 + 1;
    region.border = Number(region.x0 === 0 || region.y0 === 0 || region.x1 === image.width - 1 || region.y1 === image.height - 1);
    let sx = 0;
    let sy = 0;
    let sxx = 0;
    let syy = 0;
    let sxy = 0;
    let intensity = 0;
    let squares = 0;
    let minimum = image.maxval;
    let maximum = 0;
    let perimeter = 0;
    let runs = 0;
    let mirrorLR = 0;
    let mirrorTB = 0;
    const background = new Set();
    for (const index of region.pixels) {
        const { x, y } = pixelPoint(index, image.width);
        const value = image.pixels[index];
        sx += x;
        sy += y;
        sxx += x * x;
        syy += y * y;
        sxy += x * y;
        intensity += value;
        squares += value * value;
        minimum = Math.min(minimum, value);
        maximum = Math.max(maximum, value);
        if (DIRECTIONS[12 - setting.connectivity].some(([dx, dy]) => labelAt(labels, image, x + dx, y + dy) !== region.number)) perimeter++;
        if (labelAt(labels, image, x - 1, y) !== region.number) runs++;
        if (labelAt(labels, image, region.x0 + region.x1 - x, y) === region.number) mirrorLR++;
        if (labelAt(labels, image, x, region.y0 + region.y1 - y) === region.number) mirrorTB++;
        for (const [dx, dy] of DIRECTIONS[8]) {
            const nx = x + dx;
            const ny = y + dy;
            if (inside(image, nx, ny) && labels[ny * image.width + nx] === 0) background.add(ny * image.width + nx);
        }
    }
    let backgroundSum = 0;
    for (const index of background) backgroundSum += image.pixels[index];
    region.cx = rational(sx, area);
    region.cy = rational(sy, area);
    region.mean = rational(intensity, area);
    region.variance = rational(area * squares - intensity * intensity, area * area);
    region.min = minimum;
    region.max = maximum;
    region.contrast = background.size === 0 ? rational(0)
        : rational(intensity * background.size - backgroundSum * area, area * background.size);
    region.perimeter = perimeter;
    region.runs = runs;
    region.codes = chainCode(region, labels, image, setting.connectivity);
    region.chain = region.codes.length;
    region.straight = setting.connectivity === 4 ? region.chain : region.codes.filter(value => value % 2 === 0).length;
    region.diagonal = region.chain - region.straight;
    region.turns = 0;
    for (let index = 0; index < region.chain; index++) {
        if (region.codes[index] !== region.codes[(index + region.chain - 1) % region.chain]) region.turns++;
    }
    const length = 5 * region.straight + 7 * region.diagonal;
    region.compactness = rational(length * length, 25 * area);
    region.euler = 1 - region.holes;
    const m20 = area * sxx - sx * sx;
    const m02 = area * syy - sy * sy;
    const m11 = area * sxy - sx * sy;
    region.var_x = rational(m20, area * area);
    region.var_y = rational(m02, area * area);
    region.cov_xy = rational(m11, area * area);
    region.hu1 = rational(m20 + m02, area * area * area);
    const u = m20 - m02;
    const v = 2 * m11;
    region.anisotropy = m20 + m02 === 0 ? rational(0) : rational(Math.abs(u) + Math.abs(v), m20 + m02);
    if (compareRationals(region.anisotropy, options.isotropy) <= 0) region.orientation = 'none';
    else if (Math.abs(v) >= Math.abs(u)) region.orientation = v > 0 ? 'falling' : 'rising';
    else region.orientation = u > 0 ? 'horizontal' : 'vertical';
    region.extent = rational(area, region.width * region.height);
    region.mirror_lr = rational(mirrorLR, area);
    region.mirror_tb = rational(mirrorTB, area);
    measureHull(region, labels, holeLabels, image, setting.connectivity, options.bayMinimum);
    measureSkeleton(region, image);
}

function satisfies(region, condition) {
    let comparison;
    if (condition.feature === 'orientation') {
        comparison = region.orientation === condition.value ? 0 : 1;
    } else {
        const value = region[condition.feature];
        comparison = compareRationals(typeof value === 'number' ? rational(value) : value, condition.value);
    }
    switch (condition.operator) {
        case '<': return comparison < 0;
        case '<=': return comparison <= 0;
        case '>': return comparison > 0;
        case '>=': return comparison >= 0;
        case '=': return comparison === 0;
        case '!=': return comparison !== 0;
    }
}

function applyRules(regions, rules) {
    for (const region of regions) {
        region.kept = true;
        region.droppedBy = null;
        for (let index = 0; index < rules.filters.length; index++) {
            if (satisfies(region, rules.filters[index])) continue;
            region.kept = false;
            region.droppedBy = index;
            break;
        }
        if (!region.kept) continue;
        region.className = 'other';
        for (const rule of rules.classes) {
            if (!rule.conditions.every(condition => satisfies(region, condition))) continue;
            region.className = rule.name;
            break;
        }
        region.flags = rules.flags.filter(rule => rule.conditions.every(condition => satisfies(region, condition)))
            .map(rule => rule.name);
    }
}

function nearestNeighbors(regions) {
    const kept = regions.filter(region => region.kept);
    for (const region of kept) {
        let nearest = null;
        let best = null;
        for (const other of kept) {
            if (other === region) continue;
            const x = region.x0 + region.x1 - other.x0 - other.x1;
            const y = region.y0 + region.y1 - other.y0 - other.y1;
            const distance = x * x + y * y;
            if (best === null || distance < best) {
                best = distance;
                nearest = other.number;
            }
        }
        region.neighbor = nearest;
        region.distance2 = best === null ? null : rational(best, 4);
    }
}

function thresholdLines(image, stats, otsuResult, isoResult, options, threshold, method, setting, before) {
    const lines = [
        `image ${image.name} size ${image.width} ${image.height} maxval ${image.maxval}`,
        `histogram pixels ${stats.count} min ${stats.minimum} max ${stats.maximum} mean ${decimal(stats.sum, stats.count, 2)} median ${stats.median} mode ${stats.mode} levels ${stats.levels}`,
        `bins ${stats.binWidth} ${stats.bins.join(' ')}`,
        `otsu threshold ${otsuResult.threshold} upper ${otsuResult.upper} candidates ${otsuResult.candidates.length}`,
    ];
    otsuResult.candidates.slice(0, options.top).forEach((candidate, index) => {
        const { below, above, sumBelow, sumAbove } = candidate;
        const meanBelow = decimal(sumBelow, below, 2);
        const meanAbove = decimal(sumAbove, above, 2);
        const gap = decimal(sumAbove * below - sumBelow * above, below * above, 2);
        lines.push(`rank ${index + 1} t ${candidate.threshold} below ${below} above ${above} mean_below ${meanBelow} mean_above ${meanAbove} gap ${gap}`);
    });
    lines.push(`isodata threshold ${isoResult.threshold} iterations ${isoResult.iterations}`);
    lines.push(`threshold ${threshold} ${method} ${setting.polarity} foreground ${countMask(before)}`);
    return lines;
}

function processImage(image, options, rules) {
    const setting = options.images.get(image.name);
    const stats = histogram(image);
    const otsuResult = otsu(stats);
    const isoResult = isodata(stats);
    const method = setting.threshold === 'otsu' || setting.threshold === 'isodata' ? setting.threshold : 'fixed';
    const threshold = method === 'otsu' ? otsuResult.threshold : method === 'isodata' ? isoResult.threshold : Number(setting.threshold);
    const before = binarize(image, threshold, setting.polarity);
    let mask = before;
    const thresholds = thresholdLines(image, stats, otsuResult, isoResult, options, threshold, method, setting, before);
    for (const operation of setting.operations) {
        if (operation === 'fill') {
            mask = fillHoles(mask, image, setting.connectivity);
        } else {
            const [kind, element] = operation.split(':');
            mask = applyMorphology(mask, image.width, image.height, options.elements.get(element), kind);
        }
        thresholds.push(`morph ${operation} foreground ${countMask(mask)}`);
    }
    for (let sweep = options.sweep; sweep < image.maxval; sweep += options.sweep) {
        const binary = binarize(image, sweep, setting.polarity);
        const count = label(binary, image.width, image.height, setting.connectivity).components.length;
        thresholds.push(`sweep ${sweep} foreground ${countMask(binary)} regions ${count}`);
    }
    const connected = label(mask, image.width, image.height, setting.connectivity);
    const structure = topology(mask, connected, image, setting.connectivity);
    const result = {
        image, setting, threshold, method, before, mask, thresholds,
        labels: connected.labels, provisional: connected.provisional, ...structure,
    };
    result.four = setting.connectivity === 4 ? result.regions.length : label(mask, image.width, image.height, 4).components.length;
    result.eight = setting.connectivity === 8 ? result.regions.length : label(mask, image.width, image.height, 8).components.length;
    result.bitquad = bitQuadEuler(mask, image.width, image.height, setting.connectivity);
    for (const region of result.regions) measureRegion(region, result, options);
    applyRules(result.regions, rules);
    nearestNeighbors(result.regions);
    result.kept = result.regions.filter(region => region.kept);
    return result;
}

function mapLines(result) {
    const { image, before, mask, labels, holeLabels, regions } = result;
    const maps = [[], [], []];
    for (let y = 0; y < image.height; y++) {
        const rows = ['', '', ''];
        for (let x = 0; x < image.width; x++) {
            const index = y * image.width + x;
            rows[0] += before[index] ? mask[index] ? '#' : '-' : mask[index] ? '+' : '.';
            const number = labels[index];
            if (number === 0) {
                const symbol = holeLabels[index] === 0 ? '.' : ':';
                rows[1] += symbol;
                rows[2] += symbol;
            } else {
                const region = regions[number - 1];
                const symbol = region.kept ? SYMBOLS[number % SYMBOLS.length] : '#';
                rows[1] += symbol;
                rows[2] += region.skeletonPixels.has(index) ? symbol : '+';
            }
        }
        for (let index = 0; index < maps.length; index++) maps[index].push(rows[index]);
    }
    const names = ['morphology', 'labels', 'skeleton'];
    return maps.flatMap((rows, index) => [`${names[index]} ${image.name} ${image.width} ${image.height}`, ...rows]);
}

function regionLine(image, region) {
    return [
        image.name, region.number, region.className, region.flags.join('+') || '-',
        region.area, region.x0, region.y0, region.x1, region.y1,
        formatted(region.cx, 3), formatted(region.cy, 3), formatted(region.mean, 2), formatted(region.variance, 2),
        region.min, region.max, formatted(region.contrast, 2), region.border, region.perimeter,
        region.chain, region.straight, region.diagonal, region.turns, formatted(region.compactness, 3), region.runs,
        region.holes, region.hole_area, region.euler, region.parent === null ? '-' : region.parent, region.depth,
        formatted(region.var_x, 3), formatted(region.var_y, 3), formatted(region.cov_xy, 3), formatted(region.hu1, 4),
        region.orientation, formatted(region.anisotropy, 3), formatted(region.extent, 3),
        formatted(region.mirror_lr, 3), formatted(region.mirror_tb, 3), hullArea(region.hullDoubleArea),
        formatted(region.solidity, 3), region.feret2, formatted(region.width2, 3), formatted(region.elongation, 3),
        region.bays, region.bay_area, region.skeleton, region.endpoints, region.branches,
        region.neighbor === null ? '-' : region.neighbor,
        region.distance2 === null ? '-' : formatted(region.distance2, 2), region.codes.join('') || '-',
    ].join(',');
}

function categoryCounts(regions, rules) {
    const classes = new Map(rules.classNames.map(name => [name, { count: 0, area: 0 }]));
    const flags = new Map(rules.flags.map(rule => [rule.name, 0]));
    const orientations = new Map(ORIENTATIONS.map(name => [name, 0]));
    for (const region of regions) {
        const entry = classes.get(region.className);
        entry.count++;
        entry.area += region.area;
        for (const name of region.flags) flags.set(name, flags.get(name) + 1);
        orientations.set(region.orientation, orientations.get(region.orientation) + 1);
    }
    return { classes, flags, orientations };
}

function orientationLine(counts) {
    return ['orientations', ...ORIENTATIONS.flatMap(name => [name, counts.get(name)])].join(' ');
}

function imageSummary(result, rules) {
    const { image, setting, regions, holes, kept } = result;
    const beforeCount = countMask(result.before);
    const afterCount = countMask(result.mask);
    let holePixels = 0;
    for (const hole of holes) holePixels += hole.pixels.length;
    const lines = [
        `image ${image.name}`,
        `threshold ${result.threshold} ${result.method} ${setting.polarity} conn ${setting.connectivity}`,
        `foreground ${beforeCount} ${afterCount}`,
        `regions ${regions.length} provisional ${result.provisional} kept ${kept.length} dropped ${regions.length - kept.length}`,
        `connectivity four ${result.four} eight ${result.eight}`,
        `holes ${holes.length} hole_pixels ${holePixels} euler ${regions.length - holes.length} bitquad ${result.bitquad}`,
    ];
    for (const hole of holes) {
        lines.push(`hole ${hole.number} owner ${hole.owner} area ${hole.pixels.length} box ${hole.x0} ${hole.y0} ${hole.x1} ${hole.y1}`);
    }
    let depth = 0;
    for (const region of regions) depth = Math.max(depth, region.depth);
    lines.push(`depth_max ${depth}`);
    const tree = containmentTree(regions);
    lines.push(tree === '' ? 'tree' : `tree ${tree}`);
    let foregroundSum = 0;
    let backgroundSum = 0;
    for (let index = 0; index < image.pixels.length; index++) {
        if (result.mask[index]) foregroundSum += image.pixels[index];
        else backgroundSum += image.pixels[index];
    }
    const backgroundCount = image.pixels.length - afterCount;
    const foreground = afterCount === 0 ? '-' : decimal(foregroundSum, afterCount, 2);
    const background = backgroundCount === 0 ? '-' : decimal(backgroundSum, backgroundCount, 2);
    lines.push(`intensity foreground ${foreground} background ${background}`);
    if (kept.length === 0) {
        lines.push('area total 0 mean - largest - smallest -');
    } else {
        let area = 0;
        let largest = kept[0];
        let smallest = kept[0];
        for (const region of kept) {
            area += region.area;
            if (region.area > largest.area) largest = region;
            if (region.area < smallest.area) smallest = region;
        }
        lines.push(`area total ${area} mean ${decimal(area, kept.length, 2)} largest ${largest.number} ${largest.area} smallest ${smallest.number} ${smallest.area}`);
    }
    const counts = categoryCounts(kept, rules);
    lines.push(['classes', ...rules.classNames.flatMap(name => [name, counts.classes.get(name).count])].join(' '));
    lines.push(orientationLine(counts.orientations));
    lines.push(['flags', ...rules.flags.flatMap(rule => [rule.name, counts.flags.get(rule.name)])].join(' '));
    return lines;
}

function overallSummary(results, rules) {
    const regions = results.flatMap(result => result.regions);
    const kept = regions.filter(region => region.kept);
    let holes = 0;
    for (const result of results) holes += result.holes.length;
    const lines = [
        'overall', `images ${results.length}`,
        `regions ${regions.length} kept ${kept.length} dropped ${regions.length - kept.length}`,
        `holes ${holes} euler ${regions.length - holes}`,
    ];
    const dropped = Array(rules.filters.length).fill(0);
    for (const region of regions) if (region.droppedBy !== null) dropped[region.droppedBy]++;
    rules.filters.forEach((condition, index) => {
        lines.push(`filter ${index + 1} ${condition.feature} ${condition.operator} ${condition.raw} dropped ${dropped[index]}`);
    });
    const counts = categoryCounts(kept, rules);
    for (const name of rules.classNames) {
        const entry = counts.classes.get(name);
        const mean = entry.count === 0 ? '-' : decimal(entry.area, entry.count, 2);
        lines.push(`class ${name} count ${entry.count} area ${entry.area} mean ${mean}`);
    }
    for (const rule of rules.flags) lines.push(`flag ${rule.name} count ${counts.flags.get(rule.name)}`);
    lines.push(orientationLine(counts.orientations));
    let largest = null;
    for (const result of results) {
        for (const region of result.kept) {
            if (largest === null || region.area > largest.area) {
                largest = { image: result.image.name, number: region.number, area: region.area };
            }
        }
    }
    lines.push(largest === null ? 'largest -' : `largest ${largest.image} ${largest.number} ${largest.area}`);
    return lines;
}

function main() {
    const images = readImages();
    const options = readParameters();
    const rules = readRules();
    const results = images.map(image => processImage(image, options, rules));
    const regions = [REGION_HEADER];
    for (const result of results) {
        for (const region of result.kept) regions.push(regionLine(result.image, region));
    }
    const summaries = results.flatMap(result => imageSummary(result, rules));
    summaries.push(...overallSummary(results, rules));
    writeReports({
        'thresholds.txt': results.flatMap(result => result.thresholds),
        'labels.txt': results.flatMap(mapLines),
        'regions.csv': regions,
        'summary.txt': summaries,
    });
}

main();
