import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { readModel, writeModel, type Face, type Polygon, type Triple } from './obj_io.ts';
import {
  edgeKey,
  analyze,
  boundaryLoops,
  type Edge,
  type Component,
  type Loop,
  type Topology,
} from './topology.ts';
import { containsDirection, flip, inconsistentEdges, orient } from './orientation.ts';
import * as measure from './measure.ts';
import {
  difference,
  add,
  dot,
  cross,
  fraction,
  real,
  type Geometry,
  type Angle,
} from './measure.ts';
import * as repair from './repair.ts';

interface Settings {
  snap: number;
  merge: boolean;
  degenerate: boolean;
  duplicates: boolean;
  orient: boolean;
  outward: boolean;
  fillHoles: number;
  keepUnused: boolean;
  sections: string[];
  queries: { kind: string; values: number[] }[];
}
interface CoherentLoop extends Loop {
  kind: 'coherent' | 'mixed' | 'open';
  filled: boolean;
}
type Shape = 'convex' | 'concave' | 'flat' | 'inconsistent';
interface EdgeMeasure {
  len2: number;
  kind: 'boundary' | 'manifold' | 'nonmanifold';
  shape: Shape | null;
}
interface ComponentInfo extends Component {
  boundary: Edge[];
  nonmanifoldEdges: Edge[];
  nonmanifoldVertices: number[];
  loopCount: number;
  closed: boolean;
  manifold: boolean;
  consistent: boolean;
  solid: boolean;
  orientable: boolean;
  chi: number;
  inside: number[];
  genus: number | null;
  crosscaps: number | null;
  groups: string[];
  area: number;
  volume6: number;
  normalSum: Triple;
  angles: Record<Angle, number>;
  centroid: string[] | null;
  minimum: Triple;
  maximum: Triple;
  shapes: Record<'convex' | 'concave' | 'flat', number>;
  minDegree: number;
  maxDegree: number;
  minLength: number;
  maxLength: number;
}
const list = (values: readonly (number | string)[]): string =>
  values.length ? values.join(' ') : '-';
