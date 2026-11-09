import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { div, mul, S } from './fixed_point.ts';
import {
  bounds,
  intersect,
  outwardNormal,
  slab,
  type Bounds,
  type Hit,
  type Ray,
} from './intersect.ts';
import {
  readScene,
  type BoundedObject,
  type Color,
  type Light,
  type SceneObject,
} from './scene.ts';
import { baseColor, components, mix, reflection, transmission } from './shading.ts';
import { add, dot, length, neg, norm, scale, sub, triple, type Vec3 } from './vector3.ts';

const scene = readScene();
const settings = readFileSync('input/render.txt', 'ascii')
  .trimEnd()
  .split('\n')
  .map((line) => line.split(' ').slice(1).map(Number));
const [width, height] = settings[0];
const contrast = settings[1][0];
const maxDepth = settings[2][0];
const far = settings[3][0];
const epsilon = settings[4][0];
const pad = settings[5][0];
type Node = { box: Bounds; depth: number; visits: number } & (
  { kind: 'leaf'; objects: BoundedObject[] } | { kind: 'inner'; left: Node; right: Node }
);
const bounded = scene.objects.filter((object): object is BoundedObject => object.kind !== 'plane');
const objectBounds = new Map(bounded.map((object) => [object.number, bounds(object, pad)]));
function objectBox(object: BoundedObject): Bounds {
  const result = objectBounds.get(object.number);
  if (!result) throw new Error('Missing bounds');
  return result;
}
function union(objects: BoundedObject[]): Bounds {
  const low = (axis: number) => Math.min(...objects.map((object) => objectBox(object).lo[axis]));
  const high = (axis: number) => Math.max(...objects.map((object) => objectBox(object).hi[axis]));
  return { lo: [low(0), low(1), low(2)], hi: [high(0), high(1), high(2)] };
}
const area = (box: Bounds) => {
  const [x, y, z] = sub(box.hi, box.lo);
  return x * y + y * z + z * x;
};
function build(objects: BoundedObject[], depth: number): Node {
  const box = union(objects);
  if (objects.length <= 2) {
    return {
      kind: 'leaf',
      box,
      depth,
      visits: 0,
      objects: [...objects].sort((a, b) => a.number - b.number),
    };
  }
  let cost = Infinity;
  let left = objects.slice(0, 1);
  let right = objects.slice(1);
  for (let axis = 0; axis < 3; axis++) {
    const sorted = [...objects].sort((a, b) => {
      const aa = objectBox(a);
      const bb = objectBox(b);
      return (
        div(aa.lo[axis] + aa.hi[axis], 2) - div(bb.lo[axis] + bb.hi[axis], 2) || a.number - b.number
      );
    });
    for (let i = 1; i < sorted.length; i++) {
      const a = sorted.slice(0, i);
      const b = sorted.slice(i);
      const candidate = area(union(a)) * a.length + area(union(b)) * b.length;
      if (candidate < cost) {
        cost = candidate;
        left = a;
        right = b;
      }
    }
  }
  return {
    kind: 'inner',
    box,
    depth,
    visits: 0,
    left: build(left, depth + 1),
    right: build(right, depth + 1),
  };
}
const root = bounded.length ? build(bounded, 0) : undefined;
type RayKind = 'primary' | 'reflection' | 'refraction' | 'shadow';
type TraceKind = Exclude<RayKind, 'shadow'>;
const kinds: RayKind[] = ['primary', 'reflection', 'refraction', 'shadow'];
const counts: Record<RayKind, { rays: number; nodes: number; objects: number }> = {
  primary: { rays: 0, nodes: 0, objects: 0 },
  reflection: { rays: 0, nodes: 0, objects: 0 },
  refraction: { rays: 0, nodes: 0, objects: 0 },
  shadow: { rays: 0, nodes: 0, objects: 0 },
};
const misses: Record<TraceKind, number> = { primary: 0, reflection: 0, refraction: 0 };
const depths = Array<number>(maxDepth + 1).fill(0);
const objectCounts = scene.objects.map(() => ({ primary: 0, secondary: 0, shadow: 0 }));
const lightCounts = scene.lights.map(() => ({
  shadow: 0,
  blocked: 0,
  attenuated: 0,
  backfacing: 0,
  outside: 0,
  pixels: 0,
}));
let totalInternal = 0;
let clamped = 0;
interface Context {
  count: boolean;
  pixel?: Pixel;
  record?: string[];
}
function nearest(ray: Ray, kind: TraceKind, count: boolean): Hit | undefined {
  let best: Hit | undefined;
  const test = (object: SceneObject) => {
    if (count) counts[kind].objects++;
    const hit = intersect(object, ray, epsilon);
    if (
      hit &&
      hit.t <= far &&
      (!best || hit.t < best.t || (hit.t === best.t && hit.object.number < best.object.number))
    ) {
      best = hit;
    }
  };
  for (const object of scene.objects) if (object.kind === 'plane') test(object);
  const visit = (node: Node): void => {
    if (count) {
      counts[kind].nodes++;
      node.visits++;
    }
    const result = slab(node.box, ray);
    if (!result || result.far <= epsilon || result.near > far || (best && result.near > best.t)) {
      return;
    }
    if (node.kind === 'leaf') for (const object of node.objects) test(object);
    else {
      visit(node.left);
      visit(node.right);
    }
  };
  if (root) visit(root);
  return best;
}
function occluders(ray: Ray, distance: number, count: boolean): SceneObject[] {
  const result: SceneObject[] = [];
  const test = (object: SceneObject) => {
    if (count) counts.shadow.objects++;
    const hit = intersect(object, ray, epsilon);
    if (hit && hit.t < distance) result.push(object);
  };
  for (const object of scene.objects) if (object.kind === 'plane') test(object);
  const visit = (node: Node): void => {
    if (count) {
      counts.shadow.nodes++;
      node.visits++;
    }
    const hit = slab(node.box, ray);
    if (!hit || hit.far <= epsilon || hit.near >= distance) return;
    if (node.kind === 'leaf') for (const object of node.objects) test(object);
    else {
      visit(node.left);
      visit(node.right);
    }
  };
  if (root) visit(root);
  result.sort((a, b) => a.number - b.number);
  if (count) for (const object of result) objectCounts[object.number - 1].shadow++;
  return result;
}
function camera(qx: number, qy: number): Ray {
  const u = div((qx - 2 * width) * scene.halfWidth, 2 * width);
  const v = div((2 * height - qy) * scene.halfHeight, 2 * height);
  return {
    origin: scene.eye,
    direction: norm(add(add(scene.forward, scale(scene.right, u)), scale(scene.up, v))),
  };
}
interface Sample {
  direction: Vec3;
  distance: number;
  intensity: number;
}
const sampleCount = (light: Light) =>
  light.kind === 'area' ? light.divisions * light.divisions : 1;
