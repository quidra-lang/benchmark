'use strict';

const fs = require('node:fs');
const { orient, d2, dot, incircle, circumcenter, fraction } = require('./predicates');
const { key, Triangulation } = require('./triangulation');
const { radiusSquared, position, neighborOrder, outward, boundedArea, clippedArea } = require('./voronoi');
const { DisjointSet, nearestNeighbors, nearestComponents, minimumTree, gabriel, relativeNeighborhood, greedyRoute, dijkstra } = require('./proximity');
const { Canvas, voronoiPlot } = require('./plot');
const sum = values => values.reduce((total, value) => total + value, 0);
const joined = values => values.join(' ');
const edgeKey = (a, b) => key(Math.min(a, b), Math.max(a, b));
const yesNo = value => value ? 'yes' : 'no';
const fixed = value => {
    const text = Math.abs(value).toFixed(3);
    return value < 0 && text !== '0.000' ? '-' + text : text;
};

function readInput() {
    const raw = fs.readFileSync('input/points.txt', 'ascii').split('\n').slice(0, -1);
    const points = [null], errors = [], seen = new Map();
    raw.forEach((line, index) => {
        if (line === '' || line.startsWith('#')) return;
        const words = line.split(' ');
        if (words.length !== 2 || words.some(word => !/^-?[0-9]+$/.test(word))) {
            errors.push(`reject ${index + 1} format`);
            return;
        }
        const [x, y] = words.map(Number);
        if (x < 0 || x > 1000 || y < 0 || y > 1000) { errors.push(`reject ${index + 1} range`); return; }
        const coordinate = key(x, y);
        if (seen.has(coordinate)) { errors.push(`reject ${index + 1} duplicate ${seen.get(coordinate)}`); return; }
        seen.set(coordinate, points.length);
        points.push({ x, y });
    });
    const parameters = { plot: [61, 31], layers: ['edges', 'hull', 'sites'], sections: ['summary'], alpha: [], queries: [] };
    for (const line of fs.readFileSync('input/params.txt', 'ascii').split('\n').slice(0, -1)) {
        if (line === '' || line.startsWith('#')) continue;
        const [name, ...values] = line.split(' ');
        if (name === 'query') parameters.queries.push({ text: line.slice(6), kind: values[0], values: values.slice(1).map(Number) });
        else if (name === 'plot') parameters.plot = values.map(Number);
        else if (name === 'plot_layers') parameters.layers = values;
        else if (name === 'sections') parameters.sections = values;
        else if (name === 'alpha') parameters.alpha = values.map(Number);
    }
    return { points, parameters, errors, lines: raw.length };
}

function organize(points, mesh) {
    const triangles = mesh.triangles().map((sites, index) => ({ number: index + 1, sites }));
    const numbers = new Map(triangles.map(triangle => [triangle.sites.join(','), triangle.number]));
    const directedNumbers = new Map();
    const pairs = new Map();
    for (const triangle of triangles) {
        const [a, b, c] = triangle.sites;
        for (const [u, v] of [[a, b], [b, c], [c, a]]) {
            directedNumbers.set(key(u, v), triangle.number);
            pairs.set(edgeKey(u, v), [Math.min(u, v), Math.max(u, v)]);
        }
    }
    const edges = [...pairs.values()].sort((a, b) => a[0] - b[0] || a[1] - b[1]).map(([i, j]) => {
        const left = directedNumbers.get(key(i, j)), right = directedNumbers.get(key(j, i));
        return { i, j, left, right, kind: left !== undefined && right !== undefined ? 'inner' : 'hull', length2: d2(points[i], points[j]) };
    });
    const next = new Map(), previous = new Map();
    for (const [u, v] of mesh.hullEdges()) { next.set(u, v); previous.set(v, u); }
    const hull = [];
    const first = Math.min(...next.keys());
    let current = first;
    do { hull.push(current); current = next.get(current); } while (current !== first);
    const adjacent = Array.from({ length: points.length }, () => []);
    for (const edge of edges) { adjacent[edge.i].push(edge.j); adjacent[edge.j].push(edge.i); }
    const neighbors = adjacent.map((list, site) => site === 0 ? [] : neighborOrder(site, list, next, mesh));
    let perimeter = 0, area2 = 0;
    for (let i = 0; i < hull.length; i++) {
        const a = points[hull[i]], b = points[hull[(i + 1) % hull.length]];
        perimeter += Math.sqrt(d2(a, b));
        area2 += a.x * b.y - b.x * a.y;
    }
    return { points, mesh, triangles, numbers, directedNumbers, edges, edgeMap: new Map(edges.map(edge => [key(edge.i, edge.j), edge])),
        hull, next, previous, neighbors, perimeter, area2 };
}

