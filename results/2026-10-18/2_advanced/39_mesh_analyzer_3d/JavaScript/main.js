'use strict';

const fs = require('node:fs');
const { readModel, writeModel } = require('./obj_io');
const { edgeKey, analyze, boundaryLoops } = require('./topology');
const { containsDirection, flip, inconsistentEdges, orient } = require('./orientation');
const measure = require('./measure');
const repair = require('./repair');
const { difference, add, dot, cross, fraction, real } = measure;
const list = values => values.length ? values.join(' ') : '-';
const yes = value => value ? 'yes' : 'no';
const uniqueSorted = values => [...new Set(values)].sort((a, b) => a - b);

function readParameters() {
    const settings = { snap: 1, merge: true, degenerate: true, duplicates: true, orient: true, outward: true,
        fillHoles: 0, keepUnused: true, sections: ['summary', 'components'], queries: [] };
    const names = { fill_holes: 'fillHoles', keep_unused: 'keepUnused' };
    const lines = fs.readFileSync('input/params.txt', 'ascii').split('\n').slice(0, -1);
    for (const line of lines) {
        if (line === '' || line.startsWith('#')) continue;
        const [name, ...values] = line.split(' ');
        if (name === 'query') settings.queries.push({ kind: values[0], values: values.slice(1).map(Number) });
        else if (name === 'sections') settings.sections = values;
        else if (name === 'snap' || name === 'fill_holes') settings[names[name] ?? name] = Number(values[0]);
        else settings[names[name] ?? name] = values[0] === 'on';
    }
    return settings;
}

function nonplanar(polygon, positions) {
    const vertices = polygon.vertices.map(vertex => positions[vertex]);
    let normal = [0, 0, 0];
    for (let i = 1; i < vertices.length - 1; i++) {
        normal = add(normal, cross(difference(vertices[i], vertices[0]), difference(vertices[i + 1], vertices[0])));
    }
    return vertices.some(vertex => dot(difference(vertex, vertices[0]), normal) !== 0);
}

function cleanup(model, settings) {
    const triangles = repair.triangulate(model.polygons);
    const snapped = repair.snap(model.vertices, settings.snap);
    const representatives = repair.representatives(snapped.positions, settings.merge);
    const removal = repair.removeTriangles(triangles, representatives.numbers, snapped.positions, settings);
    const used = new Set(removal.faces.flatMap(face => face.vertices));
    const originalToNew = new Map();
    const vertices = [null];
    for (let original = 1; original < model.vertices.length; original++) {
        const output = settings.keepUnused ? representatives.numbers[original] === original : used.has(original);
        if (!output) continue;
        originalToNew.set(original, vertices.length);
        vertices.push(snapped.positions[original]);
    }
    const faces = removal.faces.map((face, i) => {
        const sequence = face.vertices.map(vertex => originalToNew.get(vertex));
        return { ...face, number: i + 1, vertices: sequence, initial: sequence.slice() };
    });
    const polygonSizes = new Map();
    for (const polygon of model.polygons) {
        polygon.nonplanar = nonplanar(polygon, snapped.positions);
        const size = polygon.vertices.length;
        polygonSizes.set(size, (polygonSizes.get(size) ?? 0) + 1);
    }
    return { triangles, snapped, representatives, removed: removal.removed, originalToNew, vertices, faces, polygonSizes };
}

function coherentLoops(faces, topology) {
    const loops = boundaryLoops(topology);
    for (const loop of loops) {
        loop.kind = 'open';
        if (!loop.closed) continue;
        let agreeing = 0;
        for (let i = 0; i < loop.length; i++) {
            const a = loop.vertices[i];
            const b = loop.vertices[(i + 1) % loop.length];
            const edge = topology.edgeMap.get(edgeKey(a, b));
            if (containsDirection(faces[edge.faces[0]], a, b)) agreeing++;
        }
        loop.kind = agreeing === 0 || agreeing === loop.length ? 'coherent' : 'mixed';
        if (agreeing === 0) loop.vertices = [loop.vertices[0], ...loop.vertices.slice(1).reverse()];
    }
    return loops;
}

