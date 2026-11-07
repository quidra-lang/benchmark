'use strict';

const { readDataset } = require('./dataset');
const { squaredDistance, buildGrid } = require('./grid_index');
const { dbscan } = require('./dbscan');
const { optics } = require('./optics');
const { fraction, root, integer, ariValue, frame, writeLines } = require('./report');
const character = label => label < 0 ? '.' : label < 26 ? String.fromCharCode(65 + label)
    : label < 52 ? String.fromCharCode(97 + label - 26) : '#';

function distanceMatrix(points) {
    const distances = points.map(() => new Int32Array(points.length));
    for (let p = 0; p < points.length; p++) {
        for (let q = p + 1; q < points.length; q++) distances[p][q] = distances[q][p] = squaredDistance(points[p], points[q]);
    }
    return distances;
}

function ceilingRoot(value) {
    let low = 1;
    let high = 1;
    while (high * high < value) high *= 2;
    while (low < high) {
        const middle = Math.floor((low + high) / 2);
        if (middle * middle >= value) high = middle;
        else low = middle + 1;
    }
    return low;
}

function kneeCurves(distances, minimum) {
    const neighbors = distances.map((row, p) => Array.from(row).filter((_, q) => p !== q).sort((a, b) => a - b).slice(0, 2 * minimum));
    const curves = [];
    for (let j = 1; j <= 2 * minimum; j++) {
        const values = neighbors.map(row => row[j - 1]);
        const order = values.map((_, p) => p).sort((a, b) => values[b] - values[a] || a - b);
        const first = values[order[0]];
        const last = values[order.at(-1)];
        let knee = 0;
        let cross = -1;
        for (let position = 0; position < order.length; position++) {
            const value = Math.abs((order.length - 1) * (values[order[position]] - first) - (last - first) * position);
            if (value > cross) { knee = position; cross = value; }
        }
        curves.push({ j, values, order, knee, cross, radius: ceilingRoot(values[order[knee]]) });
    }
    return { curves, kdist: curves[minimum - 2] };
}

function extract(ordering, radius) {
    const labels = Array(ordering.ordering.length).fill(-1);
    const limit = radius * radius;
    let cluster = -1;
    for (const p of ordering.ordering) {
        if (ordering.reach[p] > limit) {
            if (ordering.core[p] <= limit) labels[p] = ++cluster;
        } else labels[p] = cluster;
    }
    return { labels, core: ordering.core.map(value => value <= limit) };
}