function triangleProperties(model) {
    const vertices = [];
    for (const triangle of model.triangles) {
        const points = triangle.sites.map(site => model.points[site]);
        triangle.area2 = orient(...points);
        const products = points.map((point, k) => dot(point, points[(k + 1) % 3], points[(k + 2) % 3]));
        triangle.kind = products.includes(0) ? 'right' : products.some(value => value < 0) ? 'obtuse' : 'acute';
        const lengths = points.map((_, k) => d2(points[(k + 1) % 3], points[(k + 2) % 3]));
        let shortest = 0, longest = 0;
        for (let k = 1; k < 3; k++) {
            if (lengths[k] < lengths[shortest]) shortest = k;
            if (lengths[k] > lengths[longest]) longest = k;
        }
        const angles = points.map((point, k) => Math.atan2(Math.abs(orient(point, points[(k + 1) % 3], points[(k + 2) % 3])), products[k]) * 180 / Math.PI);
        triangle.minimum = angles[shortest];
        triangle.maximum = angles[longest];
        triangle.radius2 = radiusSquared(...points, triangle.area2);
        const vertex = { number: triangle.number, ...circumcenter(...points), radius2: triangle.radius2 };
        vertex.position = position(vertex, model.hull, model.points);
        vertices.push(vertex);
    }
    let smallest = model.triangles[0], largest = model.triangles[0];
    const bins = Array(6).fill(0);
    for (const triangle of model.triangles) {
        if (triangle.minimum < smallest.minimum) smallest = triangle;
        if (triangle.maximum > largest.maximum) largest = triangle;
        bins[Math.floor(triangle.minimum / 10)]++;
    }
    return { vertices, quality: { smallest, largest, mean: sum(model.triangles.map(triangle => triangle.minimum)) / model.triangles.length, bins } };
}

function voronoiCells(model) {
    const cells = [null];
    let totalArea = 0, clipTotal = 0, largest = null;
    for (let site = 1; site < model.points.length; site++) {
        const bounded = !model.next.has(site);
        const sequence = model.neighbors[site].map(neighbor => model.directedNumbers.get(key(site, neighbor))).filter(number => number !== undefined);
        const area = bounded ? boundedArea(model.points[site], sequence, model.vertices) : null;
        const clip = clippedArea(model.points[site], model.neighbors[site], model.points);
        const cell = { site, bounded, sequence, area, clip,
            incoming: bounded ? null : outward(site, model.next.get(site), model.points),
            outgoing: bounded ? null : outward(model.previous.get(site), site, model.points) };
        cells.push(cell);
        if (bounded) {
            totalArea += area;
            if (largest === null || area > largest.area) largest = cell;
        }
        clipTotal += clip;
    }
    return { cells, totalArea, clipTotal, largest };
}

function proximityGraphs(model) {
    const n = model.points.length - 1;
    const nearest = nearestNeighbors(model.points, model.neighbors);
    const groups = nearestComponents(nearest);
    const componentOf = Array(n + 1).fill(0);
    const components = groups.map((sites, index) => {
        sites.forEach(site => { componentOf[site] = index + 1; });
        const first = sites.find(site => nearest[nearest[site]] === site && site < nearest[site]);
        return { number: index + 1, sites, pair: [first, nearest[first]] };
    });
    const mutual = [];
    for (let site = 1; site <= n; site++) if (site < nearest[site] && nearest[nearest[site]] === site) mutual.push([site, nearest[site]]);
    const mst = minimumTree(model.edges, n);
    const adopted = new Set(mst);
    const ggDegree = Array(n + 1).fill(0), rngDegree = Array(n + 1).fill(0), mstDegree = Array(n + 1).fill(0);
    let closest = model.edges[0];
    for (const edge of model.edges) {
        edge.gabriel = gabriel(edge, model.mesh, model.points);
        edge.rng = relativeNeighborhood(edge, model.points);
        edge.mst = adopted.has(edge);
        if (edge.length2 < closest.length2) closest = edge;
        for (const site of [edge.i, edge.j]) {
            if (edge.gabriel) ggDegree[site]++;
            if (edge.rng) rngDegree[site]++;
            if (edge.mst) mstDegree[site]++;
        }
    }
    return { nearest, components, componentOf, mutual, mst, mstLength: sum(mst.map(edge => Math.sqrt(edge.length2))),
        ggDegree, rngDegree, mstDegree, closest };
}

