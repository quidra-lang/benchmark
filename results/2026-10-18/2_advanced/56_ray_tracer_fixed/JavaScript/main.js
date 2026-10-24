'use strict';

const fs = require('fs');
const { S, div, mul } = require('./fixed_point');
const vector = require('./vector3');
const { readScene } = require('./scene');
const intersect = require('./intersect');
const shading = require('./shading');

const kinds = ['primary', 'reflection', 'refraction', 'shadow'];
const triple = values => values.join(' ');
const readLines = path => fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
const writeLines = (name, lines) => fs.writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');

function unionBox(objects) {
  return {
    lo: [0, 1, 2].map(axis => Math.min(...objects.map(object => object.bounds.lo[axis]))),
    hi: [0, 1, 2].map(axis => Math.max(...objects.map(object => object.bounds.hi[axis])))
  };
}

function area(objects) {
  const box = unionBox(objects), [dx, dy, dz] = vector.sub(box.hi, box.lo);
  return dx * dy + dy * dz + dz * dx;
}

function buildBVH(objects, depth, nodes) {
  const node = { ...unionBox(objects), depth, visits: 0, objects: null, left: null, right: null };
  nodes.push(node);
  if (objects.length <= 2) {
    node.objects = objects.slice().sort((a, b) => a.number - b.number);
    for (const object of node.objects) object.leaf = node;
    return node;
  }
  let best = null;
  for (let axis = 0; axis < 3; axis++) {
    const ordered = objects.slice().sort((a, b) =>
      div(a.bounds.lo[axis] + a.bounds.hi[axis], 2) - div(b.bounds.lo[axis] + b.bounds.hi[axis], 2) || a.number - b.number);
    for (let i = 1; i < ordered.length; i++) {
      const left = ordered.slice(0, i), right = ordered.slice(i);
      const cost = area(left) * left.length + area(right) * right.length;
      if (!best || cost < best.cost) best = { cost, left, right };
    }
  }
  node.left = buildBVH(best.left, depth + 1, nodes);
  node.right = buildBVH(best.right, depth + 1, nodes);
  return node;
}

function readSettings() {
  const values = readLines('input/render.txt').map(line => line.split(' ').slice(1).map(Number));
  return { width: values[0][0], height: values[0][1], contrast: values[1][0], depth: values[2][0],
    far: values[3][0], epsilon: values[4][0], pad: values[5][0] };
}

class Renderer {
  constructor(scene, settings) {
    this.scene = scene;
    this.settings = settings;
    this.nodes = [];
    this.rays = Object.fromEntries(kinds.map(kind => [kind, 0]));
    this.misses = { primary: 0, reflection: 0, refraction: 0 };
    this.depthCounts = Array(settings.depth + 1).fill(0);
    this.tests = Object.fromEntries(kinds.map(kind => [kind, { nodes: 0, objects: 0 }]));
    this.totalInternal = 0;
    this.clamped = 0;
    this.supersampled = 0;
    for (const object of scene.objects) {
      object.bounds = intersect.bounds(object, settings.pad);
      object.counts = { primary: 0, secondary: 0, shadow: 0 };
    }
    for (const light of scene.lights) {
      light.counts = { pixels: 0, shadowRays: 0, blocked: 0, attenuated: 0, backfacing: 0, outside: 0 };
    }
    const bounded = scene.objects.filter(object => object.bounds);
    this.root = bounded.length ? buildBVH(bounded, 0, this.nodes) : null;
    this.planes = scene.objects.filter(object => object.kind === 'plane');
    this.pixels = [];
  }

  testNode(node, origin, direction, kind, context) {
    if (context.render) { this.tests[kind].nodes++; node.visits++; }
    return intersect.slab(node.lo, node.hi, origin, direction);
  }

  testObject(object, origin, direction, kind, context) {
    if (context.render) this.tests[kind].objects++;
    return intersect.candidate(object, origin, direction, this.settings.epsilon);
  }

  nearest(origin, direction, kind, context) {
    let best = null;
    const test = object => {
      const result = this.testObject(object, origin, direction, kind, context);
      if (result && result.t <= this.settings.far && (!best || result.t < best.t ||
          (result.t === best.t && object.number < best.object.number))) best = { ...result, object };
    };
    const visit = node => {
      const result = this.testNode(node, origin, direction, kind, context);
      if (!result || result.far <= this.settings.epsilon || result.near > this.settings.far ||
          (best && result.near > best.t)) return;
      if (node.objects) for (const object of node.objects) test(object);
      else { visit(node.left); visit(node.right); }
    };
    for (const plane of this.planes) test(plane);
    if (this.root) visit(this.root);
    return best;
  }