function xiExtraction(ordering, parameters) {
    const count = ordering.ordering.length;
    const reach = [Infinity, ...ordering.ordering.map(p => ordering.reach[p]), Infinity];
    const [u, v] = parameters.xi;
    const alpha = (v - u) * (v - u);
    const beta = v * v;
    const xle = (a, b) => b === Infinity || (a !== Infinity && beta * a <= alpha * b);
    const positions = Array(count + 1);
    for (let i = 1; i <= count; i++) {
        const a = reach[i];
        const b = reach[i + 1];
        const defined = a !== Infinity || b !== Infinity;
        const steepUp = defined && xle(a, b);
        const steepDown = defined && xle(b, a);
        positions[i] = { steepUp, steepDown, up: steepUp || a < b, down: steepDown || a > b };
    }
    function regionEnd(start, down) {
        let end = start;
        let flat = 0;
        for (let i = start; i <= count; i++) {
            const position = positions[i];
            if (down ? position.steepDown : position.steepUp) { end = i; flat = 0; }
            else if (down ? position.up : position.down) break;
            else if (++flat > parameters.minimum) break;
        }
        return end;
    }
    let downAreas = [];
    const steepAreas = [];
    const clusters = [];
    let index = 1;
    let between = 0;
    for (let s = 1; s <= count; s++) {
        if (s < index || (!positions[s].steepUp && !positions[s].steepDown)) continue;
        for (let i = index; i <= s; i++) between = Math.max(between, reach[i]);
        if (between === Infinity) downAreas = [];
        else {
            downAreas = downAreas.filter(area => xle(between, reach[area.start]));
            for (const area of downAreas) area.maximum = Math.max(area.maximum, between);
        }
        if (positions[s].steepDown) {
            const end = regionEnd(s, true);
            downAreas.push({ start: s, end, maximum: 0 });
            steepAreas.push({ direction: 'down', start: s, end });
            index = end + 1;
            between = reach[index];
        } else {
            const end = regionEnd(s, false);
            steepAreas.push({ direction: 'up', start: s, end });
            index = end + 1;
            between = reach[index];
            const candidates = [];
            for (const area of downAreas) {
                let start = area.start;
                let finish = end;
                if (!xle(area.maximum, reach[finish + 1])) continue;
                const down = reach[area.start];
                if (xle(reach[finish + 1], down)) {
                    while (reach[start + 1] > reach[finish + 1] && start < area.end) start++;
                } else if (xle(down, reach[finish + 1])) {
                    while (reach[finish - 1] > down && finish > s) finish--;
                }
                if (finish - start + 1 >= parameters.minimumSize && start <= area.end && finish >= s)
                    candidates.push({ start, end: finish, size: finish - start + 1, label: null, parent: null });
            }
            clusters.push(...candidates.reverse());
        }
    }
    const labels = Array(count).fill(-1);
    let nextLabel = 0;
    for (const cluster of clusters) {
        let free = true;
        for (let i = cluster.start; i <= cluster.end; i++) if (labels[ordering.ordering[i - 1]] !== -1) free = false;
        if (free) {
            cluster.label = nextLabel++;
            for (let i = cluster.start; i <= cluster.end; i++) labels[ordering.ordering[i - 1]] = cluster.label;
        }
    }
    for (let j = 0; j < clusters.length; j++) {
        const cluster = clusters[j];
        for (let i = 0; i < clusters.length; i++) {
            const candidate = clusters[i];
            if (i === j || candidate.start > cluster.start || candidate.end < cluster.end
                || !(candidate.size > cluster.size || (candidate.size === cluster.size && i > j))) continue;
            if (cluster.parent === null || candidate.size < clusters[cluster.parent].size) cluster.parent = i;
        }
        cluster.left = reach[cluster.start];
        cluster.right = reach[cluster.end + 1];
        cluster.valley = Infinity;
        for (let i = cluster.start + 1; i <= cluster.end; i++) cluster.valley = Math.min(cluster.valley, reach[i]);
    }
    return { labels, core: ordering.core.map(value => value !== Infinity), clusters, steepAreas };
}

function convexHull(members, points) {
    const sorted = members.slice().sort((a, b) => points[a].x - points[b].x || points[a].y - points[b].y);
    if (sorted.length <= 2) return sorted;
    const turn = (o, a, b) => (points[a].x - points[o].x) * (points[b].y - points[o].y)
        - (points[a].y - points[o].y) * (points[b].x - points[o].x);
    const chain = sequence => {
        const result = [];
        for (const p of sequence) {
            while (result.length >= 2 && turn(result.at(-2), result.at(-1), p) <= 0) result.pop();
            result.push(p);
        }
        return result.slice(0, -1);
    };
    return [...chain(sorted), ...chain(sorted.slice().reverse())];
}

function summarize(setting, points, distances) {
    const clusters = Array.from({ length: Math.max(...setting.labels) + 1 }, () => []);
    for (let p = 0; p < points.length; p++) if (setting.labels[p] >= 0) clusters[setting.labels[p]].push(p);
    setting.clusters = clusters.map(members => {
        let x = 0;
        let y = 0;
        let core = 0;
        let xmin = points[members[0]].x;
        let xmax = xmin;
        let ymin = points[members[0]].y;
        let ymax = ymin;
        for (const p of members) {
            x += points[p].x;
            y += points[p].y;
            core += Number(setting.core[p]);
            xmin = Math.min(xmin, points[p].x);
            xmax = Math.max(xmax, points[p].x);
            ymin = Math.min(ymin, points[p].y);
            ymax = Math.max(ymax, points[p].y);
        }
        let medoid = null;
        let nearest = Infinity;
        for (const p of members) {
            const dx = members.length * points[p].x - x;
            const dy = members.length * points[p].y - y;
            const value = dx * dx + dy * dy;
            if (value < nearest) { nearest = value; medoid = p; }
        }
        const hull = convexHull(members, points);
        let twiceArea = 0;
        let diameter = 0;
        for (let i = 0; i < hull.length; i++) {
            const a = points[hull[i]];
            const b = points[hull[(i + 1) % hull.length]];
            twiceArea += a.x * b.y - b.x * a.y;
            for (let j = i + 1; j < hull.length; j++) diameter = Math.max(diameter, distances[hull[i]][hull[j]]);
        }
        return { members, size: members.length, core, border: members.length - core, x, y, medoid, xmin, ymin, xmax, ymax,
            area: (xmax - xmin + 1) * (ymax - ymin + 1), hull, twiceArea: Math.abs(twiceArea), diameter };
    });
    setting.noise = setting.labels.filter(label => label === -1).length;
    setting.coreCount = setting.clusters.reduce((total, cluster) => total + cluster.core, 0);
    setting.borderCount = points.length - setting.noise - setting.coreCount;
    return setting;
}