function convexHull(sites, points) {
    if (sites.length <= 2) return sites.slice().sort((a, b) => a - b);
    const order = sites.slice().sort((a, b) => points[a].x - points[b].x || points[a].y - points[b].y || a - b);
    const chain = values => {
        const result = [];
        for (const site of values) {
            while (result.length >= 2 && orient(points[result[result.length - 2]], points[result[result.length - 1]], points[site]) <= 0) result.pop();
            result.push(site);
        }
        return result;
    };
    const hull = [...chain(order).slice(0, -1), ...chain(order.slice().reverse()).slice(0, -1)];
    const start = hull.indexOf(Math.min(...hull));
    return [...hull.slice(start), ...hull.slice(0, start)];
}

function convexLayers(points) {
    let remaining = Array.from({ length: points.length - 1 }, (_, index) => index + 1);
    const layers = [], depths = Array(points.length).fill(0);
    while (remaining.length > 0) {
        const layer = convexHull(remaining, points);
        layers.push(layer);
        for (const site of layer) depths[site] = layers.length;
        const removed = new Set(layer);
        remaining = remaining.filter(site => !removed.has(site));
    }
    return { layers, depths };
}

function supportCircle(sites, points) {
    if (sites.length === 1) return { support: sites, X: points[sites[0]].x, Y: points[sites[0]].y, D: 1, radius2: 0 };
    if (sites.length === 2) {
        const [a, b] = sites.map(site => points[site]);
        return { support: sites, X: a.x + b.x, Y: a.y + b.y, D: 2, radius2: d2(a, b) / 4 };
    }
    let [a, b, c] = sites;
    if (orient(points[a], points[b], points[c]) < 0) [b, c] = [c, b];
    return { support: [a, b, c], ...circumcenter(points[a], points[b], points[c]),
        radius2: radiusSquared(points[a], points[b], points[c], orient(points[a], points[b], points[c])) };
}

function circleMembership(circle, point, points) {
    const support = circle.support.map(site => points[site]);
    if (support.length === 1) return -d2(point, support[0]);
    if (support.length === 2) return -dot(point, support[0], support[1]);
    return incircle(...support, point);
}

function enclosingCircle(hull, points) {
    let circle = null;
    for (let i = 0; i < hull.length; i++) {
        if (circle !== null && circleMembership(circle, points[hull[i]], points) >= 0) continue;
        circle = supportCircle([hull[i]], points);
        for (let j = 0; j < i; j++) {
            if (circleMembership(circle, points[hull[j]], points) >= 0) continue;
            circle = supportCircle([hull[i], hull[j]], points);
            for (let k = 0; k < j; k++) {
                if (circleMembership(circle, points[hull[k]], points) >= 0) continue;
                circle = supportCircle([hull[i], hull[j], hull[k]], points);
            }
        }
    }
    const boundary = [];
    for (let site = 1; site < points.length; site++) if (circleMembership(circle, points[site], points) === 0) boundary.push(site);
    let diameter = null;
    for (let i = 0; i < boundary.length; i++) for (let j = i + 1; j < boundary.length; j++)
        if (boundary.every(site => dot(points[site], points[boundary[i]], points[boundary[j]]) === 0)) diameter = [boundary[i], boundary[j]];
    circle = supportCircle(diameter || boundary, points);
    return { ...circle, boundary };
}