  occluders(origin, direction, distance, context) {
    const result = [];
    const test = object => {
      const hit = this.testObject(object, origin, direction, 'shadow', context);
      if (hit && hit.t < distance) result.push(object);
    };
    const visit = node => {
      const hit = this.testNode(node, origin, direction, 'shadow', context);
      if (!hit || hit.far <= this.settings.epsilon || hit.near >= distance) return;
      if (node.objects) for (const object of node.objects) test(object);
      else { visit(node.left); visit(node.right); }
    };
    for (const plane of this.planes) test(plane);
    if (this.root) visit(this.root);
    result.sort((a, b) => a.number - b.number);
    if (context.render) for (const object of result) object.counts.shadow++;
    return result;
  }

  camera(qx, qy) {
    const { width, height } = this.settings, scene = this.scene;
    const u = div((qx - 2 * width) * scene.view[0], 2 * width);
    const v = div((2 * height - qy) * scene.view[1], 2 * height);
    return vector.normalize(vector.add(vector.add(scene.forward, vector.scale(scene.right, u)), vector.scale(scene.up, v)));
  }

  samples(light, point) {
    if (light.kind === 'sun') return [{ direction: light.direction, distance: this.settings.far, intensity: light.intensity }];
    const positions = [];
    if (light.kind === 'area') {
      const k = light.divisions;
      for (let j = 0; j < k; j++) {
        for (let i = 0; i < k; i++) {
          positions.push(light.position.map((value, axis) => value + div((2 * i + 1) * light.u[axis], 2 * k) +
            div((2 * j + 1) * light.v[axis], 2 * k)));
        }
      }
    } else positions.push(light.position);
    return positions.map(position => {
      const relative = vector.sub(position, point);
      return { direction: vector.normalize(relative), distance: vector.length(relative), intensity: div(light.intensity, light.samples) };
    });
  }

  cone(light, direction) {
    if (light.kind !== 'spot') return S;
    const cosine = -vector.dot(direction, light.direction);
    if (cosine <= light.outer) return 0;
    if (cosine >= light.inner) return S;
    return div((cosine - light.outer) * S, light.inner - light.outer);
  }

  countRay(kind, depth, context) {
    if (!context.render) return;
    this.rays[kind]++;
    context.pixel.rays++;
    if (kind !== 'shadow') {
      this.depthCounts[depth]++;
      context.pixel.rayDepth = Math.max(context.pixel.rayDepth, depth);
    }
  }

  localColor(hit, direction, context) {
    const lightResults = [], view = vector.neg(direction), material = hit.object.material;
    let diffuse = 0, specular = 0;
    for (const light of this.scene.lights) {
      const result = { number: light.number, samples: light.samples, lit: 0, diffuse: 0, specular: 0 };
      for (const sample of this.samples(light, hit.point)) {
        const ndl = vector.dot(hit.normal, sample.direction);
        if (ndl <= 0) { if (context.render) light.counts.backfacing++; continue; }
        const cone = this.cone(light, sample.direction);
        if (cone === 0) { if (context.render) light.counts.outside++; continue; }
        this.countRay('shadow', 0, context);
        if (context.render) light.counts.shadowRays++;
        const blockers = this.occluders(hit.point, sample.direction, sample.distance, context);
        let factor = cone;
        for (const object of blockers) factor = mul(factor, object.material.kt);
        if (factor === 0) { if (context.render) light.counts.blocked++; continue; }
        if (context.render && blockers.length) light.counts.attenuated++;
        result.lit++;
        const components = shading.components(material, hit.normal, sample.direction, view, ndl, mul(sample.intensity, factor));
        result.diffuse += components.diffuse;
        result.specular += components.specular;
      }
      lightResults.push(result);
      diffuse += result.diffuse;
      specular += result.specular;
    }
    const local = hit.base.map(value => {
      const raw = div(value * (this.scene.ambient + diffuse), S) + div(255 * specular, S);
      if (context.render && raw > 255) this.clamped++;
      return Math.min(raw, 255);
    });
    return { local, lightResults, illumination: lightResults.filter(result => result.lit > 0).length };
  }