function checkDbscan(setting, neighborhoods) {
    const checks = [true, true, true];
    let isolated = 0;
    const ambiguous = [];
    for (let p = 0; p < setting.labels.length; p++) {
        const label = setting.labels[p];
        const coreNeighbors = neighborhoods[p].filter(q => setting.core[q]);
        if (setting.core[p]) {
            if (coreNeighbors.some(q => setting.labels[q] !== label)) checks[0] = false;
        } else if (label >= 0) {
            if (!coreNeighbors.some(q => setting.labels[q] === label)) checks[1] = false;
            const others = [...new Set(coreNeighbors.map(q => setting.labels[q]).filter(value => value !== label))].sort((a, b) => a - b);
            if (others.length) ambiguous.push({ point: p, others });
        } else {
            if (coreNeighbors.length) checks[2] = false;
            if (neighborhoods[p].length === 1) isolated++;
        }
    }
    return { checks, isolated, ambiguous };
}

function containmentLines(settings) {
    const ordered = settings.map((setting, index) => ({ setting, index })).sort((a, b) => a.setting.radius - b.setting.radius || a.index - b.index);
    const lines = ['hierarchy'];
    for (let i = 1; i < ordered.length; i++) {
        const first = ordered[i - 1].setting;
        const second = ordered[i].setting;
        const sources = second.clusters.map(() => []);
        for (let c = 0; c < first.clusters.length; c++) {
            const point = first.clusters[c].members.find(p => first.core[p]);
            sources[second.labels[point]].push(c);
        }
        lines.push(`${first.name} -> ${second.name}`);
        for (let c = 0; c < sources.length; c++) lines.push(`  ${c} <- ` + (sources[c].length ? sources[c].join(' ') : '-'));
    }
    return lines;
}

function comparisonLines(extractions, dbscanSettings) {
    const lines = ['optics_vs_dbscan'];
    for (const first of extractions) {
        const second = dbscanSettings.find(setting => setting.radius === first.radius);
        if (!second) continue;
        const forward = new Map();
        const backward = new Map();
        for (let p = 0; p < first.labels.length; p++) {
            if (!first.core[p]) continue;
            const a = first.labels[p];
            const b = second.labels[p];
            if (!forward.has(a)) forward.set(a, new Set());
            if (!backward.has(b)) backward.set(b, new Set());
            forward.get(a).add(b);
            backward.get(b).add(a);
        }
        const same = forward.size === first.clusters.length && backward.size === second.clusters.length
            && [...forward.values(), ...backward.values()].every(values => values.size === 1);
        let borderNoise = 0;
        let moved = 0;
        for (let p = 0; p < first.labels.length; p++) {
            if (first.labels[p] === -1 && second.labels[p] >= 0) borderNoise++;
            if (same && first.labels[p] >= 0 && !forward.get(first.labels[p]).has(second.labels[p])) moved++;
        }
        lines.push(`${first.name} ${second.name} core_partition ${same ? 'same' : 'different'} border_as_noise ${borderNoise} moved ${same ? moved : '-'}`);
    }
    return lines;
}