function prepareAndFill(faces, settings) {
    const originalFaces = faces.length;
    const topology = analyze(faces);
    const inconsistentBefore = inconsistentEdges(faces, topology).length;
    if (settings.orient) orient(faces, topology);
    const inconsistent = inconsistentEdges(faces, topology);
    const loops = coherentLoops(faces, topology);
    const blocked = new Set([...topology.edges.filter(edge => edge.faces.length >= 3), ...inconsistent]
        .map(edge => topology.componentOf[edge.faces[0]]));
    let filled = 0;
    for (const loop of loops) {
        loop.filled = loop.kind === 'coherent' && loop.length >= 3 && loop.length <= settings.fillHoles
            && new Set(loop.vertices).size === loop.length && !blocked.has(loop.component);
        if (!loop.filled) continue;
        filled++;
        for (const face of repair.fillTriangles(loop)) faces.push({ ...face, number: faces.length + 1 });
    }
    return { topology, inconsistent, loops, inconsistentBefore, originalFaces, filled, fillFaces: faces.length - originalFaces };
}

function componentProperties(faces, topology) {
    const loops = coherentLoops(faces, topology);
    const inconsistent = new Set(inconsistentEdges(faces, topology).map(edge => edge.key));
    for (const component of topology.components) {
        component.boundary = component.edges.filter(edge => edge.faces.length === 1);
        component.nonmanifoldEdges = component.edges.filter(edge => edge.faces.length >= 3);
        component.nonmanifoldVertices = [];
        component.loopCount = loops.filter(loop => loop.component === component.number).length;
        component.closed = component.boundary.length === 0;
        component.consistent = !component.edges.some(edge => inconsistent.has(edge.key));
        component.chi = component.vertices.length - component.edges.length + component.faces.length;
        component.inside = [];
    }
    for (const vertex of [...topology.fans.keys()].sort((a, b) => a - b)) {
        const counts = new Map();
        for (const fan of topology.fans.get(vertex)) {
            const number = topology.componentOf[fan[0]];
            counts.set(number, (counts.get(number) ?? 0) + 1);
        }
        for (const [number, count] of counts) if (count >= 2) topology.components[number - 1].nonmanifoldVertices.push(vertex);
    }
    for (const component of topology.components) {
        component.manifold = component.nonmanifoldEdges.length === 0 && component.nonmanifoldVertices.length === 0;
        component.solid = component.closed && component.manifold && component.consistent;
    }
}

function nestAndOrient(faces, vertices, topology, settings) {
    const solids = topology.components.filter(component => component.solid);
    for (const component of solids) {
        for (const other of solids) {
            if (component === other) continue;
            const vertex = component.vertices.find(value => !other.vertexSet.has(value));
            if (vertex !== undefined && measure.winding(faces, vertices, other.faces, vertices[vertex]) !== 0) component.inside.push(other.number);
        }
    }
    let outwardComponents = 0;
    if (settings.outward) {
        for (const component of solids) {
            const volume = measure.volume6(faces, vertices, component.faces);
            const reverse = component.inside.length % 2 === 0 ? volume < 0 : volume > 0;
            if (volume === 0 || !reverse) continue;
            for (const index of component.faces) flip(faces[index]);
            outwardComponents++;
        }
    }
    const copy = faces.map(face => ({ ...face, vertices: face.vertices.slice() }));
    orient(copy, topology);
    const inconsistent = new Set(inconsistentEdges(copy, topology).map(edge => edge.key));
    for (const component of topology.components) {
        component.orientable = !component.edges.some(edge => inconsistent.has(edge.key));
        component.genus = component.manifold && component.orientable ? (2 - component.chi - component.loopCount) / 2 : null;
        component.crosscaps = component.manifold && !component.orientable ? 2 - component.chi - component.loopCount : null;
    }
    return outwardComponents;
}

function measureEdges(faces, vertices, topology, geometry) {
    for (const edge of topology.edges) {
        const delta = difference(vertices[edge.a], vertices[edge.b]);
        edge.len2 = dot(delta, delta);
        edge.kind = edge.faces.length === 1 ? 'boundary' : edge.faces.length === 2 ? 'manifold' : 'nonmanifold';
        edge.shape = null;
        if (edge.kind !== 'manifold') continue;
        const [f, g] = edge.faces;
        if (containsDirection(faces[f], edge.a, edge.b) === containsDirection(faces[g], edge.a, edge.b)) edge.shape = 'inconsistent';
        else {
            const opposite = faces[g].vertices.find(vertex => vertex !== edge.a && vertex !== edge.b);
            const side = dot(difference(vertices[opposite], vertices[faces[f].vertices[0]]), geometry[f].normal);
            edge.shape = side < 0 ? 'convex' : side > 0 ? 'concave' : 'flat';
        }
    }
}