  trace(origin, direction, kind, depth, context) {
    this.countRay(kind, depth, context);
    const record = context.record;
    if (record) record.push(`ray ${kind} ${depth} origin ${triple(origin)} direction ${triple(direction)}`);
    const intersection = this.nearest(origin, direction, kind, context);
    if (!intersection) {
      if (context.render) this.misses[kind]++;
      if (record) record.push('miss', `color ${triple(this.scene.background)}`);
      return { color: this.scene.background, hit: null };
    }
    const point = vector.add(origin, vector.scale(direction, intersection.t));
    const outward = intersect.outwardNormal(intersection.object, point, direction, intersection);
    const front = vector.dot(outward, direction) <= 0, normal = front ? outward : vector.neg(outward);
    const hit = { ...intersection, point, normal, front, base: shading.baseColor(intersection.object.material, point) };
    if (context.render) hit.object.counts[kind === 'primary' ? 'primary' : 'secondary']++;
    if (record) record.push(`hit ${hit.object.label} t ${hit.t} point ${triple(point)} normal ${triple(normal)} base ${triple(hit.base)}`);
    Object.assign(hit, this.localColor(hit, direction, context));
    if (record) {
      for (const light of hit.lightResults) {
        record.push(`light ${light.number} lit ${light.lit} of ${light.samples} diffuse ${light.diffuse} specular ${light.specular}`);
      }
      record.push(`local ${triple(hit.local)}`);
    }
    let color = hit.local;
    const material = hit.object.material;
    if (depth < this.settings.depth && (material.kr > 0 || material.kt > 0)) {
      const weights = shading.refraction(direction, normal, front, material);
      if (weights.totalInternal) {
        if (context.render) this.totalInternal++;
        if (record) record.push('total_internal_reflection');
      }
      if (record) record.push(`weights ${S - material.kr - material.kt} ${weights.wr} ${weights.wt}`);
      let reflected = [0, 0, 0], refracted = [0, 0, 0];
      if (weights.wr > 0) reflected = this.trace(point, shading.reflection(direction, normal), 'reflection', depth + 1, context).color;
      if (weights.wt > 0) refracted = this.trace(point, weights.transmitted, 'refraction', depth + 1, context).color;
      color = shading.mix([hit.local, reflected, refracted], [S - material.kr - material.kt, weights.wr, weights.wt]);
    }
    if (this.scene.fog) {
      const fog = this.scene.fog;
      const factor = hit.t <= fog.start ? 0 : hit.t >= fog.end ? S : div((hit.t - fog.start) * S, fog.end - fog.start);
      color = shading.mix([color, fog.color], [S - factor, factor]);
    }
    if (record) record.push(`color ${triple(color)}`);
    return { color, hit };
  }

  render() {
    const { width, height, contrast } = this.settings;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const pixel = { x, y, rays: 0, rayDepth: 0, samples: 1 };
        const result = this.trace(this.scene.eye, this.camera(4 * x + 2, 4 * y + 2), 'primary', 0, { render: true, pixel });
        pixel.center = result.color; pixel.color = result.color; pixel.hit = result.hit;
        pixel.label = result.hit ? result.hit.object.label : '.';
        if (result.hit) {
          for (const light of result.hit.lightResults) if (light.lit > 0) this.scene.lights[light.number - 1].counts.pixels++;
        }
        this.pixels.push(pixel);
      }
    }
    for (const pixel of this.pixels) {
      const neighbors = [[pixel.x, pixel.y - 1], [pixel.x, pixel.y + 1], [pixel.x - 1, pixel.y], [pixel.x + 1, pixel.y]]
        .filter(([x, y]) => x >= 0 && x < width && y >= 0 && y < height).map(([x, y]) => this.pixels[y * width + x]);
      if (!neighbors.some(other => other.label !== pixel.label ||
          Math.max(...pixel.center.map((value, axis) => Math.abs(value - other.center[axis]))) > contrast)) continue;
      this.supersampled++;
      pixel.samples = 4;
      const sum = [0, 0, 0];
      for (const [dx, dy] of [[1, 1], [3, 1], [1, 3], [3, 3]]) {
        const result = this.trace(this.scene.eye, this.camera(4 * pixel.x + dx, 4 * pixel.y + dy), 'primary', 0, { render: true, pixel });
        for (let axis = 0; axis < 3; axis++) sum[axis] += result.color[axis];
      }
      pixel.color = sum.map(value => div(value, 4));
    }
  }
}