function opticsSummary(ordering, maximum) {
    const sizes = [];
    for (const p of ordering.ordering) {
        if (ordering.reach[p] === Infinity) sizes.push(0);
        sizes[sizes.length - 1]++;
    }
    const core = ordering.core.filter(value => value !== Infinity).length;
    return [`optics max_eps ${maximum} core ${core} components ${sizes.length} singletons ${sizes.filter(size => size === 1).length} largest ${Math.max(...sizes)}`];
}

function sweepLines(ordering, maximum) {
    const results = [];
    const lines = [`sweep max_eps ${maximum}`, 'eps clusters noise largest'];
    for (let radius = 1; radius <= maximum; radius++) {
        const { labels } = extract(ordering, radius);
        const sizes = Array(Math.max(...labels) + 1).fill(0);
        let noise = 0;
        for (const label of labels) { if (label === -1) noise++; else sizes[label]++; }
        results.push(sizes.length);
        lines.push(`${radius} ${sizes.length} ${noise} ${Math.max(0, ...sizes)}`);
    }
    let stable = null;
    for (let start = 0; start < results.length;) {
        let end = start;
        while (end + 1 < results.length && results[end + 1] === results[start]) end++;
        const length = end - start + 1;
        if (results[start] >= 2 && (stable === null || length > stable.length)) stable = { start, end, length, clusters: results[start] };
        start = end + 1;
    }
    lines.push(stable === null ? 'stable -'
        : `stable clusters ${stable.clusters} eps ${stable.start + 1} ${stable.end + 1} length ${stable.length}`);
    return lines;
}

function outlierLines(knee, points, distances) {
    const core = knee.core.map((value, p) => value ? p : -1).filter(p => p >= 0);
    const outliers = [];
    for (let p = 0; p < points.length; p++) {
        if (knee.labels[p] !== -1) continue;
        let nearest = core[0];
        for (const q of core) if (distances[p][q] < distances[p][nearest]) nearest = q;
        outliers.push({ point: p, nearest, distance: distances[p][nearest] });
    }
    outliers.sort((a, b) => b.distance - a.distance || a.point - b.point);
    return [`outliers ${knee.name} count ${outliers.length}`, ...outliers.map(item =>
        `${points[item.point].id} nearest_core ${points[item.nearest].id} cluster ${knee.labels[item.nearest]} dist_sq ${item.distance} dist ${root(item.distance)}`)];
}

function gapLines(knee, points, distances) {
    const lines = ['gaps ' + knee.name];
    for (let a = 0; a < knee.clusters.length; a++) {
        for (let b = a + 1; b < knee.clusters.length; b++) {
            let value = Infinity;
            let first;
            let second;
            for (const p of knee.clusters[a].members) {
                for (const q of knee.clusters[b].members) {
                    if (distances[p][q] < value) { value = distances[p][q]; first = p; second = q; }
                }
            }
            lines.push(`${a} ${b} dist_sq ${value} dist ${root(value)} between ${points[first].id} ${points[second].id}`);
        }
    }
    return lines;
}

function contingencyLines(knee, xi) {
    const table = Array.from({ length: knee.clusters.length + 1 }, () => Array(xi.clusters.length + 1).fill(0));
    for (let p = 0; p < knee.labels.length; p++) table[knee.labels[p] + 1][xi.labels[p] + 1]++;
    const lines = [`contingency ${knee.name} xi`, 'columns ' + table[0].map((_, i) => i - 1).join(' ')];
    for (let r = 0; r < table.length; r++) lines.push(`${r - 1} ${table[r].join(' ')}`);
    for (let c = 0; c < xi.clusters.length; c++) {
        let matching = 0;
        for (let r = 1; r < knee.clusters.length; r++) if (table[r + 1][c + 1] > table[matching + 1][c + 1]) matching = r;
        const shared = table[matching + 1][c + 1];
        const union = knee.clusters[matching].size + xi.clusters[c].size - shared;
        lines.push(`match ${c} ${matching} shared ${shared} jaccard ${fraction(shared, union)}`);
    }
    return lines;
}