function measureComponents(faces, vertices, topology, geometry, groups) {
    for (const component of topology.components) {
        const groupNames = new Set(component.faces.map(index => faces[index].group));
        component.groups = groups.filter(group => groupNames.has(group));
        component.area = measure.area(component.faces.map(index => geometry[index]));
        component.volume6 = 0;
        component.normalSum = [0, 0, 0];
        component.angles = { acute: 0, right: 0, obtuse: 0 };
        for (const index of component.faces) {
            component.volume6 += geometry[index].determinant;
            component.normalSum = add(component.normalSum, geometry[index].normal);
            component.angles[geometry[index].angle]++;
        }
        component.centroid = component.solid && component.volume6 !== 0
            ? measure.centroid(faces, vertices, component.faces, geometry, component.volume6) : null;
        component.minimum = vertices[component.vertices[0]].slice();
        component.maximum = vertices[component.vertices[0]].slice();
        for (const vertex of component.vertices) {
            for (let k = 0; k < 3; k++) {
                component.minimum[k] = Math.min(component.minimum[k], vertices[vertex][k]);
                component.maximum[k] = Math.max(component.maximum[k], vertices[vertex][k]);
            }
        }
        component.shapes = { convex: 0, concave: 0, flat: 0 };
        const degrees = new Map(component.vertices.map(vertex => [vertex, 0]));
        for (const edge of component.edges) {
            if (Object.hasOwn(component.shapes, edge.shape)) component.shapes[edge.shape]++;
            degrees.set(edge.a, degrees.get(edge.a) + 1);
            degrees.set(edge.b, degrees.get(edge.b) + 1);
        }
        component.minDegree = Math.min(...degrees.values());
        component.maxDegree = Math.max(...degrees.values());
        component.minLength = Math.min(...component.edges.map(edge => edge.len2));
        component.maxLength = Math.max(...component.edges.map(edge => edge.len2));
    }
}

function boundaryReport(before) {
    const lines = ['loops ' + before.loops.length];
    for (const loop of before.loops) lines.push(`loop ${loop.number} component ${loop.component} length ${loop.length} ${loop.kind} ${loop.filled ? 'filled' : 'kept'} vertices ${list(loop.vertices)}`);
    const nonmanifoldEdges = before.topology.edges.filter(edge => edge.faces.length >= 3);
    lines.push('nonmanifold_edges ' + nonmanifoldEdges.length);
    for (const edge of nonmanifoldEdges) lines.push(`edge ${edge.a} ${edge.b} faces ${list(edge.faces.map(index => index + 1))}`);
    const nonmanifoldVertices = [...before.topology.fans.keys()].filter(vertex => before.topology.fans.get(vertex).length >= 2).sort((a, b) => a - b);
    lines.push('nonmanifold_vertices ' + nonmanifoldVertices.length);
    for (const vertex of nonmanifoldVertices) {
        const fans = before.topology.fans.get(vertex);
        const components = uniqueSorted(fans.map(fan => before.topology.componentOf[fan[0]]));
        lines.push(`vertex ${vertex} fans ${fans.length} components ${list(components)}`);
    }
    lines.push('inconsistent_edges ' + before.inconsistent.length);
    for (const edge of before.inconsistent) lines.push(`edge ${edge.a} ${edge.b} faces ${list(edge.faces.map(index => index + 1))}`);
    return lines;
}

function vertexQuery(value, context) {
    const { vertices, topology } = context;
    if (value < 1 || value >= vertices.length) return `vertex ${value} invalid`;
    const faces = topology.vertexFaces.get(value) ?? [];
    const edges = topology.vertexEdges.get(value) ?? [];
    const fans = topology.fans.get(value) ?? [];
    const components = uniqueSorted(faces.map(index => topology.componentOf[index]));
    return `vertex ${value} at ${vertices[value].join(' ')} faces ${faces.length} valence ${edges.length} fans ${fans.length}`
        + ` boundary ${yes(edges.some(edge => edge.faces.length === 1))} components ${list(components)}`;
}