function extent(model) {
    const candidates = model.vertices.filter(vertex => vertex.position === 'inside');
    let empty = null;
    for (const vertex of candidates) if (empty === null || vertex.radius2 > empty.radius2) empty = vertex;
    let diameter = null;
    for (let i = 1; i < model.points.length; i++) for (let j = i + 1; j < model.points.length; j++) {
        const distance = d2(model.points[i], model.points[j]);
        if (diameter === null || distance > diameter.length2) diameter = { i, j, length2: distance };
    }
    let width = null;
    for (let t = 0; t < model.hull.length; t++) {
        const u = model.hull[t], v = model.hull[(t + 1) % model.hull.length];
        const maximum = Math.max(...model.hull.map(site => orient(model.points[u], model.points[v], model.points[site])));
        const value = maximum / Math.sqrt(d2(model.points[u], model.points[v]));
        if (width === null || value < width.value) width = { u, v, value };
    }
    return { candidates, empty, diameter, width, enclosing: enclosingCircle(model.hull, model.points) };
}

function shortestPaths(model) {
    const paths = [null];
    for (let site = 1; site < model.points.length; site++) paths.push(dijkstra(site, model.neighbors, model.points));
    let total = 0, pairs = 0, maximum = null;
    for (let i = 1; i < model.points.length; i++) for (let j = i + 1; j < model.points.length; j++) {
        const distance = Math.sqrt(d2(model.points[i], model.points[j]));
        const length = paths[i].distances[j];
        const stretch = length / distance;
        total += stretch;
        pairs++;
        if (maximum === null || stretch > maximum.stretch) maximum = { i, j, stretch, length, distance };
    }
    return { paths, pairs, maximum, mean: total / pairs };
}

function alphaComplex(model, alpha) {
    const selected = model.triangles.filter(triangle => triangle.radius2 <= alpha);
    const numbers = new Set(selected.map(triangle => triangle.number));
    const sets = new DisjointSet(model.points.length - 1);
    const touched = new Set();
    let edges = 0, boundary = 0, dangling = 0;
    for (const edge of model.edges) {
        const count = Number(numbers.has(edge.left)) + Number(numbers.has(edge.right));
        if (count === 0 && !(edge.gabriel && edge.length2 <= 4 * alpha)) continue;
        edges++;
        if (count === 1) boundary++;
        if (count === 0) dangling++;
        touched.add(edge.i);
        touched.add(edge.j);
        sets.union(edge.i, edge.j);
    }
    const n = model.points.length - 1;
    return { alpha, triangles: selected.length, edges, boundary, dangling, isolated: n - touched.size,
        components: sets.count, holes: sets.count - (n - edges + selected.length), area2: sum(selected.map(triangle => triangle.area2)) };
}

function dualDescription(edge, model) {
    if (edge.kind === 'inner') return `segment ${edge.left} ${edge.right}`;
    const direction = edge.left !== undefined ? outward(edge.i, edge.j, model.points) : outward(edge.j, edge.i, model.points);
    return `ray ${edge.left === undefined ? edge.right : edge.left} ${joined(direction)}`;
}

function locate(point, model) {
    let nearest = 1;
    for (let site = 2; site < model.points.length; site++)
        if (d2(model.points[site], point) < d2(model.points[nearest], point)) nearest = site;
    let place = 'outside';
    const vertex = model.points.findIndex((candidate, site) => site > 0 && candidate.x === point.x && candidate.y === point.y);
    if (vertex >= 1) place = 'vertex ' + vertex;
    else {
        const edge = model.edges.find(edge => orient(model.points[edge.i], model.points[edge.j], point) === 0 && dot(point, model.points[edge.i], model.points[edge.j]) < 0);
        if (edge) place = `edge ${edge.i} ${edge.j}`;
        else {
            const triangle = model.triangles.find(({ sites: [a, b, c] }) => orient(model.points[a], model.points[b], point) > 0
                && orient(model.points[b], model.points[c], point) > 0 && orient(model.points[c], model.points[a], point) > 0);
            if (triangle) place = 'triangle ' + joined(triangle.sites);
        }
    }
    return `${place} nearest ${nearest} d2 ${d2(model.points[nearest], point)}`;
}