function adjustedRand(first, second) {
    const pairs = new Map();
    const rows = new Map();
    const columns = new Map();
    const increment = (map, key) => map.set(key, (map.get(key) ?? 0) + 1);
    for (let p = 0; p < first.length; p++) {
        increment(pairs, first[p] + ',' + second[p]);
        increment(rows, first[p]);
        increment(columns, second[p]);
    }
    const combinations = count => count * (count - 1) / 2;
    const total = map => [...map.values()].reduce((value, count) => value + combinations(count), 0);
    const s = total(pairs);
    const a = total(rows);
    const b = total(columns);
    const z = combinations(first.length);
    const numerator = 2 * (z * s - a * b);
    const denominator = z * (a + b) - 2 * a * b;
    return denominator === 0 ? [1, 1] : [numerator, denominator];
}

function settingLines(setting, points) {
    const lines = [`setting ${setting.name} eps ${setting.radius} clusters ${setting.clusters.length} noise ${setting.noise}`
        + ` core ${setting.coreCount} border ${setting.borderCount}`];
    for (let label = 0; label < setting.clusters.length; label++) {
        const c = setting.clusters[label];
        lines.push(`cluster ${label} ${character(label)} size ${c.size} core ${c.core} border ${c.border}`
            + ` centroid ${fraction(c.x, c.size)} ${fraction(c.y, c.size)} medoid ${points[c.medoid].id}`,
        `  bbox ${c.xmin} ${c.ymin} ${c.xmax} ${c.ymax} area ${c.area} density ${fraction(c.size, c.area)}`,
        `  hull ${c.hull.length} hull_area ${Math.floor(c.twiceArea / 2)}.${c.twiceArea % 2 ? '5' : '0'}`
            + ` diameter_sq ${c.diameter} diameter ${root(c.diameter)}`);
    }
    if (setting.check) {
        const checked = setting.check;
        lines.push('check ' + checked.checks.map(value => value ? 'ok' : 'fail').join(' '),
            'isolated ' + checked.isolated, 'ambiguous ' + checked.ambiguous.length);
        for (const item of checked.ambiguous) lines.push(`  ${points[item.point].id} cluster ${setting.labels[item.point]} also ${item.others.join(' ')}`);
    }
    return lines;
}

function clusterReport(points, parameters, grids, settings, dbscanSettings, extractions, ordering, xi, knee, distances) {
    const gridLines = ['grid'];
    for (const grid of grids.values()) {
        const cell = grid.busiest;
        gridLines.push(`eps ${grid.radius} cells ${grid.cells} busiest ${cell.gx} ${cell.gy} ${cell.points.length}`
            + ` candidates ${grid.candidates} pairs ${grid.pairs} brute_pairs ${grid.brutePairs} ${grid.matches ? 'ok' : 'mismatch'}`,
        '  occupancy ' + [...grid.occupancy.keys()].sort((a, b) => a - b).map(count => `${count}:${grid.occupancy.get(count)}`).join(' '));
    }
    const xiLines = [`xi ${parameters.xiText} min_size ${parameters.minimumSize} steep_areas ${xi.steepAreas.length}`];
    for (const area of xi.steepAreas) xiLines.push(`${area.direction} ${area.start} ${area.end}`);
    xiLines.push('xi_clusters ' + xi.clusters.length);
    for (const [j, cluster] of xi.clusters.entries()) xiLines.push(`${j} start ${cluster.start} end ${cluster.end} size ${cluster.size}`
        + ` label ${cluster.label ?? '-'} parent ${cluster.parent ?? '-'} walls ${root(cluster.left)} ${root(cluster.right)} valley ${root(cluster.valley)}`);
    const ariLines = ['ari'];
    for (let a = 0; a < settings.length; a++) {
        for (let b = a + 1; b < settings.length; b++) {
            const [numerator, denominator] = adjustedRand(settings[a].labels, settings[b].labels);
            ariLines.push(`${settings[a].name} ${settings[b].name} ${fraction(numerator, denominator)} ${ariValue(numerator, denominator)}`);
        }
    }
    const parts = [[`points ${points.length} min_pts ${parameters.minimum}`, 'settings ' + settings.map(setting => setting.name).join(' ')],
        gridLines, ...settings.map(setting => settingLines(setting, points)), containmentLines(dbscanSettings),
        comparisonLines(extractions, dbscanSettings), opticsSummary(ordering, parameters.maximum), sweepLines(ordering, parameters.maximum),
        xiLines, outlierLines(knee, points, distances), gapLines(knee, points, distances), contingencyLines(knee, settings.at(-1)), ariLines];
    return parts.flatMap((part, i) => i === 0 ? part : ['', ...part]);
}