function samples(light: Light, point: Vec3): Sample[] {
  if (light.kind === 'sun') {
    return [{ direction: light.direction, distance: far, intensity: light.intensity }];
  }
  const positions: Vec3[] = [];
  if (light.kind !== 'area') positions.push(light.position);
  else {
    for (let j = 0; j < light.divisions; j++) {
      for (let i = 0; i < light.divisions; i++) {
        const coordinate = (a: number) =>
          light.position[a] +
          div((2 * i + 1) * light.u[a], 2 * light.divisions) +
          div((2 * j + 1) * light.v[a], 2 * light.divisions);
        positions.push([coordinate(0), coordinate(1), coordinate(2)]);
      }
    }
  }
  return positions.map((position) => {
    const rel = sub(position, point);
    return {
      direction: norm(rel),
      distance: length(rel),
      intensity: div(light.intensity, positions.length),
    };
  });
}
function cone(light: Light, direction: Vec3): number {
  if (light.kind !== 'spot') return S;
  const cosine = -dot(direction, light.direction);
  return cosine <= light.outer
    ? 0
    : cosine >= light.inner
      ? S
      : div((cosine - light.outer) * S, light.inner - light.outer);
}
interface Surface {
  hit: Hit;
  point: Vec3;
  normal: Vec3;
  base: Color;
  front: boolean;
}
interface LightResult {
  lit: number;
  diffuse: number;
  specular: number;
}
interface Traced {
  color: Color;
  surface?: Surface;
  lights: LightResult[];
}
interface Pixel {
  x: number;
  y: number;
  center: Traced;
  color: Color;
  samples: number;
  rays: number;
  depth: number;
}
function trace(ray: Ray, kind: TraceKind, depth: number, context: Context): Traced {
  if (context.count) {
    counts[kind].rays++;
    depths[depth]++;
  }
  if (context.pixel) {
    context.pixel.rays++;
    context.pixel.depth = Math.max(context.pixel.depth, depth);
  }
  context.record?.push(
    `ray ${kind} ${depth} origin ${ray.origin.join(' ')} direction ${ray.direction.join(' ')}`,
  );
  const hit = nearest(ray, kind, context.count);
  if (!hit) {
    if (context.count) misses[kind]++;
    context.record?.push('miss', `color ${scene.background.join(' ')}`);
    return { color: scene.background, lights: [] };
  }
  if (context.count) {
    if (kind === 'primary') objectCounts[hit.object.number - 1].primary++;
    else objectCounts[hit.object.number - 1].secondary++;
  }
  const point = add(ray.origin, scale(ray.direction, hit.t));
  const outward = outwardNormal(hit, point, ray.direction);
  const front = dot(outward, ray.direction) <= 0;
  const normal = front ? outward : neg(outward);
  const material = hit.object.material;
  const base = baseColor(material, point);
  const view = neg(ray.direction);
  const surface: Surface = { hit, point, normal, base, front };
  context.record?.push(
    `hit ${hit.object.label} t ${hit.t} point ${point.join(' ')} normal ${normal.join(' ')} base ${base.join(' ')}`,
  );
  const lights: LightResult[] = [];
  let diffuseSum = 0;
  let specularSum = 0;
  for (const light of scene.lights) {
    const result: LightResult = { lit: 0, diffuse: 0, specular: 0 };
    const lightStats = lightCounts[light.number - 1];
    for (const sample of samples(light, point)) {
      const ndl = dot(normal, sample.direction);
      if (ndl <= 0) {
        if (context.count) lightStats.backfacing++;
        continue;
      }
      const g = cone(light, sample.direction);
      if (!g) {
        if (context.count) lightStats.outside++;
        continue;
      }
      if (context.count) {
        counts.shadow.rays++;
        lightStats.shadow++;
      }
      if (context.pixel) context.pixel.rays++;
      const blockers = occluders(
        { origin: point, direction: sample.direction },
        sample.distance,
        context.count,
      );
      let factor = g;
      for (const blocker of blockers) factor = mul(factor, blocker.material.kt);
      if (factor === 0) {
        if (context.count) lightStats.blocked++;
        continue;
      }
      if (blockers.length && context.count) lightStats.attenuated++;
      result.lit++;
      const value = components(
        material,
        normal,
        sample.direction,
        view,
        mul(sample.intensity, factor),
        ndl,
      );
      result.diffuse += value.diffuse;
      result.specular += value.specular;
    }
    lights.push(result);
    diffuseSum += result.diffuse;
    specularSum += result.specular;
    context.record?.push(
      `light ${light.number} lit ${result.lit} of ${sampleCount(light)} diffuse ${result.diffuse} specular ${result.specular}`,
    );
  }
  const local: Color = [0, 0, 0];
  for (let c = 0; c < 3; c++) {
    const raw = div(base[c] * (scene.ambient + diffuseSum), S) + div(255 * specularSum, S);
    local[c] = Math.min(raw, 255);
    if (raw > 255 && context.count) clamped++;
  }
  context.record?.push(`local ${local.join(' ')}`);
  let color = local;
  if (depth < maxDepth && (material.kr !== 0 || material.kt !== 0)) {
    const weights = transmission(material, ray.direction, normal, front);
    if (weights.tir) {
      if (context.count) totalInternal++;
      context.record?.push('total_internal_reflection');
    }
    context.record?.push(
      `weights ${S - material.kr - material.kt} ${weights.reflected} ${weights.transmitted}`,
    );
    const reflected: Color =
      weights.reflected > 0
        ? trace(
            { origin: point, direction: reflection(ray.direction, normal) },
            'reflection',
            depth + 1,
            context,
          ).color
        : [0, 0, 0];
    let transmitted: Color = [0, 0, 0];
    if (weights.transmitted > 0) {
      if (!weights.direction) throw new Error('Missing refraction direction');
      transmitted = trace(
        { origin: point, direction: weights.direction },
        'refraction',
        depth + 1,
        context,
      ).color;
    }
    color = mix([
      { color: local, weight: S - material.kr - material.kt },
      { color: reflected, weight: weights.reflected },
      { color: transmitted, weight: weights.transmitted },
    ]);
  }
  if (scene.fog) {
    const fog = scene.fog;
    const factor =
      hit.t <= fog.start
        ? 0
        : hit.t >= fog.end
          ? S
          : div((hit.t - fog.start) * S, fog.end - fog.start);
    color = mix([
      { color, weight: S - factor },
      { color: fog.color, weight: factor },
    ]);
  }
  context.record?.push(`color ${color.join(' ')}`);
  return { color, surface, lights };
}
const pixels: Pixel[] = [];
for (let y = 0; y < height; y++) {
  for (let x = 0; x < width; x++) {
    const pixel: Pixel = {
      x,
      y,
      center: { color: [0, 0, 0], lights: [] },
      color: [0, 0, 0],
      samples: 1,
      rays: 0,
      depth: 0,
    };
    pixel.center = trace(camera(4 * x + 2, 4 * y + 2), 'primary', 0, { count: true, pixel });
    pixel.color = pixel.center.color;
    pixels.push(pixel);
    if (pixel.center.surface) {
      pixel.center.lights.forEach((light, i) => {
        if (light.lit) lightCounts[i].pixels++;
      });
    }
  }
}
const label = (pixel: Pixel) => pixel.center.surface?.hit.object.label ?? '.';
const average = (colors: Color[]): Color => {
  const totals: Color = [0, 0, 0];
  for (const color of colors) for (let c = 0; c < 3; c++) totals[c] += color[c];
  return [
    div(totals[0], colors.length),
    div(totals[1], colors.length),
    div(totals[2], colors.length),
  ];
};
let supersampled = 0;
for (const pixel of pixels) {
  const resample = [
    [0, -1],
    [0, 1],
    [-1, 0],
    [1, 0],
  ].some(([dx, dy]) => {
    const x = pixel.x + dx;
    const y = pixel.y + dy;
    if (x < 0 || x >= width || y < 0 || y >= height) return false;
    const other = pixels[y * width + x];
    return (
      label(pixel) !== label(other) ||
      pixel.center.color.some(
        (component, c) => Math.abs(component - other.center.color[c]) > contrast,
      )
    );
  });
  if (resample) {
    supersampled++;
    pixel.samples = 4;
    pixel.color = average(
      [
        [1, 1],
        [3, 1],
        [1, 3],
        [3, 3],
      ].map(
        ([dx, dy]) =>
          trace(camera(4 * pixel.x + dx, 4 * pixel.y + dy), 'primary', 0, { count: true, pixel })
            .color,
      ),
    );
  }
}
const hitPixels = pixels.filter((pixel) => pixel.center.surface);
const distances = hitPixels.map((pixel) => pixel.center.surface!.hit.t);
const minimum = Math.min(...distances);
const maximum = Math.max(...distances);
const maxRays = Math.max(...pixels.map((pixel) => pixel.rays));
const image = (magic: string, components: (pixel: Pixel) => number[]): string[] => [
  magic,
  `${width} ${height}`,
  '255',
  ...Array.from({ length: height }, (_, y) =>
    pixels
      .slice(y * width, (y + 1) * width)
      .flatMap(components)
      .join(' '),
  ),
];
const maps = (character: (pixel: Pixel) => string) =>
  Array.from({ length: height }, (_, y) =>
    pixels
      .slice(y * width, (y + 1) * width)
      .map(character)
      .join(''),
  );