function answerQuery(query, model) {
    const { kind, values } = query;
    const [i, j] = values;
    const point = { x: i, y: j };
    if (kind === 'locate') return locate(point, model);
    if (kind === 'walk') {
        const walk = model.mesh.walk(point, model.triangles, model.numbers);
        const place = walk.outside ? 'outside ' + joined(walk.outside) : 'triangle ' + walk.triangle;
        return `steps ${walk.path.length - 1} ${place} path ${joined(walk.path)}`;
    }
    if (kind === 'natural') {
        const triangles = model.triangles.filter(triangle => incircle(...triangle.sites.map(site => model.points[site]), point) > 0);
        const sites = [...new Set(triangles.flatMap(triangle => triangle.sites))].sort((a, b) => a - b);
        return `triangles ${triangles.length} sites ${sites.length ? joined(sites) : '-'}`;
    }
    if (values.some(site => site < 1 || site >= model.points.length)) return 'error unknown_site';
    if (kind === 'neighbors') return `degree ${model.neighbors[i].length} sites ${joined(model.neighbors[i])}`;
    if (kind === 'route') {
        const route = greedyRoute(i, j, model.neighbors, model.points);
        return `hops ${route.path.length - 1} length ${fixed(route.length)} path ${joined(route.path)}`;
    }
    if (kind === 'path') {
        const sequence = [];
        let current = j;
        while (current !== null) {
            sequence.push(current);
            if (current === i) break;
            current = model.paths[i].previous[current];
        }
        sequence.reverse();
        const length = model.paths[i].distances[j];
        const stretch = i === j ? '-' : fixed(length / Math.sqrt(d2(model.points[i], model.points[j])));
        return `length ${fixed(length)} stretch ${stretch} hops ${sequence.length - 1} sites ${joined(sequence)}`;
    }
    if (i === j) return 'error same_site';
    const edge = model.edgeMap.get(edgeKey(i, j));
    if (edge) return `delaunay len2 ${edge.length2} gabriel ${yesNo(edge.gabriel)} rng ${yesNo(edge.rng)} mst ${yesNo(edge.mst)} dual ${dualDescription(edge, model)}`;
    const crossings = model.edges.filter(({ i: u, j: v }) => orient(model.points[i], model.points[j], model.points[u]) * orient(model.points[i], model.points[j], model.points[v]) < 0
        && orient(model.points[u], model.points[v], model.points[i]) * orient(model.points[u], model.points[v], model.points[j]) < 0);
    return `missing crossings ${crossings.length}` + (crossings.length ? ' ' + crossings.map(edge => edge.i + '-' + edge.j).join(' ') : '');
}

function delaunayPlot(model, parameters) {
    const canvas = new Canvas(...parameters.plot);
    for (const layer of parameters.layers) {
        if (layer === 'edges') for (const edge of model.edges) canvas.line(model.points[edge.i], model.points[edge.j], '.');
        else if (layer === 'mst') for (const edge of model.mst) canvas.line(model.points[edge.i], model.points[edge.j], '*');
        else if (layer === 'hull') for (let i = 0; i < model.hull.length; i++) canvas.line(model.points[model.hull[i]], model.points[model.hull[(i + 1) % model.hull.length]], '#');
        else if (layer === 'sites') for (let site = 1; site < model.points.length; site++) canvas.point(model.points[site], 'o');
        else if (layer === 'circle' && model.empty) canvas.point(model.empty, '@');
    }
    return canvas.frame();
}