function meanColor(pixels) {
  const sum = [0, 0, 0];
  for (const pixel of pixels) for (let axis = 0; axis < 3; axis++) sum[axis] += pixel.color[axis];
  return sum.map(value => div(value, pixels.length));
}

function imageFile(name, format, width, height, pixels) {
  const rows = [format, `${width} ${height}`, '255'];
  for (let y = 0; y < height; y++) {
    const row = pixels.slice(y * width, (y + 1) * width);
    rows.push((format === 'P3' ? row.flat() : row).join(' '));
  }
  writeLines(name, rows);
}

function renderingSummary(renderer) {
  const distances = renderer.pixels.filter(pixel => pixel.hit).map(pixel => pixel.hit.t);
  const minimum = distances.length ? Math.min(...distances) : null;
  const maximum = distances.length ? Math.max(...distances) : null;
  const maxRays = Math.max(...renderer.pixels.map(pixel => pixel.rays));
  const histogram = Array(8).fill(0);
  for (const pixel of renderer.pixels) {
    const [r, g, b] = pixel.color;
    histogram[div(div(299 * r + 587 * g + 114 * b, 1000), 32)]++;
  }
  return { minimum, maximum, maxRays, mean: meanColor(renderer.pixels), histogram };
}

function writeImages(renderer, summary) {
  const { width, height } = renderer.settings, pixels = renderer.pixels;
  imageFile('image.ppm', 'P3', width, height, pixels.map(pixel => pixel.color));
  imageFile('depth.pgm', 'P2', width, height, pixels.map(pixel => !pixel.hit ? 0 :
    summary.maximum === summary.minimum ? 255 : 255 - div(235 * (pixel.hit.t - summary.minimum), summary.maximum - summary.minimum)));
  imageFile('normal.ppm', 'P3', width, height, pixels.map(pixel => pixel.hit ?
    pixel.hit.normal.map(value => Math.min(255, Math.max(0, div((value + S) * 255, 2 * S)))) : [0, 0, 0]));
  imageFile('albedo.ppm', 'P3', width, height, pixels.map(pixel => pixel.hit ? pixel.hit.base : [0, 0, 0]));
  imageFile('cost.pgm', 'P2', width, height, pixels.map(pixel => div(255 * pixel.rays, summary.maxRays)));
  const maps = [['object_map.txt', pixel => pixel.label],
    ['light_map.txt', pixel => pixel.hit ? String(pixel.hit.illumination) : '.'],
    ['ray_depth.txt', pixel => String(pixel.rayDepth)]];
  for (const [name, value] of maps) {
    const rows = [];
    for (let y = 0; y < height; y++) rows.push(pixels.slice(y * width, (y + 1) * width).map(value).join(''));
    writeLines(name, rows);
  }
}

function statsLines(renderer, summary) {
  const { width, height } = renderer.settings;
  const r = renderer.rays, m = renderer.misses;
  const rows = [`image ${width} ${height}`, `supersampled ${renderer.supersampled}`,
    `rays primary ${r.primary} reflection ${r.reflection} refraction ${r.refraction} shadow ${r.shadow} total ${kinds.reduce((sum, kind) => sum + r[kind], 0)}`,
    `misses primary ${m.primary} reflection ${m.reflection} refraction ${m.refraction}`, `depth ${renderer.depthCounts.join(' ')}`];
  for (const kind of kinds) rows.push(`tests ${kind} nodes ${renderer.tests[kind].nodes} objects ${renderer.tests[kind].objects}`);
  rows.push(`total_internal_reflection ${renderer.totalInternal}`, `clamped ${renderer.clamped}`,
    summary.minimum === null ? 'distance none' : `distance ${summary.minimum} ${summary.maximum}`,
    `max_pixel_rays ${summary.maxRays}`, `mean ${triple(summary.mean)}`, `histogram ${summary.histogram.join(' ')}`);
  for (const node of renderer.nodes) {
    const description = node.objects ? 'leaf ' + node.objects.map(object => object.label).join('') : 'inner';
    rows.push(`node ${node.depth} ${description} box ${triple(node.lo)} ${triple(node.hi)} visits ${node.visits}`);
  }
  for (const object of renderer.scene.objects) {
    const selected = renderer.pixels.filter(pixel => pixel.label === object.label), c = object.counts;
    let suffix = 'box none color none';
    if (selected.length) {
      const xs = selected.map(pixel => pixel.x), ys = selected.map(pixel => pixel.y);
      suffix = `box ${Math.min(...xs)} ${Math.min(...ys)} ${Math.max(...xs)} ${Math.max(...ys)} color ${triple(meanColor(selected))}`;
    }
    rows.push(`object ${object.label} ${object.kind} primary ${c.primary} secondary ${c.secondary} shadow ${c.shadow} pixels ${selected.length} ${suffix}`);
  }
  for (const light of renderer.scene.lights) {
    const c = light.counts;
    rows.push(`light ${light.number} ${light.kind} samples ${light.samples} pixels ${c.pixels} shadow_rays ${c.shadowRays} blocked ${c.blocked} attenuated ${c.attenuated} backfacing ${c.backfacing} outside ${c.outside}`);
  }
  return rows;
}