const stats = [
  `image ${width} ${height}`,
  `supersampled ${supersampled}`,
  `rays primary ${counts.primary.rays} reflection ${counts.reflection.rays} refraction ${counts.refraction.rays} shadow ${counts.shadow.rays} total ${kinds.reduce((sum, kind) => sum + counts[kind].rays, 0)}`,
  `misses primary ${misses.primary} reflection ${misses.reflection} refraction ${misses.refraction}`,
  `depth ${depths.join(' ')}`,
  ...kinds.map(
    (kind) => `tests ${kind} nodes ${counts[kind].nodes} objects ${counts[kind].objects}`,
  ),
  `total_internal_reflection ${totalInternal}`,
  `clamped ${clamped}`,
  hitPixels.length ? `distance ${minimum} ${maximum}` : 'distance none',
  `max_pixel_rays ${maxRays}`,
  `mean ${average(pixels.map((pixel) => pixel.color)).join(' ')}`,
];
const histogram = Array<number>(8).fill(0);
for (const pixel of pixels) {
  const [r, g, b] = pixel.color;
  histogram[div(div(299 * r + 587 * g + 114 * b, 1000), 32)]++;
}
stats.push(`histogram ${histogram.join(' ')}`);
const leaves = new Map<number, number>();
function nodeLines(node: Node): void {
  stats.push(
    `node ${node.depth} ${node.kind === 'leaf' ? 'leaf ' + node.objects.map((object) => object.label).join('') : 'inner'} box ${node.box.lo.join(' ')} ${node.box.hi.join(' ')} visits ${node.visits}`,
  );
  if (node.kind === 'leaf') {
    for (const object of node.objects) leaves.set(object.number, node.depth);
  } else {
    nodeLines(node.left);
    nodeLines(node.right);
  }
}
if (root) nodeLines(root);
for (const object of scene.objects) {
  const selected = pixels.filter((pixel) => label(pixel) === object.label);
  const c = objectCounts[object.number - 1];
  const box = selected.length
    ? `${Math.min(...selected.map((pixel) => pixel.x))} ${Math.min(...selected.map((pixel) => pixel.y))} ${Math.max(...selected.map((pixel) => pixel.x))} ${Math.max(...selected.map((pixel) => pixel.y))}`
    : 'none';
  stats.push(
    `object ${object.label} ${object.kind} primary ${c.primary} secondary ${c.secondary} shadow ${c.shadow} pixels ${selected.length} box ${box} color ${selected.length ? average(selected.map((pixel) => pixel.color)).join(' ') : 'none'}`,
  );
}
for (const light of scene.lights) {
  const c = lightCounts[light.number - 1];
  stats.push(
    `light ${light.number} ${light.kind} samples ${sampleCount(light)} pixels ${c.pixels} shadow_rays ${c.shadow} blocked ${c.blocked} attenuated ${c.attenuated} backfacing ${c.backfacing} outside ${c.outside}`,
  );
}
const queryLines: string[] = [];
const queries = readFileSync('input/queries.txt', 'ascii')
  .split('\n')
  .filter((line) => line !== '');