const yes = (value: boolean): string => (value ? 'yes' : 'no');
const uniqueSorted = (values: number[]): number[] => [...new Set(values)].sort((a, b) => a - b);
function readParameters(): Settings {
  const settings: Settings = {
    snap: 1,
    merge: true,
    degenerate: true,
    duplicates: true,
    orient: true,
    outward: true,
    fillHoles: 0,
    keepUnused: true,
    sections: ['summary', 'components'],
    queries: [],
  };
  for (const line of readFileSync('input/params.txt', 'ascii').split('\n')) {
    if (line === '' || line.startsWith('#')) continue;
    const [name, ...values] = line.split(' ');
    if (name === 'query') {
      settings.queries.push({ kind: values[0], values: values.slice(1).map(Number) });
    } else if (name === 'sections') settings.sections = values;
    else if (name === 'snap') settings.snap = Number(values[0]);
    else if (name === 'fill_holes') settings.fillHoles = Number(values[0]);
    else if (name === 'keep_unused') settings.keepUnused = values[0] === 'on';
    else if (
      name === 'merge' ||
      name === 'degenerate' ||
      name === 'duplicates' ||
      name === 'orient' ||
      name === 'outward'
    ) {
      settings[name] = values[0] === 'on';
    }
  }
  return settings;
}
function nonplanar(polygon: Polygon, positions: Triple[]): boolean {
  const vertices = polygon.vertices.map((v) => positions[v]);
  let normal: Triple = [0, 0, 0];
  for (let i = 1; i < vertices.length - 1; i++) {
    normal = add(
      normal,
      cross(difference(vertices[i], vertices[0]), difference(vertices[i + 1], vertices[0])),
    );
  }
  return vertices.some((v) => dot(difference(v, vertices[0]), normal) !== 0);
}
function cleanup(model: ReturnType<typeof readModel>, settings: Settings) {
  const triangles = repair.triangulate(model.polygons);
  const snapped = repair.snap(model.vertices, settings.snap);
  const representatives = repair.representatives(snapped.positions, settings.merge);
  const removal = repair.removeTriangles(
    triangles,
    representatives.numbers,
    snapped.positions,
    settings,
  );
  const used = new Set(removal.faces.flatMap((face) => face.vertices));
  const originalToNew = new Map<number, number>();
  const vertices: Triple[] = [[0, 0, 0]];
  for (let original = 1; original < model.vertices.length; original++) {
    if (
      !(settings.keepUnused ? representatives.numbers[original] === original : used.has(original))
    ) {
      continue;
    }
    originalToNew.set(original, vertices.length);
    vertices.push(snapped.positions[original]);
  }
  const faces: Face[] = removal.faces.map((face, i): Face => {
    const [a, b, c] = face.vertices;
    const sequence: Triple = [originalToNew.get(a)!, originalToNew.get(b)!, originalToNew.get(c)!];
    return { ...face, number: i + 1, vertices: sequence, initial: [...sequence] };
  });
  const polygonSizes = new Map<number, number>();
  for (const polygon of model.polygons) {
    polygon.nonplanar = nonplanar(polygon, snapped.positions);
    const size = polygon.vertices.length;
    polygonSizes.set(size, (polygonSizes.get(size) ?? 0) + 1);
  }
  return {
    triangles,
    snapped,
    representatives,
    removed: removal.removed,
    originalToNew,
    vertices,
    faces,
    polygonSizes,
  };
}
function coherentLoops(faces: Face[], topology: Topology): CoherentLoop[] {
  return boundaryLoops(topology).map((loop) => {
    let kind: CoherentLoop['kind'] = 'open';
    if (loop.closed) {
      let agreeing = 0;
      for (let i = 0; i < loop.length; i++) {
        const a = loop.vertices[i];
        const b = loop.vertices[(i + 1) % loop.length];
        const edge = topology.edgeMap.get(edgeKey(a, b))!;
        if (containsDirection(faces[edge.faces[0]], a, b)) agreeing++;
      }
      kind = agreeing === 0 || agreeing === loop.length ? 'coherent' : 'mixed';
      if (agreeing === 0) loop.vertices = [loop.vertices[0], ...loop.vertices.slice(1).reverse()];
    }
    return { ...loop, kind, filled: false };
  });
}
function prepareAndFill(faces: Face[], settings: Settings) {
  const originalFaces = faces.length;
  const topology = analyze(faces);
  const inconsistentBefore = inconsistentEdges(faces, topology).length;
  if (settings.orient) orient(faces, topology);
  const inconsistent = inconsistentEdges(faces, topology);
  const loops = coherentLoops(faces, topology);
  const blocked = new Set(
    [...topology.edges.filter((edge) => edge.faces.length >= 3), ...inconsistent].map(
      (edge) => topology.componentOf[edge.faces[0]],
    ),
  );
  let filled = 0;
  for (const loop of loops) {
    loop.filled =
      loop.kind === 'coherent' &&
      loop.length >= 3 &&
      loop.length <= settings.fillHoles &&
      new Set(loop.vertices).size === loop.length &&
      !blocked.has(loop.component);
    if (!loop.filled) continue;
    filled++;
    for (const face of repair.fillTriangles(loop.vertices)) {
      face.number = faces.length + 1;
      faces.push(face);
    }
  }
  return {
    topology,
    inconsistentBefore,
    inconsistent,
    loops,
    originalFaces,
    filled,
    fillFaces: faces.length - originalFaces,
  };
}
function componentProperties(faces: Face[], topology: Topology): ComponentInfo[] {
  const loops = coherentLoops(faces, topology);
  const inconsistent = new Set(inconsistentEdges(faces, topology).map((edge) => edge.key));
  return topology.components.map((component): ComponentInfo => {
    const boundary = component.edges.filter((edge) => edge.faces.length === 1);
    const nonmanifoldEdges = component.edges.filter((edge) => edge.faces.length >= 3);
    const nonmanifoldVertices = component.vertices.filter(
      (v) =>
        topology.fans.get(v)!.filter((fan) => topology.componentOf[fan[0]] === component.number)
          .length >= 2,
    );
    const closed = boundary.length === 0;
    const manifold = nonmanifoldEdges.length === 0 && nonmanifoldVertices.length === 0;
    const consistent = !component.edges.some((edge) => inconsistent.has(edge.key));
    return {
      ...component,
      boundary,
      nonmanifoldEdges,
      nonmanifoldVertices,
      loopCount: loops.filter((loop) => loop.component === component.number).length,
      closed,
      manifold,
      consistent,
      solid: closed && manifold && consistent,
      orientable: false,
      chi: component.vertices.length - component.edges.length + component.faces.length,
      inside: [],
      genus: null,
      crosscaps: null,
      groups: [],
      area: 0,
      volume6: 0,
      normalSum: [0, 0, 0],
      angles: { acute: 0, right: 0, obtuse: 0 },
      centroid: null,
      minimum: [0, 0, 0],
      maximum: [0, 0, 0],
      shapes: { convex: 0, concave: 0, flat: 0 },
      minDegree: 0,
      maxDegree: 0,
      minLength: 0,
      maxLength: 0,
    };
  });
}
function nestAndOrient(
  faces: Face[],
  vertices: Triple[],
  topology: Topology,
  components: ComponentInfo[],
  settings: Settings,
): number {
  const solids = components.filter((c) => c.solid);
  for (const c of solids) {
    for (const d of solids) {
      if (c === d) continue;
      const vertex = c.vertices.find((v) => !d.vertexSet.has(v));
      if (
        vertex !== undefined &&
        measure.winding(faces, vertices, d.faces, vertices[vertex]) !== 0
      ) {
        c.inside.push(d.number);
      }
    }
  }
  let outward = 0;
  if (settings.outward) {
    for (const c of solids) {
      const volume = measure.volume6(faces, vertices, c.faces);
      const reverse = c.inside.length % 2 === 0 ? volume < 0 : volume > 0;
      if (volume !== 0 && reverse) {
        for (const index of c.faces) flip(faces[index]);
        outward++;
      }
    }
  }
  const copy = faces.map((face): Face => ({ ...face, vertices: [...face.vertices] }));
  orient(copy, topology);
  const inconsistent = new Set(inconsistentEdges(copy, topology).map((edge) => edge.key));
  for (const c of components) {
    c.orientable = !c.edges.some((edge) => inconsistent.has(edge.key));
    c.genus = c.manifold && c.orientable ? (2 - c.chi - c.loopCount) / 2 : null;
    c.crosscaps = c.manifold && !c.orientable ? 2 - c.chi - c.loopCount : null;
  }
  return outward;
}
function measureEdges(
  faces: Face[],
  vertices: Triple[],
  topology: Topology,
  geometry: Geometry[],
): Map<string, EdgeMeasure> {
  const result = new Map<string, EdgeMeasure>();
  for (const edge of topology.edges) {
    const delta = difference(vertices[edge.a], vertices[edge.b]);
    const len2 = dot(delta, delta);
    const kind =
      edge.faces.length === 1 ? 'boundary' : edge.faces.length === 2 ? 'manifold' : 'nonmanifold';
    let shape: Shape | null = null;
    if (kind === 'manifold') {
      const [f, g] = edge.faces;
      if (
        containsDirection(faces[f], edge.a, edge.b) === containsDirection(faces[g], edge.a, edge.b)
      ) {
        shape = 'inconsistent';
      } else {
        const opposite = faces[g].vertices.find((v) => v !== edge.a && v !== edge.b)!;
        const side = dot(
          difference(vertices[opposite], vertices[faces[f].vertices[0]]),
          geometry[f].normal,
        );
        shape = side < 0 ? 'convex' : side > 0 ? 'concave' : 'flat';
      }
    }
    result.set(edge.key, { len2, kind, shape });
  }
  return result;
}
function measureComponents(
  faces: Face[],
  vertices: Triple[],
  components: ComponentInfo[],
  geometry: Geometry[],
  groups: string[],
  edges: Map<string, EdgeMeasure>,
): void {
  for (const c of components) {
    const names = new Set(c.faces.map((i) => faces[i].group));
    c.groups = groups.filter((group) => names.has(group));
    c.area = measure.area(c.faces.map((i) => geometry[i]));
    for (const i of c.faces) {
      c.volume6 += geometry[i].determinant;
      c.normalSum = add(c.normalSum, geometry[i].normal);
      c.angles[geometry[i].angle]++;
    }
    c.centroid =
      c.solid && c.volume6 !== 0
        ? measure.centroid(faces, vertices, c.faces, geometry, c.volume6)
        : null;
    c.minimum = [...vertices[c.vertices[0]]];
    c.maximum = [...vertices[c.vertices[0]]];
    for (const v of c.vertices) {
      for (let k = 0; k < 3; k++) {
        c.minimum[k] = Math.min(c.minimum[k], vertices[v][k]);
        c.maximum[k] = Math.max(c.maximum[k], vertices[v][k]);
      }
    }
    const degrees = new Map(c.vertices.map((v) => [v, 0]));
    for (const edge of c.edges) {
      const shape = edges.get(edge.key)!.shape;
      if (shape === 'convex' || shape === 'concave' || shape === 'flat') c.shapes[shape]++;
      degrees.set(edge.a, degrees.get(edge.a)! + 1);
      degrees.set(edge.b, degrees.get(edge.b)! + 1);
    }
    c.minDegree = Math.min(...degrees.values());
    c.maxDegree = Math.max(...degrees.values());
    c.minLength = Math.min(...c.edges.map((e) => edges.get(e.key)!.len2));
    c.maxLength = Math.max(...c.edges.map((e) => edges.get(e.key)!.len2));
  }
}
function buildContext() {
  const settings = readParameters();
  const model = readModel();
  const clean = cleanup(model, settings);
  const { vertices, faces } = clean;
  const before = prepareAndFill(faces, settings);
  const groups = model.groups.slice();
  if (before.fillFaces) groups.push('fill');
  const topology = analyze(faces);
  const components = componentProperties(faces, topology);
  const outwardComponents = nestAndOrient(faces, vertices, topology, components, settings);
  const geometry = faces.map((face) => measure.faceGeometry(face, vertices));
  const edgeMeasures = measureEdges(faces, vertices, topology, geometry);
  measureComponents(faces, vertices, components, geometry, groups, edgeMeasures);
  const flippedFaces = faces
    .slice(0, before.originalFaces)
    .filter((face) => face.vertices.some((v, i) => v !== face.initial![i])).length;
  return {
    settings,
    model,
    clean,
    vertices,
    faces,
    before,
    groups,
    topology,
    components,
    outwardComponents,
    flippedFaces,
    geometry,
    edgeMeasures,
  };
}
type Context = ReturnType<typeof buildContext>;
function boundaryReport(before: Context['before']): string[] {
  const lines = ['loops ' + before.loops.length];
  for (const l of before.loops) {
    lines.push(
      `loop ${l.number} component ${l.component} length ${l.length} ${l.kind} ${l.filled ? 'filled' : 'kept'} vertices ${list(l.vertices)}`,
    );
  }
  const nonmanifold = before.topology.edges.filter((e) => e.faces.length >= 3);
  lines.push('nonmanifold_edges ' + nonmanifold.length);
  for (const e of nonmanifold) {
    lines.push(`edge ${e.a} ${e.b} faces ${list(e.faces.map((i) => i + 1))}`);
  }
  const vertices = [...before.topology.fans.keys()]
    .filter((v) => before.topology.fans.get(v)!.length >= 2)
    .sort((a, b) => a - b);
  lines.push('nonmanifold_vertices ' + vertices.length);
  for (const v of vertices) {
    const fans = before.topology.fans.get(v)!;
    lines.push(
      `vertex ${v} fans ${fans.length} components ${list(uniqueSorted(fans.map((fan) => before.topology.componentOf[fan[0]])))}`,
    );
  }
  lines.push('inconsistent_edges ' + before.inconsistent.length);
  for (const e of before.inconsistent) {
    lines.push(`edge ${e.a} ${e.b} faces ${list(e.faces.map((i) => i + 1))}`);
  }
  return lines;
}
function queryReport(context: Context): string[] {
  const { vertices, faces, topology: t, geometry, components, edgeMeasures } = context;
  const lines = ['[queries]'];
  for (const query of context.settings.queries) {
    const [u, v, z] = query.values;
    if (query.kind === 'vertex') {
      if (u < 1 || u >= vertices.length) {
        lines.push(`vertex ${u} invalid`);
        continue;
      }
      const incident = t.vertexFaces.get(u) ?? [];
      const edges = t.vertexEdges.get(u) ?? [];
      const fans = t.fans.get(u) ?? [];
      lines.push(
        `vertex ${u} at ${list(vertices[u])} faces ${incident.length} valence ${edges.length} fans ${fans.length} boundary ${yes(edges.some((e) => e.faces.length === 1))} components ${list(uniqueSorted(incident.map((i) => t.componentOf[i])))}`,
      );
    } else if (query.kind === 'face') {
      if (u < 1 || u > faces.length) {
        lines.push(`face ${u} invalid`);
        continue;
      }
      const i = u - 1;
      const face = faces[i];
      const neighbors = face.vertices.map((a, k) => {
        const edge = t.edgeMap.get(edgeKey(a, face.vertices[(k + 1) % 3]))!;
        return edge.faces.length === 1
          ? '-'
          : edge.faces.length >= 3
            ? '*'
            : (edge.faces[0] === i ? edge.faces[1] : edge.faces[0]) + 1;
      });
      lines.push(
        `face ${u} vertices ${list(face.vertices)} group ${face.group} polygon ${face.polygon?.number ?? '-'} line ${face.polygon?.line ?? '-'} component ${t.componentOf[i]} normal ${list(geometry[i].normal)} area ${real(Math.sqrt(geometry[i].q) / 2)} neighbors ${list(neighbors)}`,
      );
    } else if (query.kind === 'edge') {
      const a = Math.min(u, v);
      const b = Math.max(u, v);
      const edge = t.edgeMap.get(edgeKey(a, b));
      if (edge === undefined) lines.push(`edge ${a} ${b} none`);
      else {
        const m = edgeMeasures.get(edge.key)!;
        lines.push(
          `edge ${a} ${b} faces ${list(edge.faces.map((i) => i + 1))} kind ${m.kind} shape ${m.shape ?? '-'} len2 ${m.len2}`,
        );
      }
    } else if (query.kind === 'point') {
      const point: Triple = [u, v, z];
      const inside: number[] = [];
      let total = 0;
      for (const c of components) {
        if (c.solid) {
          const w = measure.winding(faces, vertices, c.faces, point);
          if (w !== 0) {
            inside.push(c.number);
            total += w;
          }
        }
      }
      lines.push(`point ${list(point)} inside ${list(inside)} winding ${total}`);
    } else if (query.kind === 'path') {
      if (u < 1 || u >= vertices.length || v < 1 || v >= vertices.length) {
        lines.push(`path ${u} ${v} invalid`);
        continue;
      }
      const parent: (number | null)[] = Array(vertices.length).fill(null);
      const queue = [u];
      parent[u] = u;
      for (let head = 0; head < queue.length; head++) {
        const w = queue[head];
        const neighbors = (t.vertexEdges.get(w) ?? [])
          .map((e) => (e.a === w ? e.b : e.a))
          .sort((a, b) => a - b);
        for (const next of neighbors) {
          if (parent[next] === null) {
            parent[next] = w;
            queue.push(next);
          }
        }
      }
      if (parent[v] === null) lines.push(`path ${u} ${v} none`);
      else {
        const path = [v];
        while (path[path.length - 1] !== u) path.push(parent[path[path.length - 1]]!);
        path.reverse();
        lines.push(`path ${u} ${v} hops ${path.length - 1} vertices ${list(path)}`);
      }
    } else {
      const direction: Triple = [u, v, z];
      const sides = geometry.map((g) => dot(g.normal, direction));
      let silhouette = 0;
      for (const e of t.edges) {
        if (e.faces.length === 2) {
          const a = sides[e.faces[0]];
          const b = sides[e.faces[1]];
          if ((a > 0 && b < 0) || (a < 0 && b > 0)) silhouette++;
        }
      }
      lines.push(
        `view ${list(direction)} front ${sides.filter((s) => s > 0).length} back ${sides.filter((s) => s < 0).length} side ${sides.filter((s) => s === 0).length} silhouette ${silhouette}`,
      );
    }
  }
  return lines;
}
function summaryReport(c: Context): string[] {
  const { model, clean, before, faces, vertices, components, geometry } = c;
  const solids = components.filter((s) => s.solid);
  let volume = 0;
  for (const s of solids) volume += s.volume6;
  const lines = [
    '[summary]',
    `lines ${model.lines}`,
    `vertices ${model.vertices.length - 1}`,
    `polygons ${model.polygons.length}`,
    `errors ${model.errors.length}`,
    `ignored ${model.ignored}`,
    `nonplanar_polygons ${model.polygons.filter((p) => p.nonplanar).length}`,
  ];
  for (const size of [...clean.polygonSizes.keys()].sort((a, b) => a - b)) {
    lines.push(`polygon_size ${size} ${clean.polygonSizes.get(size)}`);
  }
  lines.push(
    `triangles ${clean.triangles.length}`,
    `snapped ${clean.snapped.changed.length}`,
    `merged ${clean.representatives.merged}`,
  );
  for (const reason of ['repeated', 'zero_area', 'duplicate']) {
    lines.push(`removed_${reason} ${clean.removed.filter((r) => r.reason === reason).length}`);
  }
  lines.push(
    `faces ${before.originalFaces}`,
    `inconsistent_before ${before.inconsistentBefore}`,
    `flipped_faces ${c.flippedFaces}`,
    `outward_components ${c.outwardComponents}`,
    `boundary_loops ${before.loops.length}`,
    `holes_filled ${before.filled}`,
    `fill_faces ${before.fillFaces}`,
    `final_vertices ${vertices.length - 1}`,
    `final_faces ${faces.length}`,
    `components ${components.length}`,
    `solids ${solids.length}`,
    `total_area ${real(measure.area(geometry))}`,
    `total_volume ${fraction(volume, 6)}`,
  );
  return lines;
}
function cleanupReport(context: Context): string[] {
  const c = context.clean;
  const lines = ['[cleanup]', `snapped ${c.snapped.changed.length}`];
  for (const s of c.snapped.changed) {
    lines.push(`snap ${s.original} ${list(s.before)} to ${list(s.after)}`);
  }
  lines.push(`merged ${c.representatives.merged}`);
  for (const [r, members] of c.representatives.groups) {
    if (members.length >= 2) lines.push(`merge ${c.originalToNew.get(r) ?? '-'} ${list(members)}`);
  }
  lines.push(`removed ${c.removed.length}`);
  for (const r of c.removed) {
    lines.push(
      `remove ${r.triangle.number} polygon ${r.triangle.polygon.number} line ${r.triangle.polygon.line} ${r.reason}`,
    );
  }
  return lines;
}
function componentReport(context: Context): string[] {
  const lines: string[] = [];
  for (const c of context.components) {
    lines.push(
      `[component ${c.number}]`,
      `groups ${list(c.groups)}`,
      `faces ${c.faces.length}`,
      `vertices ${c.vertices.length}`,
      `edges ${c.edges.length}`,
      `boundary_edges ${c.boundary.length}`,
      `nonmanifold_edges ${c.nonmanifoldEdges.length}`,
      `nonmanifold_vertices ${c.nonmanifoldVertices.length}`,
      `boundary_loops ${c.loopCount}`,
      `closed ${yes(c.closed)}`,
      `manifold ${yes(c.manifold)}`,
      `orientable ${yes(c.orientable)}`,
      `consistent ${yes(c.consistent)}`,
      `solid ${yes(c.solid)}`,
      `euler ${c.chi}`,
    );
    lines.push(
      !c.manifold ? 'genus -' : c.orientable ? `genus ${c.genus}` : `crosscaps ${c.crosscaps}`,
      `volume ${c.solid ? fraction(c.volume6, 6) : '-'}`,
      `area ${real(c.area)}`,
      `normal_sum ${list(c.normalSum)}`,
      `bbox ${list([...c.minimum, ...c.maximum])}`,
      `inside ${c.solid ? list(c.inside) : '-'}`,
      `centroid ${c.centroid === null ? '-' : list(c.centroid)}`,
    );
    for (const shape of ['convex', 'concave', 'flat'] as const) {
      lines.push(`${shape} ${c.shapes[shape]}`);
    }
    for (const angle of ['acute', 'right', 'obtuse'] as const) {
      lines.push(`${angle} ${c.angles[angle]}`);
    }
    lines.push(`edge_len2 ${c.minLength} ${c.maxLength}`, `valence ${c.minDegree} ${c.maxDegree}`);
  }
  return lines;
}
function groupReport(c: Context): string[] {
  const lines: string[] = [];
  for (const group of c.groups) {
    const polygons = c.model.polygons.filter((p) => p.group === group);
    const triangles = c.clean.triangles.filter((t) => t.polygon.group === group);
    const indices = c.faces.map((f, i) => (f.group === group ? i : -1)).filter((i) => i >= 0);
    lines.push(
      `[group ${group}]`,
      `polygons ${polygons.length}`,
      `triangles ${triangles.length}`,
      `nonplanar ${polygons.filter((p) => p.nonplanar).length}`,
      `faces ${indices.length}`,
      `area ${real(measure.area(indices.map((i) => c.geometry[i])))}`,
      `components ${list(uniqueSorted(indices.map((i) => c.topology.componentOf[i])))}`,
    );
  }
  return lines;
}
function contactReport(c: Context): string[] {
  const lines = ['[contacts]'];
  for (let i = 0; i < c.components.length; i++) {
    for (let j = i + 1; j < c.components.length; j++) {
      const a = c.components[i];
      const b = c.components[j];
      if (!a.minimum.every((v, k) => v <= b.maximum[k] && b.minimum[k] <= a.maximum[k])) continue;
      let gap = Infinity;
      for (const u of a.vertices) {
        for (const v of b.vertices) {
          if (u !== v) {
            const delta = difference(c.vertices[u], c.vertices[v]);
            gap = Math.min(gap, dot(delta, delta));
          }
        }
      }
      lines.push(
        `contact ${a.number} ${b.number} shared ${a.vertices.filter((v) => b.vertexSet.has(v)).length} gap2 ${gap}`,
      );
    }
  }
  return lines;
}
function edgeReport(c: Context): string[] {
  const edges = c.topology.edges;
  const measured = c.edgeMeasures;
  const lines = ['[edges]', `edges ${edges.length}`];
  for (const kind of ['boundary', 'manifold', 'nonmanifold']) {
    lines.push(`${kind} ${edges.filter((e) => measured.get(e.key)!.kind === kind).length}`);
  }
  lines.push('max_faces ' + Math.max(...edges.map((e) => e.faces.length)));
  for (const shape of ['convex', 'concave', 'flat', 'inconsistent']) {
    lines.push(`${shape} ${edges.filter((e) => measured.get(e.key)!.shape === shape).length}`);
  }
  let shortest = edges[0];
  let longest = edges[0];
  for (const edge of edges) {
    if (measured.get(edge.key)!.len2 < measured.get(shortest.key)!.len2) shortest = edge;
    if (measured.get(edge.key)!.len2 > measured.get(longest.key)!.len2) longest = edge;
  }
  lines.push(
    `shortest ${shortest.a} ${shortest.b} len2 ${measured.get(shortest.key)!.len2}`,
    `longest ${longest.a} ${longest.b} len2 ${measured.get(longest.key)!.len2}`,
  );
  return lines;
}
function valenceReport(c: Context): string[] {
  const degrees = [...c.topology.vertexEdges.values()].map((edges) => edges.length);
  const histogram = new Map<number, number>();
  let total = 0;
  for (const d of degrees) {
    histogram.set(d, (histogram.get(d) ?? 0) + 1);
    total += d;
  }
  const lines = [
    '[valence]',
    `used ${degrees.length}`,
    `isolated ${c.vertices.length - 1 - degrees.length}`,
    `min ${Math.min(...degrees)}`,
    `max ${Math.max(...degrees)}`,
    `mean ${fraction(total, degrees.length)}`,
  ];
  for (const d of [...histogram.keys()].sort((a, b) => a - b)) {
    lines.push(`degree ${d} ${histogram.get(d)}`);
  }
  return lines;
}
function componentsCsv(c: Context): string[] {
  return [
    'component,faces,vertices,closed,euler,genus,volume6,area',
    ...c.components.map((p) =>
      [
        p.number,
        p.faces.length,
        p.vertices.length,
        yes(p.closed),
        p.chi,
        p.genus ?? '-',
        p.solid ? p.volume6 : '-',
        real(p.area),
      ].join(','),
    ),
  ];
}
function main(): void {
  const context = buildContext();
  const sections: Record<string, (c: Context) => string[]> = {
    summary: summaryReport,
    warnings: (c) => ['[warnings]', ...c.model.errors.map((e) => `line ${e.line} ${e.kind}`)],
    cleanup: cleanupReport,
    components: componentReport,
    groups: groupReport,
    contacts: contactReport,
    edges: edgeReport,
    valence: valenceReport,
    queries: queryReport,
  };
  const report = context.settings.sections.flatMap((section) => sections[section](context));
  mkdirSync('output', { recursive: true });
  const outputs: [string, string[]][] = [
    ['report.txt', report],
    ['components.csv', componentsCsv(context)],
    ['boundaries.txt', boundaryReport(context.before)],
  ];
  for (const [name, lines] of outputs) {
    writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
  }
  writeModel(context.vertices, context.faces);
}
main();