function kdistReport(points, curves, kdist, dbscanSettings, ordering, parameters) {
    const lines = [`k_distance k ${parameters.minimum - 1} points ${points.length}`, 'rank id kdist_sq kdist'];
    for (let i = 0; i < kdist.order.length; i++) {
        const p = kdist.order[i];
        lines.push(`${i + 1} ${points[p].id} ${kdist.values[p]} ${root(kdist.values[p])}`);
    }
    const p = kdist.order[kdist.knee];
    lines.push('', `knee rank ${kdist.knee + 1} id ${points[p].id} kdist_sq ${kdist.values[p]} kdist ${root(kdist.values[p])} cross ${kdist.cross}`,
        'suggested_eps ' + kdist.radius, '', 'knee_table');
    for (const curve of curves) {
        const point = curve.order[curve.knee];
        lines.push(`k ${curve.j} rank ${curve.knee + 1} id ${points[point].id} kdist_sq ${curve.values[point]} eps ${curve.radius}`);
    }
    lines.push('', 'core_check');
    for (const setting of dbscanSettings) {
        const count = kdist.values.filter(value => value <= setting.radius * setting.radius).length;
        const gridCore = setting.core.filter(Boolean).length;
        lines.push(`eps ${setting.radius} core ${count} non_core ${points.length - count} grid_core ${gridCore} ${count === gridCore ? 'ok' : 'mismatch'}`);
    }
    const core = ordering.core.filter(value => value !== Infinity).length;
    const match = ordering.core.every((value, p) => value === Infinity || value === kdist.values[p]);
    lines.push(`optics max_eps ${parameters.maximum} core ${core} ${match ? 'ok' : 'mismatch'}`);
    return lines;
}

function mapCells(points, width, height) {
    const xmin = Math.min(...points.map(point => point.x));
    const xmax = Math.max(...points.map(point => point.x));
    const ymin = Math.min(...points.map(point => point.y));
    const ymax = Math.max(...points.map(point => point.y));
    const rows = Array.from({ length: height }, () => Array.from({ length: width }, () => []));
    for (let p = 0; p < points.length; p++) {
        const column = Math.floor((points[p].x - xmin) * width / (xmax - xmin + 1));
        const row = Math.floor((ymax - points[p].y) * height / (ymax - ymin + 1));
        rows[row][column].push(p);
    }
    return rows;
}