queries.forEach((line, i) => {
  queryLines.push(`query ${i + 1} ${line}`);
  const [kind, ...tokens] = line.split(' ');
  const values = tokens.map((token) => (/^-?[0-9]+$/.test(token) ? +token : 0));
  if (kind === 'pixel') {
    const pixel = pixels[values[1] * width + values[0]];
    queryLines.push(
      `label ${label(pixel)} distance ${pixel.center.surface?.hit.t ?? 'none'} color ${pixel.color.join(' ')} samples ${pixel.samples} rays ${pixel.rays}`,
    );
  } else if (kind === 'trace' || kind === 'ray') {
    trace(
      kind === 'trace'
        ? camera(4 * values[0] + 2, 4 * values[1] + 2)
        : { origin: triple(values), direction: norm(triple(values, 3)) },
      'primary',
      0,
      { count: false, record: queryLines },
    );
  } else if (kind === 'object') {
    const object = scene.objects.find((object) => object.label === tokens[0]);
    if (!object) throw new Error('Unknown object');
    queryLines.push(
      `${object.kind} material ${object.material.name} bounds ${object.kind === 'plane' ? 'none leaf none' : `${objectBox(object).lo.join(' ')} ${objectBox(object).hi.join(' ')} leaf ${leaves.get(object.number)}`}`,
    );
  } else if (kind === 'visible') {
    const rel = sub(triple(values), scene.eye);
    const ray = { origin: scene.eye, direction: norm(rel) };
    const visible = !occluders(ray, length(rel) - epsilon, false).length;
    const first = nearest(ray, 'primary', false);
    queryLines.push(
      `${visible ? 'yes' : 'no'} first ${first ? `${first.object.label} t ${first.t}` : 'none'}`,
    );
  } else if (kind === 'shadow') {
    const point = triple(values);
    for (const light of scene.lights) {
      let total = 0;
      const blockers = new Set<number>();
      for (const sample of samples(light, point)) {
        let factor = cone(light, sample.direction);
        for (const object of occluders(
          { origin: point, direction: sample.direction },
          sample.distance,
          false,
        )) {
          blockers.add(object.number);
          factor = mul(factor, object.material.kt);
        }
        total += factor;
      }
      queryLines.push(
        `light ${light.number} factor ${total} occluders ${
          scene.objects
            .filter((object) => blockers.has(object.number))
            .map((object) => object.label)
            .join('') || 'none'
        }`,
      );
    }
  } else if (kind === 'region') {
    const selected = pixels.filter(
      (pixel) =>
        pixel.x >= values[0] &&
        pixel.x <= values[2] &&
        pixel.y >= values[1] &&
        pixel.y <= values[3],
    );
    queryLines.push(
      `pixels ${selected.length} mean ${average(selected.map((pixel) => pixel.color)).join(' ')}`,
    );
    for (const name of [...scene.objects.map((object) => object.label), '.']) {
      const count = selected.filter((pixel) => label(pixel) === name).length;
      if (count) queryLines.push(`label ${name} ${count}`);
    }
  }
});
mkdirSync('output', { recursive: true });
const write = (name: string, lines: string[]) =>
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
write(
  'image.ppm',
  image('P3', (pixel) => pixel.color),
);
write(
  'depth.pgm',
  image('P2', (pixel) => [
    !pixel.center.surface
      ? 0
      : minimum === maximum
        ? 255
        : 255 - div(235 * (pixel.center.surface.hit.t - minimum), maximum - minimum),
  ]),
);
write(
  'normal.ppm',
  image('P3', (pixel) =>
    pixel.center.surface
      ? pixel.center.surface.normal.map((component) =>
          Math.max(0, Math.min(255, div((component + S) * 255, 2 * S))),
        )
      : [0, 0, 0],
  ),
);
write(
  'albedo.ppm',
  image('P3', (pixel) => pixel.center.surface?.base ?? [0, 0, 0]),
);
write(
  'cost.pgm',
  image('P2', (pixel) => [div(255 * pixel.rays, maxRays)]),
);
write('object_map.txt', maps(label));
write(
  'light_map.txt',
  maps((pixel) =>
    pixel.center.surface
      ? String(pixel.center.lights.filter((light) => light.lit > 0).length)
      : '.',
  ),
);
write(
  'ray_depth.txt',
  maps((pixel) => String(pixel.depth)),
);
write('stats.txt', stats);
write('queries.txt', queryLines);