function faceQuery(value, context) {
    const { faces, topology, geometry } = context;
    if (value < 1 || value > faces.length) return `face ${value} invalid`;
    const index = value - 1;
    const face = faces[index];
    const neighbors = face.vertices.map((vertex, i) => {
        const edge = topology.edgeMap.get(edgeKey(vertex, face.vertices[(i + 1) % 3]));
        if (edge.faces.length === 1) return '-';
        if (edge.faces.length >= 3) return '*';
        return (edge.faces[0] === index ? edge.faces[1] : edge.faces[0]) + 1;
    });
    return `face ${value} vertices ${face.vertices.join(' ')} group ${face.group} polygon ${face.polygon?.number ?? '-'} line ${face.polygon?.line ?? '-'}`
        + ` component ${topology.componentOf[index]} normal ${geometry[index].normal.join(' ')} area ${real(Math.sqrt(geometry[index].q) / 2)} neighbors ${neighbors.join(' ')}`;
}

function edgeQuery(first, second, context) {
    const a = Math.min(first, second);
    const b = Math.max(first, second);
    const edge = context.topology.edgeMap.get(edgeKey(a, b));
    if (!edge) return `edge ${a} ${b} none`;
    return `edge ${a} ${b} faces ${list(edge.faces.map(index => index + 1))} kind ${edge.kind} shape ${edge.shape ?? '-'} len2 ${edge.len2}`;
}

function pointQuery(point, context) {
    const inside = [];
    let total = 0;
    for (const component of context.topology.components) {
        if (!component.solid) continue;
        const winding = measure.winding(context.faces, context.vertices, component.faces, point);
        if (winding !== 0) { inside.push(component.number); total += winding; }
    }
    return `point ${point.join(' ')} inside ${list(inside)} winding ${total}`;
}

function pathQuery(first, last, context) {
    const { vertices, topology } = context;
    if (first < 1 || first >= vertices.length || last < 1 || last >= vertices.length) return `path ${first} ${last} invalid`;
    const parent = Array(vertices.length).fill(null);
    parent[first] = first;
    const queue = [first];
    for (let head = 0; head < queue.length; head++) {
        const vertex = queue[head];
        const neighbors = (topology.vertexEdges.get(vertex) ?? []).map(edge => edge.a === vertex ? edge.b : edge.a).sort((a, b) => a - b);
        for (const next of neighbors) {
            if (parent[next] !== null) continue;
            parent[next] = vertex;
            queue.push(next);
        }
    }
    if (parent[last] === null) return `path ${first} ${last} none`;
    const path = [last];
    while (path.at(-1) !== first) path.push(parent[path.at(-1)]);
    path.reverse();
    return `path ${first} ${last} hops ${path.length - 1} vertices ${list(path)}`;
}

function viewQuery(direction, context) {
    const sides = context.geometry.map(face => dot(face.normal, direction));
    let silhouette = 0;
    for (const edge of context.topology.edges) {
        if (edge.faces.length !== 2) continue;
        const a = sides[edge.faces[0]];
        const b = sides[edge.faces[1]];
        if ((a > 0 && b < 0) || (a < 0 && b > 0)) silhouette++;
    }
    return `view ${direction.join(' ')} front ${sides.filter(value => value > 0).length} back ${sides.filter(value => value < 0).length}`
        + ` side ${sides.filter(value => value === 0).length} silhouette ${silhouette}`;
}

function queryReport(context) {
    const lines = ['[queries]'];
    for (const query of context.settings.queries) {
        const values = query.values;
        if (query.kind === 'vertex') lines.push(vertexQuery(values[0], context));
        else if (query.kind === 'face') lines.push(faceQuery(values[0], context));
        else if (query.kind === 'edge') lines.push(edgeQuery(values[0], values[1], context));
        else if (query.kind === 'point') lines.push(pointQuery(values, context));
        else if (query.kind === 'path') lines.push(pathQuery(values[0], values[1], context));
        else lines.push(viewQuery(values, context));
    }
    return lines;
}

function summaryReport(context) {
    const { model, clean, before, faces, vertices, topology, geometry } = context;
    const components = topology.components;
    const solids = components.filter(component => component.solid);
    let totalVolume = 0;
    for (const component of solids) totalVolume += component.volume6;
    const lines = ['[summary]', 'lines ' + model.lines, 'vertices ' + (model.vertices.length - 1),
        'polygons ' + model.polygons.length, 'errors ' + model.errors.length, 'ignored ' + model.ignored,
        'nonplanar_polygons ' + model.polygons.filter(polygon => polygon.nonplanar).length];
    for (const size of [...clean.polygonSizes.keys()].sort((a, b) => a - b)) lines.push(`polygon_size ${size} ${clean.polygonSizes.get(size)}`);
    lines.push('triangles ' + clean.triangles.length, 'snapped ' + clean.snapped.changed.length, 'merged ' + clean.representatives.merged);
    for (const reason of ['repeated', 'zero_area', 'duplicate']) lines.push(`removed_${reason} ${clean.removed.filter(item => item.reason === reason).length}`);
    lines.push('faces ' + before.originalFaces, 'inconsistent_before ' + before.inconsistentBefore,
        'flipped_faces ' + context.flippedFaces, 'outward_components ' + context.outwardComponents,
        'boundary_loops ' + before.loops.length, 'holes_filled ' + before.filled, 'fill_faces ' + before.fillFaces,
        'final_vertices ' + (vertices.length - 1), 'final_faces ' + faces.length, 'components ' + components.length,
        'solids ' + solids.length, 'total_area ' + real(measure.area(geometry)), 'total_volume ' + fraction(totalVolume, 6));
    return lines;
}