function sections(model, input) {
    const n = model.points.length - 1;
    const triangleCount = model.triangles.length, edgeCount = model.edges.length, hullCount = model.hull.length;
    const result = {};
    result.input = [`lines ${input.lines}`, `accepted ${n}`, `rejected ${input.errors.length}`, ...input.errors];
    let maxFlips = null;
    for (const insertion of model.insertions) if (maxFlips === null || insertion.flips > maxFlips.flips) maxFlips = insertion;
    result.summary = [
        `sites ${n}`, `triangles ${triangleCount}`, `edges ${edgeCount}`, `hull_vertices ${hullCount}`, `interior_sites ${n - hullCount}`,
        `euler ${n - edgeCount + triangleCount}`, `flips ${sum(model.insertions.map(insertion => insertion.flips))}`,
        `outside_insertions ${model.insertions.filter(insertion => insertion.kind === 'outside').length}`,
        maxFlips ? `max_flips ${maxFlips.site} ${maxFlips.flips}` : 'max_flips none',
        ...['acute', 'right', 'obtuse'].map(kind => kind + ' ' + model.triangles.filter(triangle => triangle.kind === kind).length)
    ];
    result.insertions = ['init ' + joined(model.mesh.initial), ...model.insertions.map(insertion => {
        const kind = insertion.kind === 'inside' ? 'inside ' + joined(insertion.containing) : 'outside ' + insertion.visible;
        return `insert ${insertion.site} ${kind} flips ${insertion.flips} triangles ${insertion.triangles} hull ${insertion.hull}`;
    })];
    result.triangles = model.triangles.map(triangle => {
        const [a, b, c] = triangle.sites;
        const adjacent = [[c, b], [a, c], [b, a]].map(([u, v]) => model.directedNumbers.get(key(u, v)) ?? '-');
        return `tri ${triangle.number} ${joined(triangle.sites)} area2 ${triangle.area2} ${triangle.kind} adj ${joined(adjacent)}`;
    });
    result.edges = model.edges.map(edge => `edge ${edge.i} ${edge.j} ${edge.kind} len2 ${edge.length2} left ${edge.left ?? '-'} right ${edge.right ?? '-'}`);
    result.hull = [`hull_vertices ${hullCount}`, 'order ' + joined(model.hull), 'perimeter ' + fixed(model.perimeter), 'area2 ' + model.area2];
    result.convex_layers = ['layers ' + model.layers.length, ...model.layers.map((layer, i) => `layer ${i + 1} size ${layer.length} sites ${joined(layer)}`)];
    result.quality = [`min_angle ${fixed(model.quality.smallest.minimum)} tri ${model.quality.smallest.number}`,
        `max_angle ${fixed(model.quality.largest.maximum)} tri ${model.quality.largest.number}`, 'mean_min_angle ' + fixed(model.quality.mean),
        ...model.quality.bins.map((count, i) => `bin ${i * 10} ${(i + 1) * 10} ${count}`)];
    result.vertices = [...['inside', 'on', 'outside'].map(location => location + ' ' + model.vertices.filter(vertex => vertex.position === location).length),
        ...model.vertices.map(vertex => `v ${vertex.number} ${fraction(vertex.X, vertex.D)} ${fraction(vertex.Y, vertex.D)} r ${fixed(Math.sqrt(vertex.radius2))} ${vertex.position}`)];
    result.voronoi_edges = ['segments ' + model.edges.filter(edge => edge.kind === 'inner').length, 'rays ' + hullCount,
        ...model.edges.map(edge => `ve ${edge.i} ${edge.j} ${dualDescription(edge, model)}`)];
    result.cells = [`bounded ${n - hullCount}`, `unbounded ${hullCount}`, 'total_area ' + fixed(model.totalArea), 'clip_total ' + fixed(model.clipTotal),
        model.largest ? `largest ${model.largest.site} area ${fixed(model.largest.area)}` : 'largest none',
        ...model.cells.slice(1).map(cell => cell.bounded
            ? `cell ${cell.site} bounded ${cell.sequence.length} area ${fixed(cell.area)} clip ${fixed(cell.clip)} vertices ${joined(cell.sequence)}`
            : `cell ${cell.site} unbounded ${cell.sequence.length} clip ${fixed(cell.clip)} from ${joined(cell.incoming)} vertices ${joined(cell.sequence)} to ${joined(cell.outgoing)}`)];
    result.nearest = ['mutual_pairs ' + model.mutual.length, `closest_pair ${model.closest.i} ${model.closest.j} d2 ${model.closest.length2}`,
        ...model.nearest.slice(1).map((nearest, index) => `nn ${index + 1} ${nearest} d2 ${d2(model.points[index + 1], model.points[nearest])} ${model.nearest[nearest] === index + 1 ? 'mutual' : '-'}`)];
    result.components = ['components ' + model.components.length, ...model.components.map(component =>
        `component ${component.number} size ${component.sites.length} pair ${joined(component.pair)} sites ${joined(component.sites)}`)];
    const longest = model.mst[model.mst.length - 1];
    result.mst = [`edges ${n - 1}`, 'total_length ' + fixed(model.mstLength), `longest ${longest.i} ${longest.j} len2 ${longest.length2}`,
        ...model.mst.map(edge => `mst ${edge.i} ${edge.j} len2 ${edge.length2}`)];
    result.proximity = [`delaunay ${edgeCount}`, 'gabriel ' + model.edges.filter(edge => edge.gabriel).length, 'rng ' + model.edges.filter(edge => edge.rng).length,
        `mst ${n - 1}`, `nn ${n - model.mutual.length}`, ...model.edges.filter(edge => edge.rng && !edge.mst).map(edge => `rng_extra ${edge.i} ${edge.j} len2 ${edge.length2}`)];
    const degrees = model.neighbors.slice(1).map(neighbors => neighbors.length);
    result.degrees = ['min ' + Math.min(...degrees), 'max ' + Math.max(...degrees), ...[...new Set(degrees)].sort((a, b) => a - b).map(degree =>
        `degree ${degree} count ${degrees.filter(value => value === degree).length}`)];
    result.empty_circle = ['candidates ' + model.candidates.length];
    if (model.empty) result.empty_circle.push('vertex ' + model.empty.number, `center ${fraction(model.empty.X, model.empty.D)} ${fraction(model.empty.Y, model.empty.D)}`,
        'radius ' + fixed(Math.sqrt(model.empty.radius2)), 'sites ' + joined(model.triangles[model.empty.number - 1].sites));
    else result.empty_circle.push('none');
    result.extent = [`diameter ${model.diameter.i} ${model.diameter.j} d2 ${model.diameter.length2}`,
        `width ${fixed(model.width.value)} edge ${model.width.u} ${model.width.v}`,
        `enclosing_center ${fraction(model.enclosing.X, model.enclosing.D)} ${fraction(model.enclosing.Y, model.enclosing.D)}`,
        'enclosing_radius ' + fixed(Math.sqrt(model.enclosing.radius2)), 'enclosing_sites ' + joined(model.enclosing.boundary)];
    const maximum = model.maximum;
    result.spanner = [`pairs ${model.pairs}`, `max_stretch ${fixed(maximum.stretch)} pair ${maximum.i} ${maximum.j} length ${fixed(maximum.length)} distance ${fixed(maximum.distance)}`,
        'mean_stretch ' + fixed(model.mean)];
    result.alpha = input.parameters.alpha.map(value => {
        const alpha = alphaComplex(model, value);
        return `alpha ${alpha.alpha} triangles ${alpha.triangles} edges ${alpha.edges} boundary ${alpha.boundary} dangling ${alpha.dangling} isolated ${alpha.isolated} components ${alpha.components} holes ${alpha.holes} area2 ${alpha.area2}`;
    });
    result.sites = model.points.slice(1).map((point, index) => {
        const site = index + 1;
        return `site ${site} ${point.x} ${point.y} ${model.next.has(site) ? 'hull' : 'inner'} dt ${model.neighbors[site].length} gg ${model.ggDegree[site]} rng ${model.rngDegree[site]} mst ${model.mstDegree[site]} nn ${model.nearest[site]} comp ${model.componentOf[site]} depth ${model.depths[site]}`;
    });
    result.queries = input.parameters.queries.map(query => query.text + ' ' + answerQuery(query, model));
    result.delaunay_plot = delaunayPlot(model, input.parameters);
    result.voronoi_plot = voronoiPlot(...input.parameters.plot, model.points);
    return result;
}