function queryLines(renderer, queries) {
  const rows = [], { scene, settings, pixels } = renderer;
  for (let q = 0; q < queries.length; q++) {
    const line = queries[q], [kind, ...tokens] = line.split(' '), values = tokens.map(Number);
    const context = { render: false };
    rows.push(`query ${q + 1} ${line}`);
    if (kind === 'pixel') {
      const pixel = pixels[values[1] * settings.width + values[0]];
      rows.push(`label ${pixel.label} distance ${pixel.hit ? pixel.hit.t : 'none'} color ${triple(pixel.color)} samples ${pixel.samples} rays ${pixel.rays}`);
    } else if (kind === 'trace' || kind === 'ray') {
      const origin = kind === 'trace' ? scene.eye : values.slice(0, 3);
      const direction = kind === 'trace' ? renderer.camera(4 * values[0] + 2, 4 * values[1] + 2) : vector.normalize(values.slice(3, 6));
      renderer.trace(origin, direction, 'primary', 0, { render: false, record: rows });
    } else if (kind === 'object') {
      const object = scene.objects.find(object => object.label === tokens[0]);
      const bounds = object.bounds ? `${triple(object.bounds.lo)} ${triple(object.bounds.hi)} leaf ${object.leaf.depth}` : 'none leaf none';
      rows.push(`${object.kind} material ${object.material.name} bounds ${bounds}`);
    } else if (kind === 'visible') {
      const relative = vector.sub(values, scene.eye), direction = vector.normalize(relative);
      const blockers = renderer.occluders(scene.eye, direction, vector.length(relative) - settings.epsilon, context);
      const first = renderer.nearest(scene.eye, direction, 'primary', context);
      rows.push(`${blockers.length ? 'no' : 'yes'} first ${first ? first.object.label + ' t ' + first.t : 'none'}`);
    } else if (kind === 'shadow') {
      for (const light of scene.lights) {
        let factor = 0;
        const union = new Set();
        for (const sample of renderer.samples(light, values)) {
          let transmission = renderer.cone(light, sample.direction);
          const blockers = renderer.occluders(values, sample.direction, sample.distance, context);
          for (const object of blockers) { transmission = mul(transmission, object.material.kt); union.add(object.number); }
          factor += transmission;
        }
        const labels = scene.objects.filter(object => union.has(object.number)).map(object => object.label).join('');
        rows.push(`light ${light.number} factor ${factor} occluders ${labels || 'none'}`);
      }
    } else if (kind === 'region') {
      const [x0, y0, x1, y1] = values, selected = [];
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) selected.push(pixels[y * settings.width + x]);
      rows.push(`pixels ${selected.length} mean ${triple(meanColor(selected))}`);
      for (const label of [...scene.objects.map(object => object.label), '.']) {
        const count = selected.filter(pixel => pixel.label === label).length;
        if (count) rows.push(`label ${label} ${count}`);
      }
    }
  }
  return rows;
}

function main() {
  const scene = readScene('input/scene.txt'), settings = readSettings(), queries = readLines('input/queries.txt');
  const renderer = new Renderer(scene, settings);
  renderer.render();
  const summary = renderingSummary(renderer);
  fs.mkdirSync('output', { recursive: true });
  writeImages(renderer, summary);
  writeLines('stats.txt', statsLines(renderer, summary));
  writeLines('queries.txt', queryLines(renderer, queries));
}

main();