function warningReport(context) {
    return ['[warnings]', ...context.model.errors.map(error => `line ${error.line} ${error.kind}`)];
}

function cleanupReport(context) {
    const clean = context.clean;
    const lines = ['[cleanup]', 'snapped ' + clean.snapped.changed.length];
    for (const item of clean.snapped.changed) lines.push(`snap ${item.original} ${item.before.join(' ')} to ${item.after.join(' ')}`);
    lines.push('merged ' + clean.representatives.merged);
    for (const [representative, members] of clean.representatives.groups) {
        if (members.length >= 2) lines.push(`merge ${clean.originalToNew.get(representative) ?? '-'} ${list(members)}`);
    }
    lines.push('removed ' + clean.removed.length);
    for (const item of clean.removed) {
        const triangle = item.triangle;
        lines.push(`remove ${triangle.number} polygon ${triangle.polygon.number} line ${triangle.polygon.line} ${item.reason}`);
    }
    return lines;
}

function componentReport(context) {
    const lines = [];
    for (const component of context.topology.components) {
        lines.push(`[component ${component.number}]`, 'groups ' + list(component.groups), 'faces ' + component.faces.length,
            'vertices ' + component.vertices.length, 'edges ' + component.edges.length, 'boundary_edges ' + component.boundary.length,
            'nonmanifold_edges ' + component.nonmanifoldEdges.length, 'nonmanifold_vertices ' + component.nonmanifoldVertices.length,
            'boundary_loops ' + component.loopCount, 'closed ' + yes(component.closed), 'manifold ' + yes(component.manifold),
            'orientable ' + yes(component.orientable), 'consistent ' + yes(component.consistent), 'solid ' + yes(component.solid),
            'euler ' + component.chi);
        if (!component.manifold) lines.push('genus -');
        else if (component.orientable) lines.push('genus ' + component.genus);
        else lines.push('crosscaps ' + component.crosscaps);
        lines.push('volume ' + (component.solid ? fraction(component.volume6, 6) : '-'), 'area ' + real(component.area),
            'normal_sum ' + component.normalSum.join(' '), 'bbox ' + [...component.minimum, ...component.maximum].join(' '),
            'inside ' + (component.solid ? list(component.inside) : '-'), 'centroid ' + (component.centroid === null ? '-' : component.centroid.join(' ')));
        for (const shape of ['convex', 'concave', 'flat']) lines.push(shape + ' ' + component.shapes[shape]);
        for (const angle of ['acute', 'right', 'obtuse']) lines.push(angle + ' ' + component.angles[angle]);
        lines.push(`edge_len2 ${component.minLength} ${component.maxLength}`, `valence ${component.minDegree} ${component.maxDegree}`);
    }
    return lines;
}

function groupReport(context) {
    const { groups, model, clean, faces, geometry, topology } = context;
    const lines = [];
    for (const group of groups) {
        const polygons = model.polygons.filter(polygon => polygon.group === group);
        const triangles = clean.triangles.filter(triangle => triangle.polygon.group === group);
        const indices = faces.map((face, index) => face.group === group ? index : -1).filter(index => index >= 0);
        const components = uniqueSorted(indices.map(index => topology.componentOf[index]));
        lines.push(`[group ${group}]`, 'polygons ' + polygons.length, 'triangles ' + triangles.length,
            'nonplanar ' + polygons.filter(polygon => polygon.nonplanar).length, 'faces ' + indices.length,
            'area ' + real(measure.area(indices.map(index => geometry[index]))), 'components ' + list(components));
    }
    return lines;
}