function mapReport(points, parameters, settings, knee, extractions, ordering, kdist) {
    const cells = mapCells(points, ...parameters.mapSize);
    const lines = [];
    for (const setting of settings) {
        const rows = cells.map(row => row.map(cell => {
            if (cell.length === 0) return ' ';
            const labels = [...new Set(cell.map(p => setting.labels[p]).filter(label => label >= 0))];
            return labels.length === 0 ? '.' : labels.length === 1 ? character(labels[0]) : '*';
        }).join(''));
        lines.push(`map ${setting.name} clusters ${setting.clusters.length} noise ${setting.noise}`, ...frame(rows),
            'legend ' + (setting.clusters.length ? setting.clusters.map((cluster, label) => `${character(label)}=${cluster.size}`).join(' ') : '-'), '');
    }
    const kinds = cells.map(row => row.map(cell => cell.some(p => knee.core[p]) ? '#'
        : cell.some(p => knee.labels[p] >= 0) ? '+' : cell.length ? '.' : ' ').join(''));
    lines.push('kinds ' + knee.name, ...frame(kinds), '');
    const [width, height] = parameters.kdistSize;
    const maximum = kdist.values[kdist.order[0]];
    const heights = [];
    let kneeColumn = 0;
    for (let c = 0; c < width; c++) {
        const first = Math.floor(c * points.length / width);
        const end = Math.floor((c + 1) * points.length / width);
        if (first <= kdist.knee && kdist.knee < end) kneeColumn = c;
        const value = kdist.values[kdist.order[first]];
        let h = 0;
        while (h < height && (h + 1) * (h + 1) * maximum <= height * height * value) h++;
        heights.push(h);
    }
    const plot = Array.from({ length: height }, (_, row) => heights.map((h, c) => height - row <= h ? '#' : c === kneeColumn ? ':' : ' ').join(''));
    lines.push(`kdist_plot k ${parameters.minimum - 1} max ${root(maximum)} knee_column ${kneeColumn + 1}`, ...frame(plot), '');
    const top = Math.max(...ordering.reach.filter(value => value !== Infinity));
    const columns = [...extractions, settings.at(-1)];
    lines.push(`reachability width ${parameters.reachWidth} max_reach ${root(top)} columns ${columns.map(setting => setting.name).join(' ')}`);
    for (let i = 0; i < ordering.ordering.length; i++) {
        const p = ordering.ordering[i];
        const reach = ordering.reach[p];
        let bar;
        if (reach === Infinity) bar = '-'.repeat(parameters.reachWidth);
        else {
            let length = 0;
            while (length < parameters.reachWidth && (length + 1) * (length + 1) * top <= parameters.reachWidth * parameters.reachWidth * reach) length++;
            bar = '#'.repeat(length);
        }
        lines.push(`${String(i + 1).padStart(4, ' ')} ${String(points[p].id).padStart(5, ' ')} ${root(reach).padStart(7, ' ')} `
            + columns.map(setting => character(setting.labels[p])).join('') + ' |' + bar);
    }
    return lines;
}

function main() {
    const { points, parameters } = readDataset();
    const distances = distanceMatrix(points);
    const { curves, kdist } = kneeCurves(distances, parameters.minimum);
    const radii = [...new Set([...parameters.eps, kdist.radius, parameters.maximum])].sort((a, b) => a - b);
    const grids = new Map(radii.map(radius => [radius, buildGrid(points, radius, distances)]));
    const dbscanSettings = [...parameters.eps.map(radius => ({ name: 'db' + radius, radius })), { name: 'knee' + kdist.radius, radius: kdist.radius }]
        .map(setting => {
            const neighborhoods = grids.get(setting.radius).neighborhoods;
            Object.assign(setting, dbscan(neighborhoods, parameters.minimum));
            setting.check = checkDbscan(setting, neighborhoods);
            return summarize(setting, points, distances);
        });
    const ordering = optics(grids.get(parameters.maximum).neighborhoods, parameters.minimum, distances);
    const extractions = parameters.extracts.map(radius => summarize({ name: 'op' + radius, radius, ...extract(ordering, radius) }, points, distances));
    const xi = xiExtraction(ordering, parameters);
    const xiSetting = summarize({ name: 'xi', radius: parameters.maximum, labels: xi.labels, core: xi.core }, points, distances);
    const settings = [...dbscanSettings, ...extractions, xiSetting];
    const knee = dbscanSettings.at(-1);
    const labels = ['id,' + settings.map(setting => setting.name).join(',')];
    for (let p = 0; p < points.length; p++) labels.push([points[p].id, ...settings.map(setting => setting.labels[p])].join(','));
    const opticsRows = ['order,id,core_sq,reach_sq,reach,predecessor'];
    for (const [i, p] of ordering.ordering.entries()) opticsRows.push([i + 1, points[p].id, integer(ordering.core[p]), integer(ordering.reach[p]),
        root(ordering.reach[p]), ordering.predecessor[p] < 0 ? '-' : points[ordering.predecessor[p]].id].join(','));
    writeLines('labels.csv', labels);
    writeLines('optics_order.csv', opticsRows);
    writeLines('kdist.txt', kdistReport(points, curves, kdist, dbscanSettings, ordering, parameters));
    writeLines('clusters.txt', clusterReport(points, parameters, grids, settings, dbscanSettings, extractions, ordering, xi, knee, distances));
    writeLines('maps.txt', mapReport(points, parameters, settings, knee, extractions, ordering, kdist));
}

if (require.main === module) main();