function main() {
    const input = readInput();
    const mesh = new Triangulation(input.points);
    const insertions = [];
    for (let site = 4; site < input.points.length; site++) insertions.push(mesh.insert(site));
    const model = { ...organize(input.points, mesh), insertions };
    Object.assign(model, triangleProperties(model));
    Object.assign(model, voronoiCells(model));
    Object.assign(model, proximityGraphs(model));
    Object.assign(model, convexLayers(model.points));
    Object.assign(model, extent(model));
    Object.assign(model, shortestPaths(model));
    const contents = sections(model, input);
    const groups = {
        'triangulation.txt': ['input', 'summary', 'insertions', 'triangles', 'edges', 'hull', 'convex_layers', 'quality'],
        'voronoi.txt': ['vertices', 'voronoi_edges', 'cells'],
        'derived.txt': ['nearest', 'components', 'mst', 'proximity', 'degrees', 'empty_circle', 'extent', 'spanner', 'alpha', 'sites', 'queries'],
        'plot.txt': ['delaunay_plot', 'voronoi_plot']
    };
    fs.mkdirSync('output', { recursive: true });
    for (const [file, names] of Object.entries(groups)) {
        const lines = [];
        for (const name of input.parameters.sections) if (names.includes(name)) lines.push('[' + name + ']', ...contents[name]);
        fs.writeFileSync('output/' + file, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
    }
}

main();