function contactReport(context) {
    const { vertices, topology } = context;
    const components = topology.components;
    const lines = ['[contacts]'];
    for (let i = 0; i < components.length; i++) {
        const first = components[i];
        for (let j = i + 1; j < components.length; j++) {
            const second = components[j];
            if (!first.minimum.every((value, k) => value <= second.maximum[k] && second.minimum[k] <= first.maximum[k])) continue;
            const shared = first.vertices.filter(vertex => second.vertexSet.has(vertex)).length;
            let gap = null;
            for (const a of first.vertices) {
                for (const b of second.vertices) {
                    if (a === b) continue;
                    const delta = difference(vertices[a], vertices[b]);
                    const distance = dot(delta, delta);
                    if (gap === null || distance < gap) gap = distance;
                }
            }
            lines.push(`contact ${first.number} ${second.number} shared ${shared} gap2 ${gap}`);
        }
    }
    return lines;
}

function edgeReport(context) {
    const edges = context.topology.edges;
    const lines = ['[edges]', 'edges ' + edges.length];
    for (const kind of ['boundary', 'manifold', 'nonmanifold']) lines.push(kind + ' ' + edges.filter(edge => edge.kind === kind).length);
    lines.push('max_faces ' + Math.max(...edges.map(edge => edge.faces.length)));
    for (const shape of ['convex', 'concave', 'flat', 'inconsistent']) lines.push(shape + ' ' + edges.filter(edge => edge.shape === shape).length);
    let shortest = edges[0];
    let longest = edges[0];
    for (const edge of edges) {
        if (edge.len2 < shortest.len2) shortest = edge;
        if (edge.len2 > longest.len2) longest = edge;
    }
    lines.push(`shortest ${shortest.a} ${shortest.b} len2 ${shortest.len2}`, `longest ${longest.a} ${longest.b} len2 ${longest.len2}`);
    return lines;
}

function valenceReport(context) {
    const degrees = [...context.topology.vertexEdges.values()].map(edges => edges.length);
    const histogram = new Map();
    let total = 0;
    for (const degree of degrees) {
        histogram.set(degree, (histogram.get(degree) ?? 0) + 1);
        total += degree;
    }
    const lines = ['[valence]', 'used ' + degrees.length, 'isolated ' + (context.vertices.length - 1 - degrees.length),
        'min ' + Math.min(...degrees), 'max ' + Math.max(...degrees), 'mean ' + fraction(total, degrees.length)];
    for (const degree of [...histogram.keys()].sort((a, b) => a - b)) lines.push(`degree ${degree} ${histogram.get(degree)}`);
    return lines;
}

function componentsCsv(context) {
    return ['component,faces,vertices,closed,euler,genus,volume6,area', ...context.topology.components.map(component =>
        [component.number, component.faces.length, component.vertices.length, yes(component.closed), component.chi,
            component.genus ?? '-', component.solid ? component.volume6 : '-', real(component.area)].join(','))];
}

function writeLines(name, lines) {
    fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

function main() {
    const settings = readParameters();
    const model = readModel();
    const clean = cleanup(model, settings);
    const { vertices, faces } = clean;
    const before = prepareAndFill(faces, settings);
    const groups = model.groups.slice();
    if (before.fillFaces > 0) groups.push('fill');
    const boundaries = boundaryReport(before);
    const topology = analyze(faces);
    componentProperties(faces, topology);
    const outwardComponents = nestAndOrient(faces, vertices, topology, settings);
    const geometry = faces.map(face => measure.faceGeometry(face, vertices));
    measureEdges(faces, vertices, topology, geometry);
    measureComponents(faces, vertices, topology, geometry, groups);
    const flippedFaces = faces.slice(0, before.originalFaces).filter(face =>
        face.vertices.some((vertex, i) => vertex !== face.initial[i])).length;
    const context = { settings, model, clean, before, groups, vertices, faces, topology, geometry, outwardComponents, flippedFaces };
    const sections = { summary: summaryReport, warnings: warningReport, cleanup: cleanupReport, components: componentReport,
        groups: groupReport, contacts: contactReport, edges: edgeReport, valence: valenceReport, queries: queryReport };
    const report = [];
    for (const name of settings.sections) report.push(...sections[name](context));
    fs.mkdirSync('output', { recursive: true });
    writeLines('report.txt', report);
    writeLines('components.csv', componentsCsv(context));
    writeLines('boundaries.txt', boundaries);
    writeModel(vertices, faces);
}

if (require.main === module) main();
